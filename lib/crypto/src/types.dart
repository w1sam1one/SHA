import 'dart:typed_data';

/// Length in bytes of an X25519 public key and of a SHA-256 digest.
const int publicKeyLength = 32;
const int identityHashLength = 32;

/// Thrown for every failure inside the crypto module.
///
/// Messages are fixed strings: they never contain key material, plaintext,
/// nonces or ciphertext, so they are safe to show or report.
final class CryptoException implements Exception {
  const CryptoException(this.message);

  final String message;

  @override
  String toString() => 'CryptoException: $message';
}

/// SHA-256 of a public identity key. Public by definition — safe to display,
/// share and put in QR codes.
final class IdentityHash {
  IdentityHash(List<int> bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.length != identityHashLength) {
      throw const CryptoException('Identity hash must be 32 bytes');
    }
  }

  /// Parses a 64-character hex string (case-insensitive).
  factory IdentityHash.fromHex(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw const CryptoException('Identity hash must be 64 hex characters');
    }
    return IdentityHash([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  final Uint8List bytes;

  /// Lower-case hex, 64 characters.
  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  bool operator ==(Object other) {
    if (other is! IdentityHash) return false;
    for (var i = 0; i < identityHashLength; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'IdentityHash($hex)';
}

/// The public half of an identity: an X25519 public key plus its SHA-256
/// identity hash. Contains no secret material.
final class PublicIdentity {
  /// Use [CryptoService.identityFromPublicKey] to build one: it validates the
  /// key and computes the hash.
  PublicIdentity.internal({required List<int> publicKey, required this.hash})
    : publicKey = Uint8List.fromList(publicKey).asUnmodifiableView();

  final Uint8List publicKey;
  final IdentityHash hash;

  @override
  bool operator ==(Object other) =>
      other is PublicIdentity && other.hash == hash;

  @override
  int get hashCode => hash.hashCode;

  @override
  String toString() => 'PublicIdentity(${hash.hex})';
}

/// Opaque handle to a symmetric AES-256 key shared with one peer.
///
/// The key bytes never leave the crypto module: callers can only pass the
/// handle back to the [CryptoService] that created it.
abstract interface class ConversationKey {
  /// Identity hash of the peer this key is shared with.
  IdentityHash get peer;
}
