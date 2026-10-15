import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Overwrites [bytes] with zeros. Best effort: Dart cannot guarantee that no
/// other copy exists (the GC may have moved it), but it shortens the time
/// secrets sit in memory.
void wipe(Uint8List? bytes) {
  if (bytes != null) bytes.fillRange(0, bytes.length, 0);
}

/// A 32-byte secret key whose bytes we own and zero on [SecretKeyData.destroy].
SecretKeyData ownedKey(Uint8List bytes) =>
    SecretKeyData(bytes, overwriteWhenDestroyed: true);

/// Copies a key produced by the `cryptography` package into an [ownedKey] and
/// destroys the original.
Future<SecretKeyData> takeKey(SecretKey key) async {
  final copy = Uint8List.fromList(await key.extractBytes());
  key.destroy();
  return ownedKey(copy);
}
