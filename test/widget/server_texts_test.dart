// F5 and 0002/0008: the app says plainly what the server sees, and
// recommends VPN with the sentence the owner approved (0008, 2026-11-18).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/features/settings/settings_screen.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_settings.dart';
import 'package:sha/ui/technical_info_sheet.dart';

import '../support/in_memory_vault.dart';

const vpn =
    'Vi rekommenderar VPN om du inte vill att servern ska se din IP-adress.';

final class _Settings extends TransportSettingsStore {
  @override
  Future<TransportSettings> build() async => const TransportSettings();
}

Future<void> pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyVaultProvider.overrideWithValue(InMemoryVault()),
        transportSettingsProvider.overrideWith(_Settings.new),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Inställningar says what the server sees, and recommends VPN', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    expect(
      find.text(
        'Servern kan inte läsa dina meddelanden. Den ser din IP-adress, när '
        'du hämtar och hur stora paketen är. SHA:s serverprogram sparar inte '
        'din IP-adress på disk eller i loggar. $vpn',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Teknisk information recommends VPN too', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTechnicalInfoSheet(context),
          child: const Text('öppna'),
        ),
      ),
    );
    await tester.tap(find.text('öppna'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(vpn),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(vpn), findsOneWidget);
  });
}
