// P2 in docs/ROADMAP.md: Olm is part of the app's build.
//
// Runs on an Android device or emulator (the app-android job in
// .github/workflows/ci.yml):
//
//     flutter test integration_test/olm_build_test.dart -d <device>
//
// It checks that the app's APK carries flutter_vodozemac's native library
// and that the library works: two accounts start a session from what the
// QR code will carry (0004 §1) and exchange one message each way. It uses
// only the library's public API. No app code uses Olm yet (that is P3).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fv;
import 'package:integration_test/integration_test.dart';
import 'package:vodozemac/vodozemac.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Once per process: flutter_rust_bridge throws if it is initialised twice.
  // init() itself fails if the APK has no native library, or the wrong one.
  setUpAll(fv.init);

  test('the native Olm library loads in the app build', () {
    expect(isInitialized(), isTrue);
  });

  test('a session starts and a message goes each way', () {
    final alice = Account();
    final bob = Account();
    bob.generateOneTimeKeys(1);
    final oneTimeKey = bob.oneTimeKeys.values.single;
    bob.markKeysAsPublished();

    final aliceSession = alice.createOutboundSession(
      identityKey: bob.curve25519Key,
      oneTimeKey: oneTimeKey,
    );
    final first = aliceSession.encrypt('hej');
    expect(first.messageType, 0, reason: 'before any reply: pre-key');

    final inbound = bob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: first.ciphertext,
    );
    expect(inbound.plaintext, 'hej');
    expect(inbound.session.sessionId, aliceSession.sessionId);

    final reply = inbound.session.encrypt('hej tillbaka');
    expect(reply.messageType, 1);
    expect(
      aliceSession.decrypt(
        messageType: reply.messageType,
        ciphertext: reply.ciphertext,
      ),
      'hej tillbaka',
    );
  });
}
