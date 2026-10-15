import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where long-term private key material is kept. Implementations must never
/// write it in plain form to disk, preferences or logs.
abstract interface class SecureKeyStorage {
  Future<Uint8List?> read(String name);
  Future<void> write(String name, Uint8List value);
  Future<void> delete(String name);
}

/// Android Keystore-backed storage (via `flutter_secure_storage`).
///
/// Values are encrypted with AES-256-GCM under a key that is itself wrapped by
/// an RSA key generated inside the Android Keystore (hardware-backed where the
/// device supports it) and never exportable. Only the wrapped ciphertext ever
/// touches app storage.
final class AndroidKeystoreStorage implements SecureKeyStorage {
  AndroidKeystoreStorage()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          // Fail loudly instead of silently wiping the identity if the
          // Keystore key becomes unusable.
          resetOnError: false,
          storageNamespace: 'sha_keys',
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> read(String name) async {
    final value = await _storage.read(key: name);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> write(String name, Uint8List value) =>
      _storage.write(key: name, value: base64Encode(value));

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}
