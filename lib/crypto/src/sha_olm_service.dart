import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fv;
import 'package:vodozemac/vodozemac.dart';

import 'entropy.dart';
import 'hashing.dart';
import 'key_vault.dart';
import 'olm_padding.dart';
import 'olm_service.dart';
import 'types.dart';
import 'wipe.dart';

/// Default [OlmService] (P3 in docs/ROADMAP.md).
///
/// - **One vault entry** ([stateName]) holds everything: the account pickle,
///   the session pickles per contact with their numbers, the hashes of
///   handled packets, the outbox, the received messages not yet shown and
///   the failure counters (0005 (A)). Every change is one [KeyVault.write],
///   so it is saved completely or not at all.
/// - **The pickle key** is 32 bytes from [MixedEntropy] in its own entry
///   ([pickleKeyName], 0004 §6). Pickles are encrypted by vodozemac with it,
///   and the vault entry is encrypted again by the Keystore.
/// - **Every attempt starts from the saved pickle** (0004 §6): an account or
///   session is unpickled for one attempt and thrown away if it fails, so a
///   failed decrypt cannot change what is saved.
/// - **The library's error text is never kept.** It can contain keys
///   (0003, R4). Failures become an [OlmReceiveFailure] or a fixed
///   [CryptoException].
///
/// OGRANSKAT (0004 §6). See [OlmService].
final class ShaOlmService implements OlmService {
  ShaOlmService({
    required this._vault,
    required this._entropy,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String stateName = 'olm.state.v1';
  static const String pickleKeyName = 'olm.pickle-key.v1';

  /// Hashes of handled packets are kept this long. The relay keeps a packet
  /// for 48 hours (`relay/limits.go`); the margin covers a wrong clock.
  static const Duration keepHashes = Duration(hours: 72);

  /// Shown one-time keys that no session has used are removed after this
  /// long (0004 §8 (a)); the owner may choose another number of days.
  static const Duration keepUnusedOneTimeKeys = Duration(days: 30);

  /// How long the relay keeps a packet (`relay/limits.go`, `packetTTL`).
  static const Duration relayKeepsPackets = Duration(hours: 48);

  /// For a clock that is wrong, ours or the contact's (0009, the owner's
  /// decision 2026-11-18).
  static const Duration clockMargin = Duration(hours: 24);

  /// Messages per history entry (0010 (B)). A full entry is left as it is
  /// and a new one is started, so a write stays small.
  static const int historyEntrySize = 100;

  /// Conditions 4 and 5 of rule (iv) in 0009, in milliseconds.
  static final int _oldAfter = (relayKeepsPackets + clockMargin).inMilliseconds;

  final KeyVault _vault;
  final MixedEntropy _entropy;
  final DateTime Function() _clock;
  final Sha256Hasher _hasher = Sha256Hasher();
  final Random _ids = Random.secure();

  /// The state as last saved, or null if it must be read again.
  _State? _saved;
  Uint8List? _pickleKey;
  Future<void> _tail = Future.value();

  /// Runs [action] after every earlier call has finished, so two calls never
  /// work on the same state.
  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Runs [action] (the vault's reset) with no call in progress, then
  /// forgets everything held in memory. Used by `resetIdentity()`.
  Future<void> discardAfter(Future<void> Function() action) =>
      _serial(() async {
        try {
          await action();
        } finally {
          _forget();
        }
      });

  void _forget() {
    _saved = null;
    final key = _pickleKey;
    if (key != null) wipe(key);
    _pickleKey = null;
  }

  @override
  Future<Uint8List?> identityKey() => _serial(() async {
    final state = await _load();
    return state == null ? null : base64.decode(state.identityKey);
  });

  @override
  Future<Uint8List> ensureAccount() => _serial(() async {
    final state = await _load();
    if (state != null) return base64.decode(state.identityKey);
    return _createAccount();
  });

  @override
  Future<Uint8List> createAccount() => _serial(_createAccount);

  Future<Uint8List> _createAccount() async {
    await _init();
    if (await _load() != null) {
      throw const CryptoException('An Olm account already exists');
    }
    final key = await _loadOrMakePickleKey();
    final account = Account();
    final state = _State(
      account: account.toPickleEncrypted(key),
      identityKey: base64.encode(account.curve25519Key.toBytes()),
    );
    await _save(state);
    return base64.decode(state.identityKey);
  }

  @override
  Future<OlmContactBundle> publishBundle() => _serial(() async {
    final (state, key) = await _require();
    final next = state.copy();
    // Clean up shown keys nobody used in time (0004 §8 (a)). A key that a
    // session already used is gone from the account, and removing it makes
    // the library panic and leaves that account object unusable. So each
    // removal is tried on a fresh account from the pickle, and only one
    // that worked is kept.
    final cutoff = _now() - keepUnusedOneTimeKeys.inMilliseconds;
    for (final old in [...next.shown.entries.where((e) => e.value < cutoff)]) {
      final candidate = _accountFrom(next.account, key);
      try {
        wipe(candidate.removeOneTimeKey(old.key)); // the removed private key
        next.account = candidate.toPickleEncrypted(key);
      } catch (_) {
        // Already used: nothing to remove. The object is dropped.
      }
      next.shown.remove(old.key);
    }
    final account = _accountFrom(next.account, key);
    final Curve25519PublicKey oneTimeKey;
    try {
      account.generateOneTimeKeys(1);
      oneTimeKey = account.oneTimeKeys.values.single;
      account.markKeysAsPublished();
    } catch (_) {
      throw const CryptoException('Could not make a one-time key');
    }
    next
      ..account = account.toPickleEncrypted(key)
      ..shown[oneTimeKey.toBase64()] = _now();
    // Save before the key is shown (0004 §6): a shown key must survive.
    await _save(next);
    return OlmContactBundle(
      identityKey: base64.decode(state.identityKey),
      oneTimeKey: oneTimeKey.toBytes(),
    );
  });

  @override
  Future<void> startSession(OlmContactBundle peer) =>
      _serial(() => _startSession(peer, null));

  @override
  Future<OlmContact> addContact({
    required OlmContactBundle bundle,
    required List<int> addressingKey,
    required String name,
    required DateTime metAt,
  }) => _serial(() async {
    if (addressingKey.length != olmKeyLength) {
      throw const CryptoException('Addressing keys must be 32 bytes');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const CryptoException('A contact needs a name');
    await _startSession(
      bundle,
      _Profile(
        addressingKey: _b64(addressingKey),
        name: trimmed,
        metAt: metAt.toUtc().millisecondsSinceEpoch,
      ),
    );
    final saved = _saved!.contacts[_b64(bundle.identityKey)]!;
    return (await _contactOf(_b64(bundle.identityKey), saved))!;
  });

  @override
  Future<List<OlmContact>> contacts() => _serial(() async {
    final state = await _load();
    if (state == null) return const [];
    final out = <OlmContact>[];
    for (final e in state.contacts.entries) {
      final c = await _contactOf(e.key, e.value);
      if (c != null) out.add(c);
    }
    return out
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });

  @override
  Future<String> verificationCode(List<int> peerIdentityKey) =>
      _serial(() async {
        final (state, _) = await _require();
        return verificationDigits(
          await _hasher.hash([
            ...utf8.encode('SHA/v2/verification-code'),
            ...sortedConcat(
              base64.decode(state.identityKey),
              _keyBytes(peerIdentityKey),
            ),
          ]),
        );
      });

  /// Starts an outbound session from [peer]'s bundle, and records [profile]
  /// when the contact is added from a scan. One one-time key gives at most
  /// one session (0006, 0004 §2): the same QR display scanned twice gives
  /// no second session.
  Future<void> _startSession(OlmContactBundle peer, _Profile? profile) async {
    final (state, key) = await _require();
    final peerKey = _b64(peer.identityKey);
    if (peerKey == state.identityKey) {
      throw const CryptoException('Cannot start a session with yourself');
    }
    final known = state.contacts[peerKey]?.profile;
    if (profile != null &&
        known != null &&
        known.addressingKey != profile.addressingKey) {
      // The addressing key only changes with a new identity, and then the
      // Olm key changes too. A different one here is not the same person's
      // code (0004 §3).
      throw const CryptoException(
        'The scanned code does not match the contact',
      );
    }
    final oneTimeKey = _b64(peer.oneTimeKey);
    if (state.contacts[peerKey]?.usedOneTimeKeys.contains(oneTimeKey) ??
        false) {
      if (profile != null && known == null) {
        final next = state.copy();
        next.contact(peerKey).profile = profile;
        await _save(next);
      }
      return;
    }
    final account = _account(state, key);
    final Session session;
    try {
      session = account.createOutboundSession(
        identityKey: Curve25519PublicKey.fromBytes(peer.identityKey),
        oneTimeKey: Curve25519PublicKey.fromBytes(peer.oneTimeKey),
      );
    } catch (_) {
      throw const CryptoException('The scanned keys are not usable');
    }
    final next = state.copy();
    final contact = next.contact(peerKey)
      ..usedOneTimeKeys.add(oneTimeKey)
      ..sessions.add(
        _Session(
          id: session.sessionId,
          pickle: session.toPickleEncrypted(key),
          number: next.nextNumber(),
          // Never sent on yet: counted from now (0009, condition 3).
          sent: _now(),
        ),
      );
    if (profile != null) contact.profile ??= profile;
    await _save(next);
  }

  @override
  Future<OlmOutgoing> encrypt(List<int> peer, String text) => _serial(() async {
    final (state, key) = await _require();
    final peerKey = _peerKey(peer);
    final next = state.copy();
    final contact = next.contacts[peerKey];
    if (contact == null || contact.sessions.isEmpty) {
      throw const CryptoException('No session with this contact');
    }
    final chosen = contact.chosen;
    final session = _session(chosen, key);
    // 1. Pad (0004 §4 (A)) and encrypt in memory.
    final message = session.encrypt(OlmPadding.pad(text));
    final packet = Uint8List.fromList([
      message.messageType,
      ...base64.decode(base64.normalize(message.ciphertext)),
    ]);
    final outgoing = _Outgoing(
      id: _newId(),
      peer: peerKey,
      packet: base64.encode(packet),
      text: text,
      session: chosen.id,
    );
    chosen.pickle = session.toPickleEncrypted(key);
    next.outbox.add(outgoing);
    // 2. Save the session and the packet in one write. Only then may the
    // packet leave the phone: an unsaved send would let the next message
    // reuse the same message key (0004 §6).
    await _save(next);
    return outgoing.toPublic();
  });

  @override
  Future<List<OlmOutgoing>> outbox() => _serial(() async {
    final state = await _load();
    return [...?state?.outbox.map((o) => o.toPublic())];
  });

  @override
  Future<void> markSent(String id, {bool keep = false}) => _serial(() async {
    // No pickle key needed: the outbox can be cleared even if it is lost.
    var state = await _load();
    if (state == null) return;
    final sent = state.outbox.where((o) => o.id == id).firstOrNull;
    if (sent == null) return;
    if (keep) {
      // In the history before it leaves the outbox (0010 (B)).
      await _keepInHistory(sent.peer, id: id, text: sent.text, outgoing: true);
      state = (await _load())!;
    }
    final next = state.copy()..outbox.removeWhere((o) => o.id == id);
    // 0009 (iv), condition 3: the relay has our latest packet on the
    // session from now, so a message that made it old no longer counts. A
    // packet saved before F2 has no session: then every session with the
    // contact counts as sent on now. OGRANSKAT (0009).
    for (final s in next.contacts[sent.peer]?.sessions ?? const <_Session>[]) {
      if (sent.session == null || s.id == sent.session) {
        s
          ..sent = _now()
          ..qualified = null;
      }
    }
    await _save(next);
  });

  @override
  Future<OlmReceiveResult> receive(
    List<int> peer,
    Uint8List packet, {
    DateTime? Function(String text)? writtenAt,
  }) => _serial(() async {
    final (state, key) = await _require();
    final peerKey = _peerKey(peer);
    final hash = _hex(await _hasher.hash(packet));

    // 1. Skip packets already handled: the relay hands out the same
    // packet on every fetch for 48 hours (0004 §6).
    if (state.seen.containsKey(hash)) {
      return const OlmReceiveResult.failed(OlmReceiveFailure.duplicate);
    }
    final next = state.copy()..seen[hash] = _now();

    final type = packet.isEmpty ? -1 : packet[0];
    if (packet.length < 2 || (type != 0 && type != 1)) {
      next.contact(peerKey).malformed++;
      await _save(next);
      return const OlmReceiveResult.failed(OlmReceiveFailure.malformed);
    }
    final ciphertext = base64
        .encode(Uint8List.sublistView(packet, 1))
        .replaceAll('=', '');

    // 2. Decrypt in memory: the saved sessions first, newest number
    // first, each from its saved pickle (0004 §6).
    final contact = next.contact(peerKey);
    var failure = OlmReceiveFailure.unreadable;
    for (final saved in contact.byNumber) {
      final session = _session(saved, key);
      final String text;
      try {
        text = OlmPadding.unpad(
          session.decrypt(messageType: type, ciphertext: ciphertext),
        );
      } catch (e) {
        // Classify only; the text itself is dropped here.
        final kind = _classify(e);
        if (type == 1 && kind != OlmReceiveFailure.unreadable) {
          failure = kind;
        }
        continue;
      }
      saved
        ..pickle = session.toPickleEncrypted(key)
        ..number = next.nextNumber();
      _markOld(contact, saved.id, _timeOf(text, writtenAt));
      return _keep(next, peerKey, hash, text);
    }

    // A first message no saved session could read: try a new inbound
    // session, checked against the contact's identity key (0004 §6).
    if (type == 0) {
      final account = _account(state, key);
      ({Session session, String plaintext})? inbound;
      try {
        inbound = account.createInboundSession(
          theirIdentityKey: Curve25519PublicKey.fromBytes(
            base64.decode(peerKey),
          ),
          preKeyMessageBase64: ciphertext,
        );
      } catch (_) {
        // Whatever the error, the account in memory is dropped: the
        // binding can fail after the one-time key was removed (0004 §6).
        // A type 0 message is always "unreadable" (0004 §10).
        inbound = null;
      }
      if (inbound != null) {
        next.account = account.toPickleEncrypted(key);
        final text = OlmPadding.unpad(inbound.plaintext);
        final id = inbound.session.sessionId;
        contact.sessions.add(
          _Session(
            id: id,
            pickle: inbound.session.toPickleEncrypted(key),
            number: next.nextNumber(),
            // Never sent on: counted from now (0009, condition 3).
            sent: _now(),
          ),
        );
        _markOld(contact, id, _timeOf(text, writtenAt));
        // Outside the try: a failed save must reach the caller as an
        // error, never turn into "unreadable".
        return _keep(next, peerKey, hash, text);
      }
      failure = OlmReceiveFailure.unreadable;
    }

    // No message: save the hash and the counter together (0005, item 8).
    switch (failure) {
      case OlmReceiveFailure.tooLate:
        contact.tooLate++;
      case OlmReceiveFailure.gapTooBig:
        contact.gapTooBig++;
      default:
        contact.unreadable++;
    }
    await _save(next);
    return OlmReceiveResult.failed(failure);
  });

  /// When the contact wrote [text], by the contact's clock, or null. The
  /// app's function reads it; if that fails, the time is unknown, which
  /// only keeps sessions longer.
  static DateTime? _timeOf(
    String text,
    DateTime? Function(String text)? writtenAt,
  ) {
    try {
      return writtenAt?.call(text);
    } catch (_) {
      return null;
    }
  }

  /// 0009 (iv), condition 4: the contact wrote a message on [readOn] at
  /// [writtenAt] (the contact's clock). Each other session where that is
  /// more than 48 h at the relay and 24 h for clocks after our latest packet
  /// is old from now on our clock, unless it already was: only the first
  /// such message counts (condition 5). [_removeOld] removes it later.
  /// OGRANSKAT (0009).
  void _markOld(_Contact contact, String readOn, DateTime? writtenAt) {
    if (writtenAt == null) return;
    final at = writtenAt.millisecondsSinceEpoch;
    for (final s in contact.sessions) {
      if (s.id == readOn || s.qualified != null) continue;
      final sent = s.sent;
      if (sent != null && at > sent + _oldAfter) s.qualified = _now();
    }
  }

  /// Rule (iv) in 0009: removes every session that all of this holds for,
  /// and returns how many.
  ///
  /// 1. It is not the one we send on (the highest number, 0006 (b)).
  /// 2. Nothing in the outbox is encrypted on it. A packet saved before F2
  ///    has no session, and then keeps every session with its contact.
  /// 3. and 4. A message from the contact made it old ([_markOld]), and
  ///    nothing was sent on it after that ([markSent] clears the mark).
  /// 5. It has been old for 48 h + 24 h on our clock: everything the
  ///    contact sent on it before has been fetched or has left the relay.
  ///
  /// OGRANSKAT (0009).
  int _removeOld(_State next) {
    final now = _now();
    var removed = 0;
    for (final MapEntry(key: peer, value: contact) in next.contacts.entries) {
      if (contact.sessions.length < 2) continue;
      final chosen = contact.chosen;
      final waiting = {
        for (final o in next.outbox)
          if (o.peer == peer) o.session,
      };
      contact.sessions.removeWhere((s) {
        final since = s.qualified;
        final old =
            !identical(s, chosen) &&
            !waiting.contains(s.id) &&
            !waiting.contains(null) &&
            since != null &&
            now - since >= _oldAfter;
        if (old) removed++;
        return old;
      });
    }
    return removed;
  }

  /// 3. Saves the session, the account, the message and the hash in one
  /// write; 4. only then is the message returned to be shown (0004 §6).
  Future<OlmReceiveResult> _keep(
    _State next,
    String peerKey,
    String hash,
    String text,
  ) async {
    final incoming = _Incoming(id: hash, peer: peerKey, text: text);
    next.inbox.add(incoming);
    await _save(next);
    return OlmReceiveResult.message(incoming.toPublic());
  }

  @override
  Future<List<OlmIncoming>> inbox() => _serial(() async {
    final state = await _load();
    return [...?state?.inbox.map((m) => m.toPublic())];
  });

  @override
  Future<void> markShown(String id, {bool keep = false}) => _serial(() async {
    var state = await _load();
    if (state == null) return;
    final shown = state.inbox.where((m) => m.id == id).firstOrNull;
    if (shown == null) return;
    if (keep) {
      // In the history before it leaves the inbox (0010 (B)).
      await _keepInHistory(
        shown.peer,
        id: id,
        text: shown.text,
        outgoing: false,
      );
      state = (await _load())!;
    }
    await _save(state.copy()..inbox.removeWhere((m) => m.id == id));
  });

  @override
  Future<List<OlmHistoryItem>> history() => _serial(() async {
    final state = await _load();
    if (state == null) return const [];
    final out = <OlmHistoryItem>[];
    for (final MapEntry(key: peer, value: refs) in state.history.entries) {
      for (final ref in refs) {
        for (final i in await _readEntry(ref.name) ?? const <_HistoryItem>[]) {
          out.add(
            OlmHistoryItem(
              id: i.id,
              peer: base64.decode(peer),
              text: i.text,
              outgoing: i.outgoing,
              at: DateTime.fromMillisecondsSinceEpoch(i.at, isUtc: true),
            ),
          );
        }
      }
    }
    return out;
  });

  @override
  Future<void> pruneHistory(DateTime olderThan) =>
      _serial(() => _pruneHistory(olderThan.millisecondsSinceEpoch));

  @override
  Future<void> clearHistory() => _serial(() => _pruneHistory(null));

  /// Keeps one message in the history (0010 (B)), in two writes and in this
  /// order:
  ///
  /// 1. the state, with a new entry's random name reserved, or the newest
  ///    time of the entry moved forward. So the state never knows less than
  ///    the entries hold: no entry is left that the state does not list, and
  ///    pruning never removes a message too early;
  /// 2. the entry itself, written whole.
  ///
  /// The caller takes the message off the inbox or the outbox only after
  /// this, so a crash cannot lose it. A message already in the entry, kept
  /// before a crash, is not kept again.
  Future<void> _keepInHistory(
    String peer, {
    required String id,
    required String text,
    required bool outgoing,
  }) async {
    final state = (await _load())!;
    final now = _now();
    final refs = state.history[peer] ?? const <_HistoryRef>[];
    final last = refs.isEmpty ? null : refs.last;
    final items = last == null ? null : await _readEntry(last.name);
    if (items != null && items.any((i) => i.id == id)) return;
    final next = state.copy();
    final nextRefs = next.history.putIfAbsent(peer, () => []);
    final _HistoryRef ref;
    final List<_HistoryItem> kept;
    var changed = true;
    if (items == null || items.length >= historyEntrySize) {
      // None yet, full, or damaged: a damaged entry is never written over.
      ref = _HistoryRef(name: _newEntryName(state), newest: now);
      nextRefs.add(ref);
      kept = [];
    } else {
      ref = nextRefs.last;
      kept = items;
      changed = ref.newest < now;
      if (changed) ref.newest = now;
    }
    if (changed) await _save(next);
    kept.add(_HistoryItem(id: id, outgoing: outgoing, at: now, text: text));
    final bytes = _encodeEntry(kept);
    try {
      await _vault.write(ref.name, bytes);
    } finally {
      wipe(bytes);
    }
  }

  /// Removes what was kept before [cutoff] (ms), or everything if it is
  /// null. A whole entry's vault entry is deleted first and the state saved
  /// after, so a crash leaves at most a name the state still lists, never an
  /// entry it does not.
  Future<void> _pruneHistory(int? cutoff) async {
    final state = await _load();
    if (state == null || state.history.isEmpty) return;
    final next = state.copy();
    var changed = false;
    for (final refs in next.history.values) {
      for (final ref in [...refs]) {
        if (cutoff == null || ref.newest < cutoff) {
          await _vault.delete(ref.name);
          refs.remove(ref);
          changed = true;
          continue;
        }
        final items = await _readEntry(ref.name);
        if (items == null) continue;
        final left = [
          for (final i in items)
            if (i.at >= cutoff) i,
        ];
        if (left.length == items.length) continue;
        final bytes = _encodeEntry(left);
        try {
          await _vault.write(ref.name, bytes);
        } finally {
          wipe(bytes);
        }
      }
    }
    next.history.removeWhere((_, refs) => refs.isEmpty);
    if (changed) await _save(next);
  }

  /// The messages in a history entry: empty if it is not there (a name
  /// reserved before a crash), null if it cannot be read.
  Future<List<_HistoryItem>?> _readEntry(String name) async {
    final bytes = await _vault.read(name);
    if (bytes == null) return [];
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (j['v'] != 1) return null;
      return [
        for (final i in j['items']! as List<Object?>)
          _HistoryItem.fromJson(i! as Map<String, Object?>),
      ];
    } catch (_) {
      return null;
    } finally {
      wipe(bytes);
    }
  }

  static Uint8List _encodeEntry(List<_HistoryItem> items) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'items': [for (final i in items) i.toJson()],
      }),
    ),
  );

  /// A random vault name: it says nothing about the contact or the time
  /// (0010 (B)). Vault names are file names, at most 64 characters.
  String _newEntryName(_State state) {
    final taken = {
      for (final refs in state.history.values)
        for (final r in refs) r.name,
    };
    while (true) {
      final name = 'h.${_hex(List.generate(8, (_) => _ids.nextInt(256)))}';
      if (!taken.contains(name)) return name;
    }
  }

  @override
  Future<int> removeOldSessions() => _serial(() async {
    // No pickle key needed: removing a session reads no pickle.
    final state = await _load();
    if (state == null) return 0;
    final next = state.copy();
    final removed = _removeOld(next);
    if (removed > 0) await _save(next);
    return removed;
  });

  @override
  Future<OlmFailureCounts> failureCounts(List<int> peer) => _serial(() async {
    final state = await _load();
    final c = state?.contacts[_peerKey(peer)];
    return OlmFailureCounts(
      unreadable: c?.unreadable ?? 0,
      tooLate: c?.tooLate ?? 0,
      gapTooBig: c?.gapTooBig ?? 0,
      malformed: c?.malformed ?? 0,
    );
  });

  @override
  Future<void> clearFailureCounts(List<int> peer, OlmFailureCounts shown) =>
      _serial(() async {
        final (state, _) = await _require();
        final c = state.contacts[_peerKey(peer)];
        if (c == null) return;
        int less(int now, int seen) => now > seen ? now - seen : 0;
        final next = state.copy();
        next.contacts[_peerKey(peer)]!
          ..unreadable = less(c.unreadable, shown.unreadable)
          ..tooLate = less(c.tooLate, shown.tooLate)
          ..gapTooBig = less(c.gapTooBig, shown.gapTooBig)
          ..malformed = less(c.malformed, shown.malformed);
        await _save(next);
      });

  @override
  Future<Map<String, String>> appSettings() => _serial(() async {
    final state = await _load();
    return {...?state?.settings};
  });

  @override
  Future<void> saveAppSettings(Map<String, String> settings) =>
      _serial(() async {
        final (state, _) = await _require();
        final next = state.copy();
        next.settings
          ..clear()
          ..addAll(settings);
        await _save(next);
      });

  // ---------------------------------------------------------------------

  /// Loads the native library once per process (flutter_rust_bridge throws
  /// on a second init). On Android the APK carries it; for `flutter test`
  /// on a computer, `tool/build_native_host.sh` builds it.
  static Future<void> _init() async {
    if (isInitialized()) return;
    try {
      if (Platform.isAndroid) {
        await fv.init();
      } else {
        await fv.init(
          libraryPath:
              Platform.environment['VODOZEMAC_LIB_DIR'] ?? 'build/native/',
        );
      }
    } catch (_) {
      throw const CryptoException(
        'The Olm library could not be loaded',
        CryptoErrorKind.unavailable,
      );
    }
  }

  Future<_State?> _load() async {
    final saved = _saved;
    if (saved != null) return saved;
    final bytes = await _vault.read(stateName);
    if (bytes == null) return null;
    try {
      final state = _State.decode(bytes);
      // 0009 (iv), condition 3: a session saved before F2 has no time for
      // our latest packet on it. That packet reached the relay before now,
      // so now is no earlier than the real time, and can only make the
      // session wait longer. OGRANSKAT (0009).
      state.fillMissingSentTimes(_now());
      return _saved = state;
    } catch (_) {
      throw const CryptoException(
        'Saved Olm state is damaged',
        CryptoErrorKind.corrupt,
      );
    } finally {
      wipe(bytes);
    }
  }

  Future<(_State, Uint8List)> _require() async {
    await _init();
    final state = await _load();
    if (state == null) throw const CryptoException('No Olm account');
    final key = _pickleKey ??= await _vault.read(pickleKeyName);
    if (key == null || key.length != 32) {
      throw const CryptoException(
        'Olm pickle key missing',
        CryptoErrorKind.keyInvalidated,
      );
    }
    return (state, key);
  }

  Future<Uint8List> _loadOrMakePickleKey() async {
    final existing = await _vault.read(pickleKeyName);
    if (existing != null && existing.length == 32) {
      return _pickleKey = existing;
    }
    final key = await _entropy.bytes(32, purpose: 'olm-pickle-key');
    await _vault.write(pickleKeyName, key);
    return _pickleKey = key;
  }

  /// One vault write for the whole state. If it fails, the state in memory
  /// is dropped and read again next time, so memory never runs ahead of
  /// what is on disk.
  Future<void> _save(_State next) async {
    final cutoff = _now() - keepHashes.inMilliseconds;
    next.seen.removeWhere((_, at) => at < cutoff);
    _removeOld(next);
    final bytes = next.encode();
    try {
      await _vault.write(stateName, bytes);
    } catch (_) {
      _saved = null;
      rethrow;
    } finally {
      wipe(bytes);
    }
    _saved = next;
  }

  Account _account(_State state, Uint8List key) =>
      _accountFrom(state.account, key);

  Account _accountFrom(String pickle, Uint8List key) {
    try {
      return Account.fromPickleEncrypted(pickle: pickle, pickleKey: key);
    } catch (_) {
      throw const CryptoException(
        'Saved Olm account cannot be read',
        CryptoErrorKind.corrupt,
      );
    }
  }

  Session _session(_Session saved, Uint8List key) {
    try {
      return Session.fromPickleEncrypted(pickle: saved.pickle, pickleKey: key);
    } catch (_) {
      throw const CryptoException(
        'Saved Olm session cannot be read',
        CryptoErrorKind.corrupt,
      );
    }
  }

  /// Sorts a library error into a fixed kind by its wording (vodozemac
  /// 0.11.2, `src/olm/session/mod.rs:83-87`). The text is not kept.
  static OlmReceiveFailure _classify(Object error) {
    final text = error.toString();
    if (text.contains("can't be created")) return OlmReceiveFailure.tooLate;
    if (text.contains('message gap was too big')) {
      return OlmReceiveFailure.gapTooBig;
    }
    return OlmReceiveFailure.unreadable;
  }

  Future<OlmContact?> _contactOf(String peer, _Contact c) async {
    final p = c.profile;
    if (p == null) return null;
    final identityKey = base64.decode(peer);
    return OlmContact(
      id: _hex(await _hasher.hash(identityKey)),
      identityKey: identityKey,
      addressingKey: base64.decode(p.addressingKey),
      name: p.name,
      metAt: DateTime.fromMillisecondsSinceEpoch(p.metAt, isUtc: true),
    );
  }

  /// The 20-digit code both people compare (0004 §1): the app's existing
  /// function, unchanged, with the two Olm identity keys as input.
  /// OGRANSKAT (0004 §1).
  static String verificationDigits(List<int> digest) {
    // Four groups of five digits, each from 5 bytes (as in Signal's safety
    // numbers); the modulo bias is below 2^-20 per group.
    final buffer = StringBuffer();
    for (var g = 0; g < 4; g++) {
      var value = 0;
      for (var i = 0; i < 5; i++) {
        value = value * 256 + digest[g * 5 + i];
      }
      buffer.write((value % 100000).toString().padLeft(5, '0'));
    }
    return buffer.toString();
  }

  /// `min(a, b) || max(a, b)` in byte order, as `X25519KeyAgreement` does.
  static Uint8List sortedConcat(List<int> a, List<int> b) {
    var cmp = 0;
    for (var i = 0; i < a.length && i < b.length && cmp == 0; i++) {
      cmp = a[i] - b[i];
    }
    if (cmp == 0) cmp = a.length - b.length;
    return Uint8List.fromList(cmp <= 0 ? [...a, ...b] : [...b, ...a]);
  }

  List<int> _keyBytes(List<int> key) {
    if (key.length != olmKeyLength) {
      throw const CryptoException('Olm keys must be 32 bytes');
    }
    return key;
  }

  String _peerKey(List<int> peer) {
    if (peer.length != olmKeyLength) {
      throw const CryptoException('Olm keys must be 32 bytes');
    }
    return _b64(peer);
  }

  int _now() => _clock().millisecondsSinceEpoch;

  String _newId() => _hex(List.generate(16, (_) => _ids.nextInt(256)));

  static String _b64(List<int> bytes) => base64.encode(bytes);

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Everything in the vault entry. Changed only on a [copy], which is saved
/// as a whole or thrown away.
final class _State {
  _State({
    required this.account,
    required this.identityKey,
    this.counter = 0,
    Map<String, _Contact>? contacts,
    Map<String, int>? seen,
    List<_Outgoing>? outbox,
    List<_Incoming>? inbox,
    Map<String, int>? shown,
    Map<String, String>? settings,
    Map<String, List<_HistoryRef>>? history,
  }) : history = history ?? {},
       contacts = contacts ?? {},
       seen = seen ?? {},
       outbox = outbox ?? [],
       inbox = inbox ?? [],
       shown = shown ?? {},
       settings = settings ?? {};

