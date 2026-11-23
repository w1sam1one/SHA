// F11 in docs/ROADMAP.md: FLAG_SECURE is on in every build, debug included.
// The store screenshots are taken through Flutter's own rendering
// (integration_test/screenshots_test.dart), never by turning the flag off.
//
// A check of the source, not of a running app: onCreate in MainActivity is
// exactly "super.onCreate, then set FLAG_SECURE", so nothing can return or
// branch before the flag (review of #49); setFlags is called nowhere else;
// nothing else touches the window's flags; and there is no other activity,
// in code or in a build type's manifest, that could open without the flag.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const mainActivity = 'android/app/src/main/kotlin/se/sha/sha/MainActivity.kt';
const mainManifest = 'android/app/src/main/AndroidManifest.xml';

/// The body of onCreate, line by line without comments and blank lines.
const onCreate = [
  'super.onCreate(savedInstanceState)',
  'window.setFlags(',
  'WindowManager.LayoutParams.FLAG_SECURE,',
  'WindowManager.LayoutParams.FLAG_SECURE,',
  ')',
];

/// Words that would change the window's flags some other way. If one of
/// them is needed for something that is not the window (an intent's flags,
/// a buffer size), narrow its pattern here; never remove it.
const banned = [
  'clearFlags',
  'addFlags',
  'setRecentsScreenshotEnabled',
  '0x2000', // FLAG_SECURE's value
  '8192',
];

/// `window.attributes`, `getAttributes()` and `setAttributes(...)` (second
/// review of #49).
final attributes = RegExp('attributes', caseSensitive: false);

final activityClass = RegExp(
  r'\bclass\s+(\w+)[^{]*?:\s*[\w.]*Activity\s*\(|'
  r'\bclass\s+(\w+)\s+extends\s+[\w.]*Activity\b',
);

List<String> _lines(String body) => [
  for (final line in body.split('\n'))
    if (line.trim().isNotEmpty && !line.trim().startsWith('//')) line.trim(),
];

/// The problems with FLAG_SECURE in [files] (path: source): every Kotlin and
/// Java source and every AndroidManifest.xml of every source set.
List<String> problems(Map<String, String> files) {
  final found = <String>[];
  final main = files[mainActivity];
  if (main == null) return ['$mainActivity is missing'];
  final start = main.indexOf('    override fun onCreate(');
  final open = start < 0 ? -1 : main.indexOf('{\n', start);
  final end = open < 0 ? -1 : main.indexOf('\n    }\n', open);
  final body = end < 0 ? null : _lines(main.substring(open + 2, end));
  if (body == null || body.join('\n') != onCreate.join('\n')) {
    found.add(
      'onCreate in $mainActivity is not exactly: ${onCreate.join(' ')}',
    );
  }
  var setFlags = 0;
  for (final MapEntry(key: path, value: source) in files.entries) {
    if (path.endsWith('AndroidManifest.xml')) {
      final activities = '<activity'.allMatches(source).length;
      if (source.contains('activity-alias') ||
          activities != (path == mainManifest ? 1 : 0)) {
        found.add('$path: an activity other than MainActivity');
      }
      continue;
    }
    setFlags += 'setFlags('.allMatches(source).length;
    for (final word in banned) {
      if (source.contains(word)) found.add('$path: $word');
    }
    if (attributes.hasMatch(source)) found.add('$path: the window attributes');
    final uses = 'FLAG_SECURE'.allMatches(source).length;
    if (uses != (path == mainActivity ? 2 : 0)) {
      found.add('$path: FLAG_SECURE $uses times');
    }
    for (final m in activityClass.allMatches(source)) {
      final name = m.group(1) ?? m.group(2);
      if (path != mainActivity || name != 'MainActivity') {
        found.add('$path: the activity $name');
      }
    }
  }
  if (setFlags != 1) found.add('setFlags is called $setFlags times, not once');
  return found;
}

Map<String, String> sources() => {
  for (final f in Directory('android/app/src').listSync(recursive: true))
    if (f is File &&
        (f.path.endsWith('.kt') ||
            f.path.endsWith('.java') ||
            f.path.endsWith('AndroidManifest.xml')))
      f.path: f.readAsStringSync(),
};

void main() {
  test('FLAG_SECURE is always on, in every source set', () {
    final files = sources();
    expect(files, contains(mainActivity));
    expect(files, contains(mainManifest));
    expect(problems(files), isEmpty);
  });

  test('the check finds a flag that is skipped or turned off', () {
    final good = sources();
    final main = good[mainActivity]!;
    expect(problems(good), isEmpty);
    List<String> withMain(String changed) =>
        problems({...good, mainActivity: changed});
    List<String> withFile(String path, String source) =>
        problems({...good, path: source});
    // Only in some builds.
    expect(
      withMain(
        main.replaceFirst(
          '        window.setFlags(',
          '        if (!BuildConfig.DEBUG) window.setFlags(',
        ),
      ),
      isNotEmpty,
    );
    // A return before the flag (review of #49).
    expect(
      withMain(
        main.replaceFirst(
          '        window.setFlags(',
          '        if (BuildConfig.DEBUG) return\n        window.setFlags(',
        ),
      ),
      isNotEmpty,
    );
    // Gone.
    expect(
      withMain(
        main.replaceFirst(RegExp(r'        window\.setFlags\([^)]*\)\n'), ''),
      ),
      isNotEmpty,
    );
    // Turned off again later, by its value.
    expect(
      withMain(
        main.replaceFirst(
          '    override fun configureFlutterEngine',
          '    override fun onResume() {\n        super.onResume()\n'
              '        window.setFlags(0, 0x2000)\n    }\n\n'
              '    override fun configureFlutterEngine',
        ),
      ),
      isNotEmpty,
    );
    // Turned off in a debug source set.
    const debug = 'android/app/src/debug/kotlin/se/sha/sha/Screenshots.kt';
    expect(
      withFile(debug, 'fun allow(w: Window) = w.clearFlags(SECURE)'),
      isNotEmpty,
    );
    expect(
      withFile(debug, 'fun allow(w: Window) { w.attributes = Params() }'),
      isNotEmpty,
    );
    expect(
      withFile(
        debug,
        'fun allow(w: Window) { val p = w.getAttributes(); p.flags = 0; '
        'w.setAttributes(p) }',
      ),
      isNotEmpty,
    );
    // Another activity, in code or in a manifest.
    expect(
      withFile(debug, 'class ScreenshotActivity : FlutterActivity() {}'),
      isNotEmpty,
    );
    expect(
      withFile(
        'android/app/src/debug/AndroidManifest.xml',
        '<manifest><application><activity android:name=".X"/>'
            '</application></manifest>',
      ),
      isNotEmpty,
    );
    expect(
      withFile(
        'android/app/src/debug/kotlin/se/sha/sha/MainActivity.kt',
        'class MainActivity : FlutterActivity()',
      ),
      isNotEmpty,
    );
  });
}
