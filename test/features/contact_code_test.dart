import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/qr/contact_code.dart';

import '../support/in_memory_key_storage.dart';

void main() {
  late CryptoService crypto;
  late PublicIdentity identity;

  setUp(() async {
    crypto = ShaCryptoService(storage: InMemoryKeyStorage());
    identity = await crypto.createIdentity();
  });

  test('round-trips', () async {
    final code = ContactCode.encode(identity);
    expect(code, startsWith('shaid:1:${identity.hash.hex}:'));
    final parsed = await ContactCode.parse(code, crypto);
    expect(parsed, identity);
    expect(parsed.publicKey, identity.publicKey);
  });

  test('rejects a hash that does not match the key', () async {
    final other = await ShaCryptoService(storage: InMemoryKeyStorage())
        .createIdentity();
    final parts = ContactCode.encode(identity).split(':');
    parts[2] = other.hash.hex;
    expect(
      () => ContactCode.parse(parts.join(':'), crypto),
      throwsA(isA<ContactCodeException>()),
    );
  });

  test('rejects foreign or malformed codes', () async {
    for (final raw in [
      'https://example.com',
      'shaid:2:${identity.hash.hex}:AAAA',
      'shaid:1:nothex:AAAA',
      'shaid:1:${identity.hash.hex}:!!!',
      'shaid:1:${identity.hash.hex}:AAAA',
    ]) {
      expect(
        () => ContactCode.parse(raw, crypto),
        throwsA(isA<ContactCodeException>()),
        reason: raw,
      );
    }
  });
}
