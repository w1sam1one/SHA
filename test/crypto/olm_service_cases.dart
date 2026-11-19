// P3 in docs/ROADMAP.md: Olm behind CryptoService.
//
// The spike's requirement tests R1-R7 (spike/vodozemac/test/olm_spike_test.dart,
// 0003) against the app's own classes, plus the order of saving and the
// crash cases in 0004 §6 and resetIdentity(). Run on the computer by
// test/crypto/olm_service_test.dart and on Android by
// integration_test/olm_service_test.dart (R8).
//
// Two people without a server: "sending" hands a packet from one object to
// the other. The vault is in memory, so the saved state can be read back.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

import '../support/in_memory_vault.dart';

const String stateName = 'olm.state.v1';
const String pickleKeyName = 'olm.pickle-key.v1';

/// An in-memory vault that can refuse the next write, like a crash or a
/// full disk at the moment of saving.
final class CrashingVault extends InMemoryVault {
  bool failNextWrite = false;
  int writes = 0;

  /// The write with this number, counted from 0 from when it is set, fails
  /// instead.
  int? failWriteAt;

  @override
  Future<void> write(String name, Uint8List value) async {
    final at = failWriteAt;
    if (at != null) failWriteAt = at == 0 ? null : at - 1;
    if (failNextWrite || at == 0) {
      failNextWrite = false;
      throw const CryptoException('crash', CryptoErrorKind.unavailable);
    }
    writes++;
    await super.write(name, value);
  }
}

/// One person: a vault and a fresh CryptoService on it. [restart] makes a
/// new service on the same vault, like the app starting again.
final class Person {
  Person([CrashingVault? vault, this.clock]) : vault = vault ?? CrashingVault();

  final CrashingVault vault;
  final DateTime Function()? clock;
  late CryptoService service = ShaCryptoService(vault: vault, clock: clock);
  late Uint8List key;

  OlmService get olm => service.olm;

  Future<Person> start() async {
    key = await olm.createAccount();
    return this;
  }

  void restart() => service = ShaCryptoService(vault: vault, clock: clock);

  Map<String, Object?> get savedState =>
      jsonDecode(utf8.decode(vault.values[stateName]!)) as Map<String, Object?>;

  /// A digest of every pickle in the saved state (the account and each
  /// session), so a failing test never prints the pickles themselves.
  List<int> get savedPickles => [
    for (final p in _pickles) Object.hashAll(p.codeUnits),
  ];

  List<String> get _pickles => [
    savedState['account']! as String,
    for (final c in (savedState['contacts']! as Map).values)
      for (final s in (c as Map)['sessions'] as List)
        (s as Map)['pickle'] as String,
  ];
}

/// The saved number of each of [me]'s sessions with [peer] (0006 (b)).
List<int> sessionNumbers(Person me, Person peer) {
  final contacts = me.savedState['contacts']! as Map<String, Object?>;
  final c = contacts[base64.encode(peer.key)] as Map<String, Object?>?;
  return [
    for (final s in (c?['sessions'] as List?) ?? const [])
      (s as Map)['number'] as int,
  ];
}

/// [a] scans [b]'s QR code and starts a session.
Future<void> scan(Person a, Person b) async =>
    a.olm.startSession(await b.olm.publishBundle());

Future<String?> deliver(Person to, Person from, OlmOutgoing out) async =>
    (await to.olm.receive(from.key, out.packet)).message?.text;

/// Alice scanned Bob, wrote first, and Bob answered once.
Future<(Person, Person)> established() async {
  final alice = await Person().start();
  final bob = await Person().start();
  await scan(alice, bob);
  expect(
    await deliver(bob, alice, await alice.olm.encrypt(bob.key, 'hej')),
    'hej',
  );
  expect(
    await deliver(alice, bob, await bob.olm.encrypt(alice.key, 'hej tillbaka')),
    'hej tillbaka',
  );
  return (alice, bob);
}

Uint8List flipped(Uint8List packet, int at) =>
    Uint8List.fromList(packet)..[at] ^= 0x01;

