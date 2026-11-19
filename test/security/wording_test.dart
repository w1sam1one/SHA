import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The wording rules in 0002, "Formuleringar i appen": what the app says
/// about the server and anonymity. String literals that follow each other,
/// as Dart joins them, are read as one text, so a phrase split over two lines
/// is still found. Single, double and triple quotes, raw or not, are read.
/// Block comments, whole-line comments and lib/crypto (never shown) are
/// skipped. Not handled: a comment after code on the same line, and quotes
/// inside `${...}`, which split a text in two (second review of #48).
const banned = [
  'anonym', // also "anonymt", "helt anonym"
  'spårlös',
  'inga loggar',
  'inte se din ip', // "Servern kan inte se din IP-adress"
  'ser inte din ip', // and the same said another way (review of #48)
  'ingen kan se att du använder sha',
];

/// One Dart string literal.
final String _literal = [
  "r?'''[\\s\\S]*?'''",
  'r?"""[\\s\\S]*?"""',
  r"r?'(?:[^'\\\n]|\\.)*'",
  r'r?"(?:[^"\\\n]|\\.)*"',
].join('|');

String _inside(String literal) {
  final s = literal.startsWith('r') ? literal.substring(1) : literal;
  final quote = s.startsWith("'''") || s.startsWith('"""') ? 3 : 1;
  return s.substring(quote, s.length - quote);
}

/// The texts of [source]: adjacent string literals joined, one per string.
List<String> texts(String source) {
  final code = [
    for (final line
        in source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').split('\n'))
      if (!line.trimLeft().startsWith('//')) line,
  ].join('\n');
  final run = RegExp('(?:$_literal)(?:\\s*(?:$_literal))*');
  final piece = RegExp(_literal);
  return [
    for (final m in run.allMatches(code))
      piece.allMatches(m.group(0)!).map((p) => _inside(p.group(0)!)).join(),
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
    // Other quotes, and the same promise said another way (review of #48).
    expect(offenders({'e.dart': 'const x = "Helt anonymt.";'}), hasLength(1));
    expect(
      offenders({'f.dart': "const x = '''\nHelt\nanonymt.\n''';"}),
      hasLength(1),
    );
    expect(
      offenders({'g.dart': "const x = r'Servern ser inte din IP-adress.';"}),
      hasLength(1),
    );
    expect(
      offenders({'h.dart': "const x = 'Ett ' \"anonymt\" ' namn';"}),
      hasLength(1),
    );
    expect(offenders({'c.dart': "// 'anonym' in a comment"}), isEmpty);
    // An apostrophe in a block comment does not hide the text after it.
    expect(
      offenders({'i.dart': "/* don't */ const a = 'anonymt';"}),
      hasLength(1),
    );
    expect(
      offenders({'d.dart': "const v = 'Vi rekommenderar VPN.';"}),
      isEmpty,
    );
  });
}
