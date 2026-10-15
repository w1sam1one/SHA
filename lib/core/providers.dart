import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/crypto.dart';

/// Where private key material is stored. Overridden in tests.
final secureKeyStorageProvider = Provider<SecureKeyStorage>(
  (ref) => AndroidKeystoreStorage(),
);

/// The single gateway to all cryptography in the app.
final cryptoServiceProvider = Provider<CryptoService>(
  (ref) => ShaCryptoService(storage: ref.watch(secureKeyStorageProvider)),
);