  factory _State.decode(Uint8List bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    if (j['v'] != 1) throw const FormatException('version');
    return _State(
      account: j['account']! as String,
      identityKey: j['identityKey']! as String,
      counter: j['counter']! as int,
      contacts: {
        for (final e in (j['contacts']! as Map<String, Object?>).entries)
          e.key: _Contact.fromJson(e.value! as Map<String, Object?>),
      },
      seen: Map<String, int>.from(j['seen']! as Map<String, Object?>),
      outbox: [
        for (final o in j['outbox']! as List<Object?>)
          _Outgoing.fromJson(o! as Map<String, Object?>),
      ],
      inbox: [
        for (final m in j['inbox']! as List<Object?>)
          _Incoming.fromJson(m! as Map<String, Object?>),
      ],
      shown: Map<String, int>.from(j['shown']! as Map<String, Object?>),
      // Missing in states saved before P6.
      settings: Map<String, String>.from(
        (j['settings'] as Map<String, Object?>?) ?? const {},
      ),
      // Missing in states saved before F3.
      history: {
        for (final e
            in ((j['history'] as Map<String, Object?>?) ?? const {}).entries)
          e.key: [
            for (final r in e.value! as List<Object?>)
              _HistoryRef.fromJson(r! as Map<String, Object?>),
          ],
      },
    );
  }

