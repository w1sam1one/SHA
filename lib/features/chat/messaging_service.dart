import 'dart:convert';
import 'dart:typed_data';

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

  /// Null if the packet failed authentication.
  final String? text;
}

/// Thrown for a message that cannot be sent (e.g. too long).
class MessageTooLongException implements Exception {
  const MessageTooLongException();
}

/// Builds and reads relay packets. The plaintext payload is
/// `{"v":2,"id":…,"t":…,"m":…}` — id and timestamp travel only encrypted.
class MessagingService {
  MessagingService(this._crypto);

  static const int maxTextLength = 4000;

  final CryptoService _crypto;
  final Map<String, Future<ConversationKeys>> _keys = {};

  /// Encrypts [text] for [contact] into a packet ready for the relay pool.
  Future<EncryptedMessage> seal({
    required Contact contact,
    required String text,
  }) async {
    if (text.length > maxTextLength) throw const MessageTooLongException();
    final id = newId();
    final now = DateTime.now();
    final payload = utf8.encode(
      jsonEncode({
        'v': 2,
        'id': id,
        't': now.toUtc().microsecondsSinceEpoch,
        'm': text,
      }),
    );
    try {
      final packet = await _crypto.seal(
        await _keysFor(contact),
        payload,
        now: now,
      );
      return EncryptedMessage(
        id: id,
        contactId: contact.id,
        outgoing: true,
        storedAt: now,
        packet: packet,
      );
    } finally {
      payload.fillRange(0, payload.length, 0);
    }
  }

  /// Decrypts a stored message. Returns a message with null text if the
  /// packet fails authentication or does not match its local record.
  Future<ChatMessage> open({
    required Contact contact,
    required EncryptedMessage message,
  }) async {
    final decoded = await _decode(
      contact,
      message.packet,
      message.outgoing ? MessageDirection.outgoing : MessageDirection.incoming,
    );
    if (decoded == null || decoded.id != message.id) {
      return ChatMessage(
        id: message.id,
        outgoing: message.outgoing,
        sentAt: message.storedAt,
        text: null,
      );
    }
    return ChatMessage(
      id: decoded.id,
      outgoing: message.outgoing,
      sentAt: decoded.sentAt,
      text: decoded.text,
    );
  }

  /// Turns a packet delivered by the relay pool into a stored message.
  /// Returns null for packets that do not authenticate.
  Future<EncryptedMessage?> receive({
    required Contact contact,
    required Uint8List packet,
  }) async {
    final decoded = await _decode(contact, packet, MessageDirection.incoming);
    if (decoded == null) return null;
    return EncryptedMessage(
      id: decoded.id,
      contactId: contact.id,
      outgoing: false,
      storedAt: DateTime.now(),
      packet: packet,
    );
  }

  /// Mailbox ids to poll for [contact]'s messages: today's and yesterday's
  /// (to cover clock skew and the date boundary).
  Future<List<Uint8List>> inboxMailboxes(Contact contact, DateTime now) async {
    final keys = await _keysFor(contact);
    final today = WireFormat.epochOf(now);
    return [
      for (final epoch in [today, today - 1])
        await _crypto.mailboxId(keys, MessageDirection.incoming, epoch),
    ];
  }

  /// Destroys all cached conversation keys.
  void dispose() {
    for (final pending in _keys.values) {
      pending.then(_crypto.forget, onError: (_) {});
    }
    _keys.clear();
  }

  Future<_Payload?> _decode(
    Contact contact,
    Uint8List packet,
    MessageDirection direction,
  ) async {
    final Uint8List clear;
    try {
      clear = await _crypto.open(await _keysFor(contact), packet, direction);
    } on CryptoException catch (e) {
      if (e.kind == CryptoErrorKind.corrupt) return null;
      rethrow;
    }
    try {
      final json = jsonDecode(utf8.decode(clear));
      if (json is! Map<String, Object?> ||
          json['v'] != 2 ||
          json['id'] is! String ||
          json['t'] is! int ||
          json['m'] is! String) {
        return null;
      }
      return _Payload(
        id: json['id']! as String,
        sentAt: DateTime.fromMicrosecondsSinceEpoch(
          json['t']! as int,
          isUtc: true,
        ).toLocal(),
        text: json['m']! as String,
      );
    } on FormatException {
      return null;
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  Future<ConversationKeys> _keysFor(Contact contact) async {
    final cached = _keys[contact.id];
    if (cached != null) return cached;
    final pending = _crypto.conversationKeys(contact.identity);
    _keys[contact.id] = pending;
    try {
      return await pending;
    } catch (_) {
      _keys.remove(contact.id)?.ignore();
      rethrow;
    }
  }
}

class _Payload {
  const _Payload({required this.id, required this.sentAt, required this.text});

  final String id;
  final DateTime sentAt;
  final String text;
}

final messagingServiceProvider = Provider<MessagingService>((ref) {
  final service = MessagingService(ref.watch(cryptoServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});
