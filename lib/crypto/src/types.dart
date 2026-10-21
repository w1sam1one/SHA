import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Length in bytes of an X25519 public key and of a SHA-256 digest.
const int publicKeyLength = 32;
const int identityHashLength = 32;

/// Why a crypto operation failed. Lets the UI react (e.g. "unlock your
/// phone") without the error ever carrying sensitive data.
enum CryptoErrorKind {
  /// The Keystore refused because the device is locked.
  deviceLocked,

  /// The Keystore key is gone or permanently invalidated.
  keyInvalidated,

  /// Stored data or a message failed authentication or is malformed.
  corrupt,

  /// A random source returned something unusable.
  entropy,

  /// Invalid input from the caller or a peer.
  invalidInput,

  /// Anything else (e.g. the platform Keystore is unavailable).
  unavailable,
}

/// Thrown for every failure inside the crypto module.
///
/// Messages are fixed strings: they never contain key material, plaintext,
/// nonces or ciphertext, so they are safe to show or report.
final class CryptoException implements Exception {
  const CryptoException(
    this.message, [
    this.kind = CryptoErrorKind.invalidInput,
  ]);

  final String message;
  final CryptoErrorKind kind;

  @override
  String toString() => 'CryptoException(${kind.name}): $message';
}

/// SHA-256 of a public identity key. Public by definition — safe to display
/// and put in QR codes. It never leaves the device in network traffic: relays
/// only see per-conversation mailbox ids.
final class IdentityHash {
  IdentityHash(List<int> bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.length != identityHashLength) {
      throw const CryptoException('Identity hash must be 32 bytes');
    }
  }

  /// Parses a 64-character hex string (case-insensitive).
  factory IdentityHash.fromHex(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw const CryptoException('Identity hash must be 64 hex characters');
    }
    return IdentityHash([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  final Uint8List bytes;

  /// Lower-case hex, 64 characters.
  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  bool operator ==(Object other) {
    if (other is! IdentityHash) return false;
    for (var i = 0; i < identityHashLength; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'IdentityHash($hex)';
}

/// The public half of an identity: an X25519 public key and its SHA-256
/// identity hash. The hash is always computed here, so the two can never
/// disagree.
final class PublicIdentity {
  PublicIdentity(List<int> publicKey)
    : publicKey = _checked(publicKey),
      hash = IdentityHash(Sha256().toSync().hashSync(publicKey).bytes);

  final Uint8List publicKey;
  final IdentityHash hash;

  static Uint8List _checked(List<int> key) {
    if (key.length != publicKeyLength) {
      throw const CryptoException('Public key must be 32 bytes');
    }
    return Uint8List.fromList(key).asUnmodifiableView();
  }

  @override
  bool operator ==(Object other) =>
      other is PublicIdentity && other.hash == hash;

  @override
  int get hashCode => hash.hashCode;

  @override
  String toString() => 'PublicIdentity(${hash.hex})';
}

/// Who wrote a message, from this device's point of view. Each direction
/// has its own key and mailbox, so a relay cannot reflect a message back to
/// its sender.
enum MessageDirection { outgoing, incoming }

/// Opaque handle to the keys shared with one peer. The key bytes never leave
/// the crypto module; pass the handle back to the [CryptoService] and call
/// [CryptoService.forget] when done.
abstract interface class ConversationKeys {
  /// Identity hash of the peer these keys are shared with.
  IdentityHash get peer;
}

/// Where the Keystore wrapping key lives, as reported by Android.
enum KeyProtectionLevel {
  /// Separate tamper-resistant security chip.
  strongBox,

  /// Trusted Execution Environment (hardware isolated from Android).
  trustedEnvironment,

  /// Secure hardware of an unspecified kind (Android < 12 reports only this).
  secureHardware,

  /// Software only: no hardware isolation.
  software,

  unknown,
}

final class KeyProtection {
  const KeyProtection({
    required this.level,
    required this.deviceSecure,
    required this.unlockedDeviceRequired,
  });

  final KeyProtectionLevel level;

  /// Whether the phone has a PIN, pattern, password or biometric lock.
  final bool deviceSecure;

  /// Whether the Keystore refuses to use the key while the phone is locked.
  final bool unlockedDeviceRequired;

  bool get isHardwareBacked =>
      level == KeyProtectionLevel.strongBox ||
      level == KeyProtectionLevel.trustedEnvironment ||
      level == KeyProtectionLevel.secureHardware;
}
