// F12 in docs/ROADMAP.md: the version in pubspec.yaml and the change log
// (CHANGELOG.md) go together. The top heading is exactly the version in
// pubspec.yaml; going down the file, versionCode only gets smaller, because
// Android does not install an update with a lower one; and the text, which
// goes into the release notes, keeps to the wording rules of 0002.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../security/store_texts_test.dart' show bannedEnglish, bannedSwedish;
import '../security/wording_test.dart' show banned;

/// "## 1.0.0+1 – inte släppt" or "## 1.0.1+2 – 2027-01-31".
final heading = RegExp(
  r'^## (\d+)\.(\d+)\.(\d+)\+(\d+) – (inte släppt|\d{4}-\d{2}-\d{2})$',
);

/// The problems in [changelog] for the `version:` line [pubspecVersion].
List<String> problems(String changelog, String pubspecVersion) {
  final found = <String>[];
  final headings = [
    for (final line in changelog.split('\n'))
      if (line.startsWith('## ')) line,
  ];
  if (headings.isEmpty) return ['no version heading'];
  if (!headings.first.startsWith('## $pubspecVersion – ')) {
    found.add('the top heading is not ${headings.first}, but $pubspecVersion');
  }
  int? lastCode;
  List<int>? lastName;
  for (final h in headings) {
    final m = heading.firstMatch(h);
    if (m == null) {
      found.add('not a version heading: $h');
      continue;
    }
    final name = [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
    final code = int.parse(m.group(4)!);
    if (lastCode != null && code >= lastCode) {
      found.add('versionCode $code is not smaller than $lastCode above it');
    }
    if (lastName != null && _compare(name, lastName) > 0) {
      found.add('version ${name.join('.')} is newer than the one above it');
    }
    if (m.group(5) == 'inte släppt' && h != headings.first) {
      found.add('only the top version can be "inte släppt": $h');
    }
    lastCode = code;
    lastName = name;
  }
  final lower = changelog.toLowerCase();
  for (final b in [...banned, ...bannedSwedish, ...bannedEnglish]) {
    if (lower.contains(b)) found.add('"$b" (0002)');
  }
  return found;
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

String pubspecVersion() => RegExp(
  r'^version: (\S+)$',
  multiLine: true,
).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;

void main() {
  final changelog = File('CHANGELOG.md').readAsStringSync();

  test('CHANGELOG.md starts with the version in pubspec.yaml', () {
    expect(pubspecVersion(), matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(problems(changelog, pubspecVersion()), isEmpty);
  });

  test('the check finds a version that does not match or goes backwards', () {
    final top = changelog.indexOf('\n## ');
    String withEntry(String log, String entry) =>
        '${log.substring(0, top)}\n$entry\n${log.substring(top)}';
    // The first version released, so that each case below breaks one rule.
    final released = changelog.replaceFirst(
      '## 1.0.0+1 – inte släppt',
      '## 1.0.0+1 – 2027-01-01',
    );
    expect(problems(released, '1.0.0+1'), isEmpty);
    // pubspec.yaml raised, the change log not.
    expect(problems(changelog, '1.0.1+2'), isNotEmpty);
    // A new version with the same versionCode.
    expect(
      problems(withEntry(released, '## 1.0.1+1 – 2027-02-01\n'), '1.0.1+1'),
      isNotEmpty,
    );
    // A lower version name on top.
    expect(
      problems(withEntry(released, '## 0.9.0+2 – 2027-02-01\n'), '0.9.0+2'),
      isNotEmpty,
    );
    // Two versions "inte släppt".
    expect(
      problems(withEntry(changelog, '## 1.0.1+2 – inte släppt\n'), '1.0.1+2'),
      isNotEmpty,
    );
    // A heading that is not a version.
    expect(problems('$released\n## Nästa version\n', '1.0.0+1'), isNotEmpty);
    // Wording that 0002 does not allow.
    expect(problems('$released\n- Helt anonymt.\n', '1.0.0+1'), isNotEmpty);
    // A new version on top of a released one is fine.
    expect(
      problems(withEntry(released, '## 1.0.1+2 – inte släppt\n'), '1.0.1+2'),
      isEmpty,
    );
  });
}
