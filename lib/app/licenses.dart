import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licenses Flutter does not collect by itself to the license page
/// (F5): the two fonts (SIL OFL) and the Rust crates of the Olm library
/// (`assets/licenses/rust.txt`, from `tool/rust_licenses.py`). The
/// Dart packages' licenses, among them AGPL-3.0 for flutter_vodozemac and
/// vodozemac, come from Flutter.
void registerExtraLicenses([AssetBundle? bundle]) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Manrope (typsnitt)', 'assets/fonts/Manrope-OFL.txt'),
      ('JetBrains Mono (typsnitt)', 'assets/fonts/JetBrainsMono-OFL.txt'),
      ('Rust-paket i krypteringsbiblioteket', 'assets/licenses/rust.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([name], await assets.loadString(file));
    }
  });
}