  String account;
  final String identityKey;

  /// Gives each session its number (0006 (b)): the highest is sent on.
  int counter;
  final Map<String, _Contact> contacts;

  /// SHA-256 (hex) of handled packets -> when, in ms since the epoch.
  final Map<String, int> seen;
  final List<_Outgoing> outbox;
  final List<_Incoming> inbox;

  /// One-time keys shown in a QR code (base64) -> when, in ms (0004 §8).
  final Map<String, int> shown;

  /// The app's settings (0005, item 9).
  final Map<String, String> settings;

  /// The history entries per contact, oldest first (0010 (B)).
  final Map<String, List<_HistoryRef>> history;

  int nextNumber() => ++counter;

  /// See [ShaOlmService._load].
  void fillMissingSentTimes(int now) {
    for (final c in contacts.values) {
      for (final s in c.sessions) {
        s.sent ??= now;
      }
    }
  }

  _Contact contact(String peer) => contacts.putIfAbsent(peer, _Contact.new);

  Map<String, Object?> toJson() => {
    'v': 1,
    'account': account,
    'identityKey': identityKey,
    'counter': counter,
    'contacts': {for (final e in contacts.entries) e.key: e.value.toJson()},
    'seen': seen,
    'outbox': [for (final o in outbox) o.toJson()],
    'inbox': [for (final m in inbox) m.toJson()],
    'shown': shown,
    'settings': settings,
    'history': {
      for (final e in history.entries)
        e.key: [for (final r in e.value) r.toJson()],
    },
  };

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  _State copy() => _State.decode(encode());
}

