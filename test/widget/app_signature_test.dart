// F14 in docs/ROADMAP.md (0014 (2c)): "Teknisk information" shows the
// fingerprint of the certificate the app is signed with, says what it does
// not prove, and says so plainly for a debug build or when it cannot be read.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/features/app_info/app_signature.dart';
import 'package:sha/ui/technical_info_sheet.dart';

const release =
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';

final class FakePhone implements AppSignaturePlatform {
  FakePhone(this.answer);

  final Future<AppSignature> Function() answer;

  @override
  Future<AppSignature> read() => answer();
}

Future<void> openSheet(WidgetTester tester, AppSignaturePlatform phone) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appSignaturePlatformProvider.overrideWithValue(phone)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTechnicalInfoSheet(context),
            child: const Text('öppna'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('öppna'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(AppSignatureSection.title),
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a release build shows its fingerprint and what it does not '
      'prove', (tester) async {
    await openSheet(
      tester,
      FakePhone(
        () async => const AppSignature(sha256: [release], debuggable: false),
      ),
    );
    expect(find.text(AppSignatureSection.intro), findsOneWidget);
    expect(find.text(release), findsOneWidget);
    expect(find.text(AppSignatureSection.notProof), findsOneWidget);
    expect(find.text(AppSignatureSection.debug), findsNothing);
  });

  testWidgets('a debug build says that its fingerprint is not the one on the '
      'website', (tester) async {
    await openSheet(
      tester,
      FakePhone(
        () async => const AppSignature(sha256: [release], debuggable: true),
      ),
    );
    expect(find.text(release), findsOneWidget);
    expect(find.text(AppSignatureSection.debug), findsOneWidget);
    expect(find.text(AppSignatureSection.notProof), findsOneWidget);
  });

  testWidgets('a fingerprint that cannot be read is said so, and no value '
      'is shown', (tester) async {
    // What the Kotlin side sends: a fixed code. Shown at once, not after
    // Riverpod's retries (review of #56).
    await openSheet(
      tester,
      FakePhone(() async => throw PlatformException(code: 'unavailable')),
    );
    expect(find.text(AppSignatureSection.unreadable), findsOneWidget);
    expect(find.text(AppSignatureSection.reading), findsNothing);
    expect(find.textContaining(':AB:'), findsNothing);
  });

  test('the phone\'s answer is checked before it is shown', () {
    expect(
      AppSignature.parse({
        'sha256': [release],
        'debuggable': false,
      }).sha256,
      [release],
    );
    for (final bad in [
      <String, Object?>{},
      {'sha256': <String>[]},
      {
        'sha256': ['ab:cd'],
      },
      {
        'sha256': [release.toLowerCase()],
      },
      {'sha256': 'not a list'},
    ]) {
      expect(() => AppSignature.parse(bad), throwsStateError, reason: '$bad');
    }
  });
}
