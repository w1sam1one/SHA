// F11 in docs/ROADMAP.md: the store texts in docs/butikstexter.md keep to
// the wording rules of 0002 and to the lengths of the store listing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'wording_test.dart' show banned;

/// More of the same in Swedish, said other ways (review of #49).
const bannedSwedish = [
  'spåras', // "kan inte spåras"
  'ingen ser att',
  'ser aldrig din ip',
  'loggar ingenting',
];

/// The same rules in English (0002, "Formuleringar i appen").
const bannedEnglish = [
  'anonym', // "anonymous", "anonymity"
  'untraceable',
  'no logs',
  'not see your ip', // "cannot see your IP address", "does not see …"
  "n't see your ip", // "can't see your IP address"
  'nobody can see that you use',
  'no one can see',
  'trace', // "untraceable", "leaves no trace", "cannot be traced"
  'zero logs',
  'never log',
  'never sees your ip',
];

/// Name, short and full description, in Swedish and then in English.
const limits = [30, 80, 4000, 30, 80, 4000];

/// The texts in [markdown]: the content of each ```text block.
List<String> texts(String markdown) => [
  for (final m in RegExp(
    r'^```text\n([\s\S]*?)\n```$',
    multiLine: true,
  ).allMatches(markdown))
    m.group(1)!,
];

/// Words that promise open source, which is true only once `LICENSE` is
/// AGPL-3.0 (G8; review of #49).
const openSource = [
  'open-source',
  'källkod',
  'source code',
  'agpl',
  'öppen källkod',
  'källkoden är öppen',
  'open source',
  'source code is open',
];

List<String> problems(String markdown, {required bool agpl}) {
  final found = <String>[];
  final all = texts(markdown);
  if (all.length != limits.length) {
    return ['${all.length} texts, not ${limits.length}'];
  }
  for (final (i, text) in all.indexed) {
    if (text.length > limits[i]) {
      found.add('text ${i + 1}: ${text.length} characters, over ${limits[i]}');
    }
    final lower = text.toLowerCase();
    for (final b in [...banned, ...bannedSwedish, ...bannedEnglish]) {
      if (lower.contains(b)) found.add('text ${i + 1}: "$b"');
    }
    if (!agpl) {
      for (final w in openSource) {
        if (lower.contains(w)) found.add('text ${i + 1}: "$w" before G8');
      }
    }
  }
  return found;
}

/// The website's text (docs/hemsida.md, F13): the same banned words and no
/// open source before G8, in the whole file.
List<String> websiteProblems(String text, {required bool agpl}) {
  final lower = text.toLowerCase();
  return [
    for (final b in [...banned, ...bannedSwedish, ...bannedEnglish])
      if (lower.contains(b)) '"$b"',
    if (!agpl)
      for (final w in openSource)
        if (lower.contains(w)) '"$w" before G8',
  ];
}

void main() {
  final doc = File('docs/butikstexter.md').readAsStringSync();
  final website = File('docs/hemsida.md').readAsStringSync();
  final agpl = File('LICENSE')
      .readAsStringSync()
      .contains('GNU AFFERO GENERAL PUBLIC LICENSE');
  List<String> check(String markdown) => problems(markdown, agpl: agpl);

  test('the store texts keep to 0002 and to the lengths', () {
    expect(texts(doc), hasLength(limits.length));
    expect(check(doc), isEmpty);
  });

  test('the website text keeps to 0002, and promises no open source yet', () {
    expect(websiteProblems(website, agpl: agpl), isEmpty);
    expect(
      websiteProblems('$website\nHelt anonymt.\n', agpl: agpl),
      isNotEmpty,
    );
    expect(
      websiteProblems('$website\nKällkoden är öppen.\n', agpl: false),
      isNotEmpty,
    );
  });

  test('no store text promises open source before LICENSE is AGPL-3.0', () {
    expect(
      problems(
        doc.replaceFirst(
          '• Kameran används bara för att skanna QR-koder.',
          '• Kameran används bara för att skanna QR-koder.\n'
              '• Källkoden är öppen under AGPL-3.0.',
        ),
        agpl: false,
      ),
      isNotEmpty,
    );
  });

  test('the check finds a banned word and a text that is too long', () {
    for (final (from, to) in [
      ('Det behövs inget', 'Ingen ser att du använder SHA. Det behövs inget'),
      ('No phone number', 'It leaves no trace. No phone number'),
    ]) {
      expect(check(doc.replaceFirst(from, to)), isNotEmpty, reason: to);
    }
    expect(
      check(
        doc.replaceFirst('Det behövs inget', 'Helt anonymt. Det behövs inget'),
      ),
      isNotEmpty,
    );
    expect(
      check(
        doc.replaceFirst('No phone number', 'Fully anonymous. No phone number'),
      ),
      isNotEmpty,
    );
    expect(
      check(
        doc.replaceFirst(
          'The server cannot read',
          "The server can't see your IP address and cannot read",
        ),
      ),
      isNotEmpty,
    );
    expect(
      check(doc.replaceFirst('```text\nSHA\n```', '```text\n${'S' * 31}\n```')),
      isNotEmpty,
    );
    expect(check(doc.replaceFirst('```text\nSHA\n```', '')), isNotEmpty);
  });
}
