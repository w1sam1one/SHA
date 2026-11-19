import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licenses Flutter does not collect by itself to the license page
/// (F5): the two fonts (SIL OFL), the Rust crates of the Olm library
/// (`assets/licenses/rust.txt`, from `tool/rust_licenses.py`), the Android
/// libraries (`assets/licenses/android.txt`) and ZXing. The
/// Dart packages' licenses, among them AGPL-3.0 for flutter_vodozemac and
/// vodozemac, come from Flutter.
void registerExtraLicenses([AssetBundle? bundle]) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Manrope (typsnitt)', 'assets/fonts/Manrope-OFL.txt'),
      ('JetBrains Mono (typsnitt)', 'assets/fonts/JetBrainsMono-OFL.txt'),
      ('Rust-paket i krypteringsbiblioteket', 'assets/licenses/rust.txt'),
      // 0012 (C1): the Android libraries in the APK, checked in CI against
      // Gradle's own list, and ZXing's license for the QR decoder.
      ('Android-bibliotek', 'assets/licenses/android.txt'),
      ('ZXing (QR-avkodningen)', 'assets/licenses/zxing.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([name], await assets.loadString(file));
    }
  });
}
