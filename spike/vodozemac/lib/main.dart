// Only there so Android can build an app to run integration_test in. The
// spike has no UI; everything is in test/ and integration_test/.
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: Center(child: Text('SHA vodozemac spike: run the tests')),
    ),
  ),
);
