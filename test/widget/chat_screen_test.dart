import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/theme.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/chat_screen.dart';
import 'package:sha/features/contacts/contacts_store.dart';

import '../support/in_memory_vault.dart';

const _preview =
    'Förhandsversion: meddelanden skickas inte till Jonas än och finns bara '
    'kvar tills du stänger appen.';

Future<void> _pumpChat(WidgetTester tester, {required bool transport}) async {
  final container = ProviderContainer(
    overrides: [
      keyVaultProvider.overrideWithValue(InMemoryVault()),
      transportAvailableProvider.overrideWithValue(transport),
    ],
  );
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
}

void main() {
  testWidgets('without a transport the chat says nothing is sent', (
    tester,
  ) async {
    await _pumpChat(tester, transport: false);
    expect(find.text(_preview), findsOneWidget);
    expect(
      find.text('Meddelanden är krypterade. Bara du och Jonas kan läsa dem.'),
      findsOneWidget,
    );
    expect(find.text('Skriv ett meddelande'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('with a transport the preview notice is gone', (tester) async {
    await _pumpChat(tester, transport: true);
    expect(find.text(_preview), findsNothing);
  });

  testWidgets('the header states verified in person with the date', (
    tester,
  ) async {
    await _pumpChat(tester, transport: false);
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
    await _pumpChat(tester, transport: false);
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
