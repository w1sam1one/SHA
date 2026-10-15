import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../crypto/crypto.dart';
import '../contacts/contacts_store.dart';
import 'message_store.dart';

/// A decrypted message, held only while a chat is open.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.outgoing,
    required this.sentAt,
    required this.text,
  });

  final String id;
  final bool outgoing;
  final DateTime sentAt;

  /// Null if the envelope failed authentication.
  final String? text;
}

/// Turns chat text into encrypted envelopes and back, using [CryptoService].
class MessagingService {
  MessagingService(this._crypto);

  final CryptoService _crypto;
  final Map<String, Future<ConversationKey>> _keys = {};

  Future<EncryptedMessage> seal({
    required PublicIdentity own,
    required Contact contact,
    required String text,
  }) async {
    final id = newId();
    final sentAt = DateTime.now();
    final envelope = await _crypto.encrypt(
      await _keyFor(contact),
      text,
      associatedData: _associatedData(
        id: id,
        sender: own.hash,
        recipient: contact.identity.hash,
        sentAt: sentAt,
      ),
    );
    return EncryptedMessage(
      id: id,
      contactId: contact.id,
      outgoing: true,
      sentAt: sentAt,
      envelope: envelope,
    );
  }

  Future<ChatMessage> open({
    required PublicIdentity own,
    required Contact contact,
    required EncryptedMessage message,
  }) async {
    final sender = message.outgoing ? own.hash : contact.identity.hash;
    final recipient = message.outgoing ? contact.identity.hash : own.hash;
    String? text;
    try {
      text = await _crypto.decrypt(
        await _keyFor(contact),
        message.envelope,
        associatedData: _associatedData(
          id: message.id,
          sender: sender,
          recipient: recipient,
          sentAt: message.sentAt,
        ),
      );
    } on CryptoException {
      text = null;
    }
    return ChatMessage(
      id: message.id,
      outgoing: message.outgoing,
      sentAt: message.sentAt,
      text: text,
    );
  }

  Future<ConversationKey> _keyFor(Contact contact) async {
    final cached = _keys[contact.id];
    if (cached != null) return cached;
    final pending = _crypto.conversationKey(contact.identity);
    _keys[contact.id] = pending;
    try {
      return await pending;
    } catch (_) {
      _keys.remove(contact.id)?.ignore();
      rethrow;
    }
  }

  static List<int> _associatedData({
    required String id,
    required IdentityHash sender,
    required IdentityHash recipient,
    required DateTime sentAt,
  }) => utf8.encode(
    'SHA/v1/msg|$id|${sender.hex}|${recipient.hex}|'
    '${sentAt.toUtc().microsecondsSinceEpoch}',
  );
}

final messagingServiceProvider = Provider<MessagingService>(
  (ref) => MessagingService(ref.watch(cryptoServiceProvider)),
);
