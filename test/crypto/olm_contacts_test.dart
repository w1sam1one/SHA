// P4 in docs/ROADMAP.md: the contact from a meeting, and the session rule of
// 0006 (b) and (iii), against the app's own classes.
//
// The tests listed in 0006, "Om ägaren väljer (b) och (iii)", plus the
// one-time key rules of 0004 §8 and the verification code of 0004 §1. Needs
// the native library (tool/build_native_host.sh).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

import 'olm_service_cases.dart';

/// The session [me] would send on to [peer] now: the highest number
/// (0006 (b)), read from the saved state.
String chosenSessionId(Person me, Person peer) {
  final sessions = _sessions(me, peer)
    ..sort((a, b) => (b['number']! as int).compareTo(a['number']! as int));
  return sessions.first['id']! as String;
}

int sessionCount(Person me, Person peer) => _sessions(me, peer).length;

List<Map<String, Object?>> _sessions(Person me, Person peer) {
  final contacts = me.savedState['contacts']! as Map<String, Object?>;
  final c = contacts[base64.encode(peer.key)] as Map<String, Object?>?;
  return c == null
      ? []
      : (c['sessions']! as List).cast<Map<String, Object?>>().toList();
}

Uint8List addressingKeyFor(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

void main() {
  test('a contact is saved with its addressing key, name and meeting time, '
      'and survives a restart', () async {
    final alice = await Person().start();
    final bob = await Person().start();
    final metAt = DateTime.utc(2026, 11, 16, 12);
    final added = await alice.olm.addContact(
      bundle: await bob.olm.publishBundle(),
      addressingKey: addressingKeyFor(1),
      name: '  Bob  ',
      metAt: metAt,
    );
    expect(added.name, 'Bob');
    expect(added.identityKey, bob.key);
    expect(added.addressingKey, addressingKeyFor(1));
    expect(added.metAt, metAt);
    expect(added.id, hasLength(64));

    alice.restart();
    final saved = await alice.olm.contacts();
    expect(saved.map((c) => c.name), ['Bob']);
    expect(saved.single.id, added.id);
  });

  test('a known contact with a different addressing key is refused', () async {
    final alice = await Person().start();
    final bob = await Person().start();
    await alice.olm.addContact(
      bundle: await bob.olm.publishBundle(),
      addressingKey: addressingKeyFor(1),
      name: 'Bob',
      metAt: DateTime.utc(2026),
    );
    await expectLater(
      alice.olm.addContact(
        bundle: await bob.olm.publishBundle(),
        addressingKey: addressingKeyFor(2),
        name: 'Bob',
        metAt: DateTime.utc(2026),
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  test('the verification code is the same on both phones and changes with '
      'a key', () async {
    final alice = await Person().start();
    final bob = await Person().start();
    final carol = await Person().start();
    final ab = await alice.olm.verificationCode(bob.key);
    expect(ab, matches(RegExp(r'^\d{20}$')));
    expect(await bob.olm.verificationCode(alice.key), ab);
    expect(await alice.olm.verificationCode(carol.key), isNot(ab));
  });

  group('0006 (b): the session rule', () {
    test(
      'both scan and write at the same time for several rounds: nothing '
      'is lost, and after one read reply both pick the same session',
      () async {
        final alice = await Person().start();
        final bob = await Person().start();
        final aliceQr = await alice.olm.publishBundle();
        await alice.olm.startSession(await bob.olm.publishBundle());
        await bob.olm.startSession(aliceQr);

        for (var round = 0; round < 4; round++) {
          final a = await alice.olm.encrypt(bob.key, 'a$round');
          final b = await bob.olm.encrypt(alice.key, 'b$round');
          expect(await deliver(bob, alice, a), 'a$round');
          expect(await deliver(alice, bob, b), 'b$round');
        }
        // A message that is read before the other writes again.
        expect(
          await deliver(bob, alice, await alice.olm.encrypt(bob.key, 'sist')),
          'sist',
        );
        expect(
          await deliver(alice, bob, await bob.olm.encrypt(alice.key, 'svar')),
          'svar',
        );
        expect(chosenSessionId(alice, bob), chosenSessionId(bob, alice));
      },
    );

    test(
      'a dead outbound session is left as soon as the contact writes',
      () async {
        var now = DateTime.utc(2026, 11, 1);
        final alice = await Person(null, () => now).start();
        final bob = await Person(null, () => now).start();
        final aliceQr = await alice.olm.publishBundle();
        await alice.olm.startSession(await bob.olm.publishBundle());
        await bob.olm.startSession(aliceQr);

        // 31 days later Bob cleans up his unused key: Alice's session is dead.
        now = now.add(const Duration(days: 31));
        await bob.olm.publishBundle();
        final dead = await alice.olm.encrypt(bob.key, 'kommer aldrig fram');
        expect(
          (await bob.olm.receive(alice.key, dead.packet)).failure,
          OlmReceiveFailure.unreadable,
        );

        // Bob writes on his own session; Alice reads it and switches.
        final fromBob = await bob.olm.encrypt(alice.key, 'hej');
        expect(await deliver(alice, bob, fromBob), 'hej');
        final next = await alice.olm.encrypt(bob.key, 'nu går det');
        expect(await deliver(bob, alice, next), 'nu går det');
      },
    );

    test(
      'both sessions dead: a new scan is chosen at once and works',
      () async {
        var now = DateTime.utc(2026, 11, 1);
        final alice = await Person(null, () => now).start();
        final bob = await Person(null, () => now).start();
        final aliceQr = await alice.olm.publishBundle();
        await alice.olm.startSession(await bob.olm.publishBundle());
        await bob.olm.startSession(aliceQr);

        now = now.add(const Duration(days: 31));
        await scan(alice, bob); // Bob shows a new code; old keys are cleaned
        await alice.olm.publishBundle(); // Alice cleans hers
        final out = await alice.olm.encrypt(bob.key, 'efter mötet');
        expect(
          out.packet[0],
          0,
          reason: 'the new session has the highest number',
        );
        expect(await deliver(bob, alice, out), 'efter mötet');
      },
    );

    test('after each new scan the next message goes on the newest session, '
        'whatever its id (0006 (b))', () async {
      final (alice, bob) = await established();
      for (var i = 0; i < 10; i++) {
        await scan(alice, bob);
        final before = {
          for (final s in _sessions(alice, bob)) s['id']: s['pickle'],
        };
        final newest = chosenSessionId(alice, bob);
        await alice.olm.encrypt(bob.key, 'm$i');
        final changed = [
          for (final s in _sessions(alice, bob))
            if (before[s['id']] != s['pickle']) s['id'],
        ];
        expect(changed, [newest], reason: 'round $i');
      }
    });

    test('the same QR display scanned twice gives no new session', () async {
      final alice = await Person().start();
      final bob = await Person().start();
      final qr = await bob.olm.publishBundle();
      await alice.olm.startSession(qr);
      await alice.olm.startSession(qr);
      expect(sessionCount(alice, bob), 1);
      await alice.olm.addContact(
        bundle: qr,
        addressingKey: addressingKeyFor(3),
        name: 'Bob',
        metAt: DateTime.utc(2026),
      );
      expect(sessionCount(alice, bob), 1);
      expect((await alice.olm.contacts()).single.name, 'Bob');
    });

    test('a packet no session can read changes no number', () async {
      final (alice, bob) = await established();
      final numbers = (bob.savedState['counter']! as int);
      final out = await alice.olm.encrypt(bob.key, 'x');
      final broken = Uint8List.fromList(out.packet)
        ..[out.packet.length - 1] ^= 1;
      await bob.olm.receive(alice.key, broken);
      expect(bob.savedState['counter'], numbers);
    });

    test('the numbers survive a restart', () async {
      final (alice, bob) = await established();
      final before = chosenSessionId(alice, bob);
      await scan(alice, bob);
      final after = chosenSessionId(alice, bob);
      expect(after, isNot(before));
      alice.restart();
      final out = await alice.olm.encrypt(bob.key, 'efter omstart');
      expect(
        out.packet[0],
        0,
        reason: 'still the newest session after restart',
      );
      expect(chosenSessionId(alice, bob), after);
    });

    test('no session is deleted (0006 (iii))', () async {
      final (alice, bob) = await established();
      for (var i = 0; i < 6; i++) {
        await scan(alice, bob);
      }
      expect(sessionCount(alice, bob), 7);
      final old = await alice.olm.encrypt(bob.key, 'nyast');
      expect(await deliver(bob, alice, old), 'nyast');
    });
  });

  group('0004 §8: one-time keys', () {
    test('a shown key nobody used is removed after 30 days', () async {
      var now = DateTime.utc(2026, 11, 1);
      final alice = await Person(null, () => now).start();
      final bob = await Person(null, () => now).start();
      final qr = await bob.olm.publishBundle();
      await alice.olm.startSession(qr);
      now = now.add(const Duration(days: 31));
      await bob.olm.publishBundle(); // cleans the old key
      final first = await alice.olm.encrypt(bob.key, 'för sent');
      expect(
        (await bob.olm.receive(alice.key, first.packet)).failure,
        OlmReceiveFailure.unreadable,
      );
    });

    test('a used shown key that expires does not break the QR code, and an '
        'unused one in the same pass is still removed', () async {
      var now = DateTime.utc(2026, 11, 1);
      final alice = await Person(null, () => now).start();
      final bob = await Person(null, () => now).start();
      final carol = await Person(null, () => now).start();
      // Alice uses Bob's first key: Bob reads her message, so Olm has
      // removed that key from his account.
      await scan(alice, bob);
      expect(
        await deliver(bob, alice, await alice.olm.encrypt(bob.key, 'hej')),
        'hej',
      );
      // Carol scans Bob's second code but does not write yet.
      await scan(carol, bob);

      now = now.add(const Duration(days: 31));
      final third = await bob.olm.publishBundle(); // cleans both
      expect(third.toBytes(), hasLength(64));
      expect((await bob.olm.publishBundle()).toBytes(), hasLength(64));

      final late = await carol.olm.encrypt(bob.key, 'för sent');
      expect(
        (await bob.olm.receive(carol.key, late.packet)).failure,
        OlmReceiveFailure.unreadable,
        reason: 'the unused key was removed',
      );
      // The cleanup did not touch the session with Alice.
      final next = await alice.olm.encrypt(bob.key, 'efter');
      expect(await deliver(bob, alice, next), 'efter');
    });

    test('a shown key is kept for 29 days', () async {
      var now = DateTime.utc(2026, 11, 1);
      final alice = await Person(null, () => now).start();
      final bob = await Person(null, () => now).start();
      final qr = await bob.olm.publishBundle();
      await alice.olm.startSession(qr);
      now = now.add(const Duration(days: 29));
      await bob.olm.publishBundle();
      final first = await alice.olm.encrypt(bob.key, 'i tid');
      expect(await deliver(bob, alice, first), 'i tid');
    });
  });

  test('size of a session pickle (printed, 0006 "Fakta")', () async {
    final (alice, bob) = await established();
    final rng = Random(5);
    for (var i = 0; i < 30; i++) {
      final from = rng.nextBool() ? alice : bob;
      final to = from == alice ? bob : alice;
      await deliver(to, from, await from.olm.encrypt(to.key, 'm$i'));
    }
    final contacts = alice.savedState['contacts']! as Map<String, Object?>;
    final pickle =
        (((contacts.values.single! as Map)['sessions'] as List).single
                as Map)['pickle']
            as String;
    // ignore: avoid_print
    print('PICKLE one session after 30 messages: ${pickle.length} bytes');
    expect(pickle.length, lessThan(64 * 1024));
  });
}
