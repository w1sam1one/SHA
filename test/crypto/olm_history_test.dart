// F3 in docs/ROADMAP.md: the history in vault entries of its own, by (B)
// in 0010. A message is kept in the history before it leaves the inbox or
// the outbox, so a crash neither loses it nor keeps it twice. Needs the
// native library (tool/build_native_host.sh).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/crypto/src/sha_olm_service.dart';

import 'olm_service_cases.dart';

final RegExp entryName = RegExp(r'^h\.[0-9a-f]{16}$');

final class Clock {
  DateTime now = DateTime.utc(2026, 11, 1, 12);

  DateTime call() => now;
}

List<String> historyEntries(Person p) =>
    [for (final name in p.vault.values.keys) name]
        .where(entryName.hasMatch)
        .toList();

/// The entry names the saved state knows about.
List<String> knownEntries(Person p) => [
  for (final refs in ((p.savedState['history'] as Map?) ?? const {}).values)
    for (final r in refs as List) (r as Map)['name']! as String,
];

/// Alice and Bob have met; Alice has sent [texts] and Bob has read them,
/// but not shown them yet.
Future<(Person, Person, List<OlmIncoming>)> received(
  List<String> texts, {
  Clock? clock,
  CrashingVault? bobVault,
}) async {
  final alice = await Person(null, clock?.call).start();
  final bob = await Person(bobVault, clock?.call).start();
  await scan(alice, bob);
  for (final t in texts) {
    final out = await alice.olm.encrypt(bob.key, t);
    await alice.olm.markSent(out.id);
    expect(await deliver(bob, alice, out), t);
  }
  return (alice, bob, await bob.olm.inbox());
}

