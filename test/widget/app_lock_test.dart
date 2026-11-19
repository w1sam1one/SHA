// F4, step 1 of (B) in 0011: the app is locked with the phone's own lock
// when it opens and after 5 minutes in the background. The phone's prompt is
// a fake here; on a phone it is BiometricPrompt or KeyguardManager.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/app.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/features/lock/app_lock.dart';

import '../support/in_memory_vault.dart';

final class FakeLock implements AppLockPlatform {
  FakeLock({this.secure = true});

  bool secure;
  Object? failCanLock;
  Object? failUnlock;

  /// Each call to [unlock] waits for the next answer given here.
  final List<Completer<UnlockResult>> asked = [];

  @override
  Future<bool> canLock() async {
    final e = failCanLock;
    if (e != null) throw e;
    return secure;
  }

  @override
  Future<UnlockResult> unlock({required String title, required String text}) {
    final e = failUnlock;
    if (e != null) return Future.error(e);
    final c = Completer<UnlockResult>();
    asked.add(c);
    return c.future;
  }
}

final class Clock {
  DateTime now = DateTime.utc(2026, 11, 19, 12);

  DateTime call() => now;
}

Future<void> pumpGate(WidgetTester tester, FakeLock lock, Clock clock) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockPlatformProvider.overrideWithValue(lock),
        appLockClockProvider.overrideWithValue(clock.call),
      ],
      child: const MaterialApp(home: AppLockGate(child: Text('innehållet'))),
    ),
  );
  await tester.pumpAndSettle();
}

final content = find.text('innehållet');
final locked = find.text('SHA är låst');

void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

const toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const toFront = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

void main() {
  testWidgets('locked when it opens: nothing behind the lock is built until '
      'the phone says yes', (tester) async {
    final lock = FakeLock();
    await pumpGate(tester, lock, Clock());
    expect(content, findsNothing);
    expect(locked, findsOneWidget);
    expect(lock.asked, hasLength(1), reason: 'the prompt opens by itself');

    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    expect(locked, findsNothing);
  });

  testWidgets('cancelled: still locked, and "Lås upp" asks again', (
    tester,
  ) async {
    final lock = FakeLock();
    await pumpGate(tester, lock, Clock());
    lock.asked.single.complete(UnlockResult.cancelled);
    await tester.pumpAndSettle();
    expect(content, findsNothing);

    await tester.tap(find.text('Lås upp'));
    await tester.pumpAndSettle();
    expect(lock.asked, hasLength(2));
    lock.asked.last.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
  });

  testWidgets('locks again after 5 minutes in the background, not before', (
    tester,
  ) async {
    final lock = FakeLock();
    final clock = Clock();
    await pumpGate(tester, lock, clock);
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();

    lifecycle(tester, toBackground);
    clock.now = clock.now.add(
      const Duration(minutes: 5) - const Duration(seconds: 1),
    );
    lifecycle(tester, toFront);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));

    lifecycle(tester, toBackground);
    clock.now = clock.now.add(const Duration(minutes: 5));
    lifecycle(tester, toFront);
    await tester.pumpAndSettle();
    expect(content, findsNothing);
    expect(locked, findsOneWidget);
    expect(lock.asked, hasLength(2));
  });

  testWidgets('the phone\'s own prompt does not lock the app again', (
    tester,
  ) async {
    final lock = FakeLock();
    final clock = Clock();
    await pumpGate(tester, lock, clock);
    // On Android 7–9 the PIN screen is an activity of its own: the app goes
    // to the background and back while it is shown.
    lifecycle(tester, toBackground);
    clock.now = clock.now.add(const Duration(minutes: 6));
    lifecycle(tester, toFront);
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));
  });

  testWidgets('a slow PIN screen on Android 7–9 does not lock the app again '
      'when it answers before the app is back in front', (tester) async {
    final lock = FakeLock();
    final clock = Clock();
    await pumpGate(tester, lock, clock);
    lifecycle(tester, toBackground);
    clock.now = clock.now.add(const Duration(minutes: 6));
    // Android delivers the PIN screen's answer before the app is resumed.
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    lifecycle(tester, toFront);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));
  });

  testWidgets('without a screen lock on the phone the app is not locked', (
    tester,
  ) async {
    final lock = FakeLock(secure: false);
    await pumpGate(tester, lock, Clock());
    expect(content, findsOneWidget);
    expect(lock.asked, isEmpty);
  });

  testWidgets('the phone says it has no lock when asked: the app opens', (
    tester,
  ) async {
    final lock = FakeLock();
    await pumpGate(tester, lock, Clock());
    lock.asked.single.complete(UnlockResult.unavailable);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
  });

  testWidgets('in the app, the home screen with the chats is behind the '
      'lock', (tester) async {
    final lock = FakeLock();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyVaultProvider.overrideWithValue(InMemoryVault()),
          appLockPlatformProvider.overrideWithValue(lock),
        ],
        child: const ShaApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();
    expect(locked, findsOneWidget);
    expect(find.text('Chattar'), findsNothing);
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(find.text('Chattar'), findsWidgets);
  });

  testWidgets('an error from the phone keeps it locked', (tester) async {
    final lock = FakeLock()
      ..failCanLock = StateError('x')
      ..failUnlock = StateError('y');
    await pumpGate(tester, lock, Clock());
    await tester.pumpAndSettle();
    expect(content, findsNothing);
    expect(locked, findsOneWidget);
    expect(find.text('Lås upp'), findsOneWidget);
  });
}
