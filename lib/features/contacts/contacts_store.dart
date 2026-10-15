import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/crypto.dart';

class Contact {
  const Contact({
    required this.identity,
    required this.name,
    required this.verifiedAt,
  });

  final PublicIdentity identity;
  final String name;

  /// When the two people met and confirmed matching verification codes.
  final DateTime verifiedAt;

  String get id => identity.hash.hex;
}

/// In-memory contact list (no persistence in the MVP).
class ContactsStore extends Notifier<List<Contact>> {
  @override
  List<Contact> build() => const [];

  Contact? byId(String id) {
    for (final contact in state) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  void add(Contact contact) {
    state = [
      for (final c in state)
        if (c.id != contact.id) c,
      contact,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

final contactsProvider = NotifierProvider<ContactsStore, List<Contact>>(
  ContactsStore.new,
);