void main() {
  test('a shown message is kept in an entry with a random name, and read '
      'back after a restart', () async {
    final clock = Clock();
    final (alice, bob, inbox) = await received(['hej'], clock: clock);
    await bob.olm.markShown(inbox.single.id, keep: true);
    expect(await bob.olm.inbox(), isEmpty);
    final names = historyEntries(bob);
    expect(names, hasLength(1));
    expect(knownEntries(bob), names);
    // Nothing in the name points at the contact.
    final keyHex = [
      for (final b in alice.key.take(8)) b.toRadixString(16).padLeft(2, '0'),
    ].join();
    expect(names.single, isNot(contains(keyHex)));

    bob.restart();
    final kept = await bob.olm.history();
    expect(kept.map((h) => h.text), ['hej']);
    expect(kept.single.outgoing, isFalse);
    expect(kept.single.peer, alice.key);
    expect(kept.single.at, clock.now);
    expect(kept.single.id, inbox.single.id);
  });

  test('a sent message is kept when the relay has taken it', () async {
    final alice = await Person().start();
    final bob = await Person().start();
    await scan(alice, bob);
    final out = await alice.olm.encrypt(bob.key, 'till Bob');
    await alice.olm.markSent(out.id, keep: true);
    expect(await alice.olm.outbox(), isEmpty);
    final kept = await alice.olm.history();
    expect(kept.map((h) => (h.text, h.outgoing)), [('till Bob', true)]);
    expect(kept.single.peer, bob.key);
  });

  test('without keep nothing is kept', () async {
    final (_, bob, inbox) = await received(['hej']);
    await bob.olm.markShown(inbox.single.id);
    expect(historyEntries(bob), isEmpty);
    expect(await bob.olm.history(), isEmpty);
  });

  group('a crash while keeping', () {
    for (final (at, what) in [
      (0, 'saving the state, before the entry'),
      (1, 'writing the entry'),
      (2, 'taking the message off the inbox'),
    ]) {
      test('$what: the message is neither lost nor kept twice', () async {
        final vault = CrashingVault();
        final (_, bob, inbox) = await received(['hej'], bobVault: vault);
        vault.failWriteAt = at;
        await expectLater(
          bob.olm.markShown(inbox.single.id, keep: true),
          throwsA(isA<CryptoException>()),
        );
        bob.restart();
        // Not lost: still in the inbox, so it is shown again.
        expect((await bob.olm.inbox()).map((m) => m.text), ['hej']);
        // No entry that the state does not know about.
        expect(historyEntries(bob).every(knownEntries(bob).contains), isTrue);
        // Shown again: kept once.
        await bob.olm.markShown(inbox.single.id, keep: true);
        expect((await bob.olm.history()).map((h) => h.text), ['hej']);
        expect(await bob.olm.inbox(), isEmpty);
        expect(historyEntries(bob), hasLength(1));
      });
    }
  });

  test('a full entry starts a new one, and the order is kept', () async {
    final texts = [
      for (var i = 0; i <= ShaOlmService.historyEntrySize; i++) 'm$i',
    ];
    final (_, bob, inbox) = await received(texts);
    for (final m in inbox) {
      await bob.olm.markShown(m.id, keep: true);
    }
    expect(historyEntries(bob), hasLength(2));
    expect((await bob.olm.history()).map((h) => h.text), texts);
  });

  test('pruneHistory removes what is older than the cutoff, single messages '
      'and whole entries', () async {
    final clock = Clock();
    final (_, bob, inbox) = await received(['a', 'b', 'c'], clock: clock);
    final start = clock.now;
    for (final (i, m) in inbox.indexed) {
      clock.now = start.add(Duration(days: [0, 1, 10][i]));
      await bob.olm.markShown(m.id, keep: true);
    }
    await bob.olm.pruneHistory(start.add(const Duration(days: 5)));
    expect((await bob.olm.history()).map((h) => h.text), ['c']);
    expect(historyEntries(bob), hasLength(1));

    await bob.olm.pruneHistory(start.add(const Duration(days: 11)));
    expect(await bob.olm.history(), isEmpty);
    expect(historyEntries(bob), isEmpty);
    expect(knownEntries(bob), isEmpty);
  });

  test(
    'a crash while pruning leaves no entry that the state does not know',
    () async {
      final clock = Clock();
      final vault = CrashingVault();
      final (_, bob, inbox) = await received(
        ['a'],
        clock: clock,
        bobVault: vault,
      );
      await bob.olm.markShown(inbox.single.id, keep: true);
      vault.failWriteAt = 0; // the state, after the entry was deleted
      await expectLater(
        bob.olm.pruneHistory(clock.now.add(const Duration(days: 1))),
        throwsA(isA<CryptoException>()),
      );
      bob.restart();
      expect(historyEntries(bob), isEmpty);
      expect(await bob.olm.history(), isEmpty);
      await bob.olm.pruneHistory(clock.now.add(const Duration(days: 1)));
      expect(knownEntries(bob), isEmpty);
    },
  );

  test('clearHistory deletes every entry', () async {
    final (_, bob, inbox) = await received(['a', 'b']);
    for (final m in inbox) {
      await bob.olm.markShown(m.id, keep: true);
    }
    await bob.olm.clearHistory();
    expect(historyEntries(bob), isEmpty);
    expect(knownEntries(bob), isEmpty);
    expect(await bob.olm.history(), isEmpty);
  });

  test(
    'a damaged entry is skipped, and the next message starts a new one',
    () async {
      final (_, bob, inbox) = await received(['a', 'b']);
      await bob.olm.markShown(inbox.first.id, keep: true);
      final name = historyEntries(bob).single;
      bob.vault.values[name] = Uint8List.fromList(utf8.encode('{trasig'));
      bob.restart();
      expect(await bob.olm.history(), isEmpty);
      await bob.olm.markShown(inbox.last.id, keep: true);
      expect((await bob.olm.history()).map((h) => h.text), ['b']);
      expect(historyEntries(bob), hasLength(2));
    },
  );

  test('an entry the vault cannot decrypt is skipped, and the next message '
      'starts a new one (review of #46)', () async {
    final (_, bob, inbox) = await received(['a', 'b']);
    await bob.olm.markShown(inbox.first.id, keep: true);
    bob.vault.unreadable.add(historyEntries(bob).single);
    bob.restart();
    expect(await bob.olm.history(), isEmpty);
    await bob.olm.markShown(inbox.last.id, keep: true);
    expect((await bob.olm.history()).map((h) => h.text), ['b']);
    expect(historyEntries(bob), hasLength(2));
    await bob.olm.pruneHistory(DateTime.utc(2000));
  });

  test('a message is not kept twice when a full entry was written just '
      'before a crash (review of #46)', () async {
    final vault = CrashingVault();
    final size = ShaOlmService.historyEntrySize;
    final texts = [for (var i = 0; i <= size; i++) 'm$i'];
    // A clock that stands still: appending writes only the entry, so the
    // write after it is the one that takes the message off the inbox.
    final (_, bob, inbox) = await received(
      texts,
      clock: Clock(),
      bobVault: vault,
    );
    for (final m in inbox.take(size - 1)) {
      await bob.olm.markShown(m.id, keep: true);
    }
    // The last message of the full entry: kept, then a crash before it
    // leaves the inbox.
    vault.failWriteAt = 1;
    await expectLater(
      bob.olm.markShown(inbox[size - 1].id, keep: true),
      throwsA(isA<CryptoException>()),
    );
    bob.restart();
    // The next message starts a new entry; then the first is shown again.
    await bob.olm.markShown(inbox[size].id, keep: true);
    await bob.olm.markShown(inbox[size - 1].id, keep: true);
    final ids = [for (final h in await bob.olm.history()) h.id];
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, hasLength(size + 1));
    expect(await bob.olm.inbox(), isEmpty);
  });

  test('resetIdentity deletes the history', () async {
    final (_, bob, inbox) = await received(['a']);
    await bob.olm.markShown(inbox.single.id, keep: true);
    await bob.service.resetIdentity();
    expect(historyEntries(bob), isEmpty);
  });
}
