import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'types.dart';
import 'wipe.dart';

/// Keys for one conversation, all derived from a single X25519 secret.
final class SessionSecrets {
  SessionSecrets({
    required this.sendKey,
    required this.receiveKey,
    required this.sendMailboxKey,
    required this.receiveMailboxKey,
  });

  final SecretKeyData sendKey;
  final SecretKeyData receiveKey;
  final SecretKeyData sendMailboxKey;
  final SecretKeyData receiveMailboxKey;

  void destroy() {
    sendKey.destroy();
    receiveKey.destroy();
    sendMailboxKey.destroy();
    receiveMailboxKey.destroy();
  }
}

/// X25519 followed by HKDF-SHA256.
///
///     shared = X25519(own private, peer public)
///     salt   = min(pkA, pkB) || max(pkA, pkB)
///     key    = HKDF(shared, salt, "SHA/v2/<purpose>/<direction>")
///
/// "L2H" is the direction from the lexicographically lower public key to the
/// higher one. Both people compute the same four keys; one person's send key
/// is the other's receive key.
final class X25519KeyAgreement {
  X25519KeyAgreement();

  final X25519 _x25519 = X25519();

  /// Public key for a 32-byte private key (clamped per RFC 7748).
  Future<Uint8List> publicKeyOf(Uint8List privateKey) async {
    if (privateKey.length != 32) {
      throw const CryptoException('X25519 private key must be 32 bytes');
    }
    final pair = await _x25519.newKeyPairFromSeed(privateKey);
    final publicKey = await pair.extractPublicKey();
    pair.destroy();
    return Uint8List.fromList(publicKey.bytes);
  }

  Future<SessionSecrets> derive({
    required Uint8List ownPrivateKey,
    required List<int> ownPublicKey,
    required List<int> peerPublicKey,
  }) async {
    if (peerPublicKey.length != publicKeyLength) {
      throw const CryptoException('X25519 public key must be 32 bytes');
    }
    final order = compareBytes(ownPublicKey, peerPublicKey);
    if (order == 0) {
      throw const CryptoException('Cannot derive keys with yourself');
    }
    final pair = SimpleKeyPairData(
      ownPrivateKey,
      publicKey: SimplePublicKey(ownPublicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final shared = await takeKey(
      await _x25519.sharedSecretKey(
        keyPair: pair,
        remotePublicKey: SimplePublicKey(
          peerPublicKey,
          type: KeyPairType.x25519,
        ),
      ),
    );
    try {
      // All-zero output means the peer sent a low-order point (RFC 7748 §6.1).
      if (shared.bytes.every((b) => b == 0)) {
        throw const CryptoException('Invalid peer public key');
      }
      final salt = sortedConcat(ownPublicKey, peerPublicKey);
      final ownIsLow = order < 0;
      final out = ownIsLow ? 'L2H' : 'H2L';
      final into = ownIsLow ? 'H2L' : 'L2H';
      Future<SecretKeyData> expand(String purpose, String direction) async =>
          takeKey(
            await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
              secretKey: shared,
              nonce: salt,
              info: utf8.encode('SHA/v2/$purpose/$direction'),
            ),
          );
      return SessionSecrets(
        sendKey: await expand('message-key', out),
        receiveKey: await expand('message-key', into),
        sendMailboxKey: await expand('mailbox-key', out),
        receiveMailboxKey: await expand('mailbox-key', into),
      );
    } finally {
      shared.destroy();
    }
  }

  /// `min(a, b) || max(a, b)` in lexicographic byte order.
  static Uint8List sortedConcat(List<int> a, List<int> b) {
    final aFirst = compareBytes(a, b) <= 0;
    return Uint8List.fromList(aFirst ? [...a, ...b] : [...b, ...a]);
  }

  static int compareBytes(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
