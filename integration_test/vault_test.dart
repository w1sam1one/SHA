// P3 in docs/ROADMAP.md, and 0005 "Om ägaren väljer (A) och (i)": the
// Keystore vault on a real Android system (the app-android job in
// .github/workflows/ci.yml):
//
//     flutter test integration_test/vault_test.dart -d <device>
//
// It checks what the unit tests cannot: that the Kotlin vault really
// reports a failed write, that reset() deletes the key before the files, and
// that entries left behind by an interrupted reset cannot be read.
//
// The test runs inside the app's process, so it can reach the vault's
// directory with dart:io and break it on purpose.
//
// WARNING: it resets the vault, so it deletes the identity and every key on
// the device it runs on. Run it only on an emulator or a test phone.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sha/crypto/crypto.dart';

/// Context.getNoBackupFilesDir() for the app (applicationId
/// io.github.w1sam1one.sha, 0014), plus the vault's own directory
/// (KeystoreVault.DIRECTORY).
const String vaultDirectory =
    '/data/data/io.github.w1sam1one.sha/no_backup/sha_keys';

Uint8List bytes(int length, int seed) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xff));

Future<void> chmod(String mode) async {
  final result = await Process.run('chmod', [mode, vaultDirectory]);
  expect(result.exitCode, 0, reason: 'chmod $mode: ${result.stderr}');
}

Matcher throwsKind(CryptoErrorKind kind) =>
    throwsA(isA<CryptoException>().having((e) => e.kind, 'kind', kind));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final vault = AndroidKeystoreVault();

  setUp(() async {
    if (Directory(vaultDirectory).existsSync()) await chmod('700');
    await vault.reset();
  });

  tearDownAll(() async {
    if (Directory(vaultDirectory).existsSync()) await chmod('700');
    await vault.reset();
  });

  test('write, read, overwrite and delete', () async {
    expect(await vault.read('p3.basic'), isNull);
    await vault.write('p3.basic', bytes(100, 1));
    expect(await vault.read('p3.basic'), bytes(100, 1));
    expect(
      File('$vaultDirectory/p3.basic.bin').existsSync(),
      isTrue,
      reason: 'the test must look in the vault directory the app uses',
    );

    await vault.write('p3.basic', bytes(50, 2));
    expect(await vault.read('p3.basic'), bytes(50, 2));

    await vault.delete('p3.basic');
    expect(await vault.read('p3.basic'), isNull);
    expect(File('$vaultDirectory/p3.basic.bin').existsSync(), isFalse);
  });

  test('what read and randomBytes give is the caller\'s own and can be '
      'wiped', () async {
    // The platform channel's bytes are a read-only view. The app wipes
    // what it reads (ShaOlmService._load, MixedEntropy), which threw here
    // before the vault copied them.
    await vault.write('p3.wipe', bytes(64, 4));
    final read = (await vault.read('p3.wipe'))!;
    read.fillRange(0, read.length, 0);
    expect(await vault.read('p3.wipe'), bytes(64, 4));
    final random = await vault.randomBytes(64);
    random.fillRange(0, random.length, 0);
    expect(random, everyElement(0));
  });

  test('a large entry, with the time it takes', () async {
    for (final size in [512 * 1024, 2 * 1024 * 1024]) {
      final value = bytes(size, 3);
      final write = Stopwatch()..start();
      await vault.write('p3.large', value);
      write.stop();
      final read = Stopwatch()..start();
      final back = await vault.read('p3.large');
      read.stop();
      expect(back, value);
      // Data for the 300 ms limit in 0005; P3 measures the real state.
      // ignore: avoid_print
      print(
        'VAULT ${size ~/ 1024} KiB: '
        'write ${write.elapsedMilliseconds} ms, '
        'read ${read.elapsedMilliseconds} ms',
      );
    }
  });

  test('reset removes every entry, and the vault works again', () async {
    await vault.write('p3.one', bytes(10, 4));
    await vault.write('p3.two', bytes(10, 5));
    await vault.reset();
    expect(await vault.read('p3.one'), isNull);
    expect(await vault.read('p3.two'), isNull);
    expect(Directory(vaultDirectory).listSync(), isEmpty);

    await vault.write('p3.one', bytes(10, 6));
    expect(await vault.read('p3.one'), bytes(10, 6));
  });

  test('a write that cannot be saved throws and keeps the old value', () async {
    await vault.write('p3.keep', bytes(64, 7));

    // The directory becomes read-only, so the temporary file cannot be made.
    await chmod('500');
    await expectLater(
      vault.write('p3.keep', bytes(64, 8)),
      throwsKind(CryptoErrorKind.unavailable),
    );
    await chmod('700');

    expect(await vault.read('p3.keep'), bytes(64, 7));
    expect(
      Directory(vaultDirectory).listSync().map((e) => e.path.split('/').last),
      ['p3.keep.bin'],
      reason: 'the old entry is the only file',
    );
  });

  test('a rename that fails throws instead of being ignored', () async {
    // A directory where the entry's file should go: rename(2) onto it fails.
    // reset() only deletes files, so remove the directory even if we fail.
    final blocked = Directory('$vaultDirectory/p3.blocked.bin')..createSync();
    addTearDown(() {
      if (blocked.existsSync()) blocked.deleteSync(recursive: true);
    });

    await expectLater(
      vault.write('p3.blocked', bytes(64, 10)),
      throwsKind(CryptoErrorKind.unavailable),
    );
    expect(
      File('$vaultDirectory/p3.blocked.bin.tmp').existsSync(),
      isFalse,
      reason: 'no temporary file is left behind',
    );
  });

  test('entries left by an interrupted reset cannot be read', () async {
    await vault.write('p3.a', bytes(32, 11));
    await vault.write('p3.b', bytes(32, 12));

    // A read-only directory stops reset() at the first file it deletes.
    await chmod('500');
    await expectLater(vault.reset(), throwsKind(CryptoErrorKind.unavailable));
    await chmod('700');

    // Both files are still there, but the key was deleted first.
    expect(File('$vaultDirectory/p3.a.bin').existsSync(), isTrue);
    await expectLater(
      vault.read('p3.a'),
      throwsKind(CryptoErrorKind.keyInvalidated),
    );

    // A new write makes a new key; the old file still fails authentication.
    await vault.write('p3.c', bytes(32, 13));
    await expectLater(vault.read('p3.b'), throwsKind(CryptoErrorKind.corrupt));
    expect(await vault.read('p3.c'), bytes(32, 13));
  });
}
