import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contacts/contacts_store.dart';
import 'message_store.dart';
import 'messaging_service.dart';

/// Decrypted history of one conversation. Auto-disposed, so plaintext is only
/// kept in memory while the chat is on screen.
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  ChatController(this.contactId);

  final String contactId;

  Contact get _contact {
    final contact = ref.read(contactsProvider.notifier).byId(contactId);
    if (contact == null) throw StateError('Unknown contact');
    return contact;
  }

  @override
  Future<List<ChatMessage>> build() async {
    ref.watch(contactsProvider);
    final messaging = ref.watch(messagingServiceProvider);
    final contact = _contact;
    final stored = ref
        .read(messageStoreProvider.notifier)
        .forContact(contactId);
    return Future.wait([
      for (final m in stored) messaging.open(contact: contact, message: m),
    ]);
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final store = ref.read(messageStoreProvider.notifier);
    final sealed = await ref
        .read(messagingServiceProvider)
        .seal(contact: _contact, text: trimmed);
    // Here the packet would be handed to the relay pool.
    store.add(sealed);
    if (!ref.mounted) return;
    state = AsyncData([
      ...state.value ?? const [],
      ChatMessage(
        id: sealed.id,
        outgoing: true,
        sentAt: sealed.storedAt,
        text: trimmed,
      ),
    ]);
  }
}

final chatProvider = AsyncNotifierProvider.autoDispose
    .family<ChatController, List<ChatMessage>, String>(ChatController.new);
