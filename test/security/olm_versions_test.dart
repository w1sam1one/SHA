import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app must use exactly the Olm packages that the spike measured
/// (docs/ROADMAP.md, P2). Dependabot opens separate pull requests for the
/// app's and the spike's pubspec, so this keeps the two equal.
void main() {
  const packages = ['flutter_vodozemac', 'vodozemac', 'flutter_rust_bridge'];

  String? pinOf(String pubspec, String name) => RegExp(
    '^  $name:[ \t]*([^\\s#]+)[ \t]*(#.*)?\$',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);

  test('the app pins the same Olm packages as spike/vodozemac', () {
    final app = File('pubspec.yaml').readAsStringSync();
    final spike = File('spike/vodozemac/pubspec.yaml').readAsStringSync();
    for (final name in packages) {
      final appPin = pinOf(app, name);
      expect(appPin, isNotNull, reason: '$name is missing in pubspec.yaml');
      expect(
        appPin,
        matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: '$name must be an exact version, without ^ or a range',
      );
      expect(
        appPin,
        pinOf(spike, name),
        reason: '$name differs from spike/vodozemac/pubspec.yaml',
      );
    }
  });
}
