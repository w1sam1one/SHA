import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../crypto/crypto.dart';

class Contact {
  const Contact({
    required this.identity,
    required this.name,
    required this.verifiedAt,
    this.olm,
  });

  /// From the contact's saved Olm state (P4).
  factory Contact.fromOlm(OlmContact c) => Contact(
    identity: PublicIdentity(c.addressingKey),
    name: c.name,
    verifiedAt: c.metAt,
    olm: c,
  );

  /// The contact's addressing key (0004 §3 (A)): mailbox IDs only.
  final PublicIdentity identity;
  final String name;

  /// When the two people met and confirmed matching verification codes.
  final DateTime verifiedAt;

  /// The contact as saved with Olm. Null only in older tests.
  final OlmContact? olm;

  /// SHA-256 of the Olm identity key (0004 §1); before Olm, of the X25519
  /// key.
  String get id => olm?.id ?? identity.hash.hex;
}

/// The contact list. Saved contacts are read from the Olm state, which is
/// the vault's single state entry (0005 (A)).
class ContactsStore extends Notifier<List<Contact>> {
  /// Completes when the saved contacts have been read.
  late Future<void> ready;

  @override
  List<Contact> build() {
    ready = Future(_load);
    return const [];
  }

  Future<void> _load() async {
    if (!ref.mounted) return; // rebuilt or disposed before the load ran
    final saved = await ref.read(cryptoServiceProvider).olm.contacts();
    if (!ref.mounted || saved.isEmpty) return;
    for (final c in saved) {
      _put(Contact.fromOlm(c));
    }
  }

  Contact? byId(String id) {
    for (final contact in state) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  /// Keeps [contact] in the list only (tests and older code).
  void add(Contact contact) => _put(contact);

  /// Saves a contact from a scanned code with its Olm session, then lists it.
  Future<Contact> addScanned({
    required OlmContactBundle bundle,
    required PublicIdentity addressingKey,
    required String name,
    required DateTime metAt,
  }) async {
    final saved = await ref
        .read(cryptoServiceProvider)
        .olm
        .addContact(
          bundle: bundle,
          addressingKey: addressingKey.publicKey,
          name: name,
          metAt: metAt,
        );
    final contact = Contact.fromOlm(saved);
    _put(contact);
    return contact;
  }

  void _put(Contact contact) {
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
