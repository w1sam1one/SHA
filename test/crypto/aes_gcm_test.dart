import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/crypto/src/aes_gcm.dart';

void main() {
  final aead = Aes256Gcm();
  final key = SecretKey(List.generate(32, (i) => i));
  final message = utf8.encode('Hej från SHA');

  test('round-trips and uses the documented envelope layout', () async {
    final envelope = await aead.seal(key, message);
    expect(envelope.length, message.length + Aes256Gcm.overhead);
    expect(envelope[0], Aes256Gcm.envelopeVersion);
    expect(await aead.open(key, envelope), message);
  });

  test('uses a fresh nonce for every message', () async {
    final nonces = <String>{};
    for (var i = 0; i < 2000; i++) {
      final envelope = await aead.seal(key, message);
      nonces.add(base64Encode(envelope.sublist(1, 1 + Aes256Gcm.nonceLength)));
    }
    expect(nonces, hasLength(2000));
  });

  test('same plaintext encrypts to different ciphertexts', () async {
    final a = await aead.seal(key, message);
    final b = await aead.seal(key, message);
    expect(a, isNot(equals(b)));
  });

  test('rejects tampered ciphertext, nonce and tag', () async {
    final envelope = await aead.seal(key, message);
    for (final index in [1, 13, envelope.length - 1]) {
      final tampered = Uint8List.fromList(envelope)..[index] ^= 0x01;
      expect(
        () => aead.open(key, tampered),
        throwsA(isA<CryptoException>()),
        reason: 'byte $index',
      );
    }
  });

  test('rejects the wrong key', () async {
    final envelope = await aead.seal(key, message);
    final other = SecretKey(List.filled(32, 7));
    expect(() => aead.open(other, envelope), throwsA(isA<CryptoException>()));
  });

  test('binds associated data', () async {
    final envelope = await aead.seal(key, message, associatedData: [1, 2, 3]);
    expect(await aead.open(key, envelope, associatedData: [1, 2, 3]), message);
    expect(
      () => aead.open(key, envelope, associatedData: [1, 2, 4]),
      throwsA(isA<CryptoException>()),
    );
  });

  test('rejects short envelopes and unknown versions', () async {
    expect(
      () => aead.open(key, Uint8List(Aes256Gcm.overhead - 1)),
      throwsA(isA<CryptoException>()),
    );
    final envelope = await aead.seal(key, message);
    envelope[0] = 99;
    expect(() => aead.open(key, envelope), throwsA(isA<CryptoException>()));
  });

  test('refuses keys that are not 256 bits', () async {
    final short = SecretKey(List.filled(16, 1));
    expect(() => aead.seal(short, message), throwsA(anything));
  });

  test('matches an independent AES-256-GCM implementation', () async {
    // Decrypt our envelope with the package's cipher directly, using the
    // nonce and tag from the documented byte offsets.
    final envelope = await aead.seal(key, message, associatedData: [9]);
    final box = SecretBox(
      envelope.sublist(13, envelope.length - 16),
      nonce: envelope.sublist(1, 13),
      mac: Mac(envelope.sublist(envelope.length - 16)),
    );
    final clear = await AesGcm.with256bits().decrypt(
      box,
      secretKey: key,
      aad: [9],
    );
    expect(clear, message);
  });
}
