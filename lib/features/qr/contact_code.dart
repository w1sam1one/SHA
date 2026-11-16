import 'dart:convert';
import 'dart:typed_data';

import '../../crypto/crypto.dart';

class ContactCodeException implements Exception {
  const ContactCodeException(this.message);

  /// User-facing (Swedish) reason.
  final String message;

  @override
  String toString() => 'ContactCodeException: $message';
}

/// What a scanned code gives: the Olm bundle and the contact's addressing
/// key (0004 §1 and §3 (A)). Everything in it is public.
final class ScannedCode {
  const ScannedCode({required this.bundle, required this.addressingKey});

  final OlmContactBundle bundle;

  /// The contact's static X25519 key, used only for mailbox IDs.
  final PublicIdentity addressingKey;
}

/// Text carried in an SHA contact QR code (0004 §1):
///
///     shaid:2:<base64url without "=" of 96 bytes>
///
/// The 96 bytes are the Olm identity key, one new one-time key and the
/// addressing key, 32 bytes each: 8 + 128 = 136 characters. There is no hash
/// in the code (0004 §1 (a)): the two people compare the verification code.
abstract final class ContactCode {
  static const String scheme = 'shaid';
  static const int version = 2;
  static const int maxLength = 160;
  static const int _bytes = 3 * olmKeyLength;
  static const String _damaged = 'Koden verkar vara skadad. Skanna igen.';

  static String encode(OlmContactBundle bundle, PublicIdentity addressingKey) {
    final payload = Uint8List.fromList([
      ...bundle.identityKey,
      ...bundle.oneTimeKey,
      ...addressingKey.publicKey,
    ]);
    return '$scheme:$version:${base64Url.encode(payload).replaceAll('=', '')}';
  }

  /// Parses a scanned code. Only `shaid:2` is read (0004 §1).
  static ScannedCode parse(String raw) {
    final text = raw.trim();
    final parts = text.split(':');
    if (text.length > maxLength || parts.length < 3 || parts[0] != scheme) {
      throw const ContactCodeException('Det här är inte en SHA-kod.');
    }
    if (parts[1] == '1') {
      throw const ContactCodeException(
        'Koden kommer från en äldre version av SHA. Be din kontakt uppdatera '
        'appen.',
      );
    }
    if (parts[1] != '$version') {
      throw const ContactCodeException(
        'Koden kommer från en version av SHA som inte stöds.',
      );
    }
    if (parts.length != 3) throw const ContactCodeException(_damaged);
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(parts[2]));
    } on FormatException {
      throw const ContactCodeException(_damaged);
    }
    if (bytes.length != _bytes) throw const ContactCodeException(_damaged);
    try {
      return ScannedCode(
        bundle: OlmContactBundle.fromBytes(bytes.sublist(0, 2 * olmKeyLength)),
        addressingKey: PublicIdentity(bytes.sublist(2 * olmKeyLength)),
      );
    } on CryptoException {
      throw const ContactCodeException(_damaged);
    }
  }
}
