// P6: the app's settings in the Olm state entry (0005, item 9), and taking
// shown failures off the counters (0004 §10). Needs the native library
// (tool/build_native_host.sh).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

import 'olm_service_cases.dart';

void main() {
  test('settings are empty without an account, and saving needs one', () async {
    final alice = Person();
    expect(await alice.olm.appSettings(), isEmpty);
    await expectLater(
      alice.olm.saveAppSettings({'server': 'https://a.example'}),
      throwsA(isA<CryptoException>()),
    );
  });

  test('settings are saved in the state entry and survive a restart', () async {
    final alice = await Person().start();
    await alice.olm.saveAppSettings({
      'server': 'https://a.example',
      'interval': '15',
    });
    expect(alice.savedState['settings'], {
      'server': 'https://a.example',
      'interval': '15',
    });
    expect(alice.vault.values.keys, {stateName, pickleKeyName});
    alice.restart();
    expect(await alice.olm.appSettings(), {
      'server': 'https://a.example',
      'interval': '15',
    });
    await alice.olm.saveAppSettings({'interval': '60'});
    expect(await alice.olm.appSettings(), {'interval': '60'});
  });

  test('resetIdentity removes the settings', () async {
    final alice = await Person().start();
    await alice.olm.saveAppSettings({'interval': '5'});
    await alice.service.resetIdentity();
    expect(await alice.olm.appSettings(), isEmpty);
  });

  test('shown failures are taken off; newer ones stay', () async {
    final (alice, bob) = await established();
    Future<void> broken(int n) async {
      for (var i = 0; i < n; i++) {
        final out = await alice.olm.encrypt(bob.key, 'x$i');
        await bob.olm.receive(alice.key, flipped(out.packet, 20));
      }
    }

    await broken(2);
    final shown = await bob.olm.failureCounts(alice.key);
    expect(shown.unreadable, 2);
    await broken(1); // arrives after the app read the counts
    await bob.olm.clearFailureCounts(alice.key, shown);
    expect((await bob.olm.failureCounts(alice.key)).unreadable, 1);
    bob.restart();
    expect((await bob.olm.failureCounts(alice.key)).unreadable, 1);
    await bob.olm.clearFailureCounts(alice.key, shown); // never below 0
    expect((await bob.olm.failureCounts(alice.key)).unreadable, 0);
  });

  test('clearing for an unknown contact changes nothing', () async {
    final alice = await Person().start();
    final before = alice.savedPickles;
    await alice.olm.clearFailureCounts(
      Uint8List(32)..[0] = 9,
      const OlmFailureCounts(unreadable: 1),
    );
    expect(alice.savedPickles, before);
    expect(alice.savedState['contacts'], isEmpty);
  });
}
