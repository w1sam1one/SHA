import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/avatar.dart';
import '../../ui/time_format.dart';
import '../contacts/contacts_store.dart';
import 'chat_screen.dart';
import 'message_store.dart';

/// Conversations that have at least one message. Shows metadata only: nothing
/// is decrypted until a chat is opened.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final messages = ref.watch(messageStoreProvider);
    final threads =
        [
          for (final c in contacts)
            if (messages[c.id]?.isNotEmpty ?? false)
              (contact: c, messages: messages[c.id]!),
        ]..sort(
          (a, b) =>
              b.messages.last.storedAt.compareTo(a.messages.last.storedAt),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chattar', style: TextStyle(fontSize: 26)),
      ),
      body: threads.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'Inga chattar än. Öppna en kontakt för att skriva ditt första '
                  'meddelande.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ShaColors.textSecondary),
                ),
              ),
            )
          : ListView(
              children: [
                for (final t in threads)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 64,
                    leading: ContactAvatar(
                      name: t.contact.name,
                      hash: t.contact.identity.hash,
                    ),
                    title: Text(
                      t.contact.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      t.messages.length == 1
                          ? '1 meddelande'
                          : '${t.messages.length} meddelanden',
                    ),
                    trailing: Text(
                      formatTime(t.messages.last.storedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShaColors.textMuted,
                      ),
                    ),
                    onTap: () => ChatScreen.open(context, t.contact.id),
                  ),
              ],
            ),
    );
  }
}
