import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/message_store.dart';
import 'package:sha/features/chat/messaging_service.dart';
import 'package:sha/features/contacts/contacts_store.dart';

import '../support/in_memory_key_storage.dart';

void main() {
  late PublicIdentity own;
  late Contact contact;
  late MessagingService messaging;

  setUp(() async {
    final crypto = ShaCryptoService(storage: InMemoryKeyStorage());
    own = await crypto.createIdentity();
    final peer = await ShaCryptoService(storage: InMemoryKeyStorage())
        .createIdentity();
    contact = Contact(
      identity: peer,
      name: 'Jonas',
      verifiedAt: DateTime(2026),
    );
    messaging = MessagingService(crypto);
  });

  test('stores only ciphertext and decrypts it back', () async {
    final sealed = await messaging.seal(
      own: own,
      contact: contact,
      text: 'Hej Jonas',
    );
    expect(String.fromCharCodes(sealed.envelope), isNot(contains('Hej Jonas')));
    final opened = await messaging.open(
      own: own,
      contact: contact,
      message: sealed,
    );
    expect(opened.text, 'Hej Jonas');
  });

  test('tampered metadata fails authentication', () async {
    final sealed = await messaging.seal(
      own: own,
      contact: contact,
      text: 'Hej',
    );
    final moved = EncryptedMessage(
      id: sealed.id,
      contactId: sealed.contactId,
      outgoing: sealed.outgoing,
      sentAt: sealed.sentAt.add(const Duration(minutes: 1)),
      envelope: Uint8List.fromList(sealed.envelope),
    );
    final opened = await messaging.open(
      own: own,
      contact: contact,
      message: moved,
    );
    expect(opened.text, isNull);
  });
}
