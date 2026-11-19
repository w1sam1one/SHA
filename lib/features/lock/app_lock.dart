import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';

/// What the phone said when asked to unlock.
enum UnlockResult {
  unlocked,
  cancelled,

  /// The phone has no screen lock: there is nothing to unlock with.
  unavailable,
}

/// The phone's own lock (F4, step 1 of (B) in 0011): fingerprint, face or
/// the phone's PIN, pattern or password. On Android 11 and later
/// `BiometricPrompt`, before that `KeyguardManager` (Android 10's
/// `BiometricPrompt` can fail to show the PIN: review of #47). No new
/// dependency, and no key is derived from anything.
abstract interface class AppLockPlatform {
  /// Whether the phone has a screen lock to unlock with.
  Future<bool> canLock();

  Future<UnlockResult> unlock({required String title, required String text});

  /// The phone's time since it started, deep sleep included
  /// (`SystemClock.elapsedRealtime`). Unlike the wall clock, nobody can set
  /// it back.
  Future<Duration> elapsed();
}

/// [AppLockPlatform] on Android (`AppLockChannel.kt`).
final class MethodChannelAppLock implements AppLockPlatform {
  const MethodChannelAppLock();

  static const MethodChannel _channel = MethodChannel('se.sha.sha/app_lock');

  @override
  Future<bool> canLock() async =>
      await _channel.invokeMethod<bool>('canLock') ?? false;

  @override
  Future<UnlockResult> unlock({
    required String title,
    required String text,
  }) async {
    final answer = await _channel.invokeMethod<String>('unlock', {
      'title': title,
      'text': text,
    });
    return switch (answer) {
      'unlocked' => UnlockResult.unlocked,
      'unavailable' => UnlockResult.unavailable,
      _ => UnlockResult.cancelled,
    };
  }

  @override
  Future<Duration> elapsed() async {
    final ms = await _channel.invokeMethod<int>('elapsed');
    if (ms == null) throw StateError('No time from the phone');
    return Duration(milliseconds: ms);
  }
}

final appLockPlatformProvider = Provider<AppLockPlatform>(
  (ref) => const MethodChannelAppLock(),
);

enum AppLockState {
  /// Asking the phone whether it has a lock.
  checking,
  locked,

  /// The phone's prompt is shown.
  unlocking,
  open,

  /// Open, but in the background: the screen is covered until the time away
  /// is checked on return, so not even one frame of it shows if the app
  /// locks then (second review of #47).
  covered,
}

/// Locked when the app opens, and again after [backgroundLimit] in the
/// background (0011, the owner's decision). An error from the phone keeps
/// the app locked; only "no screen lock" opens it without a prompt, and then
/// the home screen already warns that the phone has none.
///
/// The lock only hides the screen. The vault's key does not require the
/// phone to be unlocked yet: that is step 2, after G6 (0011).
class AppLock extends Notifier<AppLockState> {
  static const Duration backgroundLimit = Duration(minutes: 5);

  static const String promptTitle = 'Lås upp SHA';
  static const String promptText = 'Använd telefonens skärmlås.';

  /// The phone's time when the app went to the background while open, or
  /// null if it could not be read.
  Future<Duration?>? _awayAt;

  /// False from the app's last trip to the background until it is in front
  /// again.
  bool _inFront = true;

  @override
  AppLockState build() {
    scheduleMicrotask(_check);
    return AppLockState.checking;
  }

  Future<void> _check() async {
    bool canLock;
    try {
      canLock = await ref.read(appLockPlatformProvider).canLock();
    } on Object {
      canLock = true; // unknown: stay locked
    }
    if (!ref.mounted) return;
    state = canLock ? AppLockState.locked : AppLockState.open;
    if (canLock) await unlock();
  }

  /// Shows the phone's prompt, unless it is already shown.
  Future<void> unlock() async {
    if (state != AppLockState.locked) return;
    state = AppLockState.unlocking;
    UnlockResult result;
    try {
      result = await ref
          .read(appLockPlatformProvider)
          .unlock(title: promptTitle, text: promptText);
    } on Object {
      result = UnlockResult.cancelled;
    }
    if (!ref.mounted) return;
    state = result == UnlockResult.cancelled
        ? AppLockState.locked
        : AppLockState.open;
  }

  /// The app went to the background. Only counted while it is open: the
  /// phone's own PIN screen (Android 7–10) also sends the app there.
  void hidden() {
    _inFront = false;
    if (state != AppLockState.open) return;
    state = AppLockState.covered;
    _awayAt = _elapsed();
  }

  /// The app is in front again. If the phone's time cannot be read, the app
  /// locks: it never opens on a time it does not know. If it goes to the
  /// background again before the time is known, nothing happens until it is
  /// back, and the time is still counted from the first trip.
  Future<void> resumed() async {
    _inFront = true;
    if (state != AppLockState.covered) return;
    final since = await _awayAt;
    final now = await _elapsed();
    if (!ref.mounted || state != AppLockState.covered || !_inFront) return;
    if (since == null || now == null || now - since >= backgroundLimit) {
      state = AppLockState.locked;
      await unlock();
    } else {
      state = AppLockState.open;
    }
  }

  Future<Duration?> _elapsed() async {
    try {
      return await ref.read(appLockPlatformProvider).elapsed();
    } on Object {
      return null;
    }
  }
}

final appLockProvider = NotifierProvider<AppLock, AppLockState>(AppLock.new);

/// Shows [child] only while the app is unlocked ([AppLock]). While it is
/// locked, nothing of [child] is built. In the app [child] is the whole
/// navigator (`MaterialApp.builder`), so a chat or a dialog opened on top is
/// behind the lock too, and is closed when the app locks (review of #47).
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        lock.hidden();
      case AppLifecycleState.resumed:
        unawaited(lock.resumed());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    if (state == AppLockState.open || state == AppLockState.covered) {
      final covered = state == AppLockState.covered;
      // The same tree in both states, so a short trip to the background keeps
      // what was open. The app's own messenger goes with the navigator: a
      // notice shown when the app locks is gone with it (second review of
      // #47).
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: covered,
            child: TickerMode(
              enabled: !covered,
              child: ScaffoldMessenger(child: widget.child),
            ),
          ),
          if (covered) const ColoredBox(color: ShaColors.background),
        ],
      );
    }
    return _LockScreen(
      showButton: state == AppLockState.locked,
      onUnlock: () => ref.read(appLockProvider.notifier).unlock(),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.showButton, required this.onUnlock});

  final bool showButton;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: ShaColors.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'SHA är låst',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lås upp med telefonens eget lås, till exempel '
                  'fingeravtryck eller PIN-kod.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ShaColors.textSecondary),
                ),
                const SizedBox(height: 24),
                if (showButton)
                  FilledButton(
                    onPressed: onUnlock,
                    child: const Text('Lås upp'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
