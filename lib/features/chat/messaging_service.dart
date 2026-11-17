import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../crypto/crypto.dart';
import '../contacts/contacts_store.dart';
import 'message_payload.dart';
import 'message_store.dart';

/// Thrown for a message that cannot be sent (e.g. too long).
class MessageTooLongException implements Exception {
  const MessageTooLongException();
}

/// Messages with Olm (P6): the text goes into a [MessagePayload], which the
/// Olm service pads, encrypts and saves in the outbox before anything
/// leaves the phone (0004 §4 and §6). The mailbox IDs come from the
/// contact's addressing key (0004 §3 (A)).
class MessagingService {
  MessagingService(this._crypto, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const int maxTextLength = 4000;

  final CryptoService _crypto;
  final DateTime Function() _clock;
  final Map<String, Future<ConversationKeys>> _keys = {};

  /// Encrypts [text] for [contact] and saves it in the outbox. Send the
  /// packet only after this returns.
  Future<(OlmOutgoing, ChatMessage)> send({
    required Contact contact,
    required String text,
  }) async {
    if (text.length > maxTextLength) throw const MessageTooLongException();
    final olm = contact.olm;
    if (olm == null) throw const CryptoException('Contact has no session');
    final payload = MessagePayload(id: newId(), sentAt: _clock(), text: text);
    final out = await _crypto.olm.encrypt(olm.identityKey, payload.encode());
    return (out, outgoingMessage(out)!);
  }

  /// The message in an outbox entry; null if it is not a payload.
  ChatMessage? outgoingMessage(OlmOutgoing out) {
    final p = MessagePayload.decode(out.text);
    if (p == null) return null;
    return ChatMessage(
      id: p.id,
      outgoing: true,
      sentAt: p.sentAt.toLocal(),
      text: p.text,
      savedId: out.id,
      pending: true,
    );
  }

  /// The message in an inbox entry. A message that Olm read but that is not
  /// a payload is shown as one that could not be read.
  ChatMessage incomingMessage(OlmIncoming m) {
    final p = MessagePayload.decode(m.text);
    return ChatMessage(
      id: p?.id ?? m.id,
      outgoing: false,
      sentAt: p?.sentAt.toLocal() ?? _clock(),
      text: p?.text,
      savedId: m.id,
      shown: false,
    );
  }

  /// Today's mailbox for messages to [contact].
  Future<Uint8List> outgoingMailbox(Contact contact) async => _crypto.mailboxId(
    await _keysFor(contact),
    MessageDirection.outgoing,
    WireFormat.epochOf(_clock()),
  );

  /// Mailbox IDs to fetch for [contact]'s messages: today's and yesterday's
  /// (to cover clock skew and the date boundary).
  Future<List<Uint8List>> inboxMailboxes(Contact contact) async {
    final keys = await _keysFor(contact);
    final today = WireFormat.epochOf(_clock());
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

final messagingServiceProvider = Provider<MessagingService>((ref) {
  final service = MessagingService(ref.watch(cryptoServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});
