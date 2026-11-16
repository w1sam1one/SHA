import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'aes_gcm.dart';
import 'crypto_service.dart';
import 'entropy.dart';
import 'hashing.dart';
import 'key_agreement.dart';
import 'key_vault.dart';
import 'olm_service.dart';
import 'padding.dart';
import 'sha_olm_service.dart';
import 'types.dart';
import 'wipe.dart';
import 'wire_format.dart';

/// Default [CryptoService], built only on the `cryptography` package.
final class ShaCryptoService implements CryptoService {
  ShaCryptoService({
    required KeyVault vault,
    EntropySource? localEntropy,
    DateTime Function()? clock,
  }) : _vault = vault,
       _entropy = MixedEntropy(platform: vault, local: localEntropy) {
    _olm = ShaOlmService(vault: vault, entropy: _entropy, clock: clock);
  }

  static const String privateKeyName = 'identity.x25519.private.v2';
  static const String publicKeyName = 'identity.x25519.public.v2';

  static final List<int> _verifyLabel = utf8.encode('SHA/v2/verification-code');
  static final List<int> _mailboxLabel = utf8.encode('SHA/v2/mailbox');

  final KeyVault _vault;
  final MixedEntropy _entropy;
  final Sha256Hasher _hasher = Sha256Hasher();
  final Aes256Gcm _aead = Aes256Gcm();
  final X25519KeyAgreement _agreement = X25519KeyAgreement();
  late final ShaOlmService _olm;

  @override
  OlmService get olm => _olm;

  PublicIdentity? _identity;
  Future<PublicIdentity?>? _loading;
  Future<PublicIdentity>? _creating;

  @override
  Future<PublicIdentity?> loadIdentity() async =>
      _identity ??
      await (_loading ??= _load().whenComplete(() => _loading = null));

  Future<PublicIdentity?> _load() async {
    final publicKey = await _vault.read(publicKeyName);
    if (publicKey != null) {
      return _identity = PublicIdentity(publicKey);
    }
    // Recover if a previous creation stopped between the two writes.
    final privateKey = await _vault.read(privateKeyName);
    if (privateKey == null) return null;
    try {
      final recovered = await _agreement.publicKeyOf(privateKey);
      await _vault.write(publicKeyName, recovered);
      return _identity = PublicIdentity(recovered);
    } finally {
      wipe(privateKey);
    }
  }

  @override
  Future<PublicIdentity> createIdentity() =>
      _creating ??= _create().whenComplete(() => _creating = null);

  Future<PublicIdentity> _create() async {
    if (await loadIdentity() != null) {
      throw const CryptoException('An identity already exists');
    }
    final privateKey = await _entropy.bytes(32, purpose: 'identity-x25519');
    try {
      final publicKey = await _agreement.publicKeyOf(privateKey);
      await _vault.write(privateKeyName, privateKey);
      await _vault.write(publicKeyName, publicKey);
      return _identity = PublicIdentity(publicKey);
    } finally {
      wipe(privateKey);
    }
  }

  @override
  Future<void> resetIdentity() async {
    // Let in-flight loads and creates finish first (including any started
    // while waiting), so none can write the old identity back after the
    // vault has been cleared. Their errors are irrelevant here: the point is
    // to discard whatever they were doing.
    while (_creating != null || _loading != null) {
      try {
        await (_creating ?? _loading);
      } catch (_) {}
    }
    // The vault deletes its key first and then every entry, the Olm state
    // and pickle key included. Olm calls in progress finish first, and Olm
    // forgets what it holds in memory afterwards.
    await _olm.discardAfter(_vault.reset);
    _identity = null;
    _loading = null;
    _creating = null;
  }

  @override
  Future<KeyProtection> keyProtection() => _vault.protection();

  @override
  Future<Uint8List> sha256(List<int> data) => _hasher.hash(data);