void olmServiceCases() {
  test(
    'R1 the QR bundle: identity key and a new one-time key, 64 bytes',
    () async {
      final bob = await Person().start();
      final first = await bob.olm.publishBundle();
      final second = await bob.olm.publishBundle();
      expect(first.toBytes(), hasLength(64));
      expect(first.identityKey, bob.key);
      expect(second.identityKey, bob.key);
      expect(first.oneTimeKey, isNot(second.oneTimeKey));
      expect(
        OlmContactBundle.fromBytes(first.toBytes()).toBytes(),
        first.toBytes(),
      );
      expect(await bob.olm.identityKey(), bob.key);
    },
  );

  test('R2 Alice writes first, Bob answers, both read the text', () async {
    final alice = await Person().start();
    final bob = await Person().start();
    await scan(alice, bob);

    final first = await alice.olm.encrypt(bob.key, 'hej');
    expect(first.packet[0], 0, reason: 'type 0 until a reply is read');
    expect(await deliver(bob, alice, first), 'hej');

    final reply = await bob.olm.encrypt(alice.key, 'hej tillbaka');
    expect(reply.packet[0], 1);
    expect(await deliver(alice, bob, reply), 'hej tillbaka');

    final next = await alice.olm.encrypt(bob.key, 'och igen');
    expect(next.packet[0], 1, reason: 'Alice has read a reply');
    expect(await deliver(bob, alice, next), 'och igen');
  });

  group('R3 many messages', () {
    test('100 each way, reordered, one lost, across ratchet turns', () async {
      final (alice, bob) = await established();
      final rng = Random(3);
      for (var round = 0; round < 10; round++) {
        for (final (from, to) in [(alice, bob), (bob, alice)]) {
          final sent = [
            for (var i = 0; i < 10; i++)
              await from.olm.encrypt(to.key, 'r$round-$i'),
          ];
          for (final out in sent) {
            await from.olm.markSent(out.id);
          }
          final order = [...sent]..shuffle(rng);
          if (round == 4 && from == alice) order.removeAt(0);
          for (final out in order) {
            expect(await deliver(to, from, out), out.text);
          }
        }
      }
    });

    test('only the 40 most recent skipped keys are kept', () async {
      final (alice, bob) = await established();
      final sent = [
        for (var i = 0; i < 42; i++) await alice.olm.encrypt(bob.key, 'm$i'),
      ];
      expect(await deliver(bob, alice, sent.last), 'm41');
      final late = await bob.olm.receive(alice.key, sent.first.packet);
      expect(late.failure, OlmReceiveFailure.tooLate);
      expect(await deliver(bob, alice, sent[40]), 'm40');
      expect((await bob.olm.failureCounts(alice.key)).tooLate, 1);
    });

    test('a gap of more than 2000 messages is rejected', () async {
      final (alice, bob) = await established();
      OlmOutgoing? last;
      for (var i = 0; i < 2002; i++) {
        last = await alice.olm.encrypt(bob.key, 'm$i');
        await alice.olm.markSent(last.id);
      }
      final result = await bob.olm.receive(alice.key, last!.packet);
      expect(result.failure, OlmReceiveFailure.gapTooBig);
      expect((await bob.olm.failureCounts(alice.key)).gapTooBig, 1);
    });
  });

  group('R4 rejected', () {
    test('a changed packet, and the session still works after', () async {
      final (alice, bob) = await established();
      final out = await alice.olm.encrypt(bob.key, 'orört');
      for (final at in [out.packet.length ~/ 2, out.packet.length - 1]) {
        final result = await bob.olm.receive(
          alice.key,
          flipped(out.packet, at),
        );
        expect(
          result.failure,
          OlmReceiveFailure.unreadable,
          reason: 'byte $at',
        );
      }
      expect(await deliver(bob, alice, out), 'orört');
      expect((await bob.olm.failureCounts(alice.key)).unreadable, 2);
    });

    test('the same packet twice gives one message, and counts once', () async {
      final (alice, bob) = await established();
      final out = await alice.olm.encrypt(bob.key, 'en gång');
      expect(await deliver(bob, alice, out), 'en gång');
      final again = await bob.olm.receive(alice.key, out.packet);
      expect(again.failure, OlmReceiveFailure.duplicate);
      expect(await bob.olm.inbox(), hasLength(2)); // 'hej' and 'en gång'

      // A changed copy of a message not read yet. (A changed copy of one
      // already read counts as "too late": its message key is used up.)
      final unread = await alice.olm.encrypt(bob.key, 'oläst');
      final broken = flipped(unread.packet, unread.packet.length - 1);
      await bob.olm.receive(alice.key, broken);
      await bob.olm.receive(alice.key, broken);
      expect((await bob.olm.failureCounts(alice.key)).unreadable, 1);
    });

    test('a first message replayed after its hash expired is unreadable, and '
        'the saved account is unchanged', () async {
      var now = DateTime.utc(2026, 11, 16);
      final alice = await Person(null, () => now).start();
      final bob = await Person(null, () => now).start();
      await scan(alice, bob);
      final first = await alice.olm.encrypt(bob.key, 'första');
      expect(await deliver(bob, alice, first), 'första');

      now = now.add(const Duration(hours: 73));
      await bob.olm.receive(alice.key, Uint8List.fromList([7, 7])); // prunes
      bob.restart(); // also after a restart
      final pickles = bob.savedPickles; // the account and every session
      final replay = await bob.olm.receive(alice.key, first.packet);
      expect(replay.failure, OlmReceiveFailure.unreadable);
      expect(bob.savedPickles, pickles);
    });

    test(
      'a first message is checked against the scanned identity key',
      () async {
        final alice = await Person().start();
        final bob = await Person().start();
        final carol = await Person().start();
        await scan(alice, bob);
        final first = await alice.olm.encrypt(bob.key, 'från Alice');

        final pickles = bob.savedPickles;
        final asCarol = await bob.olm.receive(carol.key, first.packet);
        expect(asCarol.failure, OlmReceiveFailure.unreadable);
        expect(bob.savedPickles, pickles, reason: 'the account is unchanged');

        // Not a duplicate: the hash was saved with the failure, so the same
        // bytes count as handled. A real first message from Alice still works
        // as long as her one-time key was not used.
        final second = await alice.olm.encrypt(bob.key, 'igen');
        expect(await deliver(bob, alice, second), 'igen');
      },
    );

    test('a broken packet is malformed and counted', () async {
      final (alice, bob) = await established();
      for (final bad in [
        Uint8List(0),
        Uint8List.fromList([1]),
        Uint8List.fromList([9, 1, 2]),
      ]) {
        expect(
          (await bob.olm.receive(alice.key, bad)).failure,
          OlmReceiveFailure.malformed,
        );
      }
      expect((await bob.olm.failureCounts(alice.key)).malformed, 3);
    });
  });

  test('R5 both scan at once: two sessions, nothing is lost', () async {
    final alice = await Person().start();
    final bob = await Person().start();
    final aliceQr = await alice.olm.publishBundle();
    final bobQr = await bob.olm.publishBundle();
    await alice.olm.startSession(bobQr);
    await bob.olm.startSession(aliceQr);

    final a1 = await alice.olm.encrypt(bob.key, 'a1');
    final b1 = await bob.olm.encrypt(alice.key, 'b1');
    expect(await deliver(bob, alice, a1), 'a1');
    expect(await deliver(alice, bob, b1), 'b1');

    // Crossed rounds: both write before reading the other.
    for (var i = 0; i < 3; i++) {
      final a = await alice.olm.encrypt(bob.key, 'a$i');
      final b = await bob.olm.encrypt(alice.key, 'b$i');
      expect(await deliver(bob, alice, a), 'a$i');
      expect(await deliver(alice, bob, b), 'b$i');
    }
    // One reply that does not cross.
    final a = await alice.olm.encrypt(bob.key, 'sist');
    expect(await deliver(bob, alice, a), 'sist');
    final b = await bob.olm.encrypt(alice.key, 'svar');
    expect(await deliver(alice, bob, b), 'svar');
    expect(b.packet[0], 1);
  });

  test('a new scan is sent on at once (0006 (b))', () async {
    final (alice, bob) = await established();
    final before = await alice.olm.encrypt(bob.key, 'gammal');
    expect(before.packet[0], 1);
    await scan(alice, bob);
    final after = await alice.olm.encrypt(bob.key, 'ny');
    expect(
      after.packet[0],
      0,
      reason: 'the new session has the highest number',
    );
    expect(await deliver(bob, alice, before), 'gammal');
    expect(await deliver(bob, alice, after), 'ny');
  });

  test(
    'R6 the saved state survives a restart; a wrong pickle key fails',
    () async {
      final (alice, bob) = await established();
      alice.restart();
      bob.restart();
      expect(await alice.olm.identityKey(), alice.key);
      final out = await alice.olm.encrypt(bob.key, 'efter omstart');
      expect(await deliver(bob, alice, out), 'efter omstart');

      bob.vault.values[pickleKeyName] = Uint8List(32)..fillRange(0, 32, 7);
      bob.restart();
      final next = await alice.olm.encrypt(bob.key, 'fel nyckel');
      await expectLater(
        bob.olm.receive(alice.key, next.packet),
        throwsA(
          isA<CryptoException>()
              .having((e) => e.kind, 'kind', CryptoErrorKind.corrupt)
              .having(
                (e) => e.message,
                'message',
                'Saved Olm session cannot be read',
              ),
        ),
      );
    },
  );

  test('R7 packet size: one type byte plus the Olm message, padded to the '
      'bucket (0004 §4 (A))', () async {
    final (alice, bob) = await established();
    // The spike's R7 lengths. 0 and 100 share a bucket and a size.
    for (final (length, size) in [
      (0, 1 + 304),
      (100, 1 + 304),
      (1000, 1 + 1072),
      (10000, 1 + 16433),
    ]) {
      final out = await alice.olm.encrypt(bob.key, 'x' * length);
      expect(out.packet.length, size, reason: '$length characters');
      expect(await deliver(bob, alice, out), 'x' * length);
    }
  });

  group('0004 §6 crashes', () {
    test('receive: a crash before saving changes nothing; the packet is read '
        'again after the restart', () async {
      final (alice, bob) = await established();
      final out = await alice.olm.encrypt(bob.key, 'viktigt');
      bob.vault.failNextWrite = true;
      await expectLater(
        bob.olm.receive(alice.key, out.packet),
        throwsA(isA<CryptoException>()),
      );
      bob.restart();
      expect(await deliver(bob, alice, out), 'viktigt');
    });

    test('receive: a crash while saving a new inbound session is an error, '
        'not "unreadable"', () async {
      final alice = await Person().start();
      final bob = await Person().start();
      await scan(alice, bob);
      final first = await alice.olm.encrypt(bob.key, 'första');
      bob.vault.failNextWrite = true;
      await expectLater(
        bob.olm.receive(alice.key, first.packet),
        throwsA(isA<CryptoException>()),
      );
      bob.restart();
      expect(await deliver(bob, alice, first), 'första');
    });

    test('receive: after saving, the message waits until shown, and the '
        'packet is skipped', () async {
      final (alice, bob) = await established();
      final out = await alice.olm.encrypt(bob.key, 'sparat');
      expect(await deliver(bob, alice, out), 'sparat');
      bob.restart(); // before the app showed it
      final waiting = await bob.olm.inbox();
      expect(waiting.map((m) => m.text), contains('sparat'));
      expect(
        (await bob.olm.receive(alice.key, out.packet)).failure,
        OlmReceiveFailure.duplicate,
      );
      for (final m in waiting) {
        await bob.olm.markShown(m.id);
      }
      bob.restart();
      expect(await bob.olm.inbox(), isEmpty);
    });

    test(
      'send: a crash before saving leaves no packet; the next one works',
      () async {
        final (alice, bob) = await established();
        alice.vault.failNextWrite = true;
        await expectLater(
          alice.olm.encrypt(bob.key, 'aldrig sparat'),
          throwsA(isA<CryptoException>()),
        );
        alice.restart();
        expect(
          (await alice.olm.outbox()).map((o) => o.text),
          isNot(contains('aldrig sparat')),
        );
        final out = await alice.olm.encrypt(bob.key, 'nästa');
        expect(await deliver(bob, alice, out), 'nästa');
      },
    );

    test(
      'send: after saving, the outbox keeps the same bytes until sent',
      () async {
        final (alice, bob) = await established();
        final out = await alice.olm.encrypt(bob.key, 'i utkorgen');
        alice.restart(); // before the relay answered
        final waiting = await alice.olm.outbox();
        final again = waiting.singleWhere((o) => o.id == out.id);
        expect(again.packet, out.packet);
        expect(again.text, 'i utkorgen');
        expect(await deliver(bob, alice, again), 'i utkorgen');
        expect(
          (await bob.olm.receive(alice.key, again.packet)).failure,
          OlmReceiveFailure.duplicate,
        );
        await alice.olm.markSent(out.id);
        alice.restart();
        expect(
          (await alice.olm.outbox()).where((o) => o.id == out.id),
          isEmpty,
        );
      },
    );

    test(
      'QR: a crash while saving the new one-time key shows nothing',
      () async {
        final bob = await Person().start();
        bob.vault.failNextWrite = true;
        await expectLater(
          bob.olm.publishBundle(),
          throwsA(isA<CryptoException>()),
        );
        bob.restart();
        expect((await bob.olm.publishBundle()).toBytes(), hasLength(64));
      },
    );

    test('a packet no session can read gives no session a new number '
        '(0006 (b))', () async {
      // Alice has two sessions: the one Bob answered on, and a new scan
      // with the highest number, which she sends on (type 0).
      final (alice, bob) = await established();
      await scan(alice, bob);
      final numbers = sessionNumbers(alice, bob);
      expect(numbers, hasLength(2));
      final counter = alice.savedState['counter'];
      // A changed copy of a real packet from Bob: every session fails.
      final real = await bob.olm.encrypt(alice.key, 'från Bob');
      final changed = flipped(real.packet, real.packet.length - 1);
      expect(
        (await alice.olm.receive(bob.key, changed)).failure,
        isNot(isNull),
      );
      expect(sessionNumbers(alice, bob), numbers);
      expect(alice.savedState['counter'], counter);
      final next = await alice.olm.encrypt(bob.key, 'efter');
      expect(next.packet[0], 0, reason: 'still the newest session');
    });

    test('a changed first message (type 0) is unreadable, the account is '
        'unchanged, and the real one is still read', () async {
      final alice = await Person().start();
      final bob = await Person().start();
      await scan(alice, bob);
      final first = await alice.olm.encrypt(bob.key, 'första');
      expect(first.packet[0], 0);
      final pickles = bob.savedPickles;
      final changed = flipped(first.packet, first.packet.length - 1);
      expect(
        (await bob.olm.receive(alice.key, changed)).failure,
        OlmReceiveFailure.unreadable,
      );
      expect(bob.savedPickles, pickles, reason: 'account and sessions');
      expect(await deliver(bob, alice, first), 'första');
    });

    test('two first messages in a row give one inbound session', () async {
      final alice = await Person().start();
      final bob = await Person().start();
      await scan(alice, bob);
      final a = await alice.olm.encrypt(bob.key, 'ett');
      final b = await alice.olm.encrypt(bob.key, 'två');
      expect([a.packet[0], b.packet[0]], [0, 0]);
      expect(await deliver(bob, alice, a), 'ett');
      expect(await deliver(bob, alice, b), 'två');
      expect(sessionNumbers(bob, alice), hasLength(1));
    });

    test(
      'a failed attempt on the wrong session changes nothing saved',
      () async {
        // Bob has an inbound session from Alice and has not answered yet.
        // A failed decrypt on such a session changes it in memory (0004 §6,
        // double_ratchet.rs:168-191), so it must not be saved.
        final alice = await Person().start();
        final bob = await Person().start();
        await scan(alice, bob);
        expect(
          await deliver(bob, alice, await alice.olm.encrypt(bob.key, 'hej')),
          'hej',
        );
        final stranger = await Person().start();
        await scan(stranger, bob);
        final foreign = await stranger.olm.encrypt(bob.key, 'främmande');
        final pickles = bob.savedPickles;
        final numbers = sessionNumbers(bob, alice);
        final counter = bob.savedState['counter'];
        final result = await bob.olm.receive(alice.key, foreign.packet);
        expect(result.failure, OlmReceiveFailure.unreadable);
        expect(bob.savedPickles, pickles);
        expect(sessionNumbers(bob, alice), numbers);
        expect(bob.savedState['counter'], counter);

        // The session still works afterwards.
        final next = await alice.olm.encrypt(bob.key, 'sedan');
        expect(await deliver(bob, alice, next), 'sedan');
      },
    );
  });

  test(
    'resetIdentity() leaves nothing, and a new account is unrelated',
    () async {
      final (alice, bob) = await established();
      await alice.service.createIdentity();
      await alice.olm.encrypt(bob.key, 'i utkorgen');
      await alice.service.resetIdentity();
      expect(alice.vault.values.keys, isEmpty);
      expect(await alice.olm.identityKey(), isNull);
      expect(await alice.olm.outbox(), isEmpty);
      final fresh = await alice.olm.createAccount();
      expect(fresh, isNot(alice.key));
    },
  );

  test('a damaged state gives a fixed error, not the library text', () async {
    final (alice, bob) = await established();
    bob.vault.values[stateName] = Uint8List.fromList(utf8.encode('{"v":1}'));
    bob.restart();
    await expectLater(
      bob.olm.inbox(),
      throwsA(
        isA<CryptoException>().having(
          (e) => e.message,
          'message',
          'Saved Olm state is damaged',
        ),
      ),
    );
    expect(alice.key, hasLength(32));
  });
}
