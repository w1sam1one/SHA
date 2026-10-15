import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

void main() {
  test('pads to fixed buckets and round-trips', () {
    for (final length in [
      0,
      1,
      255,
      256,
      1023,
      5000,
      MessagePadding.maxPayload,
    ]) {
      final data = List.generate(length, (i) => (i * 7 + 1) % 256);
      final padded = MessagePadding.pad(data);
      expect(MessagePadding.buckets, contains(padded.length));
      expect(MessagePadding.unpad(padded), data, reason: 'length $length');
    }
  });

  test('short and medium messages share a size', () {
    expect(
      MessagePadding.pad([1]).length,
      MessagePadding.pad(List.filled(200, 1)).length,
    );
  });

  test('rejects oversized payloads and malformed padding', () {
    expect(
      () => MessagePadding.pad(List.filled(MessagePadding.maxPayload + 1, 0)),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => MessagePadding.unpad(List.filled(256, 0)),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => MessagePadding.unpad(List.filled(255, 0)),
      throwsA(isA<CryptoException>()),
    );
  });
}
