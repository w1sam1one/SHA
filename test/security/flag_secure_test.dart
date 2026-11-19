// F11 in docs/ROADMAP.md: FLAG_SECURE is on in every build, debug included.
// The store screenshots are taken through Flutter's own rendering
// (integration_test/screenshots_test.dart), never by turning the flag off.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const mainActivity = 'android/app/src/main/kotlin/se/sha/sha/MainActivity.kt';

/// What the window must get in onCreate, directly in the method's body: not
/// inside an `if`, so that no build type or setting can skip it.
const setSecure =
    '        window.setFlags(\n'
    '            WindowManager.LayoutParams.FLAG_SECURE,\n'
    '            WindowManager.LayoutParams.FLAG_SECURE,\n'
    '        )\n';

/// The problems with FLAG_SECURE in [files] (path: source), all the Android
/// sources of every source set.
List<String> problems(Map<String, String> files) {
  final found = <String>[];
  final main = files[mainActivity];
  if (main == null) return ['$mainActivity is missing'];
  final start = main.indexOf('    override fun onCreate(');
  final end = start < 0 ? -1 : main.indexOf('\n    }\n', start);
  if (end < 0 || !main.substring(start, end + 1).contains(setSecure)) {
    found.add('onCreate in $mainActivity does not always set FLAG_SECURE');
  }
  for (final MapEntry(key: path, value: source) in files.entries) {
    if (path != mainActivity && path.endsWith('/MainActivity.kt')) {
      found.add('$path: a second MainActivity');
    }
    for (final word in ['clearFlags', 'setRecentsScreenshotEnabled']) {
      if (source.contains(word)) found.add('$path: $word');
    }
    final uses = 'FLAG_SECURE'.allMatches(source).length;
    if (uses != (path == mainActivity ? 2 : 0)) {
      found.add('$path: FLAG_SECURE $uses times');
    }
  }
  return found;
}

void main() {
  test('FLAG_SECURE is always on, in every source set', () {
    final files = {
      for (final f in Directory('android/app/src').listSync(recursive: true))
        if (f is File && (f.path.endsWith('.kt') || f.path.endsWith('.java')))
          f.path: f.readAsStringSync(),
    };
    expect(files, contains(mainActivity));
    expect(problems(files), isEmpty);
  });

  test('the check finds a flag that is skipped or turned off', () {
    final good = File(mainActivity).readAsStringSync();
    expect(problems({mainActivity: good}), isEmpty);
    // Only in some builds.
    final onlySome = good.replaceFirst(
      '        window.setFlags(',
      '        if (!BuildConfig.DEBUG) window.setFlags(',
    );
    expect(onlySome, isNot(good));
    expect(problems({mainActivity: onlySome}), isNotEmpty);
    // Turned off again in a debug source set.
    expect(
      problems({
        mainActivity: good,
        'android/app/src/debug/kotlin/se/sha/sha/Screenshots.kt':
            'fun allow(w: Window) = w.clearFlags(LayoutParams.FLAG_SECURE)',
      }),
      isNotEmpty,
    );
    // Gone.
    expect(
      problems({mainActivity: good.replaceFirst(setSecure, '')}),
      isNotEmpty,
    );
    // Another MainActivity in a build type's source set.
    expect(
      problems({
        mainActivity: good,
        'android/app/src/debug/kotlin/se/sha/sha/MainActivity.kt': 'class X',
      }),
      isNotEmpty,
    );
  });
}
