import 'dart:typed_data';

import 'entropy.dart';
import 'types.dart';

/// Device-bound storage for long-term secrets, plus the platform's own
/// CSPRNG. Implementations must never write a secret in plain form to disk,
/// preferences, backups or logs.
abstract interface class KeyVault implements EntropySource {
  /// Returns the stored value, or null if there is none.
  Future<Uint8List?> read(String name);

  Future<void> write(String name, Uint8List value);

  Future<void> delete(String name);

  /// Deletes every stored entry and the vault's own key, so the next [write]
  /// starts from scratch. Irreversible. Does nothing if the vault is empty.
  Future<void> reset();

  /// How the vault's key is protected on this device.
  Future<KeyProtection> protection();
}
