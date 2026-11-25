// F13 in docs/ROADMAP.md (0014): the private signing key, and the file that
// points to it, are never in the repository. .gitignore already ignores
// them; this stops one that is added anyway (git add -f). It reads git's
// own list of files, so a key that sits ignored on the owner's computer is
// not an error.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final keyFile = RegExp(
  r'(^|/)(key\.properties|[^/]*\.(jks|keystore|p12|pfx|pepk|pk8|bks))$',
  caseSensitive: false,
);

List<String> keyFiles(Iterable<String> tracked) => [
  for (final path in tracked)
    if (keyFile.hasMatch(path)) path,
];

void main() {
  test('no signing key or key.properties is in the repository', () {
    // -z: paths as they are, also with å, ä or ö, which git otherwise
    // quotes (review of #55).
    final result = Process.runSync('git', ['ls-files', '-z']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final tracked = (result.stdout as String).split('\x00');
    expect(tracked, contains('pubspec.yaml'));
    expect(keyFiles(tracked), isEmpty);
  });

  test('the check finds a key file', () {
    for (final path in [
      'android/key.properties',
      'upload-keystore.jks',
      'android/app/release.keystore',
      'keys/sha.P12',
      'keys/nyckel-ä.jks',
      'signing/release.pk8',
    ]) {
      expect(keyFiles(['README.md', path]), [path], reason: path);
    }
    expect(keyFiles(['docs/keystore.md', 'lib/key_properties.dart']), isEmpty);
  });
}
