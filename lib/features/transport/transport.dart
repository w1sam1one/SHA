import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../crypto/crypto.dart';
import '../chat/message_store.dart';
import '../chat/messaging_service.dart';
import '../contacts/contacts_store.dart';
import 'fetch_plan.dart';
import 'relay_client.dart';
import 'transport_settings.dart';

/// What the app last heard from the server.
enum ServerStatus {
  /// No server address is set: nothing is sent or fetched.
  notConfigured,
  ok,

  /// `429` (0004 §10): the app waits for `Retry-After`.
  busy,

  /// `507` (0004 §10): a message waits in the outbox.
  full,

  /// No answer. Messages wait in the outbox.
  unavailable,
}

/// The network and the clock, swapped in tests.
final relayClientFactoryProvider = Provider<RelayClient Function(Uri)>(
  (ref) => HttpRelayClient.new,
);
final transportTimerProvider =
    Provider<Timer Function(Duration, void Function())>((ref) => Timer.new);
final transportRandomProvider = Provider<Random>((ref) => Random.secure());
final transportClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The server address and the fetch interval (0005, item 9).
class TransportSettingsStore extends AsyncNotifier<TransportSettings> {
  @override
  Future<TransportSettings> build() async => TransportSettings.fromMap(
    await ref.read(cryptoServiceProvider).olm.appSettings(),
  );

  Future<void> save(TransportSettings settings) async {
    final olm = ref.read(cryptoServiceProvider).olm;
    await olm.ensureAccount();
    await olm.saveAppSettings(settings.toMap());
    state = AsyncData(settings);
  }
}

final transportSettingsProvider =
    AsyncNotifierProvider<TransportSettingsStore, TransportSettings>(
      TransportSettingsStore.new,
    );

class ServerStatusNotifier extends Notifier<ServerStatus> {
  @override
  ServerStatus build() => ServerStatus.notConfigured;

  void set(ServerStatus status) => state = status;
}

final serverStatusProvider =
    NotifierProvider<ServerStatusNotifier, ServerStatus>(
      ServerStatusNotifier.new,
    );

/// Counts up when a packet from a contact could not be read, so an open
/// chat reads the failure counters again.
class FailureTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final failureTickProvider = NotifierProvider<FailureTick, int>(FailureTick.new);

/// Sends the outbox and fetches the contacts' mailboxes, only while the app
/// is open (0002, 0004 §9 (b)).
///
/// - **Fetching:** each round, every mailbox (today's and yesterday's per
///   contact) is fetched once, at its own random time in the interval, with
///   its own connection ([planRound]).
/// - **Sending:** right after a message is saved, and again each round. A
///   packet leaves the outbox only when the server answered `204`, and a
///   retry sends the same bytes (0004 §6).
/// - **`429`:** nothing is sent or fetched until `Retry-After` has passed.
/// - **Nothing in the background:** [pause] stops every timer when the app
///   is not in front, including when the phone is locked.
class Transport {
  Transport(this._ref) {
    _ref
      ..listen(transportSettingsProvider, (_, _) {
        if (_running) _restart();
      })
      // Keeps the contact list loaded while the transport exists.
      ..listen(contactsProvider, (_, _) {});
  }

  final Ref _ref;
  final List<Timer> _timers = [];
  bool _running = false;
  bool _restored = false;
  DateTime? _busyUntil;
  Future<void>? _sending;
  bool _sendAgain = false;

  CryptoService get _crypto => _ref.read(cryptoServiceProvider);
  MessagingService get _messaging => _ref.read(messagingServiceProvider);
  DateTime _now() => _ref.read(transportClockProvider)();

  bool get running => _running;

  /// The app is in front: start a round now.
  void resume() {
    if (_running) return;
    _running = true;
    _restart();
  }

  /// The app is not in front: stop every timer. A request already sent is
  /// let finish.
  void pause() {
    _running = false;
    _cancelTimers();
  }

  void dispose() => pause();

  /// Messages saved before the app was closed: the inbox (not yet shown)
  /// and the outbox (not yet sent) (0005 (i)).
  Future<void> restoreSaved() async {
    if (_restored) return;
    _restored = true;
    final store = _ref.read(messageStoreProvider.notifier);
    final olm = _crypto.olm;
    for (final m in await olm.inbox()) {
      store.add(await _contactId(m.peer), _messaging.incomingMessage(m));
    }
    for (final o in await olm.outbox()) {
      final message = _messaging.outgoingMessage(o);
      if (message != null) store.add(await _contactId(o.peer), message);
    }
  }

  /// Sends everything in the outbox, in order. Stops at the first packet
  /// the server does not take.
  Future<void> sendPending() {
    final running = _sending;
    if (running != null) {
      _sendAgain = true;
      return running;
    }
    return _sending = () async {
      try {
        do {
          _sendAgain = false;
          await _sendOutbox();
        } while (_sendAgain);
      } finally {
        _sending = null;
      }
    }();
  }

