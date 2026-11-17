// 0004 §1: every display of the QR code has a new one-time key. Needs the
// native library (tool/build_native_host.sh).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sha/app/app.dart';
import 'package:sha/core/providers.dart';

import '../support/in_memory_vault.dart';

void main() {
  testWidgets('no key before the tab is opened, and a new key each time', (
    tester,
  ) async {
    final storage = InMemoryVault();
    int shown() {
      final raw = storage.values['olm.state.v1'];
      if (raw == null) return 0;
      final state = jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
      return (state['shown']! as Map).length;
    }

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
    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();
    expect(shown(), 0, reason: 'the tab is not built before it is opened');

    Future<void> openQr() async {
      await tester.tap(find.text('Min QR').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await openQr();
    expect(shown(), 1);
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.tap(find.text('Kontakter'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    await openQr();
    expect(shown(), 2, reason: 'a new one-time key, saved before it is shown');
  });
}
