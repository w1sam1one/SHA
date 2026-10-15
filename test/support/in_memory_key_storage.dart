import 'dart:typed_data';

import 'package:sha/crypto/crypto.dart';

/// Test double for the Android Keystore storage.
class InMemoryKeyStorage implements SecureKeyStorage {
  final Map<String, Uint8List> values = {};

  @override
  Future<Uint8List?> read(String name) async {
    final value = values[name];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String name, Uint8List value) async {
    values[name] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String name) async => values.remove(name);
}
