// F4, step 1 of (B) in 0011: the app is locked with the phone's own lock
// when it opens and after 5 minutes in the background. The phone's prompt and
// its clock are fakes here; on a phone they are BiometricPrompt or
// KeyguardManager, and SystemClock.elapsedRealtime.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Object? failElapsed;

  /// The phone's time since it started, which no one can set.
  Duration now = const Duration(hours: 1);

  /// While set, [elapsed] waits for it: the channel's answer is on its way.
  Completer<void>? holdElapsed;

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

  @override
  Future<Duration> elapsed() async {
    final e = failElapsed;
    if (e != null) throw e;
    final hold = holdElapsed;
    if (hold != null) await hold.future;
    return now;
  }
}

/// The lock around the whole navigator, as in the app: a page opened on
/// top of the first one is behind it too.
Future<void> pumpGate(WidgetTester tester, FakeLock lock) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appLockPlatformProvider.overrideWithValue(lock)],
      child: MaterialApp(
        builder: (context, child) => AppLockGate(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Text('innehållet'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('en chatt')),
                    ),
                  ),
                  child: const Text('öppna'),
                ),
                TextButton(
                  // As after adding a contact with TalkBack on: it stays.
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Alice är tillagd.'),
                      duration: Duration(days: 1),
                    ),
                  ),
                  child: const Text('notis'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final content = find.text('innehållet');
final locked = find.text('SHA är låst');

Future<void> lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
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

Future<FakeLock> unlocked(WidgetTester tester) async {
  final lock = FakeLock();
  await pumpGate(tester, lock);
  lock.asked.single.complete(UnlockResult.unlocked);
  await tester.pumpAndSettle();
  return lock;
}

void main() {
  testWidgets('locked when it opens: nothing behind the lock is built until '
      'the phone says yes', (tester) async {
    final lock = FakeLock();
    await pumpGate(tester, lock);
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
    await pumpGate(tester, lock);
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
    final lock = await unlocked(tester);

    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 5) - const Duration(seconds: 1);
    await lifecycle(tester, toFront);
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));

    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 5);
    await lifecycle(tester, toFront);
    expect(content, findsNothing);
    expect(locked, findsOneWidget);
    expect(lock.asked, hasLength(2));
  });

  testWidgets('a page opened on top is hidden when the app locks again, and '
      'is closed (review of #47)', (tester) async {
    final lock = await unlocked(tester);
    await tester.tap(find.text('öppna'));
    await tester.pumpAndSettle();
    expect(find.text('en chatt'), findsOneWidget);

    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 6);
    await lifecycle(tester, toFront);
    expect(find.text('en chatt'), findsNothing);
    expect(locked, findsOneWidget);

    lock.asked.last.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    expect(find.text('en chatt'), findsNothing);
  });

  testWidgets('a notice shown when the app locks is not on the lock screen '
      '(second review of #47)', (tester) async {
    final lock = await unlocked(tester);
    await tester.tap(find.text('notis'));
    await tester.pumpAndSettle();
    expect(find.text('Alice är tillagd.'), findsOneWidget);

    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 6);
    await lifecycle(tester, toFront);
    expect(locked, findsOneWidget);
    expect(find.text('Alice är tillagd.'), findsNothing);
  });

  testWidgets('back from the background, the first frame is covered until '
      'the time is checked; a short trip keeps what was open (second review '
      'of #47)', (tester) async {
    final lock = await unlocked(tester);
    await tester.tap(find.text('öppna'));
    await tester.pumpAndSettle();

    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 1);
    // The channel's answer about the time is still on its way.
    final hold = lock.holdElapsed = Completer<void>();
    for (final s in toFront) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(find.text('en chatt'), findsNothing);
    expect(locked, findsNothing);

    hold.complete();
    lock.holdElapsed = null;
    await tester.pumpAndSettle();
    expect(find.text('en chatt'), findsOneWidget);
    expect(lock.asked, hasLength(1));
  });

  testWidgets('if the phone\'s time cannot be read when the app goes to the '
      'background, it locks on return', (tester) async {
    final lock = await unlocked(tester);
    lock.failElapsed = StateError('x');
    await lifecycle(tester, toBackground);
    lock.failElapsed = null;
    await lifecycle(tester, toFront);
    expect(locked, findsOneWidget);
  });

  testWidgets('back in the background while the time is checked: nothing '
      'opens and nothing is asked until the app is in front again', (
    tester,
  ) async {
    final lock = await unlocked(tester);
    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 6);
    final hold = lock.holdElapsed = Completer<void>();
    for (final s in toFront) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    await lifecycle(tester, toBackground);
    hold.complete();
    lock.holdElapsed = null;
    await tester.pumpAndSettle();
    expect(lock.asked, hasLength(1), reason: 'no prompt in the background');
    expect(content, findsNothing);

    await lifecycle(tester, toFront);
    expect(locked, findsOneWidget);
    expect(lock.asked, hasLength(2));
  });

  testWidgets('the time is the phone\'s own since it started, so setting the '
      'clock back does not open the app (review of #47)', (tester) async {
    final lock = await unlocked(tester);
    await lifecycle(tester, toBackground);
    // The wall clock is not read at all: only the phone's own time moves.
    lock.now += const Duration(minutes: 30);
    await lifecycle(tester, toFront);
    expect(locked, findsOneWidget);
  });

  testWidgets('if the phone\'s time cannot be read, the app locks again', (
    tester,
  ) async {
    final lock = await unlocked(tester);
    await lifecycle(tester, toBackground);
    lock.failElapsed = StateError('x');
    await lifecycle(tester, toFront);
    expect(locked, findsOneWidget);
  });

  testWidgets('each trip to the background is counted on its own', (
    tester,
  ) async {
    final lock = await unlocked(tester);
    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 1);
    await lifecycle(tester, toFront);
    lock.now += const Duration(minutes: 10); // in use
    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 1);
    await lifecycle(tester, toFront);
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));
  });

  testWidgets('the phone\'s own prompt does not lock the app again', (
    tester,
  ) async {
    final lock = FakeLock();
    await pumpGate(tester, lock);
    // On Android 7–10 the PIN screen is an activity of its own: the app goes
    // to the background and back while it is shown.
    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 6);
    await lifecycle(tester, toFront);
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));
  });

  testWidgets('a slow PIN screen does not lock the app again when it answers '
      'before the app is back in front', (tester) async {
    final lock = FakeLock();
    await pumpGate(tester, lock);
    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 6);
    // Android delivers the PIN screen's answer before the app is resumed.
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    await lifecycle(tester, toFront);
    expect(content, findsOneWidget);
    expect(lock.asked, hasLength(1));
  });

  testWidgets('without a screen lock on the phone the app is not locked', (
    tester,
  ) async {
    final lock = FakeLock(secure: false);
    await pumpGate(tester, lock);
    expect(content, findsOneWidget);
    expect(lock.asked, isEmpty);
  });

  testWidgets('the phone says it has no lock when asked: the app opens', (
    tester,
  ) async {
    final lock = FakeLock();
    await pumpGate(tester, lock);
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
    expect(locked, findsNothing, reason: 'the first screen has nothing yet');
    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();
    expect(locked, findsOneWidget);
    expect(find.text('Chattar'), findsNothing);
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    expect(find.text('Chattar'), findsWidgets);
  });

  testWidgets('in the app, a screen opened on top of the home screen is '
      'behind the lock too (review of #47)', (tester) async {
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
    lock.asked.single.complete(UnlockResult.unlocked);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Min QR').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Skanna en kontakts kod'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Skanna en kontakts kod'));
    await tester.pumpAndSettle();
    expect(find.text('Skanna kontakt'), findsOneWidget);

    await lifecycle(tester, toBackground);
    lock.now += const Duration(minutes: 6);
    await lifecycle(tester, toFront);
    expect(find.text('Skanna kontakt'), findsNothing);
    expect(locked, findsOneWidget);
  });

  testWidgets('an error from the phone keeps it locked', (tester) async {
    final lock = FakeLock()
      ..failCanLock = StateError('x')
      ..failUnlock = StateError('y');
    await pumpGate(tester, lock);
    expect(content, findsNothing);
    expect(locked, findsOneWidget);
    expect(find.text('Lås upp'), findsOneWidget);
  });

  group('the channel to Android', () {
    const channel = MethodChannel('se.sha.sha/app_lock');
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    void answer(Object? Function(MethodCall call) reply) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => reply(call),
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    }

    test('only "unlocked" unlocks; anything else is cancelled', () async {
      const platform = MethodChannelAppLock();
      for (final (reply, want) in [
        ('unlocked', UnlockResult.unlocked),
        ('unavailable', UnlockResult.unavailable),
        ('cancelled', UnlockResult.cancelled),
        ('something else', UnlockResult.cancelled),
        (null, UnlockResult.cancelled),
      ]) {
        answer((_) => reply);
        expect(
          await platform.unlock(title: 't', text: 'x'),
          want,
          reason: '$reply',
        );
      }
    });

    test('no answer to canLock is "no lock", and elapsed is in ms', () async {
      const platform = MethodChannelAppLock();
      answer((call) => call.method == 'elapsed' ? 90000 : null);
      expect(await platform.canLock(), isFalse);
      expect(await platform.elapsed(), const Duration(seconds: 90));
    });
  });
}
