import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'types.dart';

/// AES-256-GCM producing `nonce (12) || ciphertext || tag (16)`.
///
/// A fresh 96-bit nonce is drawn from the OS CSPRNG (`Random.secure`) on every
/// [encrypt] call. There is deliberately no way to pass a nonce in, so one can
/// never be reused by mistake. Random 96-bit nonces are safe for up to 2^32
/// messages per key (NIST SP 800-38D §8.3); every direction of every
/// conversation has its own key.
final class Aes256Gcm {
  Aes256Gcm();

  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int overhead = nonceLength + tagLength;

  final AesGcm _algorithm = AesGcm.with256bits(nonceLength: nonceLength);

  Future<Uint8List> encrypt(
    SecretKey key,
    List<int> plaintext, {
    List<int> associatedData = const [],
  }) async {
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: _algorithm.newNonce(),
      aad: associatedData,
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Throws [CryptoException] unless key, data and associated data match.
  Future<Uint8List> decrypt(
    SecretKey key,
    List<int> data, {
    List<int> associatedData = const [],
  }) async {
    if (data.length < overhead) {
      throw const CryptoException(
        'Ciphertext too short',
        CryptoErrorKind.corrupt,
      );
    }
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: nonceLength,
      macLength: tagLength,
      copy: true,
    );
    try {
      final clear = await _algorithm.decrypt(
        box,
        secretKey: key,
        aad: associatedData,
      );
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const CryptoException(
        'Message authentication failed',
        CryptoErrorKind.corrupt,
      );
    }
  }
}
