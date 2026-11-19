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
/// the phone's PIN. On Android 10 and later `BiometricPrompt`, before that
/// `KeyguardManager`. No new dependency, and no key is derived from anything.
abstract interface class AppLockPlatform {
  /// Whether the phone has a screen lock to unlock with.
  Future<bool> canLock();

  Future<UnlockResult> unlock({required String title, required String text});
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
}

final appLockPlatformProvider = Provider<AppLockPlatform>(
  (ref) => const MethodChannelAppLock(),
);

/// The clock for the time in the background, swapped in tests.
final appLockClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

enum AppLockState {
  /// Asking the phone whether it has a lock.
  checking,
  locked,

  /// The phone's prompt is shown.
  unlocking,
  open,
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

  DateTime? _hiddenAt;

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
  /// phone's own PIN screen (Android 7–9) also sends the app there.
  void hidden() {
    if (state == AppLockState.open) _hiddenAt ??= _now();
  }

  /// The app is in front again.
  void resumed() {
    final since = _hiddenAt;
    _hiddenAt = null;
    if (state != AppLockState.open || since == null) return;
    if (_now().difference(since) >= backgroundLimit) {
      state = AppLockState.locked;
      unawaited(unlock());
    }
  }

  DateTime _now() => ref.read(appLockClockProvider)();
}

final appLockProvider = NotifierProvider<AppLock, AppLockState>(AppLock.new);

/// Shows [child] only while the app is unlocked ([AppLock]). While it is
/// locked, nothing of [child] is built.
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
        lock.resumed();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    if (state == AppLockState.open) return widget.child;
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
                  'Lås upp med telefonens eget lås: fingeravtryck, ansikte '
                  'eller PIN-kod.',
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
