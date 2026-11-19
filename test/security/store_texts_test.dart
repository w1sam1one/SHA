// F11 in docs/ROADMAP.md: the store texts in docs/butikstexter.md keep to
// the wording rules of 0002 and to the lengths of the store listing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'wording_test.dart' show banned;

/// The same rules in English (0002, "Formuleringar i appen").
const bannedEnglish = [
  'anonym', // "anonymous", "anonymity"
  'untraceable',
  'no logs',
  'not see your ip', // "cannot see your IP address", "does not see …"
  "n't see your ip", // "can't see your IP address"
  'nobody can see that you use',
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

List<String> problems(String markdown) {
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
    for (final b in [...banned, ...bannedEnglish]) {
      if (lower.contains(b)) found.add('text ${i + 1}: "$b"');
    }
  }
  return found;
}

void main() {
  final doc = File('docs/butikstexter.md').readAsStringSync();

  test('the store texts keep to 0002 and to the lengths', () {
    expect(texts(doc), hasLength(limits.length));
    expect(problems(doc), isEmpty);
  });

  test('the check finds a banned word and a text that is too long', () {
    expect(
      problems(
        doc.replaceFirst('Det behövs inget', 'Helt anonymt. Det behövs inget'),
      ),
      isNotEmpty,
    );
    expect(
      problems(
        doc.replaceFirst('No phone number', 'Fully anonymous. No phone number'),
      ),
      isNotEmpty,
    );
    expect(
      problems(
        doc.replaceFirst(
          'The server cannot read',
          "The server can't see your IP address and cannot read",
        ),
      ),
      isNotEmpty,
    );
    expect(
      problems(
        doc.replaceFirst('```text\nSHA\n```', '```text\n${'S' * 31}\n```'),
      ),
      isNotEmpty,
    );
    expect(problems(doc.replaceFirst('```text\nSHA\n```', '')), isNotEmpty);
  });
}
