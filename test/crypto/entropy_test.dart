import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/crypto/src/entropy.dart';

class _Fixed implements EntropySource {
  _Fixed(this.byteFor);

  final int Function(int index) byteFor;

  @override
  Future<Uint8List> randomBytes(int length) async =>
      Uint8List.fromList(List.generate(length, byteFor));
}

void main() {
  test('output depends on both sources', () async {
    final platform = _Fixed((i) => i);
    final a = await MixedEntropy(
      platform: platform,
      local: _Fixed((i) => i * 3 + 1),
    ).bytes(32, purpose: 't');
    final b = await MixedEntropy(
      platform: platform,
      local: _Fixed((i) => i * 5 + 2),
    ).bytes(32, purpose: 't');
    expect(a, hasLength(32));
    expect(a, isNot(equals(b)));
  });

  test('purposes are domain-separated', () async {
    final mixed = MixedEntropy(
      platform: _Fixed((i) => i),
      local: _Fixed((i) => i + 9),
    );
    expect(
      await mixed.bytes(32, purpose: 'a'),
      isNot(equals(await mixed.bytes(32, purpose: 'b'))),
    );
  });

  test('refuses a stuck source or two identical sources', () async {
    final stuck = MixedEntropy(
      platform: _Fixed((_) => 0),
      local: _Fixed((i) => i),
    );
    expect(
      () => stuck.bytes(32, purpose: 't'),
      throwsA(
        isA<CryptoException>().having(
          (e) => e.kind,
          'kind',
          CryptoErrorKind.entropy,
        ),
      ),
    );
    final same = MixedEntropy(
      platform: _Fixed((i) => i),
      local: _Fixed((i) => i),
    );
    expect(() => same.bytes(32, purpose: 't'), throwsA(isA<CryptoException>()));
  });
}
