import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/theme.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/chat_screen.dart';
import 'package:sha/features/chat/notice_texts.dart';
import 'package:sha/features/contacts/contacts_store.dart';
import 'package:sha/features/transport/transport.dart';
import 'package:sha/features/transport/transport_settings.dart';

import '../support/in_memory_vault.dart';

const _noServer =
    'Ingen server är inställd än. Meddelanden sparas och skickas när du har '
    'skrivit in serverns adress under Inställningar.';

/// Settings fixed for the test, so no vault or Olm is needed.
final class _FixedSettings extends TransportSettingsStore {
  _FixedSettings(this._settings);

  final TransportSettings _settings;

  @override
  Future<TransportSettings> build() async => _settings;
}

Future<ProviderContainer> _pumpChat(
  WidgetTester tester, {
  ServerStatus status = ServerStatus.ok,
  Uri? server,
}) async {
  final container = ProviderContainer(
    overrides: [
      keyVaultProvider.overrideWithValue(InMemoryVault()),
      transportSettingsProvider.overrideWith(
        () => _FixedSettings(TransportSettings(server: server)),
      ),
    ],
  );
  container.read(serverStatusProvider.notifier).set(status);
  addTearDown(container.dispose);
  final peer = PublicIdentity(List.generate(32, (i) => i + 1));
  container
      .read(contactsProvider.notifier)
      .add(
        Contact(
          identity: peer,
          name: 'Jonas',
          verifiedAt: DateTime(2026, 10, 12),
        ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildShaTheme(),
        home: ChatScreen(contactId: peer.hash.hex),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('without a server address the chat says so', (tester) async {
    await _pumpChat(tester);
    expect(find.text(_noServer), findsOneWidget);
    expect(
      find.text('Meddelanden är krypterade. Bara du och Jonas kan läsa dem.'),
      findsOneWidget,
    );
    expect(find.text('Skriv ett meddelande'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('the server texts of 0004 §10, and none when all is well', (
    tester,
  ) async {
    final container = await _pumpChat(
      tester,
      server: Uri.parse('https://server.example.se'),
    );
    expect(find.text(_noServer), findsNothing, reason: 'review S1');
    expect(find.text(NoticeTexts.serverBusy), findsNothing);

    container.read(serverStatusProvider.notifier).set(ServerStatus.busy);
    await tester.pump();
    expect(
      find.text('Servern är upptagen. Appen försöker igen om en stund.'),
      findsOneWidget,
    );

    // "Full" is shown only in a chat with a message waiting: none here.
    container.read(serverStatusProvider.notifier).set(ServerStatus.full);
    await tester.pump();
    expect(find.text(NoticeTexts.serverFull), findsNothing);

    container.read(serverStatusProvider.notifier).set(ServerStatus.unavailable);
    await tester.pump();
    expect(find.text(NoticeTexts.serverFull), findsNothing);
  });

  testWidgets('the header states verified in person with the date', (
    tester,
  ) async {
    await _pumpChat(tester);
    expect(find.text('Verifierad i person · Möttes 12 okt'), findsOneWidget);
    // The AppBar title merges its children into one spoken header, so the
    // badge and the tag are read as parts of the same label.
    final handle = tester.ensureSemantics();
    final header = _label(tester.getSemantics(find.byType(AppBar)));
    handle.dispose();
    expect(header, contains('Verifierad i person, möttes 12 okt'));
    expect(
      RegExp('Verifierad i person').allMatches(header),
      hasLength(2),
      reason: 'badge + tag: $header',
    );
  });

  testWidgets('"Teknisk information" lists what does not exist yet', (
    tester,
  ) async {
    await _pumpChat(tester);
    await tester.tap(find.text('Teknisk information'));
    await tester.pumpAndSettle();
    expect(find.text('Finns inte än'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Inget app-lås med biometri eller PIN.'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Inget app-lås med biometri eller PIN.'), findsOneWidget);
  });
}

/// All labels in a semantics subtree, depth first.
String _label(SemanticsNode node) {
  final parts = <String>[node.label];
  node.visitChildren((child) {
    parts.add(_label(child));
    return true;
  });
  return parts.where((p) => p.isNotEmpty).join('\n');
}
