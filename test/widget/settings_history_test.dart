// F3, 0010 (B): the history choice under Inställningar, with the owner's
// four choices and 30 days by default.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/features/settings/settings_screen.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_settings.dart';

import '../support/in_memory_vault.dart';

/// Settings in memory, so no vault or Olm is needed. [saved] records each
/// save.
final class _RecordingSettings extends TransportSettingsStore {
  final List<TransportSettings> saved = [];

  @override
  Future<TransportSettings> build() async => const TransportSettings();

  @override
  Future<void> save(TransportSettings settings) async {
    saved.add(settings);
    state = AsyncData(settings);
  }
}

void main() {
  testWidgets('the four choices, 30 days chosen, and a new choice is saved', (
    tester,
  ) async {
    final store = _RecordingSettings();
    final container = ProviderContainer(
      overrides: [
        keyVaultProvider.overrideWithValue(InMemoryVault()),
        transportSettingsProvider.overrideWith(() => store),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1 år'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Spara meddelanden'), findsOneWidget);
    expect(
      find.text(
        'Meddelanden sparas krypterade på telefonen och tas bort ur appen '
        'efter den tid du väljer.',
      ),
      findsOneWidget,
    );
    for (final label in ['Spara inte', '7 dagar', '30 dagar', '1 år']) {
      expect(find.text(label), findsOneWidget);
    }
    final chosen = tester.widget<RadioGroup<HistoryLength>>(
      find.byType(RadioGroup<HistoryLength>),
    );
    expect(chosen.groupValue, HistoryLength.month);

    await tester.tap(find.text('Spara inte'));
    await tester.pumpAndSettle();
    expect(store.saved.single.history, HistoryLength.none);
  });
}
