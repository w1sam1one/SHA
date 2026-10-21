import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for lib/ui/trust_display.dart being the single place that
/// decides how "verified in person" looks. Every contact is verified in
/// person by definition, so no screen may pass a "verified" flag around.
void main() {
  const trustFile = 'lib/ui/trust_display.dart';

  List<String> offenders(RegExp pattern, {Set<String> allowed = const {}}) => [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart') && !allowed.contains(f.path))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (pattern.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
  ];

  test('no verified: true/false flags in lib/', () {
    expect(offenders(RegExp(r'verified:\s*(true|false)')), isEmpty);
  });

  test("'Verifierad' appears only in $trustFile", () {
    expect(offenders(RegExp('Verifierad'), allowed: {trustFile}), isEmpty);
  });

  test('the verified colour and icon appear only in $trustFile', () {
    expect(
      offenders(
        RegExp(r'ShaColors\.(success|onSuccess)\b|Icons\.verified_rounded'),
        allowed: {trustFile},
      ),
      isEmpty,
    );
  });
}
