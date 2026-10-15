import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/avatar.dart';
import '../../ui/time_format.dart';
import '../chat/chat_screen.dart';
import '../qr/scan_screen.dart';
import 'contacts_store.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(contactsProvider);
    final q = _query.trim().toLowerCase();
    final contacts = q.isEmpty
        ? all
        : all.where((c) => c.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontakter', style: TextStyle(fontSize: 26)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScanScreen.open(context),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Skanna'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
              hintText: 'Sök bland kontakter',
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(
                ShaColors.surfaceHigh,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? const _EmptyContacts()
                : ListView(
                    padding: const EdgeInsets.only(top: 12, bottom: 96),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Text(
                          'Verifierade · ${contacts.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ShaColors.textSecondary,
                          ),
                        ),
                      ),
                      for (final contact in contacts)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          minTileHeight: 64,
                          leading: ContactAvatar(
                            name: contact.name,
                            hash: contact.identity.hash,
                            verified: true,
                          ),
                          title: Text(
                            contact.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Verifierad',
                                  style: TextStyle(
                                    color: ShaColors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ' · möttes ${formatDay(contact.verifiedAt)}',
                                ),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFA7B0B6),
                            ),
                          ),
                          onTap: () => ChatScreen.open(context, contact.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 48,
              color: ShaColors.textMuted,
            ),
            SizedBox(height: 16),
            Text(
              'Inga kontakter än',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Träffa personen, skanna varandras QR-koder och jämför '
              'kontrollkoden.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ShaColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
