import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

import '../support/in_memory_key_storage.dart';

void main() {
  group('identity', () {
    test(
      'first launch has no identity; create stores only the private key',
      () async {
        final storage = InMemoryKeyStorage();
        final crypto = ShaCryptoService(storage: storage);
        expect(await crypto.loadIdentity(), isNull);

        final identity = await crypto.createIdentity();
        expect(storage.values.keys, [ShaCryptoService.identityKeyName]);
        expect(storage.values.values.single, hasLength(32));
        expect(identity.publicKey, hasLength(32));
        expect(
          identity.hash.bytes,
          await crypto.sha256(identity.publicKey),
          reason: 'identity hash is SHA-256 of the public key',
        );
      },
    );

    test('identity survives a restart', () async {
      final storage = InMemoryKeyStorage();
      final created = await ShaCryptoService(storage: storage).createIdentity();
      final loaded = await ShaCryptoService(storage: storage).loadIdentity();
      expect(loaded, created);
      expect(loaded!.publicKey, created.publicKey);
    });

    test('never overwrites an existing identity', () async {
      final storage = InMemoryKeyStorage();
      await ShaCryptoService(storage: storage).createIdentity();
      expect(
        () => ShaCryptoService(storage: storage).createIdentity(),
        throwsA(isA<CryptoException>()),
      );
    });

    test('identityFromPublicKey validates length', () async {
      final crypto = ShaCryptoService(storage: InMemoryKeyStorage());
      expect(
        () => crypto.identityFromPublicKey(List.filled(31, 1)),
        throwsA(isA<CryptoException>()),
      );
    });

    test('SHA-256 matches the FIPS 180-2 test vector', () async {
      final crypto = ShaCryptoService(storage: InMemoryKeyStorage());
      final digest = await crypto.sha256(utf8.encode('abc'));
      expect(
        IdentityHash(digest).hex,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('two people', () {
    late ShaCryptoService alice;
    late ShaCryptoService bob;
    late PublicIdentity aliceId;
    late PublicIdentity bobId;

    setUp(() async {
      alice = ShaCryptoService(storage: InMemoryKeyStorage());
      bob = ShaCryptoService(storage: InMemoryKeyStorage());
      aliceId = await alice.createIdentity();
      bobId = await bob.createIdentity();
    });

    test('derive the same key: Alice encrypts, Bob decrypts', () async {
      final aliceKey = await alice.conversationKey(bobId);
      final bobKey = await bob.conversationKey(aliceId);
      final ad = utf8.encode('header');
      final envelope = await alice.encrypt(
        aliceKey,
        'Ses i morgon?',
        associatedData: ad,
      );
      expect(
        await bob.decrypt(bobKey, envelope, associatedData: ad),
        'Ses i morgon?',
      );
    });

    test('see the same verification code', () async {
      final a = await alice.verificationCode(bobId);
      final b = await bob.verificationCode(aliceId);
      expect(a, b);
      expect(a, matches(RegExp(r'^\d{6}$')));
    });

    test('a third party cannot decrypt', () async {
      final eve = ShaCryptoService(storage: InMemoryKeyStorage());
      await eve.createIdentity();
      final eveKey = await eve.conversationKey(bobId);
      final envelope = await alice.encrypt(
        await alice.conversationKey(bobId),
        'hemligt',
      );
      expect(
        () => eve.decrypt(eveKey, envelope),
        throwsA(isA<CryptoException>()),
      );
    });

    test('rejects key handles not created by the crypto module', () async {
      final forged = _ForgedKey(bobId.hash);
      expect(() => alice.encrypt(forged, 'x'), throwsA(isA<CryptoException>()));
    });

    test('rejects a low-order peer key', () async {
      final zero = await alice.identityFromPublicKey(Uint8List(32));
      expect(
        () => alice.conversationKey(zero),
        throwsA(isA<CryptoException>()),
      );
    });

    test('cannot derive a key with yourself', () async {
      expect(
        () => alice.conversationKey(aliceId),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  test('string forms never contain secret material', () async {
    final storage = InMemoryKeyStorage();
    final crypto = ShaCryptoService(storage: storage);
    await crypto.createIdentity();
    final peer = ShaCryptoService(storage: InMemoryKeyStorage());
    final key = await crypto.conversationKey(await peer.createIdentity());
    final privateHex = storage.values.values.single
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(key.toString(), isNot(contains(privateHex)));
    expect(key.toString(), startsWith('ConversationKey(peer: '));
    expect(const CryptoException('x').toString(), 'CryptoException: x');
  });
}

class _ForgedKey implements ConversationKey {
  _ForgedKey(this.peer);

  @override
  final IdentityHash peer;
}
