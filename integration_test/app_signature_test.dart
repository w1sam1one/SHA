// F14 in docs/ROADMAP.md (0014 (2c)): on the emulator, Android tells the
// app which certificate it is signed with (`PackageManager.signingInfo`,
// android/app/src/main/kotlin/se/sha/sha/app/AppSignatureChannel.kt). A
// test build is a debug build, signed with the debug key.
//
//     flutter test integration_test/app_signature_test.dart -d <emulator>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sha/features/app_info/app_signature.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the app reads its own signing certificate', () async {
    final signature = await const MethodChannelAppSignature().read();
    expect(signature.sha256, hasLength(1));
    expect(
      signature.sha256.single,
      matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')),
    );
    expect(signature.debuggable, isTrue);
  });
}
