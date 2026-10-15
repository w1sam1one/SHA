import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'types.dart';

/// AES-256-GCM with a sealed-envelope format:
///
///     version (1 byte) || nonce (12 bytes) || ciphertext || GCM tag (16 bytes)
///
/// A fresh 96-bit nonce is drawn from a CSPRNG for every [seal] call. There is
/// deliberately no way for a caller to supply a nonce, so a nonce can never be
/// reused by mistake.
///
/// Random 96-bit nonces stay safe for up to 2^32 messages per key (NIST
/// SP 800-38D §8.3); keys must be rotated well before that.
final class Aes256Gcm {
  Aes256Gcm();

  static const int envelopeVersion = 1;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int overhead = 1 + nonceLength + tagLength;

  final AesGcm _algorithm = AesGcm.with256bits(nonceLength: nonceLength);

  /// Encrypts [plaintext] and returns the envelope. [associatedData] is
  /// authenticated but not encrypted; the same bytes must be given to [open].
  Future<Uint8List> seal(
    SecretKey key,
    List<int> plaintext, {
    List<int> associatedData = const [],
  }) async {
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: associatedData,
    );
    return Uint8List.fromList([envelopeVersion, ...box.concatenation()]);
  }

  /// Verifies and decrypts an envelope produced by [seal]. Throws
  /// [CryptoException] if the envelope, key or associated data do not match.
  Future<List<int>> open(
    SecretKey key,
    Uint8List envelope, {
    List<int> associatedData = const [],
  }) async {
    if (envelope.length < overhead) {
      throw const CryptoException('Envelope too short');
    }
    if (envelope[0] != envelopeVersion) {
      throw const CryptoException('Unsupported envelope version');
    }
    final box = SecretBox.fromConcatenation(
      Uint8List.sublistView(envelope, 1),
      nonceLength: nonceLength,
      macLength: tagLength,
      copy: true,
    );
    try {
      return await _algorithm.decrypt(box, secretKey: key, aad: associatedData);
    } on SecretBoxAuthenticationError {
      throw const CryptoException('Message authentication failed');
    }
  }
}
