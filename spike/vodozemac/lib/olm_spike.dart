/// Spike for decision D3 (docs/decisions/0003-protocol-library.md).
///
/// Thin helpers around flutter_vodozemac's public API: how the QR content
/// is put together, which session to use when both people scanned each
/// other, and how state is stored. No cryptography of its own: every key,
/// message and pickle comes from the library.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fv;
import 'package:vodozemac/vodozemac.dart';

/// Loads the native library. On Android the plugin ships it inside the APK.
/// For `flutter test` on a computer, tool/build_native_host.sh builds it into
/// build/native/ (or set VODOZEMAC_LIB_DIR).
Future<void> initOlm() async {
  if (isInitialized()) return;
  if (Platform.isAndroid) {
    await fv.init();
  } else {
    await fv.init(
      libraryPath: Platform.environment['VODOZEMAC_LIB_DIR'] ?? 'build/native/',
    );
  }
}

/// Bytes in a Curve25519 public key.
const int curve25519KeyLength = 32;

/// What the other person needs to start an outbound Olm session with you,
/// and nothing else: your Curve25519 identity key followed by one unused
/// one-time key. 64 bytes.
///
/// Not needed: the Ed25519 key (Matrix signs device keys with it so a server
/// cannot swap them; here the in-person scan does that job) and the
/// one-time key's id (the receiving account finds the key by its public part
/// inside the pre-key message).
final class ContactBundle {
  ContactBundle({required this.identityKey, required this.oneTimeKey});

  /// Parses the 64 bytes produced by [toBytes].
  factory ContactBundle.fromBytes(Uint8List bytes) {
    if (bytes.length != 2 * curve25519KeyLength) {
      throw const FormatException('contact bundle must be 64 bytes');
    }
    return ContactBundle(
      identityKey: Curve25519PublicKey.fromBytes(
        Uint8List.sublistView(bytes, 0, curve25519KeyLength),
      ),
      oneTimeKey: Curve25519PublicKey.fromBytes(
        Uint8List.sublistView(bytes, curve25519KeyLength),
      ),
    );
  }

  final Curve25519PublicKey identityKey;
  final Curve25519PublicKey oneTimeKey;

  Uint8List toBytes() =>
      Uint8List.fromList([...identityKey.toBytes(), ...oneTimeKey.toBytes()]);
}

/// Makes a fresh one-time key and returns the bundle to show as a QR code.
/// The key is marked as published so the next QR gets a new one; its private
/// half stays in the account until a pre-key message uses it.
ContactBundle publishContactBundle(Account account) {
  account.generateOneTimeKeys(1);
  final oneTimeKey = account.oneTimeKeys.values.single;
  account.markKeysAsPublished();
  return ContactBundle(
    identityKey: account.curve25519Key,
    oneTimeKey: oneTimeKey,
  );
}

/// When both people scanned each other at the same time, each side ends up
/// with two sessions: the one it started and the one the other started. Both
/// work. Both sides must send on the same one, so pick by a value both see
/// identically: the session id (the same on both ends of a session). Use the
/// smallest. Keep the other one to decrypt messages already sent with it.
Session chooseSession(Iterable<Session> sessions) {
  Session? chosen;
  for (final s in sessions) {
    if (chosen == null || s.sessionId.compareTo(chosen.sessionId) < 0) {
      chosen = s;
    }
  }
  if (chosen == null) throw StateError('no session');
  return chosen;
}

/// Everything one person keeps, as encrypted pickles. In the app, the 32-byte
/// pickle key would come from the Keystore vault (see 0003); here it is a
/// parameter.
final class StoredState {
  StoredState({required this.account, required this.sessions});

  final String account;
  final Map<String, String> sessions; // session id -> pickle

  static StoredState save(
    Account account,
    Iterable<Session> sessions,
    Uint8List pickleKey,
  ) => StoredState(
    account: account.toPickleEncrypted(pickleKey),
    sessions: {
      for (final s in sessions) s.sessionId: s.toPickleEncrypted(pickleKey),
    },
  );

  ({Account account, Map<String, Session> sessions}) restore(
    Uint8List pickleKey,
  ) => (
    account: Account.fromPickleEncrypted(pickle: account, pickleKey: pickleKey),
    sessions: {
      for (final e in sessions.entries)
        e.key: Session.fromPickleEncrypted(
          pickle: e.value,
          pickleKey: pickleKey,
        ),
    },
  );
}
