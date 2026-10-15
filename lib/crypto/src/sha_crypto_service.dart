import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'aes_gcm.dart';
import 'crypto_service.dart';
import 'hashing.dart';
import 'key_agreement.dart';
import 'secure_key_storage.dart';
import 'types.dart';

/// Default [CryptoService], built only on the `cryptography` package.
final class ShaCryptoService implements CryptoService {
  ShaCryptoService({required this._storage});

  /// Storage slot for the identity's X25519 private key.
  static const String identityKeyName = 'sha.identity.x25519.v1';

  static final List<int> _verifyLabel = utf8.encode('SHA/v1/verification-code');

  final SecureKeyStorage _storage;
  final Sha256Hasher _hasher = Sha256Hasher();
  final Aes256Gcm _aead = Aes256Gcm();
  final X25519KeyAgreement _agreement = X25519KeyAgreement();

  SimpleKeyPair? _keyPair;
  PublicIdentity? _identity;
  Future<PublicIdentity?>? _loading;

  @override
  Future<PublicIdentity?> loadIdentity() =>
      _identity != null ? Future.value(_identity) : (_loading ??= _load());

  Future<PublicIdentity?> _load() async {
    try {
      final stored = await _storage.read(identityKeyName);
      if (stored == null) return null;
      try {
        await _adopt(
          await _agreement.keyPairFromPrivateKey(Uint8List.fromList(stored)),
        );
      } finally {
        // Best effort: Dart cannot guarantee no other copy exists.
        stored.fillRange(0, stored.length, 0);
      }
      return _identity;
    } finally {
      _loading = null;
    }
  }

  @override
  Future<PublicIdentity> createIdentity() async {
    if (await loadIdentity() != null) {
      throw const CryptoException('An identity already exists');
    }
    final keyPair = await _agreement.newKeyPair();
    final privateKey = Uint8List.fromList(
      await keyPair.extractPrivateKeyBytes(),
    );
    try {
      await _storage.write(identityKeyName, privateKey);
    } finally {
      privateKey.fillRange(0, privateKey.length, 0);
    }
    await _adopt(keyPair);
    return _identity!;
  }

  Future<void> _adopt(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    _identity = await identityFromPublicKey(publicKey.bytes);
    _keyPair = keyPair;
  }

  @override
  Future<PublicIdentity> identityFromPublicKey(List<int> publicKey) async {
    if (publicKey.length != publicKeyLength) {
      throw const CryptoException('Public key must be 32 bytes');
    }
    return PublicIdentity.internal(
      publicKey: publicKey,
      hash: IdentityHash(await _hasher.hash(publicKey)),
    );
  }

  @override
  Future<Uint8List> sha256(List<int> data) => _hasher.hash(data);

  @override
  Future<ConversationKey> conversationKey(PublicIdentity peer) async {
    final own = await _requireIdentity();
    if (own == peer) {
      throw const CryptoException('Cannot derive a key with yourself');
    }
    final secret = await _agreement.deriveSharedKey(
      ownKeyPair: _keyPair!,
      ownPublicKey: own.publicKey,
      peerPublicKey: peer.publicKey,
    );
    return _ConversationKey(peer.hash, secret);
  }

  @override
  Future<String> verificationCode(PublicIdentity peer) async {
    final own = await _requireIdentity();
    final digest = await _hasher.hash([
      ..._verifyLabel,
      ...X25519KeyAgreement.sortedConcat(own.publicKey, peer.publicKey),
    ]);
    final value = ByteData.sublistView(digest, 0, 4).getUint32(0) % 1000000;
    return value.toString().padLeft(6, '0');
  }

  @override
  Future<Uint8List> encrypt(
    ConversationKey key,
    String plaintext, {
    List<int> associatedData = const [],
  }) => _aead.seal(
    _secretOf(key),
    utf8.encode(plaintext),
    associatedData: associatedData,
  );

  @override
  Future<String> decrypt(
    ConversationKey key,
    Uint8List envelope, {
    List<int> associatedData = const [],
  }) async {
    final clear = await _aead.open(
      _secretOf(key),
      envelope,
      associatedData: associatedData,
    );
    try {
      return utf8.decode(clear);
    } on FormatException {
      throw const CryptoException('Decrypted message is not valid UTF-8');
    }
  }

  Future<PublicIdentity> _requireIdentity() async {
    final identity = await loadIdentity();
    if (identity == null) {
      throw const CryptoException('No identity on this device');
    }
    return identity;
  }

  SecretKey _secretOf(ConversationKey key) {
    if (key is! _ConversationKey) {
      throw const CryptoException('Unknown conversation key');
    }
    return key._secret;
  }
}

final class _ConversationKey implements ConversationKey {
  _ConversationKey(this.peer, this._secret);

  @override
  final IdentityHash peer;

  final SecretKey _secret;

  @override
  String toString() => 'ConversationKey(peer: ${peer.hex})';
}
