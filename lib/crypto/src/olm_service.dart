import 'dart:typed_data';

import 'olm_padding.dart';
import 'types.dart';

/// Bytes in a Curve25519 public key.
const int olmKeyLength = 32;

/// What one person shows in the QR code (0004 §1): the Olm Curve25519
/// identity key followed by one unused one-time key. 64 bytes, all public.
final class OlmContactBundle {
  OlmContactBundle({
    required List<int> identityKey,
    required List<int> oneTimeKey,
  }) : identityKey = _key(identityKey),
       oneTimeKey = _key(oneTimeKey);

  /// Parses the 64 bytes made by [toBytes].
  factory OlmContactBundle.fromBytes(List<int> bytes) {
    if (bytes.length != 2 * olmKeyLength) {
      throw const CryptoException('Contact bundle must be 64 bytes');
    }
    return OlmContactBundle(
      identityKey: bytes.sublist(0, olmKeyLength),
      oneTimeKey: bytes.sublist(olmKeyLength),
    );
  }

  final Uint8List identityKey;
  final Uint8List oneTimeKey;

  Uint8List toBytes() => Uint8List.fromList([...identityKey, ...oneTimeKey]);

  static Uint8List _key(List<int> key) {
    if (key.length != olmKeyLength) {
      throw const CryptoException('Olm keys must be 32 bytes');
    }
    return Uint8List.fromList(key).asUnmodifiableView();
  }
}

/// A contact met in person (0001, D1), as saved in the state (0005, item 3).
/// Everything here is public, except that the name is private to the user.
final class OlmContact {
  OlmContact({
    required this.id,
    required this.identityKey,
    required this.addressingKey,
    required this.name,
    required this.metAt,
  });

  /// SHA-256 (hex) of the Olm identity key (0004 §1).
  final String id;

  /// The contact's Olm identity key (Curve25519).
  final Uint8List identityKey;

  /// The contact's static X25519 key for mailbox IDs (0004 §3 (A)).
  final Uint8List addressingKey;
  final String name;

  /// When the two people met and compared the verification code (UTC).
  final DateTime metAt;
}

/// A message that is saved in the outbox and waits for the relay. It stays
/// until [OlmService.markSent] (0004 §6, 0005 (i)). Resending must use the
/// same [packet], never a new encryption.
final class OlmOutgoing {
  OlmOutgoing({
    required this.id,
    required this.peer,
    required this.packet,
    required this.text,
  });

  final String id;

  /// The contact's Olm identity key.
  final Uint8List peer;
  final Uint8List packet;
  final String text;
}

/// A message that was read and saved. It stays until [OlmService.markShown]
/// (0005 (i)).
final class OlmIncoming {
  OlmIncoming({required this.id, required this.peer, required this.text});

  final String id;

  /// The contact's Olm identity key.
  final Uint8List peer;
  final String text;
}

/// Why a packet gave no message (0004 §10). A fixed type: the library's own
/// error text can contain keys and is never kept, shown or logged.
enum OlmReceiveFailure {
  /// The packet was already handled (0004 §6, step 1). Nothing to show.
  duplicate,

  /// Not a packet at all: wrong type byte or too short.
  malformed,

  /// No session could read it, and for a first message (type 0) no new
  /// session could be made from it: changed, wrong session, a cleaned-up
  /// one-time key or a chain that was pushed out.
  unreadable,

  /// A normal message (type 1) that came too late to be read.
  tooLate,

  /// More than 2000 messages are missing before it.
  gapTooBig,
}

/// The result of [OlmService.receive]: a saved message, or why there is none.
final class OlmReceiveResult {
  const OlmReceiveResult.message(OlmIncoming this.message) : failure = null;
  const OlmReceiveResult.failed(OlmReceiveFailure this.failure)
    : message = null;

  final OlmIncoming? message;
  final OlmReceiveFailure? failure;
}

