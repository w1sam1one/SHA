// R8: the same requirement tests, run on an Android device or emulator:
//   flutter test integration_test/olm_spike_test.dart -d <device>
// On Android the plugin builds and bundles the native library itself.

import 'package:integration_test/integration_test.dart';

import '../test/olm_spike_test.dart' as spike;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  spike.main();
}
