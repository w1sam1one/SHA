import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A message as stored: only the sealed AES-256-GCM envelope, never plaintext.
/// The metadata is bound to the ciphertext as associated data, so it cannot be
/// altered without decryption failing.
class EncryptedMessage {
  const EncryptedMessage({
    required this.id,
    required this.contactId,
    required this.outgoing,
    required this.sentAt,
    required this.envelope,
  });

  final String id;
  final String contactId;
  final bool outgoing;
  final DateTime sentAt;
  final Uint8List envelope;
}

/// In-memory store of encrypted messages, keyed by contact id.
class MessageStore extends Notifier<Map<String, List<EncryptedMessage>>> {
  @override
  Map<String, List<EncryptedMessage>> build() => const {};

  List<EncryptedMessage> forContact(String contactId) =>
      state[contactId] ?? const [];

  void add(EncryptedMessage message) {
    state = {
      ...state,
      message.contactId: [...forContact(message.contactId), message],
    };
  }
}

final messageStoreProvider =
    NotifierProvider<MessageStore, Map<String, List<EncryptedMessage>>>(
      MessageStore.new,
    );
