// F11 in docs/ROADMAP.md: screenshots for the store, of the real app.
//
// FLAG_SECURE is on in every build (MainActivity.kt, and
// test/security/flag_secure_test.dart), so the phone's own screenshots are
// black. This test takes them through Flutter's own rendering instead
// (integration_test's takeScreenshot), in a debug test build that is never
// the release app. In CI it runs on the emulator and checks that every
// picture shows something (the app-android job in .github/workflows/ci.yml):
//
//     flutter test integration_test/screenshots_test.dart -d <emulator>
//
// To save the pictures on the computer (docs/release.md, point 5):
//
//     flutter drive --driver=test_driver/screenshots.dart \
//       --target=integration_test/screenshots_test.dart -d <emulator>
//
// Only on an emulator, never on a phone where SHA is used: `flutter test`
// and `flutter drive` uninstall the app when the test is done (and can
// before it starts), which erases its identity, contacts and history
// (review of #49).
//
// The app must start as it does for a new user, and the test makes a new
// identity. If SHA already has an identity on the device, the test stops
// before the first picture, so that the pictures do not show it and its
// contacts. That protects the pictures, not the app's data.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sha/app/app.dart';
import 'package:sha/app/licenses.dart';
import 'package:sha/features/chat/chats_screen.dart';
import 'package:sha/features/contacts/contacts_screen.dart';
import 'package:sha/features/qr/my_qr_screen.dart';
import 'package:sha/features/settings/settings_screen.dart';

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

    /// A picture of the screen that [shows] finds, and not of the lock
    /// (review of #49: with a screen lock, the app locks after "Fortsätt").
    Future<void> shoot(String name, Finder shows) async {
      await tester.pumpAndSettle();
      expect(find.text('SHA är låst'), findsNothing, reason: '$name: locked');
      expect(shows, findsOneWidget, reason: '$name: not the right screen');
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
          'only on an emulator.',
    );
    await shoot('1-identitet', find.text('Fortsätt'));
    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();
    Future<void> tab(String label) => tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    // Each tab by its screen: only the shown one is on stage in the
    // IndexedStack. The app opens on Kontakter, so every tab is tapped.
    for (final (name, label, screen) in [
      ('2-chattar', 'Chattar', ChatsScreen),
      ('3-min-qr', 'Min QR', MyQrScreen),
      ('4-kontakter', 'Kontakter', ContactsScreen),
      ('5-installningar', 'Inställningar', SettingsScreen),
    ]) {
      await tab(label);
      await shoot(name, find.byType(screen));
    }
  });
}
