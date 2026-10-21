import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for the security rules in lib/crypto/README.md.
void main() {
  List<File> dartFiles(String dir) => [
    for (final f in Directory(dir).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('lib/ contains no logging calls', () {
    final banned = RegExp(
      r'\b(print|debugPrint|debugPrintStack)\s*\(|'
      r"\blog\s*\(|dart:developer|package:logging|stdout\.|stderr\.",
    );
    final offenders = [
      for (final file in dartFiles('lib'))
        for (final (i, line) in file.readAsLinesSync().indexed)
          if (banned.hasMatch(line)) '${file.path}:${i + 1}',
    ];
    expect(offenders, isEmpty);
  });

  test('crypto module does not depend on UI or app code', () {
    // Only the platform-channel binding (flutter/services.dart) is allowed.
    final banned = RegExp(
      r"^import 'package:(flutter/(?!services\.dart)|flutter_riverpod|sha/)|"
      r"^import '\.\./\.\./",
    );
    final offenders = [
      for (final file in dartFiles('lib/crypto'))
        for (final line in file.readAsLinesSync())
          if (banned.hasMatch(line)) '${file.path}: $line',
    ];
    expect(offenders, isEmpty);
  });

  test('native Keystore code does not log', () {
    final banned = RegExp(r'\bLog\.|println\(|printStackTrace\(');
    final offenders = [
      for (final f in Directory(
        'android/app/src/main/kotlin',
      ).listSync(recursive: true))
        if (f is File && f.path.endsWith('.kt'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (banned.hasMatch(line)) '${f.path}:${i + 1}',
    ];
    expect(offenders, isEmpty);
  });
}
