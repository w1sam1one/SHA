import 'dart:typed_data';

import 'types.dart';

/// The only entry point the rest of the app uses for cryptography.
///
/// - Identity: an X25519 key pair whose private key lives in a Keystore-backed
///   [KeyVault] and is only unwrapped for the moment it is needed. The
///   identity hash is SHA-256(public key).
/// - Conversations: X25519 + HKDF-SHA256 give separate keys and mailbox
///   pseudonyms per direction.
/// - Messages: padded, then AES-256-GCM with a fresh random nonce, in the
///   relay packet format described in `wire_format.dart`.
abstract interface class CryptoService {
  /// This device's identity, or null if none has been created yet.
  Future<PublicIdentity?> loadIdentity();

  /// Generates a new identity from mixed platform + Dart randomness and stores
  /// it in the vault. Throws [CryptoException] if one already exists.
  Future<PublicIdentity> createIdentity();

  /// How the private key is protected on this device.
  Future<KeyProtection> keyProtection();

  /// Permanently deletes this device's identity, every other vault entry and
  /// the vault key. Afterwards [loadIdentity] returns null and
  /// [createIdentity] makes a new, unrelated identity. Irreversible: it is
  /// the way out when the vault key is lost and the identity cannot be read.
  Future<void> resetIdentity();

  /// SHA-256 of [data].
  Future<Uint8List> sha256(List<int> data);

  /// Derives the keys shared with [peer]. Throws for invalid or own keys.
  Future<ConversationKeys> conversationKeys(PublicIdentity peer);

  /// Destroys the key material behind [keys]; the handle is unusable after.
  void forget(ConversationKeys keys);

  /// 20-digit code both people compare after scanning each other's QR codes.
  /// Derived from both public keys, so a swapped QR code shows a different
  /// code on the two phones. 66 bits make it infeasible to grind a key that
  /// collides.
  Future<String> verificationCode(PublicIdentity peer);

  /// The 16-byte mailbox pseudonym for one direction of a conversation on a
  /// given day ([WireFormat.epochOf]).
  Future<Uint8List> mailboxId(
    ConversationKeys keys,
    MessageDirection direction,
    int epoch,
  );

  /// Pads and encrypts [payload] into a relay packet addressed to today's
  /// outgoing mailbox.
  Future<Uint8List> seal(
    ConversationKeys keys,
    List<int> payload, {
    required DateTime now,
  });

  /// Authenticates and decrypts a packet. Use [MessageDirection.outgoing] to
  /// read back your own sent messages. Throws [CryptoException] if anything
  /// was altered.
  Future<Uint8List> open(
    ConversationKeys keys,
    Uint8List packet,
    MessageDirection direction,
  );
}
