import 'package:flutter/services.dart';

import 'key_vault.dart';
import 'types.dart';

/// [KeyVault] backed by the Android Keystore through the app's own native
/// code (`android/app/src/main/kotlin/se/sha/sha/keystore/`).
///
/// - Values are encrypted with AES-256-GCM by a key that is generated *inside*
///   the Keystore — in StrongBox when the phone has one, otherwise the TEE —
///   and can never be exported. The key only works while the phone is
///   unlocked (API 28+).
/// - The encrypted blobs live in the app's `noBackupFilesDir`, which other
///   apps cannot read and which is never backed up or transferred.
/// - Each blob is bound to its name, so blobs cannot be swapped.
/// - There is no exported component: only this app's process can reach it.
final class AndroidKeystoreVault implements KeyVault {
  AndroidKeystoreVault([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'se.sha/keystore';
  static final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  final MethodChannel _channel;

  @override
  Future<Uint8List?> read(String name) =>
      _call<Uint8List>('read', {'name': _checkName(name)});

  @override
  Future<void> write(String name, Uint8List value) =>
      _call<void>('write', {'name': _checkName(name), 'value': value});

  @override
  Future<void> delete(String name) =>
      _call<void>('delete', {'name': _checkName(name)});

  @override
  Future<Uint8List> randomBytes(int length) async {
    if (length <= 0 || length > 1024) {
      throw const CryptoException('Invalid random length');
    }
    final bytes = await _call<Uint8List>('randomBytes', {'length': length});
    if (bytes == null || bytes.length != length) {
      throw const CryptoException(
        'Platform random source failed',
        CryptoErrorKind.entropy,
      );
    }
    return bytes;
  }

  @override
  Future<KeyProtection> protection() async {
    final map = await _call<Map<Object?, Object?>>('protection', const {});
    return KeyProtection(
      level: switch (map?['level']) {
        'strongbox' => KeyProtectionLevel.strongBox,
        'tee' => KeyProtectionLevel.trustedEnvironment,
        'secure_hardware' => KeyProtectionLevel.secureHardware,
        'software' => KeyProtectionLevel.software,
        _ => KeyProtectionLevel.unknown,
      },
      deviceSecure: map?['deviceSecure'] == true,
      unlockedDeviceRequired: map?['unlockedDeviceRequired'] == true,
    );
  }

  static String _checkName(String name) {
    if (!_validName.hasMatch(name)) {
      throw const CryptoException('Invalid vault entry name');
    }
    return name;
  }

  Future<T?> _call<T>(String method, Map<String, Object> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      // Native errors carry only a fixed code; map it to a fixed message.
      throw switch (e.code) {
        'LOCKED' => const CryptoException(
          'Device is locked',
          CryptoErrorKind.deviceLocked,
        ),
        'INVALIDATED' => const CryptoException(
          'Keystore key is no longer valid',
          CryptoErrorKind.keyInvalidated,
        ),
        'CORRUPT' => const CryptoException(
          'Stored key failed authentication',
          CryptoErrorKind.corrupt,
        ),
        _ => const CryptoException(
          'Keystore unavailable',
          CryptoErrorKind.unavailable,
        ),
      };
    } on MissingPluginException {
      throw const CryptoException(
        'Keystore unavailable',
        CryptoErrorKind.unavailable,
      );
    }
  }
}