final class _Contact {
  _Contact({
    List<_Session>? sessions,
    this.unreadable = 0,
    this.tooLate = 0,
    this.gapTooBig = 0,
    this.malformed = 0,
    this.profile,
    List<String>? usedOneTimeKeys,
  }) : sessions = sessions ?? [],
       usedOneTimeKeys = usedOneTimeKeys ?? [];

  factory _Contact.fromJson(Map<String, Object?> j) => _Contact(
    sessions: [
      for (final s in j['sessions']! as List<Object?>)
        _Session.fromJson(s! as Map<String, Object?>),
    ],
    profile: j['profile'] == null
        ? null
        : _Profile.fromJson(j['profile']! as Map<String, Object?>),
    usedOneTimeKeys: List<String>.from(j['usedOneTimeKeys']! as List<Object?>),
    unreadable: j['unreadable']! as int,
    tooLate: j['tooLate']! as int,
    gapTooBig: j['gapTooBig']! as int,
    malformed: j['malformed']! as int,
  );

  final List<_Session> sessions;
  int unreadable;
  int tooLate;
  int gapTooBig;
  int malformed;

  /// Set when the contact was added from a scan (P4); null for a peer that
  /// only appears in packets.
  _Profile? profile;

  /// The contact's one-time keys (base64) that already gave a session here.
  final List<String> usedOneTimeKeys;

