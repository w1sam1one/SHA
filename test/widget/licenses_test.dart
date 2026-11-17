// F5: the license page lists the fonts and the Rust crates, which Flutter
// does not collect by itself.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the fonts and the Rust crates are on the license page', () async {
    registerExtraLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((e) => e.packages.contains(package))
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');

    expect(textOf('Manrope (font)'), contains('SIL OPEN FONT LICENSE'));
    expect(textOf('JetBrains Mono (font)'), contains('SIL OPEN FONT LICENSE'));
    final rust = textOf('Rust crates in the Olm library');
    expect(rust, contains('vodozemac 0.11.2: Apache-2.0'));
    expect(rust, contains('Apache License'));
    // Crates without a license file are still named with their license.
    expect(rust, contains('matrix-pickle 0.2.3: Apache-2.0'));
  });
}
