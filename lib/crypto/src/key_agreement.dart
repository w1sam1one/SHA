import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'types.dart';

/// X25519 key agreement followed by HKDF-SHA256, producing one AES-256 key
/// per pair of identities.
final class X25519KeyAgreement {
  X25519KeyAgreement();

  static final List<int> _info = utf8.encode('SHA/v1/conversation-key');

  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  /// Rebuilds a key pair from its 32-byte private key.
  Future<SimpleKeyPair> keyPairFromPrivateKey(List<int> privateKey) {
    if (privateKey.length != 32) {
      throw const CryptoException('X25519 private key must be 32 bytes');
    }
    return _x25519.newKeyPairFromSeed(privateKey);
  }

  /// Derives the shared AES-256 key between [ownKeyPair] and [peerPublicKey].
  ///
  /// Both sides compute the same key: the HKDF salt is the two public keys in
  /// sorted order, so the result does not depend on who calls first.
  Future<SecretKey> deriveSharedKey({
    required SimpleKeyPair ownKeyPair,
    required List<int> ownPublicKey,
    required List<int> peerPublicKey,
  }) async {
    if (peerPublicKey.length != publicKeyLength) {
      throw const CryptoException('X25519 public key must be 32 bytes');
    }
    final shared = await _x25519.sharedSecretKey(
      keyPair: ownKeyPair,
      remotePublicKey: SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
    );
    // An all-zero result means the peer sent a low-order point (RFC 7748 §6.1).
    // extractBytes() may return the key's own buffer, so it is only read here.
    final sharedBytes = await shared.extractBytes();
    if (sharedBytes.every((b) => b == 0)) {
      throw const CryptoException('Invalid peer public key');
    }
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: sortedConcat(ownPublicKey, peerPublicKey),
      info: _info,
    );
  }

  /// `min(a, b) || max(a, b)` in lexicographic byte order.
  static Uint8List sortedConcat(List<int> a, List<int> b) {
    final first = compareBytes(a, b) <= 0 ? a : b;
    final second = identical(first, a) ? b : a;
    return Uint8List.fromList([...first, ...second]);
  }

  static int compareBytes(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