  /// The session to send on: the highest number (0006 (b)).
  _Session get chosen => byNumber.first;

  List<_Session> get byNumber =>
      [...sessions]..sort((a, b) => b.number.compareTo(a.number));

  Map<String, Object?> toJson() => {
    'sessions': [for (final s in sessions) s.toJson()],
    'unreadable': unreadable,
    'tooLate': tooLate,
    'gapTooBig': gapTooBig,
    'malformed': malformed,
    'profile': profile?.toJson(),
    'usedOneTimeKeys': usedOneTimeKeys,
  };
}

/// What the QR code and the meeting gave: kept with the contact (0005, 3).
final class _Profile {
  _Profile({
    required this.addressingKey,
    required this.name,
    required this.metAt,
  });

  factory _Profile.fromJson(Map<String, Object?> j) => _Profile(
    addressingKey: j['addressingKey']! as String,
    name: j['name']! as String,
    metAt: j['metAt']! as int,
  );

  final String addressingKey;
  final String name;
  final int metAt;

  Map<String, Object?> toJson() => {
    'addressingKey': addressingKey,
    'name': name,
    'metAt': metAt,
  };
}

final class _Session {
  _Session({
    required this.id,
    required this.pickle,
    required this.number,
    this.sent,
    this.qualified,
  });

