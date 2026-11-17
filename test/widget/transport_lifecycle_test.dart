// 0002 and 0004 §9: no fetching when the app is not in front or the phone
// is locked.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_lifecycle.dart';

import '../support/in_memory_vault.dart';

void main() {
  testWidgets('runs only while the app is in front', (tester) async {
    final container = ProviderContainer(
      overrides: [keyVaultProvider.overrideWithValue(InMemoryVault())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TransportLifecycle(child: SizedBox()),
      ),
    );
    await tester.pump();
    final transport = container.read(transportProvider);
    expect(transport.running, isTrue);

    // Locking the phone or leaving the app ends in "paused".
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(transport.running, isFalse, reason: '$state');
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(transport.running, isTrue);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 5));
  });
}
