import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidKeystoreVault.channelName);
  final vault = AndroidKeystoreVault();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void respond(Object? Function(MethodCall call) handler) => messenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));

  test('maps native error codes to fixed exceptions', () async {
    for (final (code, kind) in [
      ('LOCKED', CryptoErrorKind.deviceLocked),
      ('INVALIDATED', CryptoErrorKind.keyInvalidated),
      ('CORRUPT', CryptoErrorKind.corrupt),
      ('WRITE_FAILED', CryptoErrorKind.unavailable),
      ('ANYTHING', CryptoErrorKind.unavailable),
    ]) {
      respond((_) => throw PlatformException(code: code, message: 'secret?'));
      await expectLater(
        vault.read('identity.x25519.private.v2'),
        throwsA(
          isA<CryptoException>()
              .having((e) => e.kind, 'kind', kind)
              .having((e) => e.toString(), 'text', isNot(contains('secret'))),
        ),
      );
    }
  });

  test('reset calls the native "reset" method and maps its errors', () async {
    final calls = <String>[];
    respond((call) {
      calls.add(call.method);
      return null;
    });
    await vault.reset();
    expect(calls, ['reset']);

    for (final (code, kind) in [
      ('UNAVAILABLE', CryptoErrorKind.unavailable),
      ('LOCKED', CryptoErrorKind.deviceLocked),
    ]) {
      respond((_) => throw PlatformException(code: code, message: 'secret?'));
      await expectLater(
        vault.reset(),
        throwsA(
          isA<CryptoException>()
              .having((e) => e.kind, 'kind', kind)
              .having((e) => e.toString(), 'text', isNot(contains('secret'))),
        ),
      );
    }
  });

  test('rejects unsafe entry names before reaching native code', () async {
    var called = false;
    respond((_) => called = true);
    for (final name in ['../x', 'A', '', '.hidden', 'a/b']) {
      expect(
        () => vault.read(name),
        throwsA(isA<CryptoException>()),
        reason: name,
      );
    }
    expect(called, isFalse);
  });

  test('rejects short platform randomness', () async {
    respond((_) => Uint8List(10));
    await expectLater(vault.randomBytes(64), throwsA(isA<CryptoException>()));
  });

  test('reads the protection report', () async {
    respond(
      (_) => {
        'level': 'strongbox',
        'deviceSecure': true,
        'unlockedDeviceRequired': true,
      },
    );
    final p = await vault.protection();
    expect(p.level, KeyProtectionLevel.strongBox);
    expect(p.isHardwareBacked, isTrue);
  });
}
