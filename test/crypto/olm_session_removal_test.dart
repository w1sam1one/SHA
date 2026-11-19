// F2 in docs/ROADMAP.md: old sessions are removed by rule (iv) in 0009, with
// 24 hours for clocks. OGRANSKAT (0009).
//
// The tests listed in 0009, "Testa", against the app's own classes. A
// message's text here is its writer's clock in milliseconds, the way the
// app's payload carries `t` (MessagePayload). Needs the native library
// (tool/build_native_host.sh).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/crypto/src/sha_olm_service.dart';

import 'olm_service_cases.dart';

/// 48 hours at the relay and 24 for clocks (0009, conditions 4 and 5).
const Duration wait = Duration(hours: 72);
const Duration ms = Duration(milliseconds: 1);

/// One clock for both people: the margin for wrong clocks is not what is
/// tested here.
final class Clock {
  Clock() : now = DateTime.utc(2026, 11, 1, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

DateTime? writtenAt(String text) {
  final at = int.tryParse(text);
  return at == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
}

/// [from] writes to [to], with its clock's time as the text. The relay
/// takes the packet at once unless [send] is false.
Future<OlmOutgoing> write(
  Person from,
  Person to,
  Clock clock, {
  bool send = true,
}) async {
  final out = await from.olm.encrypt(
    to.key,
    '${clock.now.millisecondsSinceEpoch}',
  );
  if (send) await from.olm.markSent(out.id);
  return out;
}

/// [to] reads [out] from [from], handing over the writer's time.
Future<String?> read(Person to, Person from, OlmOutgoing out) async =>
    (await to.olm.receive(
      from.key,
      out.packet,
      writtenAt: writtenAt,
    )).message?.text;

List<Map<String, Object?>> sessionsOf(Person me, Person peer) {
  final contacts = me.savedState['contacts']! as Map<String, Object?>;
  final c = contacts[base64.encode(peer.key)] as Map<String, Object?>?;
  return c == null
      ? []
      : (c['sessions']! as List).cast<Map<String, Object?>>().toList();
}

/// [me]'s sessions with [peer], in the order they were made.
List<String> sessionIds(Person me, Person peer) => [
  for (final s in sessionsOf(me, peer)) s['id']! as String,
];

/// Changes [person]'s saved state the way [change] says and starts the
/// service again on it, like an older version of the app had saved it.
void rewriteSaved(Person person, void Function(Map<String, Object?>) change) {
  final state = person.savedState;
  change(state);
  person.vault.values[stateName] = Uint8List.fromList(
    utf8.encode(jsonEncode(state)),
  );
  person.restart();
}

typedef MovedOn = ({
  Person alice,
  Person bob,
  Clock clock,
  String s1,
  String s2,
});

/// Alice scanned Bob and wrote on S1; Bob answered on it. [gap] later Bob
/// met Alice again and wrote on the new session S2, which Alice read: the
/// message that can make S1 old for Alice (condition 4).
Future<MovedOn> movedOn({Duration gap = const Duration(hours: 73)}) async {
  final clock = Clock();
  final alice = await Person(null, clock.call).start();
  final bob = await Person(null, clock.call).start();
  await scan(alice, bob);
  expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
  expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
  final s1 = sessionIds(alice, bob).single;
  clock.advance(gap);
  await scan(bob, alice);
  expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
  final ids = sessionIds(alice, bob);
  expect(ids, [s1, isNot(s1)]);
  return (alice: alice, bob: bob, clock: clock, s1: s1, s2: ids.last);
}

void main() {
  test('the rule counts with the relay keeping a packet 48 hours', () {
    expect(
      File('relay/limits.go').readAsStringSync(),
      contains('packetTTL = 48 * time.Hour'),
    );
    expect(ShaOlmService.relayKeepsPackets, const Duration(hours: 48));
    expect(ShaOlmService.clockMargin, const Duration(hours: 24));
  });

  test('the old session goes 72 h after the contact moved on, not before, '
      'and the chat goes on', () async {
    final m = await movedOn();
    m.clock.advance(wait - ms);
    expect(await m.alice.olm.removeOldSessions(), 0);
    expect(sessionIds(m.alice, m.bob), [m.s1, m.s2]);

    m.clock.advance(ms);
    expect(await m.alice.olm.removeOldSessions(), 1);
    expect(sessionIds(m.alice, m.bob), [m.s2]);
    expect(await m.alice.olm.removeOldSessions(), 0);

    final next = await write(m.alice, m.bob, m.clock);
    expect(await read(m.bob, m.alice, next), isNotNull);
    expect(
      await read(m.alice, m.bob, await write(m.bob, m.alice, m.clock)),
      isNotNull,
    );
  });

  test('a message written 72 h or less after our last packet on S makes S '
      'old for nothing (conditions 3 and 4)', () async {
    final m = await movedOn(gap: wait);
    m.clock.advance(const Duration(days: 30));
    expect(await m.alice.olm.removeOldSessions(), 0);
    expect(sessionIds(m.alice, m.bob), [m.s1, m.s2]);

    // A message written later does it, 72 h after it was read.
    expect(
      await read(m.alice, m.bob, await write(m.bob, m.alice, m.clock)),
      isNotNull,
    );
    m.clock.advance(wait - ms);
    expect(await m.alice.olm.removeOldSessions(), 0);
    m.clock.advance(ms);
    expect(await m.alice.olm.removeOldSessions(), 1);
    expect(sessionIds(m.alice, m.bob), [m.s2]);
  });

  test('without the contact\'s time no session is removed', () async {
    final m = await movedOn(gap: wait);
    m.clock.advance(const Duration(days: 30));
    // Not a time: what the app sees for a text that is not a payload.
    final text = await m.bob.olm.encrypt(m.alice.key, 'hej');
    await m.bob.olm.markSent(text.id);
    expect(await read(m.alice, m.bob, text), 'hej');
    // And no way to tell the time at all.
    final timed = await write(m.bob, m.alice, m.clock);
    expect(
      (await m.alice.olm.receive(m.bob.key, timed.packet)).message,
      isNotNull,
    );
    m.clock.advance(const Duration(days: 30));
    expect(await m.alice.olm.removeOldSessions(), 0);
    expect(sessionIds(m.alice, m.bob), [m.s1, m.s2]);
  });

  test('m2 read before m1 (0009, the counterexample): S stays until m1 is '
      'read, and while it is the session we send on', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final s1 = sessionIds(alice, bob).single;

    clock.advance(const Duration(hours: 73));
    final m1 = await write(bob, alice, clock); // on S1, before midnight
    await scan(bob, alice);
    final m2 = await write(bob, alice, clock); // on S2, after it
    expect(await read(alice, bob, m2), isNotNull, reason: 'today first');
    expect(await alice.olm.removeOldSessions(), 0);
    clock.advance(const Duration(hours: 1));
    expect(await read(alice, bob, m1), isNotNull, reason: 'then yesterday');

    // m1 made S1 the newest again: it is kept while it is sent on.
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0);
    final s2 = sessionIds(alice, bob).last;
    expect(sessionIds(alice, bob), [s1, s2]);

    // Bob writes on S2 again: S2 is the newest, and S1 can go.
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    expect(sessionIds(alice, bob), [s2]);
  });

