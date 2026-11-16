// P6: two apps, a fake server and fake timers. The messages, the outbox,
// 507 and 429, duplicates, failures (0004 §10), restarting, and the
// rounds of 0004 §9 (b). Needs the native library
// (tool/build_native_host.sh).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/features/chat/chat_controller.dart';
import 'package:sha/features/transport/relay_client.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_settings.dart';

import '../support/two_apps.dart';

void main() {
  test('a message goes Alice → server → Bob, and back', () async {
    final (alice, bob) = await met();
    await alice.send('Hej Bob');
    expect(alice.relay.dropped, hasLength(1));
    expect(alice.relay.dropped.single[0], 3, reason: 'packet format 3');
    expect(alice.messages.single.pending, isFalse);
    expect(await alice.crypto.olm.outbox(), isEmpty);
    expect(alice.status, ServerStatus.ok);

    await bob.fetchAll();
    expect(bob.texts, ['Hej Bob']);
    expect(bob.messages.single.shown, isFalse);

    await bob.send('Hej Alice');
    await alice.fetchAll();
    expect(alice.texts, ['Hej Bob', 'Hej Alice']);
  });

  test(
    'the same packet fetched again gives one message and no failure',
    () async {
      final (alice, bob) = await met();
      await alice.send('en gång');
      final ticks = bob.container.read(failureTickProvider);
      await bob.fetchAll();
      await bob.fetchAll();
      expect(bob.texts, ['en gång']);
      expect(bob.container.read(failureTickProvider), ticks);
      expect((await bob.crypto.olm.inbox()), hasLength(1));
    },
  );

  test(
    '507: the message waits and is sent again with the same bytes',
    () async {
      final (alice, bob) = await met();
      alice.relay.failDrop = const RelayFull();
      await alice.send('vänta');
      expect(alice.status, ServerStatus.full);
      expect(alice.messages.single.pending, isTrue);
      final saved = (await alice.crypto.olm.outbox()).single.packet;

      await alice.transport.sendPending();
      expect(alice.status, ServerStatus.ok);
      expect(alice.relay.dropped.single.sublist(17), saved);
      expect(alice.messages.single.pending, isFalse);
      await bob.fetchAll();
      expect(bob.texts, ['vänta']);
    },
  );

  test(
    '429: nothing is sent or fetched until Retry-After has passed',
    () async {
      final (alice, bob) = await met();
      alice.relay.failDrop = const RelayBusy(Duration(seconds: 30));
      await alice.send('upptagen');
      expect(alice.status, ServerStatus.busy);

      alice.now = alice.now.add(const Duration(seconds: 29));
      final fetches = alice.relay.fetches;
      await alice.transport.sendPending();
      await alice.fetchAll();
      expect(alice.relay.dropped, isEmpty);
      expect(alice.relay.fetches, fetches);

      alice.now = alice.now.add(const Duration(seconds: 2));
      await alice.transport.sendPending();
      expect(alice.relay.dropped, hasLength(1));
      await bob.fetchAll();
      expect(bob.texts, ['upptagen']);
    },
  );

  test('no answer: the message waits in the outbox', () async {
    final (alice, _) = await met();
    alice.relay.failDrop = const RelayUnavailable();
    await alice.send('nätet');
    expect(alice.status, ServerStatus.unavailable);
    expect(await alice.crypto.olm.outbox(), hasLength(1));
    expect(alice.messages.single.pending, isTrue);
  });

  test('a changed packet is counted and shown once in the open chat', () async {
    final (alice, bob) = await met();
    await alice.send('original');
    final box = bob.relay.boxes.values.single;
    box[0] = Uint8List.fromList(box[0])..[box[0].length - 1] ^= 1;
    await bob.fetchAll();
    expect(bob.texts, isEmpty);
    expect(
      (await bob.crypto.olm.failureCounts(bob.peer.olm!.identityKey))
          .unreadable,
      1,
    );

    final sub = bob.container.listen(chatProvider(bob.peer.id), (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(sub.read().notices, [
      'Ett meddelande från Alice kunde inte läsas. Händer det igen, träffas '
          'och skanna varandras QR-koder på nytt.',
    ]);
    // Taken off the saved counter once shown.
    expect(
      (await bob.crypto.olm.failureCounts(bob.peer.olm!.identityKey))
          .unreadable,
      0,
    );
  });

  test('a packet that is not format 3 is counted as malformed and shows '
      'nothing', () async {
    final (alice, bob) = await met();
    await alice.send('x');
    final box = bob.relay.boxes.values.single;
    box.add(Uint8List.fromList([2, ...box[0].sublist(1)]));
    final ticks = bob.container.read(failureTickProvider);
    await bob.fetchAll();
    await bob.fetchAll();
    expect(bob.texts, ['x']);
    expect(bob.container.read(failureTickProvider), ticks);
    final counts = await bob.crypto.olm.failureCounts(
      bob.peer.olm!.identityKey,
    );
    expect(counts.malformed, 1, reason: 'counted once, not per fetch');
  });

  test('an open chat marks messages shown; until then they survive a '
      'restart, and so does the outbox', () async {
    final (alice, bob) = await met();
    await alice.send('läs mig');
    await bob.fetchAll();
    alice.relay.failDrop = const RelayUnavailable();
    await alice.send('inte skickat');

    await bob.restart();
    await bob.transport.restoreSaved();
    expect(bob.texts, ['läs mig']);
    await alice.restart();
    await alice.transport.restoreSaved();
    expect(alice.texts, ['inte skickat']);
    expect(alice.messages.single.pending, isTrue);

    final sub = bob.container.listen(chatProvider(bob.peer.id), (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(sub.read().messages.single.text, 'läs mig');
    expect(await bob.crypto.olm.inbox(), isEmpty);
    expect(bob.messages.single.shown, isTrue);

    await alice.transport.sendPending();
    await bob.fetchAll();
    expect(bob.texts, ['läs mig', 'inte skickat']);
  });

  test('rounds: every mailbox once inside the interval, then a new round; '
      'pause stops every timer', () async {
    final (alice, _) = await met();
    alice.transport.resume();
    await pumpEventQueue();
    // Two mailboxes for the one contact, and the next round.
    expect(alice.timers, hasLength(3));
    final round = alice.timers.last;
    expect(round.after, FetchInterval.five.duration);
    for (final t in alice.timers.take(2)) {
      expect(t.after, lessThan(FetchInterval.five.duration));
    }
    final fetches = alice.relay.fetches;
    for (final t in alice.timers.take(2)) {
      t.fire();
    }
    await pumpEventQueue();
    expect(alice.relay.fetches, fetches + 2);

    round.fire();
    await pumpEventQueue();
    expect(alice.timers, hasLength(6));

    alice.transport.pause();
    expect(alice.timers.where((t) => t.isActive), isEmpty);
    expect(alice.transport.running, isFalse);
  });

  test('the first round after a start waits for the saved contacts', () async {
    final (alice, _) = await met();
    alice.container.dispose();
    alice.newContainer();
    await alice.container.read(transportSettingsProvider.future);
    alice.transport.resume(); // contacts not read yet
    await pumpEventQueue();
    expect(alice.timers, hasLength(3), reason: 'two mailboxes and a round');
  });

  test('a new interval starts a new round with it', () async {
    final (alice, _) = await met();
    alice.transport.resume();
    await pumpEventQueue();
    await alice.container
        .read(transportSettingsProvider.notifier)
        .save(
          TransportSettings(
            server: Uri.parse('https://server.test'),
            interval: FetchInterval.sixty,
          ),
        );
    await pumpEventQueue();
    expect(
      alice.timers.where((t) => t.isActive).last.after,
      FetchInterval.sixty.duration,
    );
    expect(alice.timers.take(3).where((t) => t.isActive), isEmpty);
  });

  test('a failed save while fetching is not lost: the next round reads the '
      'packet again (0004 §6)', () async {
    final relay = FakeRelay();
    final alice = await App(relay).start();
    final bobVault = FailingVault();
    final bob = await App(relay, bobVault).start();
    await exchange(alice, bob);
    await alice.send('viktigt');

    bob.transport.resume();
    await pumpEventQueue();
    bobVault.failWrites = true;
    for (final t in [...bob.timers.take(2)]) {
      t.fire(); // must not throw out of the timer
    }
    await pumpEventQueue();
    expect(bob.texts, isEmpty);

    bobVault.failWrites = false;
    await bob.fetchAll();
    expect(bob.texts, ['viktigt']);
  });

  test('without a server address nothing is sent or fetched', () async {
    final relay = FakeRelay();
    final alice = App(relay);
    await alice.crypto.createIdentity();
    await alice.crypto.olm.ensureAccount();
    await alice.container.read(transportSettingsProvider.future);
    alice.transport.resume();
    await pumpEventQueue();
    expect(alice.timers, isEmpty);
    expect(alice.status, ServerStatus.notConfigured);
    await alice.transport.sendPending();
    expect(relay.dropped, isEmpty);
  });
}
