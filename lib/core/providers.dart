import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/crypto.dart';

/// Keystore-backed storage and platform randomness. Overridden in tests.
final keyVaultProvider = Provider<KeyVault>((ref) => AndroidKeystoreVault());

/// The single gateway to all cryptography in the app.
final cryptoServiceProvider = Provider<CryptoService>(
  (ref) => ShaCryptoService(vault: ref.watch(keyVaultProvider)),
);

/// Whether messages actually leave this phone. There is no transport yet:
/// messages are only kept in memory here. Flip to true only when a real
/// transport sends and receives.
final transportAvailableProvider = Provider<bool>((ref) => false);

/// How this phone protects the identity key (StrongBox, TEE, …).
final keyProtectionProvider = FutureProvider<KeyProtection>(
  (ref) => ref.watch(cryptoServiceProvider).keyProtection(),
);