  test('a packet on S waiting in the outbox keeps S, and sending it starts '
      'the wait over (condition 2)', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final s1 = sessionIds(alice, bob).single;
    final late = await write(alice, bob, clock, send: false); // no server

    clock.advance(const Duration(hours: 73));
    await scan(bob, alice);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    final s2 = sessionIds(alice, bob).last;
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0, reason: 'S1 is in use');

    await alice.olm.markSent(late.id);
    expect(sessionIds(alice, bob), [s1, s2]);
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0, reason: 'sent on again');

    // The late packet makes S1 Bob's newest again, and he answers on it.
    expect(await read(bob, alice, late), isNotNull);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
  });

  test('five new scans while the contact is silent remove nothing, and the '
      'contact\'s next message is read (0006 (i))', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    for (var i = 0; i < 5; i++) {
      clock.advance(const Duration(days: 2));
      await scan(alice, bob);
      await write(alice, bob, clock); // never fetched by Bob
    }
    clock.advance(const Duration(days: 30));
    expect(await alice.olm.removeOldSessions(), 0);
    final ids = sessionIds(alice, bob);
    expect(ids, hasLength(6));

    // Bob is back and writes on the session he has.
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    expect(await alice.olm.removeOldSessions(), 0);
    clock.advance(wait);
    // He wrote long after Alice's packets on the five, so they can go.
    expect(await alice.olm.removeOldSessions(), 5);
    expect(sessionIds(alice, bob), [ids.first]);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
  });

  test('an active chat: S goes 72 h after the first message that makes it '
      'old, not later', () async {
    final m = await movedOn();
    for (var i = 0; i < 5; i++) {
      m.clock.advance(const Duration(hours: 12));
      expect(
        await read(m.alice, m.bob, await write(m.bob, m.alice, m.clock)),
        isNotNull,
      );
    }
    expect(sessionIds(m.alice, m.bob), [m.s1, m.s2]);
    m.clock.advance(const Duration(hours: 12));
    // Any save checks the rule; this one is the next message.
    expect(
      await read(m.alice, m.bob, await write(m.bob, m.alice, m.clock)),
      isNotNull,
    );
    expect(sessionIds(m.alice, m.bob), [m.s2]);
  });

  test('a message on S itself never makes S old', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final s1 = sessionIds(alice, bob).single;
    clock.advance(const Duration(hours: 73));
    // Bob still writes on S1, long after Alice's last packet there.
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    // Alice meets Bob again but has not written on the new session yet.
    await scan(alice, bob);
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0);
    // S1 is still Bob's newest, and he writes on it.
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    expect(sessionIds(alice, bob).first, s1);
  });

  test('a session made from the contact\'s first message counts from when '
      'it was made', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    // Bob reads Alice's first message on a new session, and never answers
    // on it.
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final s1 = sessionIds(bob, alice).single;
    clock.advance(const Duration(hours: 73));
    await scan(bob, alice);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    clock.advance(wait);
    expect(await bob.olm.removeOldSessions(), 1);
    expect(sessionIds(bob, alice), isNot(contains(s1)));
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
  });

  test('a later send on S moves its time (condition 3)', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final late = await write(alice, bob, clock, send: false);
    clock.advance(const Duration(hours: 50));
    await alice.olm.markSent(late.id); // the relay takes it 50 h later
    expect(await read(bob, alice, late), isNotNull);
    // Written 73 h after the first packet, but only 23 h after the last.
    clock.advance(const Duration(hours: 23));
    await scan(bob, alice);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    clock.advance(const Duration(days: 30));
    expect(await alice.olm.removeOldSessions(), 0);
    expect(sessionIds(alice, bob), hasLength(2));
  });

  test('condition 4 counts with when the contact wrote, not when we read '
      'it', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    clock.advance(const Duration(hours: 10));
    await scan(bob, alice);
    final m = await write(bob, alice, clock); // 10 h after Alice's packet
    clock.advance(const Duration(hours: 90));
    expect(await read(alice, bob, m), isNotNull); // read 100 h after it
    clock.advance(const Duration(days: 30));
    expect(await alice.olm.removeOldSessions(), 0);
    expect(sessionIds(alice, bob), hasLength(2));
  });

  test('condition 5 counts from when we read the message, not from when it '
      'was written', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    clock.advance(const Duration(hours: 73));
    final m1 = await write(bob, alice, clock); // on S1
    await scan(bob, alice);
    final m2 = await write(bob, alice, clock); // on S2
    // Both waited 100 h, for example in Bob's outbox without a server.
    clock.advance(const Duration(hours: 100));
    expect(await read(alice, bob, m2), isNotNull);
    expect(sessionIds(alice, bob), hasLength(2));
    expect(await read(alice, bob, m1), isNotNull);
  });

  test('the times survive a restart', () async {
    final m = await movedOn();
    final s1 = sessionsOf(m.alice, m.bob).first;
    expect(s1['sent'], isA<int>());
    expect(s1['qualified'], isA<int>());
    m.alice.restart();
    m.clock.advance(wait);
    expect(await m.alice.olm.removeOldSessions(), 1);
    expect(sessionIds(m.alice, m.bob), [m.s2]);
  });

  test('sessions saved before F2 count as sent when the state is first '
      'read', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final s1 = sessionIds(alice, bob).single;
    clock.advance(const Duration(days: 10));
    rewriteSaved(alice, (state) {
      for (final c in (state['contacts']! as Map).values) {
        for (final s in (c as Map)['sessions'] as List) {
          (s as Map)
            ..remove('sent')
            ..remove('qualified');
        }
      }
    });

    // The last send on S1 was 10 days ago, but that is no longer known.
    await scan(bob, alice);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0);

    // Counted from when the state was read, S1 can go in the end.
    clock.advance(ms);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 1);
    expect(sessionIds(alice, bob), isNot(contains(s1)));
  });

  test('an outbox entry saved before F2 keeps all the contact\'s sessions '
      'until it is sent', () async {
    final clock = Clock();
    final alice = await Person(null, clock.call).start();
    final bob = await Person(null, clock.call).start();
    await scan(alice, bob);
    expect(await read(bob, alice, await write(alice, bob, clock)), isNotNull);
    final s1 = sessionIds(alice, bob).single;
    final late = await write(alice, bob, clock, send: false);
    rewriteSaved(alice, (state) {
      for (final o in state['outbox']! as List) {
        (o as Map).remove('session');
      }
    });

    clock.advance(const Duration(hours: 73));
    await scan(bob, alice);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
    final s2 = sessionIds(alice, bob).last;
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0, reason: 'which session?');

    // Sent on an unknown session: every session counts as sent on now.
    await alice.olm.markSent(late.id);
    expect(sessionIds(alice, bob), [s1, s2]);
    clock.advance(wait);
    expect(await alice.olm.removeOldSessions(), 0);
    expect(await read(bob, alice, late), isNotNull);
    expect(await read(alice, bob, await write(bob, alice, clock)), isNotNull);
  });
}
