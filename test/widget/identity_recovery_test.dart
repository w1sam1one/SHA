import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/app.dart';
import 'package:sha/core/errors.dart';
import 'package:sha/core/providers.dart';
import 'package:sha/crypto/crypto.dart';

import '../support/in_memory_vault.dart';

/// A vault whose key is gone: every read fails until [reset] is called.
class _BrokenVault extends InMemoryVault {
  _BrokenVault(
    this.kind, {
    this.resetFails = false,
    this.stillBrokenAfterReset = false,
  });

  final CryptoErrorKind kind;
  final bool resetFails;
  final bool stillBrokenAfterReset;
  bool wasReset = false;

  @override
  Future<Uint8List?> read(String name) async {
    if (!wasReset || stillBrokenAfterReset) {
      throw CryptoException('Vault key lost', kind);
    }
    return super.read(name);
  }

  @override
  Future<void> reset() async {
    if (resetFails) {
      throw const CryptoException('No', CryptoErrorKind.unavailable);
    }
    wasReset = true;
    await super.reset();
  }
}

const _title = 'Din identitet kan inte öppnas';
const _startOver = 'Skapa ny identitet…';
const _confirm = 'Radera och skapa ny';
const _understood = 'Jag förstår att mina kontakter måste träffa mig igen';

Future<void> _settleCrypto(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _launch(WidgetTester tester, KeyVault vault) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [keyVaultProvider.overrideWithValue(vault)],
      child: const ShaApp(),
    ),
  );
  await _settleCrypto(tester);
  await tester.pumpAndSettle();
}

FilledButton _confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, _confirm));

void main() {
  for (final kind in [
    CryptoErrorKind.keyInvalidated,
    CryptoErrorKind.corrupt,
  ]) {
    testWidgets('${kind.name}: recovery screen offers retry and start over', (
      tester,
    ) async {
      await _launch(tester, _BrokenVault(kind));
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Försök igen'), findsOneWidget);
      expect(find.text(_startOver), findsOneWidget);
    });
  }

  testWidgets('confirm stays disabled until the box is ticked', (tester) async {
    final vault = _BrokenVault(CryptoErrorKind.keyInvalidated);
    await _launch(tester, vault);

    await tester.tap(find.text(_startOver));
    await tester.pumpAndSettle();
    expect(find.text('Radera och skapa ny identitet?'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.tap(find.text(_understood));
    await tester.pumpAndSettle();
    expect(_confirmButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Avbryt'));
    await tester.pumpAndSettle();
    expect(vault.wasReset, isFalse);
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('confirming resets and runs first-launch onboarding', (
    tester,
  ) async {
    final vault = _BrokenVault(CryptoErrorKind.keyInvalidated);
    await _launch(tester, vault);

    await tester.tap(find.text(_startOver));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_understood));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_confirm));
    await tester.pump();
    await _settleCrypto(tester);
    await tester.pumpAndSettle();

    expect(vault.wasReset, isTrue);
    expect(find.text('Din identitet är skapad'), findsOneWidget);
    expect(vault.values, hasLength(2));
  });

  testWidgets('a failed reset keeps the screen and explains why', (
    tester,
  ) async {
    await _launch(
      tester,
      _BrokenVault(CryptoErrorKind.keyInvalidated, resetFails: true),
    );
    await tester.tap(find.text(_startOver));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_understood));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_confirm));
    await tester.pump();
    await _settleCrypto(tester);
    await tester.pumpAndSettle();

    expect(find.text(_title), findsOneWidget);
    expect(
      find.text(
        describeError(const CryptoException('No', CryptoErrorKind.unavailable)),
      ),
      findsOneWidget,
    );
    expect(find.text(_startOver), findsOneWidget);
  });

  testWidgets('if it still fails after the reset, the buttons work again', (
    tester,
  ) async {
    await _launch(
      tester,
      _BrokenVault(CryptoErrorKind.keyInvalidated, stillBrokenAfterReset: true),
    );
    await tester.tap(find.text(_startOver));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_understood));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_confirm));
    await tester.pump();
    await _settleCrypto(tester);
    await tester.pumpAndSettle();

    expect(find.text(_title), findsOneWidget);
    final startOver = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, _startOver),
    );
    expect(startOver.onPressed, isNotNull);
  });

  testWidgets('a locked phone shows retry only, never the reset', (
    tester,
  ) async {
    await _launch(tester, _BrokenVault(CryptoErrorKind.deviceLocked));
    expect(find.text('Försök igen'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(find.text(_startOver), findsNothing);
  });

  testWidgets('no overflow at text scale 2.0 on a phone', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _launch(tester, _BrokenVault(CryptoErrorKind.keyInvalidated));
    expect(tester.takeException(), isNull);
    expect(find.text(_title), findsOneWidget);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text(_title))).scale(10),
      20,
    );

    await tester.ensureVisible(find.text(_startOver));
    await tester.tap(find.text(_startOver));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(_understood));
    await tester.tap(find.text(_understood));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
