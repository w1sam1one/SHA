import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The wording rules in 0002, "Formuleringar i appen": what the app says
/// about the server and anonymity. String literals that follow each other,
/// as Dart joins them, are read as one text, so a phrase split over two lines
/// is still found. Comments and lib/crypto (never shown) are skipped.
const banned = [
  'anonym', // also "anonymt", "helt anonym"
  'spårlös',
  'inga loggar',
  'servern kan inte se din ip-adress',
  'ingen kan se att du använder sha',
];

/// The texts of [source]: adjacent string literals joined, one per string.
List<String> texts(String source) {
  final code = [
    for (final line in source.split('\n'))
      if (!line.trimLeft().startsWith('//')) line,
  ].join('\n');
  final run = RegExp(r"'(?:[^'\\\n]|\\.)*'(?:\s*'(?:[^'\\\n]|\\.)*')*");
  final piece = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
  return [
    for (final m in run.allMatches(code))
      piece.allMatches(m.group(0)!).map((p) => p.group(1)!).join(),
  ];
}

List<String> offenders(Map<String, String> files) => [
  for (final MapEntry(key: path, value: source) in files.entries)
    for (final t in texts(source))
      for (final b in banned)
        if (t.toLowerCase().contains(b)) '$path: $t',
];

void main() {
  test('no text in the app breaks the wording rules of 0002', () {
    final files = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.startsWith('lib/crypto/'))
          f.path: f.readAsStringSync(),
    };
    expect(files, isNotEmpty);
    expect(offenders(files), isEmpty);
  });

  test('the check finds a banned phrase, also split over two literals', () {
    expect(
      offenders({
        'a.dart': "final t = 'Servern kan inte '\n    'se din IP-adress.';",
      }),
      hasLength(1),
    );
    expect(offenders({'b.dart': "const x = 'Helt anonymt';"}), hasLength(1));
    expect(offenders({'c.dart': "// 'anonym' in a comment"}), isEmpty);
    expect(
      offenders({'d.dart': "const v = 'Vi rekommenderar VPN.';"}),
      isEmpty,
    );
  });
}
