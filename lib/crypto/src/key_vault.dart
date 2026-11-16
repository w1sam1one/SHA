import 'dart:typed_data';

import 'entropy.dart';
import 'types.dart';

/// Device-bound storage for long-term secrets, plus the platform's own
/// CSPRNG. Implementations must never write a secret in plain form to disk,
/// preferences, backups or logs.
abstract interface class KeyVault implements EntropySource {
  /// Returns the stored value, or null if there is none.
  Future<Uint8List?> read(String name);

  /// Stores [value] under [name], replacing any old value in one step.
  /// Completes only once the value is on disk. Throws [CryptoException] if
  /// it may not have been saved; then either the old or the new value may be
  /// read back (both complete), so the caller must read it again rather
  /// than assume either.
  Future<void> write(String name, Uint8List value);

  /// Throws [CryptoException] if the entry may still be there.
  Future<void> delete(String name);

  /// Deletes the vault's own key first and then every stored entry, so the
  /// next [write] starts from scratch. If it is interrupted, entries that are
  /// left can no longer be read. Irreversible. Does nothing if the vault is
  /// empty.
  Future<void> reset();

  /// How the vault's key is protected on this device.
  Future<KeyProtection> protection();
}