/// How many packets from one contact gave no message, per kind (0004 §10).
/// Saved in the same write as each packet's hash (0005, item 8).
final class OlmFailureCounts {
  const OlmFailureCounts({
    this.unreadable = 0,
    this.tooLate = 0,
    this.gapTooBig = 0,
    this.malformed = 0,
  });

  final int unreadable;
  final int tooLate;
  final int gapTooBig;
  final int malformed;
}

/// Olm (vodozemac) behind the crypto module: the account, the sessions per
/// contact and the order of saving in 0004 §6. The whole state is one vault
/// entry (0005 (A)); messages are kept only until shown or sent (0005 (i)).
///
/// OGRANSKAT (0004 §6): the order on crashes, the pickles and the pickle
/// key, that a type 0 message is tried on saved sessions first, and that
/// every attempt starts from the saved pickle. To be reviewed by a
/// cryptography expert before the app is given to anyone.
///
/// A contact is its Olm identity key until contacts are built (P4).
///
/// - **One instance per vault.** Each instance keeps the last saved state
///   in memory and runs its calls one at a time. Two live instances on the
///   same vault could write back an older state, which 0004 §6 forbids. The
///   app has one [CryptoService] for the whole process.
/// - **A call that throws may still have saved.** A failed vault write can
///   leave the new state on disk (`KeyVault.write`). After an exception from
///   [encrypt] or [receive], read [outbox] and [inbox] again rather than
///   assume nothing was saved.
abstract interface class OlmService {
  /// This device's Olm identity key, or null if there is no account yet.
  Future<Uint8List?> identityKey();

  /// Makes a new account and saves it. Throws if one already exists.
  Future<Uint8List> createAccount();

  /// This device's Olm identity key, making and saving the account first if
  /// there is none (the first time a QR code is shown or scanned).
  Future<Uint8List> ensureAccount();

  /// A new one-time key for the QR code. The account is saved before this
  /// returns, so the key is never shown unsaved (0004 §6).
  Future<OlmContactBundle> publishBundle();

  /// Starts a session from a scanned [peer] bundle and saves it. A one-time
  /// key that already gave a session with the contact gives no second one
  /// (0006): the same QR display scanned twice starts nothing.
  Future<void> startSession(OlmContactBundle peer);

  /// Adds the contact from a scanned code, with the session, in one write
  /// (P4). [addressingKey] is the contact's X25519 key from the code (0004
  /// §3 (A)). Throws if a known contact's code has a different addressing
  /// key.
  Future<OlmContact> addContact({
    required OlmContactBundle bundle,
    required List<int> addressingKey,
    required String name,
    required DateTime metAt,
  });

  /// Saved contacts, by name.
  Future<List<OlmContact>> contacts();

  /// The 20-digit code both people compare (0004 §1), from the two Olm
  /// identity keys. OGRANSKAT (0004 §1).
  Future<String> verificationCode(List<int> peerIdentityKey);

  /// Encrypts [text] for [peer] and saves the session and the packet in the
  /// outbox before returning (0004 §6). Send [OlmOutgoing.packet] only after
  /// this returns.
  ///
  /// The text is padded with spaces to a fixed size first (0004 §4 (A),
  /// [OlmPadding]), and [receive] removes spaces at the end again. Throws
  /// [CryptoException] for more than [OlmPadding.maxBytes] bytes of UTF-8.
  Future<OlmOutgoing> encrypt(List<int> peer, String text);

  /// Messages saved but not yet accepted by the relay.
  Future<List<OlmOutgoing>> outbox();

  /// The relay accepted the packet: remove it from the outbox.
  Future<void> markSent(String id);

  /// Handles one packet from [peer] in the order of 0004 §6 and saves the
  /// result before returning. Show the message only after this returns.
  Future<OlmReceiveResult> receive(List<int> peer, Uint8List packet);

  /// Messages read and saved but not yet shown.
  Future<List<OlmIncoming>> inbox();

  /// The app has shown the message: remove it.
  Future<void> markShown(String id);

  /// Packets from [peer] that gave no message.
  Future<OlmFailureCounts> failureCounts(List<int> peer);
}
