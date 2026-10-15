import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// SHA-256 and HMAC-SHA256 via the `cryptography` package.
final class Sha256Hasher {
  Sha256Hasher();

  final Sha256 _sha256 = Sha256();
  final Hmac _hmac = Hmac.sha256();

  Future<Uint8List> hash(List<int> data) async {
    final digest = await _sha256.hash(data);
    return Uint8List.fromList(digest.bytes);
  }

  Future<Uint8List> hmac(SecretKey key, List<int> data) async {
    final mac = await _hmac.calculateMac(data, secretKey: key);
    return Uint8List.fromList(mac.bytes);
  }
}
