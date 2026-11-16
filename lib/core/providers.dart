import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/crypto.dart';

/// Keystore-backed storage and platform randomness. Overridden in tests.
final keyVaultProvider = Provider<KeyVault>((ref) => AndroidKeystoreVault());

/// The single gateway to all cryptography in the app.
final cryptoServiceProvider = Provider<CryptoService>(
  (ref) => ShaCryptoService(vault: ref.watch(keyVaultProvider)),
);

/// How this phone protects the identity key (StrongBox, TEE, …).
final keyProtectionProvider = FutureProvider<KeyProtection>(
  (ref) => ref.watch(cryptoServiceProvider).keyProtection(),
);
