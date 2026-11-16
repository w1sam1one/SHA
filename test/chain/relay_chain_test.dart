// P7 (0004 §11, item 9): two apps against the real relay (relay/), over
// plain HTTP on this computer. The answers 204, 507 and 429, duplicates,
// and crashes before and after saving (0004 §6).
//
// Needs the relay binary (tool/build_relay.sh, or SHA_RELAY_BIN) and the
// native library (tool/build_native_host.sh).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/transport/relay_client.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_settings.dart';

import '../support/two_apps.dart';

/// One relay process on a free port of this computer.
final class RelayProcess {
  RelayProcess._(this._process, this.uri);

  final Process _process;
  final Uri uri;

  static Future<RelayProcess> start([List<String> flags = const []]) async {
    final bin = Platform.environment['SHA_RELAY_BIN'] ?? 'build/relay/relay';
    if (!File(bin).existsSync()) {
      fail('No relay at $bin. Run tool/build_relay.sh first.');
    }
    final free = await ServerSocket.bind('127.0.0.1', 0);
    final port = free.port;
    await free.close();
    final process = await Process.start(bin, [
      '-addr',
      '127.0.0.1:$port',
      ...flags,
    ]);
    process.stdout.drain<void>().ignore();
    process.stderr.drain<void>().ignore();
    final uri = Uri.parse('http://127.0.0.1:$port');
    final relay = RelayProcess._(process, uri);
    addTearDown(relay.stop);
    for (var i = 0; i < 100; i++) {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          uri.replace(path: '/healthz'),
        )).close();
        await response.drain<void>();
        if (response.statusCode == 200) return relay;
      } on IOException {
        // Not listening yet.
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('The relay did not start');
  }

  Future<void> stop() async {
    _process.kill();
    await _process.exitCode;
  }
}

/// Counts the requests that reach the network.
final class Counting implements RelayClient {
  Counting(this._inner);

  final RelayClient _inner;
  int calls = 0;

  @override
  Future<void> drop(Uint8List mailboxId, Uint8List packet) {
    calls++;
    return _inner.drop(mailboxId, packet);
  }

  @override
  Future<List<Uint8List>> fetch(Uint8List mailboxId) {
    calls++;
    return _inner.fetch(mailboxId);
  }
}

/// Alice and Bob on [relay], after meeting.
Future<(App, App)> onRelay(
  RelayProcess relay, {
  FailingVault? aliceVault,
  FailingVault? bobVault,
  Counting? aliceClient,
}) async {
  App app(FailingVault? vault, Counting? counting) =>
      App(FakeRelay(), vault, (uri) => counting ?? HttpRelayClient(uri))
        ..server = relay.uri;

  final alice = await app(aliceVault, aliceClient).start();
  final bob = await app(bobVault, null).start();
  await exchange(alice, bob);
  return (alice, bob);
}

Future<void> moveTo(App app, RelayProcess relay) => app.container
    .read(transportSettingsProvider.notifier)
    .save(TransportSettings(server: relay.uri));

void main() {
  test('204: Alice → relay → Bob and back, and packets fetched again give '
      'one message each', () async {
    final relay = await RelayProcess.start();
    final (alice, bob) = await onRelay(relay);
    await alice.send('Hej Bob');
    expect(alice.status, ServerStatus.ok);
    expect(alice.messages.single.pending, isFalse);

    await bob.fetchAll();
    await bob.fetchAll(); // the relay hands out the same packets again
    expect(bob.texts, ['Hej Bob']);

    await bob.send('Hej Alice');
    await bob.send('Hur är det?');
    await alice.fetchAll();
    await alice.fetchAll();
    expect(alice.texts, ['Hej Bob', 'Hej Alice', 'Hur är det?']);
    final key = alice.peer.olm!.identityKey;
    final counts = await alice.crypto.olm.failureCounts(key);
    expect(
      [counts.unreadable, counts.tooLate, counts.gapTooBig, counts.malformed],
      [0, 0, 0, 0],
    );
  });

  test('507: the message waits in the outbox and is sent again with the '
      'same bytes when there is room', () async {
    final small = await RelayProcess.start(['-max-packets-per-mailbox', '1']);
    final (alice, bob) = await onRelay(small);
    await alice.send('ett');
    await alice.send('två');
    expect(alice.status, ServerStatus.full);
    expect([for (final m in alice.messages) m.pending], [false, true]);
    final waiting = (await alice.crypto.olm.outbox()).single.packet;

    await bob.fetchAll();
    expect(bob.texts, ['ett']);

    // Both move to a relay with room.
    final big = await RelayProcess.start();
    await moveTo(alice, big);
    await moveTo(bob, big);
    await alice.transport.sendPending();
    expect(alice.status, ServerStatus.ok);
    expect(await alice.crypto.olm.outbox(), isEmpty);
    final there = await HttpRelayClient(big.uri)
        .fetch(await alice.messaging.outgoingMailbox(alice.peer));
    expect(there.single.sublist(PacketV3.headerLength - 1), waiting);

    await bob.fetchAll();
    expect(bob.texts, ['ett', 'två']);
  });

  test('429: the app sends and fetches nothing until Retry-After', () async {
    final strict = await RelayProcess.start(['-rate-limit', '3']);
    final counting = Counting(HttpRelayClient(strict.uri));
    final (alice, _) = await onRelay(strict, aliceClient: counting);
    await alice.send('ett'); // 1
    await alice.fetchAll(); // 2 and 3
    await alice.fetchAll(); // 4: 429
    expect(alice.status, ServerStatus.busy);
    final calls = counting.calls;

    await alice.send('två');
    await alice.fetchAll();
    expect(counting.calls, calls, reason: 'nothing reached the network');
    expect(alice.messages.last.pending, isTrue);

    alice.now = alice.now.add(const Duration(seconds: 61));
    await alice.transport.sendPending();
    expect(counting.calls, greaterThan(calls));
  });

  test('a crash after the relay took the packet: it is sent again, and '
      'read once', () async {
    final relay = await RelayProcess.start();
    final aliceVault = FailingVault();
    final (alice, bob) = await onRelay(relay, aliceVault: aliceVault);
    final ticks = bob.container.read(failureTickProvider);

    // The relay answers 204, then saving "sent" fails.
    aliceVault.failWritesAfter(1);
    await expectLater(alice.send('igen'), throwsA(isA<CryptoException>()));
    aliceVault.failWrites = false;

    await alice.restart();
    await alice.transport.restoreSaved();
    expect(alice.messages.single.pending, isTrue);
    await alice.transport.sendPending();
    expect(await alice.crypto.olm.outbox(), isEmpty);

    final box = await HttpRelayClient(relay.uri)
        .fetch(await alice.messaging.outgoingMailbox(alice.peer));
    expect(box, hasLength(2), reason: 'the same packet twice');
    expect(box[0], box[1]);

    await bob.fetchAll();
    expect(bob.texts, ['igen']);
    expect(bob.container.read(failureTickProvider), ticks);
  });

  test('a crash while reading: the packet is read after the restart', () async {
    final relay = await RelayProcess.start();
    final bobVault = FailingVault();
    final (alice, bob) = await onRelay(relay, bobVault: bobVault);
    await alice.send('vänta på mig');

    bobVault.failWrites = true;
    await expectLater(bob.fetchAll(), throwsA(isA<CryptoException>()));
    bobVault.failWrites = false;
    expect(bob.texts, isEmpty);

    await bob.restart();
    await bob.fetchAll();
    expect(bob.texts, ['vänta på mig']);
  });
}
