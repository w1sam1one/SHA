import 'dart:typed_data';

import 'types.dart';

/// The only entry point the rest of the app uses for cryptography.
///
/// - Identity: an X25519 key pair; the identity hash is SHA-256(public key).
///   The private key is held in [SecureKeyStorage] and never returned.
/// - Messages: AES-256-GCM with a fresh random nonce per message, under a key
///   derived with X25519 + HKDF-SHA256 for each contact.
abstract interface class CryptoService {
  /// Returns this device's identity, or null if none has been created yet.
  Future<PublicIdentity?> loadIdentity();

  /// Generates a new identity and stores its private key securely.
  /// Throws [CryptoException] if an identity already exists.
  Future<PublicIdentity> createIdentity();

  /// Validates a peer's public key and computes its identity hash.
  Future<PublicIdentity> identityFromPublicKey(List<int> publicKey);

  /// SHA-256 of [data].
  Future<Uint8List> sha256(List<int> data);

  /// Derives the AES-256 key shared between this device's identity and [peer].
  Future<ConversationKey> conversationKey(PublicIdentity peer);

  /// Six-digit code both people should see after exchanging QR codes. It is
  /// derived from both public keys, so a swapped or tampered QR code shows a
  /// different code on the two phones.
  Future<String> verificationCode(PublicIdentity peer);

  /// Encrypts [plaintext] into a sealed envelope (nonce and tag included).
  /// [associatedData] is authenticated but not encrypted.
  Future<Uint8List> encrypt(
    ConversationKey key,
    String plaintext, {
    List<int> associatedData = const [],
  });

  /// Decrypts an envelope from [encrypt]. Throws [CryptoException] if it was
  /// tampered with or the key or associated data do not match.
  Future<String> decrypt(
    ConversationKey key,
    Uint8List envelope, {
    List<int> associatedData = const [],
  });
}
