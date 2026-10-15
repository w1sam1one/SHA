import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A message as stored: the relay packet exactly as sent or received, never
/// plaintext. Message id and timestamp are also inside the ciphertext; the
/// copies here are local-only bookkeeping and never leave the device.
class EncryptedMessage {
  const EncryptedMessage({
    required this.id,
    required this.contactId,
    required this.outgoing,
    required this.storedAt,
    required this.packet,
  });

  final String id;
  final String contactId;
  final bool outgoing;
  final DateTime storedAt;
  final Uint8List packet;
}

/// In-memory store of encrypted messages, keyed by contact id.
class MessageStore extends Notifier<Map<String, List<EncryptedMessage>>> {
  @override
  Map<String, List<EncryptedMessage>> build() => const {};

  List<EncryptedMessage> forContact(String contactId) =>
      state[contactId] ?? const [];

  bool contains(String contactId, String messageId) =>
      forContact(contactId).any((m) => m.id == messageId);

  /// Adds [message] unless one with the same id exists (replay protection).
  /// Returns whether it was added.
  bool add(EncryptedMessage message) {
    if (contains(message.contactId, message.id)) return false;
    state = {
      ...state,
      message.contactId: [...forContact(message.contactId), message],
    };
    return true;
  }
}

final messageStoreProvider =
    NotifierProvider<MessageStore, Map<String, List<EncryptedMessage>>>(
      MessageStore.new,
    );
