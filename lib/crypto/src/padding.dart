import 'dart:typed_data';

import 'types.dart';

/// Pads payloads to a few fixed sizes so relays cannot tell messages apart by
/// length. ISO/IEC 7816-4 style: `data || 0x80 || 0x00…`.
///
/// Padding is applied before encryption and removed only after the GCM tag
/// has been verified, so it cannot act as a padding oracle.
abstract final class MessagePadding {
  static const List<int> buckets = [256, 1024, 4096, 16384, 65536];

  /// Largest payload that fits in the largest bucket.
  static int get maxPayload => buckets.last - 1;

  static Uint8List pad(List<int> data) {
    final size = buckets.firstWhere(
      (b) => data.length < b,
      orElse: () => throw const CryptoException('Message too long'),
    );
    return Uint8List(size)
      ..setRange(0, data.length, data)
      ..[data.length] = 0x80;
  }

  static Uint8List unpad(List<int> padded) {
    if (!buckets.contains(padded.length)) {
      throw const CryptoException('Bad padding', CryptoErrorKind.corrupt);
    }
    var i = padded.length - 1;
    while (i >= 0 && padded[i] == 0) {
      i--;
    }
    if (i < 0 || padded[i] != 0x80) {
      throw const CryptoException('Bad padding', CryptoErrorKind.corrupt);
    }
    return Uint8List.fromList(padded.sublist(0, i));
  }
}