  @override
  Future<ConversationKeys> conversationKeys(PublicIdentity peer) async {
    final own = await _requireIdentity();
    if (own == peer) {
      throw const CryptoException('Cannot derive keys with yourself');
    }
    final privateKey = await _vault.read(privateKeyName);
    if (privateKey == null) {
      throw const CryptoException(
        'Private key missing',
        CryptoErrorKind.keyInvalidated,
      );
    }
    try {
      final secrets = await _agreement.derive(
        ownPrivateKey: privateKey,
        ownPublicKey: own.publicKey,
        peerPublicKey: peer.publicKey,
      );
      return _ConversationKeys(peer.hash, secrets);
    } finally {
      wipe(privateKey);
    }
  }

  @override
  void forget(ConversationKeys keys) => _secretsOf(keys).destroy();

  @override
  Future<String> verificationCode(PublicIdentity peer) async {
    final own = await _requireIdentity();
    final digest = await _hasher.hash([
      ..._verifyLabel,
      ...X25519KeyAgreement.sortedConcat(own.publicKey, peer.publicKey),
    ]);
    // Four groups of five digits, each from 5 bytes (as in Signal's safety
    // numbers); the modulo bias is below 2^-20 per group.
    final buffer = StringBuffer();
    for (var g = 0; g < 4; g++) {
      var value = 0;
      for (var i = 0; i < 5; i++) {
        value = value * 256 + digest[g * 5 + i];
      }
      buffer.write((value % 100000).toString().padLeft(5, '0'));
    }
    return buffer.toString();
  }

  @override
  Future<Uint8List> mailboxId(
    ConversationKeys keys,
    MessageDirection direction,
    int epoch,
  ) async {
    final secrets = _secretsOf(keys);
    final key = direction == MessageDirection.outgoing
        ? secrets.sendMailboxKey
        : secrets.receiveMailboxKey;
    final epochBytes = ByteData(8)..setUint64(0, epoch);
    final mac = await _hasher.hmac(key, [
      ..._mailboxLabel,
      ...epochBytes.buffer.asUint8List(),
    ]);
    return Uint8List.fromList(mac.sublist(0, WireFormat.mailboxIdLength));
  }

  @override
  Future<Uint8List> seal(
    ConversationKeys keys,
    List<int> payload, {
    required DateTime now,
  }) async {
    final secrets = _secretsOf(keys);
    final header = Uint8List(WireFormat.headerLength)
      ..[0] = WireFormat.version
      ..setRange(
        1,
        WireFormat.headerLength,
        await mailboxId(
          keys,
          MessageDirection.outgoing,
          WireFormat.epochOf(now),
        ),
      );
    final padded = MessagePadding.pad(payload);
    try {
      final body = await _aead.encrypt(
        secrets.sendKey,
        padded,
        associatedData: header,
      );
      return Uint8List.fromList([...header, ...body]);
    } finally {
      wipe(padded);
    }
  }

  @override
  Future<Uint8List> open(
    ConversationKeys keys,
    Uint8List packet,
    MessageDirection direction,
  ) async {
    final secrets = _secretsOf(keys);
    WireFormat.checkHeader(packet);
    final clear = await _aead.decrypt(
      direction == MessageDirection.outgoing
          ? secrets.sendKey
          : secrets.receiveKey,
      Uint8List.sublistView(packet, WireFormat.headerLength),
      associatedData: Uint8List.sublistView(packet, 0, WireFormat.headerLength),
    );
    try {
      return MessagePadding.unpad(clear);
    } finally {
      wipe(clear);
    }
  }

  Future<PublicIdentity> _requireIdentity() async {
    final identity = await loadIdentity();
    if (identity == null) {
      throw const CryptoException('No identity on this device');
    }
    return identity;
  }

  SessionSecrets _secretsOf(ConversationKeys keys) {
    if (keys is! _ConversationKeys) {
      throw const CryptoException('Unknown conversation keys');
    }
    return keys._secrets;
  }
}

final class _ConversationKeys implements ConversationKeys {
  _ConversationKeys(this.peer, this._secrets);

  @override
  final IdentityHash peer;

  final SessionSecrets _secrets;

  @override
  String toString() => 'ConversationKeys(peer: ${peer.hex})';
}
