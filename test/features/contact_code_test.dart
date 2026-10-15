import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/qr/contact_code.dart';

import '../support/in_memory_vault.dart';

void main() {
  late PublicIdentity identity;

  setUp(() async {
    identity = await ShaCryptoService(vault: InMemoryVault()).createIdentity();
  });

  test('round-trips', () {
    final code = ContactCode.encode(identity);
    expect(code, startsWith('shaid:1:${identity.hash.hex}:'));
    final parsed = ContactCode.parse(code);
    expect(parsed, identity);
    expect(parsed.publicKey, identity.publicKey);
  });

  test('rejects a hash that does not match the key', () async {
    final other = await ShaCryptoService(vault: InMemoryVault())
        .createIdentity();
    final parts = ContactCode.encode(identity).split(':');
    parts[2] = other.hash.hex;
    expect(
      () => ContactCode.parse(parts.join(':')),
      throwsA(isA<ContactCodeException>()),
    );
  });

  test('rejects foreign, malformed or oversized codes', () {
    for (final raw in [
      'https://example.com',
      'shaid:2:${identity.hash.hex}:AAAA',
      'shaid:1:nothex:AAAA',
      'shaid:1:${identity.hash.hex}:!!!',
      'shaid:1:${identity.hash.hex}:AAAA',
      '${ContactCode.encode(identity)}${'A' * 200}',
    ]) {
      expect(
        () => ContactCode.parse(raw),
        throwsA(isA<ContactCodeException>()),
        reason: raw,
      );
    }
  });
}
