// F5: the license page lists what Flutter does not collect by itself: the
// fonts, the Rust crates, the Android libraries and ZXing.
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

    expect(textOf('Manrope (typsnitt)'), contains('SIL OPEN FONT LICENSE'));
    expect(
      textOf('JetBrains Mono (typsnitt)'),
      contains('SIL OPEN FONT LICENSE'),
    );
    final rust = textOf('Rust-paket i krypteringsbiblioteket');
    expect(rust, contains('vodozemac 0.11.2: Apache-2.0'));
    expect(rust, contains('Apache License'));
    // Crates without a license file are still named with their license.
    expect(rust, contains('matrix-pickle 0.2.3: Apache-2.0'));

    // 0012 (C1): the Android libraries, checked in CI against Gradle's own
    // list, and ZXing's license for the QR decoder.
    final android = textOf('Android-bibliotek');
    expect(android, contains('Gradles lista'));
    expect(android, contains('Apache License'));
    final zxing = textOf('ZXing (QR-avkodningen)');
    expect(zxing, contains('https://github.com/zxing/zxing'));
    expect(zxing, contains('Apache License'));
  });
}
