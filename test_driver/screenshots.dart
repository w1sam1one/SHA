// F11: saves the pictures that integration_test/screenshots_test.dart takes,
// as build/screenshots/<name>.png on the computer. Only `flutter drive` runs
// this file; it is never part of the app (docs/butikstexter.md, "Skärmbilder").
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, image, [args]) async {
    final file = File('build/screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(image);
    stdout.writeln('saved ${file.path}');
    return true;
  },
);
