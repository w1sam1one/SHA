// Two apps for the transport tests (P6) and the whole chain (P7): each has
// its own vault, a relay (fake or real), fake timers and a clock it can
// move. Needs the native library (tool/build_native_host.sh).
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/message_store.dart';
import 'package:sha/features/chat/messaging_service.dart';
import 'package:sha/features/contacts/contacts_store.dart';
import 'package:sha/features/transport/relay_client.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_settings.dart';

import 'in_memory_vault.dart';

String hex(List<int> b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

/// The relay's two functions in memory. [failDrop] and [failFetch] answer
/// the next call with an error instead.
final class FakeRelay implements RelayClient {
  final Map<String, List<Uint8List>> boxes = {};
  final List<Uint8List> dropped = [];
  RelayException? failDrop;
  RelayException? failFetch;
  int fetches = 0;

  /// Mailboxes (hex) that answer 507 to every drop.
  final Set<String> full = {};

  @override
  Future<void> drop(Uint8List mailboxId, Uint8List packet) async {
    final e = failDrop;
    failDrop = null;
    if (e != null) throw e;
    if (full.contains(hex(mailboxId))) throw const RelayFull();
    dropped.add(packet);
    boxes.putIfAbsent(hex(mailboxId), () => []).add(packet);
  }

  @override
  Future<List<Uint8List>> fetch(Uint8List mailboxId) async {
    fetches++;
    final e = failFetch;
    failFetch = null;
    if (e != null) throw e;
    return [...?boxes[hex(mailboxId)]];
  }
}

final class FakeTimer implements Timer {
  FakeTimer(this.after, this.callback);

  final Duration after;
  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// One phone: its own vault, the shared relay, fake timers and a clock.
/// With [olmOnAppClock] the Olm service uses [now] too; otherwise it uses
/// the computer's clock.
final class App {
  App(
    this.relay, [
    InMemoryVault? vault,
    RelayClient Function(Uri)? client,
    this.olmOnAppClock = false,
  ]) : vault = vault ?? InMemoryVault(),
       _client = client ?? ((_) => relay) {
    _container();
  }

  final bool olmOnAppClock;

  /// The fake relay, or one that is never used when [client] is given.
  final FakeRelay relay;
  final RelayClient Function(Uri) _client;
  Uri server = Uri.parse('https://server.test');
  final InMemoryVault vault;
  final List<FakeTimer> timers = [];
  DateTime now = DateTime.utc(2026, 11, 16, 12);
  late ProviderContainer container;
  late PublicIdentity identity;

  void _container() => newContainer();

  void newContainer() {
    container = ProviderContainer(
      overrides: [
        keyVaultProvider.overrideWithValue(vault),
        if (olmOnAppClock)
          cryptoServiceProvider.overrideWith(
            (ref) => ShaCryptoService(
              vault: ref.watch(keyVaultProvider),
              clock: () => now,
            ),
          ),
        relayClientFactoryProvider.overrideWithValue(_client),
        transportTimerProvider.overrideWithValue((d, f) {
          final t = FakeTimer(d, f);
          timers.add(t);
          return t;
        }),
        transportClockProvider.overrideWithValue(() => now),
        transportRandomProvider.overrideWithValue(Random(7)),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<App> start() async {
    identity = await crypto.createIdentity();
    await crypto.olm.ensureAccount();
    await container
        .read(transportSettingsProvider.notifier)
        .save(TransportSettings(server: server));
    return this;
  }

  /// The app starting again on the same vault.
  Future<void> restart() async {
    container.dispose();
    _container();
    await container.read(transportSettingsProvider.future);
    await container.read(contactsProvider.notifier).ready;
  }

  CryptoService get crypto => container.read(cryptoServiceProvider);
  Transport get transport => container.read(transportProvider);
  MessagingService get messaging => container.read(messagingServiceProvider);
  ServerStatus get status => container.read(serverStatusProvider);
  List<Contact> get contacts => container.read(contactsProvider);
  Contact get peer => contacts.single;
  List<ChatMessage> get messages =>
      container.read(messageStoreProvider.notifier).forContact(peer.id);

  Future<void> send(String text) async {
    final (_, message) = await messaging.send(contact: peer, text: text);
    container.read(messageStoreProvider.notifier).add(peer.id, message);
    await transport.sendPending();
  }

  Future<void> fetchAll() async {
    for (final c in contacts) {
      for (final m in await messaging.inboxMailboxes(c)) {
        await transport.fetch(c, m);
      }
    }
  }

  List<String?> get texts => [for (final m in messages) m.text];
}

/// A vault whose writes fail while [failWrites] is set.
final class FailingVault extends InMemoryVault {
  bool failWrites = false;

  /// The next read throws, once.
  bool failNextRead = false;

  @override
  Future<Uint8List?> read(String name) async {
    if (failNextRead) {
      failNextRead = false;
      throw const CryptoException('locked', CryptoErrorKind.deviceLocked);
    }
    return super.read(name);
  }

  int? _okLeft;

  /// Lets [n] more writes through, then sets [failWrites].
  void failWritesAfter(int n) => _okLeft = n;

  @override
  Future<void> write(String name, Uint8List value) async {
    final left = _okLeft;
    if (left != null) {
      if (left == 0) {
        _okLeft = null;
        failWrites = true;
      } else {
        _okLeft = left - 1;
      }
    }
    if (failWrites) {
      throw const CryptoException('crash', CryptoErrorKind.unavailable);
    }
    await super.write(name, value);
  }
}

/// Alice and Bob meet and scan each other's codes.
Future<(App, App)> met() async {
  final relay = FakeRelay();
  final alice = await App(relay).start();
  final bob = await App(relay).start();
  await exchange(alice, bob);
  return (alice, bob);
}

Future<void> exchange(App alice, App bob) async {
  final aliceCode = await alice.crypto.olm.publishBundle();
  final bobCode = await bob.crypto.olm.publishBundle();
  await alice.container
      .read(contactsProvider.notifier)
      .addScanned(
        bundle: bobCode,
        addressingKey: bob.identity,
        name: 'Bob',
        metAt: alice.now,
      );
  await bob.container
      .read(contactsProvider.notifier)
      .addScanned(
        bundle: aliceCode,
        addressingKey: alice.identity,
        name: 'Alice',
        metAt: bob.now,
      );
}
