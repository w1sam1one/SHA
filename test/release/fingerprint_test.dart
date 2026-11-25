// F13 in docs/ROADMAP.md (0014 (2b)): the signing certificate's SHA-256
// fingerprint stands, the same, in README.md, SECURITY.md and the website's
// text (docs/hemsida.md), and each links to the releases for the APK's own
// SHA-256. Until the owner has made the key (G9), all three say so instead.
//
// It stands in two forms: keytool's (upper case, with colons) and the one
// `apksigner verify --print-certs` prints (lower case, no colons), so that
// a reader can compare with either tool (review of #55).
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

/// The same value as apksigner prints it.
final apksignerLine = RegExp(
  r'^Samma värde som apksigner visar det: (.+)$',
  multiLine: true,
);
final apksignerForm = RegExp(r'^`[0-9a-f]{64}`$');

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
    final other = apksignerLine.allMatches(text).toList();
    if (other.length != 1) {
      found.add('$path: ${other.length} apksigner lines, not 1');
    } else {
      final lower = other.single.group(1)!.trim();
      final expected = value == notYet
          ? notYet
          : value.replaceAll(':', '').toLowerCase();
      if (lower != expected) {
        found.add('$path: the apksigner form $lower is not $expected');
      } else if (lower != notYet && !apksignerForm.hasMatch(lower)) {
        found.add('$path: not an apksigner digest: $lower');
      }
    }
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
    String lower(String keytool) => keytool.replaceAll(':', '').toLowerCase();
    Map<String, String> filled(
      String value, {
      String? onlyIn,
      String? apksigner,
    }) => {
      for (final MapEntry(key: path, value: text) in sources.entries)
        path: onlyIn == null || onlyIn == path
            ? text
                  .replaceFirst(
                    'Signeringscertifikatets SHA-256: $notYet',
                    'Signeringscertifikatets SHA-256: $value',
                  )
                  .replaceFirst(
                    'Samma värde som apksigner visar det: $notYet',
                    'Samma värde som apksigner visar det: '
                        '${apksigner ?? lower(value)}',
                  )
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
    // The apksigner form does not match keytool's.
    expect(
      problems(filled(real, apksigner: lower(real).replaceFirst('a', 'b'))),
      isNotEmpty,
    );
    // The apksigner form left out.
    expect(
      problems({
        ...sources,
        'README.md': sources['README.md']!.replaceFirst(apksignerLine, ''),
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
