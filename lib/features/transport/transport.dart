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
    // A shorter time takes effect at once (0010 (B)).
    await pruneHistory(
      olm,
      settings.history,
      ref.read(transportClockProvider)(),
    );
  }

  /// Removes from the history what is older than [length] allows, or all
  /// of it with [HistoryLength.none].
  static Future<void> pruneHistory(
    OlmService olm,
    HistoryLength length,
    DateTime now,
  ) => length.keeps
      ? olm.pruneHistory(now.subtract(length.duration))
      : olm.clearHistory();
}

final transportSettingsProvider =
    AsyncNotifierProvider<TransportSettingsStore, TransportSettings>(
      TransportSettingsStore.new,
    );

class ServerStatusNotifier extends Notifier<ServerStatus> {
  /// Neutral until the server has answered: the chat says "no server"
  /// from the settings, not from this.
  @override
  ServerStatus build() => ServerStatus.ok;

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
  /// Put in front of a packet that is not format 3, so the Olm service
  /// counts it as malformed: it is never an Olm type (0 or 1).
  static const int notAPacket = 0xff;

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

  /// Counts rounds: a round started before a restart schedules nothing.
  int _generation = 0;
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
    final olm = _crypto.olm;
    final store = _ref.read(messageStoreProvider.notifier);
    // The history first (0010 (B)): a message that is both there and still
    // in the inbox or the outbox, after a crash, is shown once. Only what the
    // chosen time keeps, even if a round could not prune.
    final length = (await _ref.read(transportSettingsProvider.future)).history;
    final from = _now().subtract(length.duration);
    for (final h in await olm.history()) {
      if (!length.keeps || h.at.isBefore(from)) continue;
      store.add(await _contactId(h.peer), _messaging.historyMessage(h));
    }
    for (final m in await olm.inbox()) {
      await _addIncoming(await _contactId(m.peer), m);
    }
    for (final o in await olm.outbox()) {
      final message = _messaging.outgoingMessage(o);
      if (message != null) store.add(await _contactId(o.peer), message);
    }
    _restored = true; // only after it worked: a failure is tried again
  }

  /// Adds a read message to the chat. A second message with the same ID is
  /// not shown, so it is removed from the inbox at once: no text stays on
  /// disk that will never be shown (0005 (i)).
  Future<void> _addIncoming(String contactId, OlmIncoming m) async {
    final added = _ref
        .read(messageStoreProvider.notifier)
        .add(contactId, _messaging.incomingMessage(m));
    if (!added) await _crypto.olm.markShown(m.id);
  }

  /// Sends everything in the outbox, in order. A full mailbox (507) skips
  /// the rest for that contact only; 429 or no answer stops everything.
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
    final keep = (await _ref.read(transportSettingsProvider.future)).history;
    final full = <String>{};
    for (final out in await _crypto.olm.outbox()) {
      final contact = _contactFor(contacts, out.peer);
      if (contact == null || full.contains(contact.id)) continue;
      final packet = PacketV3.wrap(
        await _messaging.outgoingMailbox(contact),
        out.packet,
      );
      final error = await _call(
        () => client.drop(packet.sublist(1, 17), packet),
      );
      if (error is RelayFull) {
        full.add(contact.id); // keep the order for this contact
        continue;
      }
      if (error != null) return;
      await _crypto.olm.markSent(out.id, keep: keep.keeps);
      final message = _messaging.outgoingMessage(out);
      if (message != null) {
        store.update(
          contact.id,
          message.id,
          (m) => m.copyWith(pending: false, clearSavedId: true),
        );
      }
    }
    // Another contact's success must not hide a message that waits.
    if (full.isNotEmpty) _status(ServerStatus.full);
  }

  /// Fetches one mailbox of [contact] and reads every packet in it.
  Future<void> fetch(Contact contact, Uint8List mailbox) async {
    final client = _client();
    final olm = contact.olm;
    if (client == null || olm == null || _isBusy()) return;
    late List<Uint8List> packets;
    if (await _call(() async => packets = await client.fetch(mailbox)) !=
        null) {
      return;
    }
    for (final packet in packets) {
      final Uint8List inner;
      try {
        inner = PacketV3.unwrap(packet);
      } on CryptoException {
        // Not a version 3 packet: shows nothing (0004 §10). It is passed on
        // behind a byte that is never an Olm type, so it is counted as
        // malformed, once, whatever its own first byte is.
        await _crypto.olm.receive(
          olm.identityKey,
          Uint8List.fromList([notAPacket, ...packet]),
        );
        continue;
      }
      final result = await _crypto.olm.receive(
        olm.identityKey,
        inner,
        writtenAt: _messaging.writtenAt,
      );
      final message = result.message;
      if (message != null) {
        await _addIncoming(contact.id, message);
      } else if (result.failure != OlmReceiveFailure.duplicate &&
          result.failure != OlmReceiveFailure.malformed) {
        _ref.read(failureTickProvider.notifier).bump();
      }
    }
  }

  void _restart() {
    _cancelTimers();
    final generation = ++_generation;
    if (_running) unawaited(_round(generation));
  }

  /// One round. A failure (a locked phone, a failed read) is not thrown:
  /// the next round is still planned and tries again.
  Future<void> _round(int generation) async {
    final settings = _ref.read(transportSettingsProvider).value;
    final server = settings?.server;
    var next =
        (settings?.interval ?? TransportSettings.defaultInterval).duration;
    bool current() => _running && generation == _generation;
    try {
      // What the history may no longer keep goes first, also before a server
      // is set (0010 (B)). A failure here does not stop the round.
      try {
        // The saved choice, read first: never the default before the
        // settings are loaded (review of #46).
        final saved = await _ref.read(transportSettingsProvider.future);
        await TransportSettingsStore.pruneHistory(
          _crypto.olm,
          saved.history,
          _now(),
        );
      } on Object {
        // The text is not kept. The next round tries again.
      }
      // Saved messages are shown even before a server is set.
      await restoreSaved();
      // Old sessions go even when nothing else is saved (0009 (iv)).
      _quietly(_crypto.olm.removeOldSessions());
      if (server == null) {
        _status(ServerStatus.notConfigured);
        return;
      }
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
      if (!current()) return;
      final round = planRound(
        mailboxes,
        next,
        _ref.read(transportRandomProvider),
      );
      next = round.length;
      final timer = _ref.read(transportTimerProvider);
      for (final r in round.requests) {
        _timers.add(
          timer(r.at, () => _quietly(fetch(r.item.contact, r.item.mailbox))),
        );
      }
    } catch (_) {
      // The text is not kept. The next round tries again.
    } finally {
      if (server != null && current()) {
        _timers.add(_ref.read(transportTimerProvider)(next, _restart));
      }
    }
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

  /// Runs one request. Returns null if the server answered as hoped, or
  /// what went wrong; a failure also sets the status.
  Future<RelayException?> _call(Future<void> Function() request) async {
    try {
      await request();
      _status(ServerStatus.ok);
      return null;
    } on RelayBusy catch (e) {
      _busyUntil = _now().add(e.retryAfter);
      _status(ServerStatus.busy);
      return e;
    } on RelayFull catch (e) {
      _status(ServerStatus.full);
      return e;
    } on RelayUnavailable catch (e) {
      _status(ServerStatus.unavailable);
      return e;
    }
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
