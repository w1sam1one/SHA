import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrail: app code must not write to the console or system log, where
/// keys, nonces or plaintext could leak.
void main() {
  test('lib/ contains no logging calls', () {
    final banned = RegExp(
      r'\b(print|debugPrint|debugPrintStack)\s*\(|'
      r"\blog\s*\(|dart:developer|package:logging|stdout\.|stderr\.",
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (banned.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('crypto module does not depend on UI or app code', () {
    final offenders = <String>[];
    for (final file in Directory('lib/crypto').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        if (RegExp(r"^import 'package:(flutter/|flutter_riverpod|sha/)")
                .hasMatch(line) ||
            RegExp(r"^import '\.\./\.\./").hasMatch(line)) {
          offenders.add('${file.path}: $line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