  Future<void> _sendOutbox() async {
    final client = _client();
    if (client == null || _isBusy()) return;
    await _ref.read(contactsProvider.notifier).ready;
    final contacts = _ref.read(contactsProvider);
    final store = _ref.read(messageStoreProvider.notifier);
    for (final out in await _crypto.olm.outbox()) {
      final contact = _contactFor(contacts, out.peer);
      if (contact == null) continue;
      final packet = PacketV3.wrap(
        await _messaging.outgoingMailbox(contact),
        out.packet,
      );
      if (!await _call(() => client.drop(packet.sublist(1, 17), packet))) {
        return;
      }
      await _crypto.olm.markSent(out.id);
      final message = _messaging.outgoingMessage(out);
      if (message != null) {
        store.update(
          contact.id,
          message.id,
          (m) => m.copyWith(pending: false, clearSavedId: true),
        );
      }
    }
  }

  /// Fetches one mailbox of [contact] and reads every packet in it.
  Future<void> fetch(Contact contact, Uint8List mailbox) async {
    final client = _client();
    final olm = contact.olm;
    if (client == null || olm == null || _isBusy()) return;
    late List<Uint8List> packets;
    if (!await _call(() async => packets = await client.fetch(mailbox))) {
      return;
    }
    final store = _ref.read(messageStoreProvider.notifier);
    for (final packet in packets) {
      final Uint8List inner;
      try {
        inner = PacketV3.unwrap(packet);
      } on CryptoException {
        // Not a version 3 packet. Passed on whole: its first byte is not an
        // Olm type, so it is counted as malformed, once (0004 §10).
        await _crypto.olm.receive(olm.identityKey, packet);
        continue;
      }
      final result = await _crypto.olm.receive(olm.identityKey, inner);
      final message = result.message;
      if (message != null) {
        store.add(contact.id, _messaging.incomingMessage(message));
      } else if (result.failure != OlmReceiveFailure.duplicate &&
          result.failure != OlmReceiveFailure.malformed) {
        _ref.read(failureTickProvider.notifier).bump();
      }
    }
  }

  void _restart() {
    _cancelTimers();
    if (_running) unawaited(_round());
  }

  Future<void> _round() async {
    final settings = _ref.read(transportSettingsProvider).value;
    if (settings?.server == null) {
      _status(ServerStatus.notConfigured);
      return;
    }
    await restoreSaved();
    _quietly(sendPending());
    final mailboxes = <({Contact contact, Uint8List mailbox})>[];
    // The first round after start waits for the saved contacts.
    await _ref.read(contactsProvider.notifier).ready;
    for (final c in _ref.read(contactsProvider)) {
      if (c.olm == null) continue;
      for (final m in await _messaging.inboxMailboxes(c)) {
        mailboxes.add((contact: c, mailbox: m));
      }
    }
    if (!_running) return;
    final round = planRound(
      mailboxes,
      settings!.interval.duration,
      _ref.read(transportRandomProvider),
    );
    final timer = _ref.read(transportTimerProvider);
    for (final r in round.requests) {
      _timers.add(
        timer(r.at, () => _quietly(fetch(r.item.contact, r.item.mailbox))),
      );
    }
    _timers.add(timer(round.length, _restart));
  }

  /// Runs [work] in the background. A failure (for example a locked phone
  /// or a failed vault write) leaves everything saved as it was (0004 §6),
  /// and the next round tries again. Its text is not kept.
  static void _quietly(Future<void> work) => unawaited(work.catchError((_) {}));

  /// [sendPending] in the background, for the chat.
  void sendSoon() => _quietly(sendPending());

  RelayClient? _client() {
    final server = _ref.read(transportSettingsProvider).value?.server;
    if (server == null) {
      _status(ServerStatus.notConfigured);
      return null;
    }
    return _ref.read(relayClientFactoryProvider)(server);
  }

  bool _isBusy() {
    final until = _busyUntil;
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _busyUntil = null;
    return false;
  }

  /// Runs one request. Returns whether the server answered as hoped; a
  /// failure only sets the status.
  Future<bool> _call(Future<void> Function() request) async {
    try {
      await request();
      _status(ServerStatus.ok);
      return true;
    } on RelayBusy catch (e) {
      _busyUntil = _now().add(e.retryAfter);
      _status(ServerStatus.busy);
    } on RelayFull {
      _status(ServerStatus.full);
    } on RelayUnavailable {
      _status(ServerStatus.unavailable);
    }
    return false;
  }

  void _status(ServerStatus status) =>
      _ref.read(serverStatusProvider.notifier).set(status);

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  static Contact? _contactFor(List<Contact> contacts, Uint8List peer) {
    for (final c in contacts) {
      final key = c.olm?.identityKey;
      if (key != null && _same(key, peer)) return c;
    }
    return null;
  }

  Future<String> _contactId(Uint8List peer) async {
    final hash = await _crypto.sha256(peer);
    return [for (final b in hash) b.toRadixString(16).padLeft(2, '0')].join();
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final transportProvider = Provider<Transport>((ref) {
  final transport = Transport(ref);
  ref.onDispose(transport.dispose);
  return transport;
});
