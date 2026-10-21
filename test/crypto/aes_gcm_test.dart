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

  test('round-trips with nonce || ciphertext || tag layout', () async {
    final data = await aead.encrypt(key, message);
    expect(data.length, message.length + Aes256Gcm.overhead);
    expect(await aead.decrypt(key, data), message);
  });

  test('uses a fresh nonce for every message', () async {
    final nonces = <String>{};
    for (var i = 0; i < 2000; i++) {
      final data = await aead.encrypt(key, message);
      nonces.add(base64Encode(data.sublist(0, Aes256Gcm.nonceLength)));
    }
    expect(nonces, hasLength(2000));
  });

  test('rejects tampered nonce, ciphertext and tag', () async {
    final data = await aead.encrypt(key, message);
    for (final index in [0, 12, data.length - 1]) {
      final tampered = Uint8List.fromList(data)..[index] ^= 0x01;
      expect(
        () => aead.decrypt(key, tampered),
        throwsA(isA<CryptoException>()),
        reason: 'byte $index',
      );
    }
  });

  test('rejects the wrong key and wrong associated data', () async {
    final data = await aead.encrypt(key, message, associatedData: [1, 2, 3]);
    expect(
      () => aead.decrypt(
        SecretKey(List.filled(32, 7)),
        data,
        associatedData: [1, 2, 3],
      ),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => aead.decrypt(key, data, associatedData: [1, 2, 4]),
      throwsA(isA<CryptoException>()),
    );
  });

  test('rejects short input and non-256-bit keys', () async {
    expect(
      () => aead.decrypt(key, Uint8List(Aes256Gcm.overhead - 1)),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => aead.encrypt(SecretKey(List.filled(16, 1)), message),
      throwsA(anything),
    );
  });

  test('matches the package cipher at the documented offsets', () async {
    final data = await aead.encrypt(key, message, associatedData: [9]);
    final box = SecretBox(
      data.sublist(12, data.length - 16),
      nonce: data.sublist(0, 12),
      mac: Mac(data.sublist(data.length - 16)),
    );
    expect(
      await AesGcm.with256bits().decrypt(box, secretKey: key, aad: [9]),
      message,
    );
  });
}
