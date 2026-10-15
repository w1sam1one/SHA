import 'dart:math';

final Random _random = Random.secure();

/// Random 128-bit identifier as 32 hex characters.
String newId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
