import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/qr/contact_code.dart';

import '../support/in_memory_vault.dart';

/// The code format of 0004 §1. The Olm keys here are just 32 bytes each:
/// the format does not need the native library.
void main() {
  late PublicIdentity addressing;
  final bundle = OlmContactBundle(
    identityKey: List.generate(32, (i) => i),
    oneTimeKey: List.generate(32, (i) => 100 + i),
  );

  setUp(() async {
    addressing = await ShaCryptoService(vault: InMemoryVault())
        .createIdentity();
  });

  test(
    'shaid:2 round-trips the bundle and the addressing key, 136 characters',
    () {
      final code = ContactCode.encode(bundle, addressing);
      expect(code, startsWith('shaid:2:'));
      expect(code, hasLength(136));
      final parsed = ContactCode.parse(code);
      expect(parsed.bundle.identityKey, bundle.identityKey);
      expect(parsed.bundle.oneTimeKey, bundle.oneTimeKey);
      expect(parsed.addressingKey, addressing);
    },
  );

  test('a shaid:1 code asks the contact to update the app', () {
    expect(
      () => ContactCode.parse('shaid:1:${addressing.hash.hex}:AAAA'),
      throwsA(
        isA<ContactCodeException>().having(
          (e) => e.message,
          'message',
          'Koden kommer från en äldre version av SHA. Be din kontakt '
              'uppdatera appen.',
        ),
      ),
    );
  });

  test('rejects foreign, damaged and oversized codes', () {
    final good = ContactCode.encode(bundle, addressing);
    String withBytes(int n) =>
        'shaid:2:${base64Url.encode(Uint8List(n)).replaceAll('=', '')}';
    for (final raw in [
      'https://example.com',
      'shaid:3:AAAA',
      withBytes(95),
      withBytes(97),
      'shaid:2:!!!',
      '$good:extra',
      '$good${'A' * 30}',
    ]) {
      expect(
        () => ContactCode.parse(raw),
        throwsA(isA<ContactCodeException>()),
        reason: raw,
      );
    }
  });
}
