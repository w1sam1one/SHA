import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/identity_controller.dart';
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
}
