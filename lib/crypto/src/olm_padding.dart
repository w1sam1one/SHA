import 'dart:convert';

import 'padding.dart';
import 'types.dart';

/// Padding inside Olm (0004 §4 (A)): the text is filled with spaces to
/// exactly B − 1 bytes of UTF-8, where B is the smallest bucket it is
/// shorter than.
///
/// - B − 1 leaves 15 when divided by 16, so PKCS7 inside Olm adds exactly
///   one byte and the ciphertext is exactly B.
/// - The app's text is JSON (`MessagePayload`), and JSON allows spaces after
///   the value. It never ends with a space itself, so [unpad] gives the same
///   text back.
/// - It is applied before encryption and removed only after Olm has checked
///   the MAC, so it cannot act as a padding oracle.
///
/// OGRANSKAT (0004 §4): the size still shows the bucket, a first message
/// (type 0) and a long chain without a reply.
abstract final class OlmPadding {
  /// The same five sizes as [MessagePadding].
  static const List<int> buckets = MessagePadding.buckets;

  /// The largest text in bytes of UTF-8: one less than the largest bucket.
  static int get maxBytes => buckets.last - 1;

  static String pad(String text) {
    final bytes = utf8.encode(text).length;
    final bucket = buckets.firstWhere(
      (b) => bytes < b,
      orElse: () => throw const CryptoException('Message too long'),
    );
    return text + ' ' * (bucket - 1 - bytes);
  }

  /// Removes the spaces at the end, and nothing else.
  static String unpad(String padded) {
    var end = padded.length;
    while (end > 0 && padded.codeUnitAt(end - 1) == 0x20) {
      end--;
    }
    return padded.substring(0, end);
  }
}
