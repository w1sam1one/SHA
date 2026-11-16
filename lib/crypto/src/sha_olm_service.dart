import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fv;
import 'package:vodozemac/vodozemac.dart';

import 'entropy.dart';
import 'hashing.dart';
import 'key_vault.dart';
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
  Future<Uint8List> createAccount() => _serial(() async {
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
  });

  @override
  Future<OlmContactBundle> publishBundle() => _serial(() async {
    final (state, key) = await _require();
    final account = _account(state, key);
    account.generateOneTimeKeys(1);
    final oneTimeKey = account.oneTimeKeys.values.single;
    account.markKeysAsPublished();
    // Save before the key is shown (0004 §6): a shown key must survive.
    final next = state.copy()..account = account.toPickleEncrypted(key);
    await _save(next);
    return OlmContactBundle(
      identityKey: base64.decode(state.identityKey),
      oneTimeKey: oneTimeKey.toBytes(),
    );
  });

  @override
  Future<void> startSession(OlmContactBundle peer) => _serial(() async {
    final (state, key) = await _require();
    if (_b64(peer.identityKey) == state.identityKey) {
      throw const CryptoException('Cannot start a session with yourself');
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
    next
        .contact(_b64(peer.identityKey))
        .sessions
        .add(
          _Session(
            id: session.sessionId,
            pickle: session.toPickleEncrypted(key),
            number: next.nextNumber(),
          ),
        );
    await _save(next);
  });

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
    // 1. Encrypt in memory.
    final message = session.encrypt(text);
    final packet = Uint8List.fromList([
      message.messageType,
      ...base64.decode(base64.normalize(message.ciphertext)),
    ]);
    final outgoing = _Outgoing(
      id: _newId(),
      peer: peerKey,
      packet: base64.encode(packet),
      text: text,
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
  Future<void> markSent(String id) => _serial(() async {
    // No pickle key needed: the outbox can be cleared even if it is lost.
    final state = await _load();
    if (state == null) return;
    final next = state.copy()..outbox.removeWhere((o) => o.id == id);
    if (next.outbox.length != state.outbox.length) await _save(next);
  });

  @override
  Future<OlmReceiveResult> receive(List<int> peer, Uint8List packet) =>
      _serial(() async {
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
            text = session.decrypt(messageType: type, ciphertext: ciphertext);
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
            contact.sessions.add(
              _Session(
                id: inbound.session.sessionId,
                pickle: inbound.session.toPickleEncrypted(key),
                number: next.nextNumber(),
              ),
            );
            // Outside the try: a failed save must reach the caller as an
            // error, never turn into "unreadable".
            return _keep(next, peerKey, hash, inbound.plaintext);
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
  Future<void> markShown(String id) => _serial(() async {
    final state = await _load();
    if (state == null) return;
    final next = state.copy()..inbox.removeWhere((m) => m.id == id);
    if (next.inbox.length != state.inbox.length) await _save(next);
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
      return _saved = _State.decode(bytes);
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

  Account _account(_State state, Uint8List key) {
    try {
      return Account.fromPickleEncrypted(pickle: state.account, pickleKey: key);
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
  }) : contacts = contacts ?? {},
       seen = seen ?? {},
       outbox = outbox ?? [],
       inbox = inbox ?? [];

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

  int nextNumber() => ++counter;

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
  }) : sessions = sessions ?? [];

  factory _Contact.fromJson(Map<String, Object?> j) => _Contact(
    sessions: [
      for (final s in j['sessions']! as List<Object?>)
        _Session.fromJson(s! as Map<String, Object?>),
    ],
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
  };
}

final class _Session {
  _Session({required this.id, required this.pickle, required this.number});

  factory _Session.fromJson(Map<String, Object?> j) => _Session(
    id: j['id']! as String,
    pickle: j['pickle']! as String,
    number: j['number']! as int,
  );

  final String id;
  String pickle;
  int number;

  Map<String, Object?> toJson() => {
    'id': id,
    'pickle': pickle,
    'number': number,
  };
}

final class _Outgoing {
  _Outgoing({
    required this.id,
    required this.peer,
    required this.packet,
    required this.text,
  });

  factory _Outgoing.fromJson(Map<String, Object?> j) => _Outgoing(
    id: j['id']! as String,
    peer: j['peer']! as String,
    packet: j['packet']! as String,
    text: j['text']! as String,
  );

  final String id;
  final String peer;
  final String packet;
  final String text;

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
