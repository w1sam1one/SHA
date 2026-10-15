import 'dart:convert';

import '../../crypto/crypto.dart';

class ContactCodeException implements Exception {
  const ContactCodeException(this.message);

  /// User-facing (Swedish) reason.
  final String message;

  @override
  String toString() => 'ContactCodeException: $message';
}

/// Text carried in an SHA contact QR code:
///
///     shaid:1:<identity hash, 64 hex>:<X25519 public key, base64url>
///
/// Everything in it is public. The identity hash lets the scanner check that
/// the code was read intact: it must equal SHA-256 of the public key.
abstract final class ContactCode {
  static const String scheme = 'shaid';
  static const int version = 1;

  static String encode(PublicIdentity identity) {
    final key = base64Url.encode(identity.publicKey).replaceAll('=', '');
    return '$scheme:$version:${identity.hash.hex}:$key';
  }

  /// Parses and verifies a scanned code.
  static Future<PublicIdentity> parse(String raw, CryptoService crypto) async {
    final parts = raw.trim().split(':');
    if (parts.length != 4 || parts[0] != scheme) {
      throw const ContactCodeException('Det här är inte en SHA-kod.');
    }
    if (parts[1] != '$version') {
      throw const ContactCodeException(
        'Koden kommer från en version av SHA som inte stöds.',
      );
    }
    final IdentityHash claimed;
    final List<int> publicKey;
    try {
      claimed = IdentityHash.fromHex(parts[2]);
      publicKey = base64Url.decode(base64Url.normalize(parts[3]));
    } on FormatException {
      throw const ContactCodeException('Koden är skadad.');
    } on CryptoException {
      throw const ContactCodeException('Koden är skadad.');
    }
    final PublicIdentity identity;
    try {
      identity = await crypto.identityFromPublicKey(publicKey);
    } on CryptoException {
      throw const ContactCodeException('Koden innehåller en ogiltig nyckel.');
    }
    if (identity.hash != claimed) {
      throw const ContactCodeException(
        'Kodens hash stämmer inte med nyckeln. Skanna igen.',
      );
    }
    return identity;
  }
}
