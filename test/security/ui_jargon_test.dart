import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// User-visible text stays plain: algorithm names appear only in
/// lib/ui/technical_info_sheet.dart. Skips lib/crypto (its messages are never
/// shown; see lib/core/errors.dart), comments and kDebugMode-only code (the
/// lines indented under a line that mentions kDebugMode).
void main() {
  test('no crypto jargon in user-visible strings', () {
    final jargon = RegExp(r'SHA-256|\bAES\b|StrongBox|\bTEE\b');
    final hash = RegExp('hash', caseSensitive: false);
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.startsWith('lib/crypto/') ||
          f.path == 'lib/ui/technical_info_sheet.dart') {
        continue;
      }
      int? debugIndent;
      for (final (i, raw) in f.readAsLinesSync().indexed) {
        final line = raw.trimLeft();
        final indent = raw.length - line.length;
        if (line.startsWith('//') || line.startsWith('import ')) continue;
        if (debugIndent != null && (line.isEmpty || indent > debugIndent)) {
          continue;
        }
        debugIndent = line.contains('kDebugMode') ? indent : null;
        if (debugIndent != null) continue;
        for (final m in literal.allMatches(line)) {
          final text = m.group(1)!.replaceAll(interpolation, '');
          if (jargon.hasMatch(text) || hash.hasMatch(text)) {
            offenders.add('${f.path}:${i + 1}: $text');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
