import 'dart:math';
import 'dart:typed_data';

import 'package:sha/crypto/crypto.dart';

/// Test double for the Android Keystore vault.
class InMemoryVault implements KeyVault {
  InMemoryVault({
    this.protectionValue = const KeyProtection(
      level: KeyProtectionLevel.strongBox,
      deviceSecure: true,
      unlockedDeviceRequired: true,
    ),
    Uint8List Function(int length)? random,
  }) : _random = random; // ignore: prefer_initializing_formals

  final Map<String, Uint8List> values = {};
  final KeyProtection protectionValue;
  final Uint8List Function(int length)? _random;
  final Random _secure = Random.secure();

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

  @override
  Future<Uint8List> randomBytes(int length) async =>
      _random?.call(length) ??
      Uint8List.fromList(List.generate(length, (_) => _secure.nextInt(256)));

  @override
  Future<KeyProtection> protection() async => protectionValue;
}
