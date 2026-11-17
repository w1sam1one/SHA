// P3 in docs/ROADMAP.md, on Android (the app-android job):
//
//     flutter test integration_test/olm_service_test.dart -d <device>
//
// - R8: the same Olm cases as test/crypto/olm_service_test.dart, with the
//   library from the APK.
// - The measurement in 0005: the whole state in the real Keystore vault,
//   with 20 contacts and 3 sessions each, 5 packets of the largest size in
//   the outbox and 20 received messages. A write over 300 ms means Claude
//   stops and asks the owner, so the numbers are printed, not asserted.
//
// WARNING: the measurement resets the vault, so it deletes the identity and
// every key on the device it runs on. Run it only on an emulator or a test
// phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sha/crypto/crypto.dart';

import '../test/crypto/olm_service_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  olmServiceCases();

  test('0005 measurement: one write and the read at start', () async {
    final vault = AndroidKeystoreVault();
    await vault.reset();
    final me = ShaCryptoService(vault: vault);
    final myKey = await me.olm.createAccount();

    // 20 contacts, 3 sessions each; one answer from each, so 20 messages
    // wait in the inbox and some sessions have a receiving chain.
    final peers = <Person>[];
    for (var i = 0; i < 20; i++) {
      final peer = await Person().start();
      peers.add(peer);
      for (var s = 0; s < 3; s++) {
        await me.olm.startSession(await peer.olm.publishBundle());
      }
      final hello = await me.olm.encrypt(peer.key, 'hej');
      await me.olm.markSent(hello.id);
      expect(
        (await peer.olm.receive(myKey, hello.packet)).message?.text,
        'hej',
      );
      final answer = await peer.olm.encrypt(myKey, 'svar ' * 200);
      expect(
        (await me.olm.receive(peer.key, answer.packet)).message,
        isNotNull,
      );
    }
    // 5 packets of the largest size: the relay takes 65 712 bytes, of which
    // about 64 000 can be text (0004 §5).
    for (var i = 0; i < 5; i++) {
      await me.olm.encrypt(peers.first.key, 'x' * 64000);
    }
    expect(await me.olm.inbox(), hasLength(20));
    expect(await me.olm.outbox(), hasLength(5));

    final state = (await vault.read('olm.state.v1'))!;
    final writes = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      await vault.write('olm.state.v1', state);
      writes.add(watch.elapsedMilliseconds);
    }
    final sends = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      final out = await me.olm.encrypt(peers[1].key, 'kort');
      sends.add(watch.elapsedMilliseconds);
      await me.olm.markSent(out.id);
    }
    final restarted = ShaCryptoService(vault: vault);
    final watch = Stopwatch()..start();
    await restarted.olm.outbox();
    final readAtStart = watch.elapsedMilliseconds;

    // ignore: avoid_print
    print(
      'MEASURE-0005 state ${state.length ~/ 1024} KiB; '
      'vault write ${writes.join('/')} ms (max ${writes.reduce(_max)}); '
      'encrypt incl. save ${sends.join('/')} ms (max ${sends.reduce(_max)}); '
      'read at start $readAtStart ms; limit 300 ms per write',
    );
    await vault.reset();
  });

  test(
    'P4 measurement: a write with 50 sessions for one contact',
    measureManySessions,
  );
}

int _max(int a, int b) => a > b ? a : b;

/// P4 (0005 after G5): with no deletion of sessions (0006 (iii)) there is no
/// upper limit per contact, so one write is measured with many sessions for
/// one contact. Printed, not asserted, as for the 0005 measurement.
Future<void> measureManySessions() async {
  final vault = AndroidKeystoreVault();
  await vault.reset();
  final me = ShaCryptoService(vault: vault);
  await me.olm.createAccount();
  final peer = await Person().start();
  for (var i = 0; i < 50; i++) {
    await me.olm.startSession(await peer.olm.publishBundle());
  }
  final state = (await vault.read('olm.state.v1'))!;
  final writes = <int>[];
  for (var i = 0; i < 5; i++) {
    final watch = Stopwatch()..start();
    final out = await me.olm.encrypt(peer.key, 'kort');
    writes.add(watch.elapsedMilliseconds);
    await me.olm.markSent(out.id);
  }
  // ignore: avoid_print
  print(
    'MEASURE-P4 50 sessions for one contact: state ${state.length ~/ 1024} KiB; '
    'encrypt incl. save ${writes.join('/')} ms (max ${writes.reduce(_max)}); '
    'limit 300 ms per write',
  );
  await vault.reset();
}
