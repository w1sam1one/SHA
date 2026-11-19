// F11 in docs/ROADMAP.md: screenshots for the store, of the real app.
//
// FLAG_SECURE is on in every build (MainActivity.kt, and
// test/security/flag_secure_test.dart), so the phone's own screenshots are
// black. This test takes them through Flutter's own rendering instead
// (integration_test's takeScreenshot), in a debug test build that is never
// the release app. In CI it runs on the emulator and checks that every
// picture shows something (the app-android job in .github/workflows/ci.yml):
//
//     flutter test integration_test/screenshots_test.dart -d <device>
//
// To save the pictures on the computer (docs/release.md, point 5):
//
//     flutter drive --driver=test_driver/screenshots.dart \
//       --target=integration_test/screenshots_test.dart -d <device>
//
// The app must start as it does for a new user, and the test makes a new
// identity on the device. If SHA already has an identity there, the test
// stops before the first picture: the pictures would show it and its
// contacts. It never deletes anything. Run it on an emulator, or on a test
// phone where SHA is not installed.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sha/app/app.dart';
import 'package:sha/app/licenses.dart';

/// How many different colours a picture has, from a sample of its pixels.
Future<int> colours(WidgetTester tester, List<int> png) async {
  final count = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = data!.buffer.asUint32List();
    final seen = <int>{};
    for (var i = 0; i < pixels.length; i += 97) {
      seen.add(pixels[i]);
    }
    image.dispose();
    return seen.length;
  });
  return count!;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots of the real app, with FLAG_SECURE on', (
    tester,
  ) async {
    registerExtraLicenses();
    await tester.pumpWidget(const ProviderScope(child: ShaApp()));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();

    Future<void> shoot(String name) async {
      await tester.pumpAndSettle();
      final png = await binding.takeScreenshot(name);
      // A black or blank picture has one colour; a screen with text, icons
      // and a QR code has many.
      expect(
        await colours(tester, png),
        greaterThan(3),
        reason: '$name shows nothing',
      );
    }

    // A new user first sees the new identity.
    expect(
      find.text('Fortsätt'),
      findsOneWidget,
      reason:
          'SHA already has an identity on this device. Run the screenshots '
          'on an emulator, or on a test phone where SHA is not installed.',
    );
    await shoot('1-identitet');
    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();
    Future<void> tab(String label) => tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await shoot('2-chattar');
    await tab('Min QR');
    await shoot('3-min-qr');
    await tab('Kontakter');
    await shoot('4-kontakter');
    await tab('Inställningar');
    await shoot('5-installningar');
  });
}