  factory _Session.fromJson(Map<String, Object?> j) => _Session(
    id: j['id']! as String,
    pickle: j['pickle']! as String,
    number: j['number']! as int,
    // Missing in states saved before F2.
    sent: j['sent'] as int?,
    qualified: j['qualified'] as int?,
  );

  final String id;
  String pickle;
  int number;

  /// When the relay took our latest packet on this session, or when it was
  /// made if we never sent on it, in ms on our clock (0009, `sentS`).
  int? sent;

  /// When a message from the contact first made this session old, in ms on
  /// our clock, or null (0009, `qualifiedAt`).
  int? qualified;

  Map<String, Object?> toJson() => {
    'id': id,
    'pickle': pickle,
    'number': number,
    'sent': sent,
    'qualified': qualified,
  };
}

final class _Outgoing {
  _Outgoing({
    required this.id,
    required this.peer,
    required this.packet,
    required this.text,
    required this.session,
  });

  factory _Outgoing.fromJson(Map<String, Object?> j) => _Outgoing(
    id: j['id']! as String,
    peer: j['peer']! as String,
    packet: j['packet']! as String,
    text: j['text']! as String,
    // Missing in states saved before F2.
    session: j['session'] as String?,
  );

  final String id;
  final String peer;
  final String packet;
  final String text;

