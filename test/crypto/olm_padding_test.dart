// 0004 §4 (A): the text inside an Olm message is padded with spaces to
// exactly B − 1 bytes of UTF-8, where B is the bucket. No native library.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

int bytesOf(String s) => utf8.encode(s).length;

void main() {
  test('the buckets are the same five sizes as today', () {
    expect(OlmPadding.buckets, MessagePadding.buckets);
    expect(OlmPadding.maxBytes, 65535);
  });

  test('pads to exactly B − 1 bytes, for every bucket', () {
    var previous = 0;
    for (final b in OlmPadding.buckets) {
      // The smallest text in this bucket, and the two largest.
      for (final n in [previous, b - 2, b - 1]) {
        final text = 'x' * n;
        final padded = OlmPadding.pad(text);
        expect(bytesOf(padded), b - 1, reason: 'B=$b, n=$n');
        expect(padded, startsWith(text));
        expect(padded.substring(text.length).trim(), isEmpty);
      }
      previous = b;
    }
  });

  test('text of exactly B − 1 bytes stays in B, B bytes goes to the next', () {
    expect(bytesOf(OlmPadding.pad('a' * 255)), 255);
    expect(bytesOf(OlmPadding.pad('a' * 256)), 1023);
    expect(bytesOf(OlmPadding.pad('a' * 1023)), 1023);
    expect(bytesOf(OlmPadding.pad('a' * 1024)), 4095);
    expect(bytesOf(OlmPadding.pad('')), 255);
  });

  test('counts bytes, not characters: å and emoji near the limit', () {
    // å is 2 bytes and 😀 is 4 bytes in UTF-8.
    final at = 'å' * 127; // 254 bytes
    expect(bytesOf(OlmPadding.pad(at)), 255);
    final over = '${'a' * 252}😀'; // 256 bytes, 253 code units
    expect(bytesOf(OlmPadding.pad(over)), 1023);
    final exact = '${'a' * 251}😀'; // 255 bytes
    expect(bytesOf(OlmPadding.pad(exact)), 255);
  });

  test('the largest text fits and one byte more is refused', () {
    expect(bytesOf(OlmPadding.pad('a' * 65535)), 65535);
    expect(() => OlmPadding.pad('a' * 65536), throwsA(isA<CryptoException>()));
    expect(
      () => OlmPadding.pad('${'a' * 65532}😀'),
      throwsA(isA<CryptoException>()),
    );
  });

  test('unpad gives the text back, also with å and emoji', () {
    for (final text in [
      '',
      'hej',
      '{"v":3,"m":"å ä ö 😀"}',
      'å' * 127,
      '${'a' * 251}😀',
      'a' * 65535,
    ]) {
      expect(OlmPadding.unpad(OlmPadding.pad(text)), text);
    }
  });

  test('a padded JSON payload is still valid JSON', () {
    final json = jsonEncode({'v': 3, 'm': 'å 😀'});
    expect(jsonDecode(OlmPadding.pad(json)), {'v': 3, 'm': 'å 😀'});
  });

  test('unpad only removes spaces at the end', () {
    expect(OlmPadding.unpad('a b  '), 'a b');
    expect(OlmPadding.unpad(' a\n'), ' a\n');
    expect(OlmPadding.unpad('a\t '), 'a\t');
  });
}
