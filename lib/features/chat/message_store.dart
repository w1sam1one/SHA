import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A message in a conversation, as text.
///
/// Olm cannot read back what this phone sent, so the text is kept in memory
/// while the app runs. On disk a message is in the outbox or the inbox of
/// the Olm state until it has been sent or shown (0005 (i)), and then in the
/// history for as long as the settings say (0010 (B)).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.outgoing,
    required this.sentAt,
    required this.text,
    this.savedId,
    this.pending = false,
    this.shown = true,
  });

  /// The message ID inside the encryption (0004 §5). The same ID is kept
  /// only once.
  final String id;
  final bool outgoing;
  final DateTime sentAt;

  /// Null if Olm read the message but it was not a message from SHA.
  final String? text;

  /// Its ID in the outbox (outgoing) or the inbox (incoming) while it is
  /// still saved there.
  final String? savedId;

  /// Outgoing: still in the outbox, not yet taken by the server.
  final bool pending;

  /// Incoming: false until the chat has shown it.
  final bool shown;

  ChatMessage copyWith({
    bool? pending,
    bool? shown,
    bool clearSavedId = false,
  }) => ChatMessage(
    id: id,
    outgoing: outgoing,
    sentAt: sentAt,
    text: text,
    savedId: clearSavedId ? null : savedId,
    pending: pending ?? this.pending,
    shown: shown ?? this.shown,
  );
}

/// The messages in memory, per contact ID, in time order.
class MessageStore extends Notifier<Map<String, List<ChatMessage>>> {
  @override
  Map<String, List<ChatMessage>> build() => const {};

  List<ChatMessage> forContact(String contactId) =>
      state[contactId] ?? const [];

  /// Adds [message] unless one with the same ID is there. Returns whether
  /// it was added.
  bool add(String contactId, ChatMessage message) {
    final list = forContact(contactId);
    if (list.any((m) => m.id == message.id)) return false;
    state = {
      ...state,
      contactId: [...list, message]
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt)),
    };
    return true;
  }

  /// Changes the message with [id], if there is one.
  void update(
    String contactId,
    String id,
    ChatMessage Function(ChatMessage) change,
  ) {
    final list = forContact(contactId);
    if (!list.any((m) => m.id == id)) return;
    state = {
      ...state,
      contactId: [for (final m in list) m.id == id ? change(m) : m],
    };
  }
}

final messageStoreProvider =
    NotifierProvider<MessageStore, Map<String, List<ChatMessage>>>(
      MessageStore.new,
    );
