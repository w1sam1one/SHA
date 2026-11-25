// F13 in docs/ROADMAP.md (0014 (2b)): the signing certificate's SHA-256
// fingerprint stands, the same, in README.md, SECURITY.md and the website's
// text (docs/hemsida.md), and each links to the releases for the APK's own
// SHA-256. Until the owner has made the key (G9), all three say so instead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const files = ['README.md', 'SECURITY.md', 'docs/hemsida.md'];
const releases = 'https://github.com/w1sam1one/SHA/releases';
const notYet = 'inte skapat än (G9)';

/// "Signeringscertifikatets SHA-256: `AA:BB:…`" (32 bytes) or the text for
/// a key not yet made.
final line = RegExp(
  r'^Signeringscertifikatets SHA-256: (.+)$',
  multiLine: true,
);
final fingerprint = RegExp(r'^`([0-9A-F]{2}:){31}[0-9A-F]{2}`$');

/// The problems in [sources] (path: text).
List<String> problems(Map<String, String> sources) {
  final found = <String>[];
  final values = <String, String>{};
  for (final MapEntry(key: path, value: text) in sources.entries) {
    final matches = line.allMatches(text).toList();
    if (matches.length != 1) {
      found.add('$path: ${matches.length} fingerprint lines, not 1');
      continue;
    }
    final value = matches.single.group(1)!.trim();
    if (value != notYet && !fingerprint.hasMatch(value)) {
      found.add('$path: not a SHA-256 fingerprint: $value');
    }
    values[path] = value;
    if (!text.contains(releases)) found.add('$path: no link to $releases');
  }
  if (values.values.toSet().length > 1) {
    found.add('the fingerprints differ: $values');
  }
  return found;
}

void main() {
  final sources = {for (final f in files) f: File(f).readAsStringSync()};

  test('the certificate fingerprint is the same in every place', () {
    expect(problems(sources), isEmpty);
  });

  test('the check finds a fingerprint that differs, is wrong or is gone', () {
    const real =
        '`AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
        'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89`';
    Map<String, String> filled(String value, {String? onlyIn}) => {
      for (final MapEntry(key: path, value: text) in sources.entries)
        path: onlyIn == null || onlyIn == path
            ? text.replaceFirst(notYet, value)
            : text,
    };
    expect(problems(filled(real)), isEmpty);
    // Filled in only in one place.
    expect(problems(filled(real, onlyIn: 'README.md')), isNotEmpty);
    // Not a fingerprint: too short, or lower case.
    expect(problems(filled('`AB:CD`')), isNotEmpty);
    expect(problems(filled(real.toLowerCase())), isNotEmpty);
    // Gone from one file.
    expect(
      problems({
        ...sources,
        'SECURITY.md': sources['SECURITY.md']!.replaceFirst(line, ''),
      }),
      isNotEmpty,
    );
    // Twice in one file, so that one of them can be left stale.
    expect(
      problems({
        ...sources,
        'README.md':
            '${sources['README.md']}\nSigneringscertifikatets SHA-256: $notYet\n',
      }),
      isNotEmpty,
    );
    // No link to the releases.
    expect(
      problems({
        ...sources,
        'docs/hemsida.md': sources['docs/hemsida.md']!.replaceAll(
          releases,
          'https://example.com',
        ),
      }),
      isNotEmpty,
    );
  });
}
