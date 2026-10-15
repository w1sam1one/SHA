import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// SHA-256 via the `cryptography` package.
final class Sha256Hasher {
  Sha256Hasher();

  final Sha256 _algorithm = Sha256();

  Future<Uint8List> hash(List<int> data) async {
    final digest = await _algorithm.hash(data);
    return Uint8List.fromList(digest.bytes);
  }
}