  /// The id of the session [packet] is encrypted on; null if it was saved
  /// before F2 (0009, condition 2).
  final String? session;

  OlmOutgoing toPublic() => OlmOutgoing(
    id: id,
    peer: base64.decode(peer),
    packet: base64.decode(packet),
    text: text,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'peer': peer,
    'packet': packet,
    'text': text,
    'session': session,
  };
}

final class _Incoming {
  _Incoming({required this.id, required this.peer, required this.text});

  factory _Incoming.fromJson(Map<String, Object?> j) => _Incoming(
    id: j['id']! as String,
    peer: j['peer']! as String,
    text: j['text']! as String,
  );

  final String id;
  final String peer;
  final String text;

  OlmIncoming toPublic() =>
      OlmIncoming(id: id, peer: base64.decode(peer), text: text);

  Map<String, Object?> toJson() => {'id': id, 'peer': peer, 'text': text};
}

/// One history entry in the state: its vault name, and a time no earlier
/// than the newest message in it, in ms on our clock (0010 (B)).
final class _HistoryRef {
  _HistoryRef({required this.name, required this.newest});

  factory _HistoryRef.fromJson(Map<String, Object?> j) =>
      _HistoryRef(name: j['name']! as String, newest: j['newest']! as int);

  final String name;
  int newest;

  Map<String, Object?> toJson() => {'name': name, 'newest': newest};
}

/// One message in a history entry.
final class _HistoryItem {
  _HistoryItem({
    required this.id,
    required this.outgoing,
    required this.at,
    required this.text,
  });

  factory _HistoryItem.fromJson(Map<String, Object?> j) => _HistoryItem(
    id: j['id']! as String,
    outgoing: j['out']! as bool,
    at: j['at']! as int,
    text: j['text']! as String,
  );

  final String id;
  final bool outgoing;
  final int at;
  final String text;

  Map<String, Object?> toJson() => {
    'id': id,
    'out': outgoing,
    'at': at,
    'text': text,
  };
}
