import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/theme.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/qr/add_contact_sheet.dart';

void main() {
  testWidgets('asks the other person to scan back', (tester) async {
    final peer = PublicIdentity(List.generate(32, (i) => 200 - i));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShaTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAddContactSheet(
                context,
                peer: peer,
                verificationCode: '12345678901234567890',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Be den andra också skanna din QR-kod, annars kan ni inte skriva '
        'till varandra.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Jonas');
    await tester.pump();
    expect(
      find.text(
        'Be Jonas också skanna din QR-kod, annars kan ni inte skriva till '
        'varandra.',
      ),
      findsOneWidget,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final enabled = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(enabled.borderSide.color, ShaColors.fieldBorder);
  });
}
