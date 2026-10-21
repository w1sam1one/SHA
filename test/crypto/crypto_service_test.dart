import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

import '../support/in_memory_vault.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);

  group('identity', () {
    test('create stores the private key only in the vault', () async {
      final vault = InMemoryVault();
      final crypto = ShaCryptoService(vault: vault);
      expect(await crypto.loadIdentity(), isNull);

      final identity = await crypto.createIdentity();
      expect(vault.values.keys, {
        ShaCryptoService.privateKeyName,
        ShaCryptoService.publicKeyName,
      });
      expect(vault.values[ShaCryptoService.privateKeyName], hasLength(32));
      expect(vault.values[ShaCryptoService.publicKeyName], identity.publicKey);
      expect(identity.hash.bytes, await crypto.sha256(identity.publicKey));
    });

    test('survives a restart and never overwrites', () async {
      final vault = InMemoryVault();
      final created = await ShaCryptoService(vault: vault).createIdentity();
      final again = ShaCryptoService(vault: vault);
      expect(await again.loadIdentity(), created);
      expect(() => again.createIdentity(), throwsA(isA<CryptoException>()));
    });

    test(
      'recovers the public key if only the private key was written',
      () async {
        final vault = InMemoryVault();
        final created = await ShaCryptoService(vault: vault).createIdentity();
        vault.values.remove(ShaCryptoService.publicKeyName);
        expect(await ShaCryptoService(vault: vault).loadIdentity(), created);
      },
    );

    test('reset deletes the identity; a new one is unrelated', () async {
      final vault = InMemoryVault();
      final crypto = ShaCryptoService(vault: vault);
      final old = await crypto.createIdentity();

      await crypto.resetIdentity();
      expect(vault.values, isEmpty);
      expect(await crypto.loadIdentity(), isNull);

      final fresh = await crypto.createIdentity();
      expect(fresh.publicKey, isNot(equals(old.publicKey)));
      expect(await ShaCryptoService(vault: vault).loadIdentity(), fresh);
    });

    test('reset on an empty vault does nothing and does not throw', () async {
      final crypto = ShaCryptoService(vault: InMemoryVault());
      await crypto.resetIdentity();
      expect(await crypto.loadIdentity(), isNull);
    });

    test('reset waits for an in-flight create and then removes it', () async {
      final vault = InMemoryVault();
      final crypto = ShaCryptoService(vault: vault);
      final creating = crypto.createIdentity();
      await crypto.resetIdentity();
      await creating;
      expect(vault.values, isEmpty);
      expect(await crypto.loadIdentity(), isNull);
    });

    test('identity keys use the platform random source', () async {
      Uint8List broken(int n) => Uint8List(n);
      final crypto = ShaCryptoService(vault: InMemoryVault(random: broken));
      expect(
        () => crypto.createIdentity(),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.kind,
            'kind',
            CryptoErrorKind.entropy,
          ),
        ),
      );
    });

    test('PublicIdentity always matches its key', () {
      expect(
        () => PublicIdentity(List.filled(31, 1)),
        throwsA(isA<CryptoException>()),
      );
      final digest = PublicIdentity(
        utf8.encode('abcdefghijklmnopqrstuvwxyz012345'),
      );
      expect(digest.hash.hex, hasLength(64));
    });

    test('SHA-256 matches the FIPS 180-2 test vector', () async {
      final crypto = ShaCryptoService(vault: InMemoryVault());
      expect(
        IdentityHash(await crypto.sha256(utf8.encode('abc'))).hex,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('two people', () {
    late ShaCryptoService alice;
    late ShaCryptoService bob;
    late PublicIdentity aliceId;
    late PublicIdentity bobId;
    late ConversationKeys aliceKeys;
    late ConversationKeys bobKeys;

    setUp(() async {
      alice = ShaCryptoService(vault: InMemoryVault());
      bob = ShaCryptoService(vault: InMemoryVault());
      aliceId = await alice.createIdentity();
      bobId = await bob.createIdentity();
      aliceKeys = await alice.conversationKeys(bobId);
      bobKeys = await bob.conversationKeys(aliceId);
    });

    test('Alice seals, Bob opens, Alice can re-read her own message', () async {
      final packet = await alice.seal(
        aliceKeys,
        utf8.encode('Ses i morgon?'),
        now: now,
      );
      expect(
        utf8.decode(await bob.open(bobKeys, packet, MessageDirection.incoming)),
        'Ses i morgon?',
      );
      expect(
        utf8.decode(
          await alice.open(aliceKeys, packet, MessageDirection.outgoing),
        ),
        'Ses i morgon?',
      );
    });

    test('a packet reflected back to its sender is rejected', () async {
      final packet = await alice.seal(aliceKeys, utf8.encode('hej'), now: now);
      expect(
        () => alice.open(aliceKeys, packet, MessageDirection.incoming),
        throwsA(isA<CryptoException>()),
      );
    });

    test('packet reveals neither identity nor length', () async {
      final short = await alice.seal(aliceKeys, utf8.encode('ja'), now: now);
      final longer = await alice.seal(
        aliceKeys,
        List.filled(180, 65),
        now: now,
      );
      expect(short.length, longer.length);
      expect(WireFormat.packetSizes, contains(short.length));
      final hex = short.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      for (final secretish in [aliceId.hash.hex, bobId.hash.hex]) {
        expect(hex, isNot(contains(secretish.substring(0, 16))));
      }
    });

    test(
      'mailboxes match across the pair and rotate per day and direction',
      () async {
        final epoch = WireFormat.epochOf(now);
        final aliceOut = await alice.mailboxId(
          aliceKeys,
          MessageDirection.outgoing,
          epoch,
        );
        final bobIn = await bob.mailboxId(
          bobKeys,
          MessageDirection.incoming,
          epoch,
        );
        final bobOut = await bob.mailboxId(
          bobKeys,
          MessageDirection.outgoing,
          epoch,
        );
        final aliceOutTomorrow = await alice.mailboxId(
          aliceKeys,
          MessageDirection.outgoing,
          epoch + 1,
        );
        expect(aliceOut, hasLength(WireFormat.mailboxIdLength));
        expect(aliceOut, bobIn);
        expect(aliceOut, isNot(equals(bobOut)));
        expect(aliceOut, isNot(equals(aliceOutTomorrow)));

        final packet = await alice.seal(aliceKeys, [1], now: now);
        expect(WireFormat.mailboxIdOf(packet), aliceOut);
      },
    );

    test('changing the mailbox id breaks authentication', () async {
      final packet = await alice.seal(aliceKeys, [1, 2, 3], now: now);
      packet[1] ^= 0x01;
      expect(
        () => bob.open(bobKeys, packet, MessageDirection.incoming),
        throwsA(isA<CryptoException>()),
      );
    });

    test('a third party cannot decrypt', () async {
      final eve = ShaCryptoService(vault: InMemoryVault());
      await eve.createIdentity();
      final eveKeys = await eve.conversationKeys(bobId);
      final packet = await alice.seal(
        aliceKeys,
        utf8.encode('hemligt'),
        now: now,
      );
      expect(
        () => eve.open(eveKeys, packet, MessageDirection.incoming),
        throwsA(isA<CryptoException>()),
      );
    });

    test('see the same 20-digit verification code', () async {
      final code = await alice.verificationCode(bobId);
      expect(code, await bob.verificationCode(aliceId));
      expect(code, matches(RegExp(r'^\d{20}$')));
    });

    test('forgotten keys cannot be used', () async {
      alice.forget(aliceKeys);
      expect(() => alice.seal(aliceKeys, [1], now: now), throwsA(anything));
    });

    test('rejects forged handles, low-order keys and yourself', () async {
      expect(
        () => alice.seal(_ForgedKeys(bobId.hash), [1], now: now),
        throwsA(isA<CryptoException>()),
      );
      expect(
        () => alice.conversationKeys(PublicIdentity(Uint8List(32))),
        throwsA(isA<CryptoException>()),
      );
      expect(
        () => alice.conversationKeys(aliceId),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  test('string forms never contain secret material', () async {
    final vault = InMemoryVault();
    final crypto = ShaCryptoService(vault: vault);
    await crypto.createIdentity();
    final peer = ShaCryptoService(vault: InMemoryVault());
    final keys = await crypto.conversationKeys(await peer.createIdentity());
    final privateHex = vault.values[ShaCryptoService.privateKeyName]!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(keys.toString(), isNot(contains(privateHex)));
    expect(keys.toString(), startsWith('ConversationKeys(peer: '));
    expect(
      const CryptoException('x', CryptoErrorKind.corrupt).toString(),
      'CryptoException(corrupt): x',
    );
  });
}

class _ForgedKeys implements ConversationKeys {
  _ForgedKeys(this.peer);

  @override
  final IdentityHash peer;
}
