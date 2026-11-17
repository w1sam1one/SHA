import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licenses Flutter does not collect by itself to the license page
/// (F5): the two fonts (SIL OFL) and the Rust crates built into the Olm
/// library (`assets/licenses/rust.txt`, from `tool/rust_licenses.py`). The
/// Dart packages' licenses, among them AGPL-3.0 for flutter_vodozemac and
/// vodozemac, come from Flutter.
void registerExtraLicenses([AssetBundle? bundle]) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Manrope (font)', 'assets/fonts/Manrope-OFL.txt'),
      ('JetBrains Mono (font)', 'assets/fonts/JetBrainsMono-OFL.txt'),
      ('Rust crates in the Olm library', 'assets/licenses/rust.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([name], await assets.loadString(file));
    }
  });
}
