import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/app.dart';
import 'package:sha/core/providers.dart';

import '../support/in_memory_vault.dart';

void main() {
  testWidgets('first launch creates an identity and shows it', (tester) async {
    final storage = InMemoryVault();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyVaultProvider.overrideWithValue(storage)],
        child: const ShaApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Din identitet är skapad'), findsOneWidget);
    expect(storage.values, hasLength(2));

    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();
    expect(find.text('Inga kontakter än'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
