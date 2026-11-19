import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../crypto/crypto.dart';
import '../features/home/home_shell.dart';
import '../features/lock/app_lock.dart';
import '../features/onboarding/identity_controller.dart';
import '../features/onboarding/identity_recovery_screen.dart';
import '../features/onboarding/identity_screen.dart';
import 'theme.dart';

class ShaApp extends StatelessWidget {
  const ShaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SHA',
      debugShowCheckedModeBanner: false,
      theme: buildShaTheme(),
      // The lock is around the whole navigator, so that a chat or a dialog
      // opened on top is behind it too (review of #47).
      builder: (context, child) => _Locked(child: child!),
      home: const _Root(),
    );
  }
}

/// Loads (or creates) the identity, then shows onboarding or the main app.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(identityProvider)) {
      AsyncData(:final value) =>
        value.firstLaunch ? const IdentityScreen() : const HomeShell(),
      // Keyed by the error: the screen keeps its "busy" state while the
      // provider reloads (same error), and starts fresh if it fails again.
      AsyncError(:final error) when _needsRecovery(error) =>
        IdentityRecoveryScreen(key: ObjectKey(error)),
      AsyncError(:final error) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_bad_outlined, size: 48),
                const SizedBox(height: 16),
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(identityProvider),
                  child: const Text('Försök igen'),
                ),
              ],
            ),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }

  /// The key protecting the identity is gone or unreadable: retrying alone
  /// can never succeed, so offer to start over.
  static bool _needsRecovery(Object error) =>
      error is CryptoException &&
      (error.kind == CryptoErrorKind.keyInvalidated ||
          error.kind == CryptoErrorKind.corrupt);
}

/// The app lock (F4, 0011 (B)) once there is an identity: the first screen
/// has nothing to hide yet. Once on, it stays on, also while the identity is
/// read again.
class _Locked extends ConsumerWidget {
  const _Locked({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider).value;
    if (identity == null || identity.firstLaunch) return child;
    return AppLockGate(child: child);
  }
}
