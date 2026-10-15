import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/message_store.dart';
import 'package:sha/features/chat/messaging_service.dart';
import 'package:sha/features/contacts/contacts_store.dart';

import '../support/in_memory_vault.dart';

void main() {
  late MessagingService aliceSide;
  late MessagingService bobSide;
  late Contact bobAsSeenByAlice;
  late Contact aliceAsSeenByBob;

  setUp(() async {
    final alice = ShaCryptoService(vault: InMemoryVault());
    final bob = ShaCryptoService(vault: InMemoryVault());
    final aliceId = await alice.createIdentity();
    final bobId = await bob.createIdentity();
    bobAsSeenByAlice = Contact(
      identity: bobId,
      name: 'Bob',
      verifiedAt: DateTime(2026),
    );
    aliceAsSeenByBob = Contact(
      identity: aliceId,
      name: 'Alice',
      verifiedAt: DateTime(2026),
    );
    aliceSide = MessagingService(alice);
    bobSide = MessagingService(bob);
  });

  test('a message travels Alice → relay → Bob', () async {
    final sent = await aliceSide.seal(
      contact: bobAsSeenByAlice,
      text: 'Hej Bob',
    );
    expect(String.fromCharCodes(sent.packet), isNot(contains('Hej Bob')));
    expect(String.fromCharCodes(sent.packet), isNot(contains(sent.id)));

    final received = await bobSide.receive(
      contact: aliceAsSeenByBob,
      packet: sent.packet,
    );
    expect(received, isNotNull);
    expect(received!.id, sent.id);
    final opened = await bobSide.open(
      contact: aliceAsSeenByBob,
      message: received,
    );
    expect(opened.text, 'Hej Bob');
    expect(
      (await aliceSide.open(contact: bobAsSeenByAlice, message: sent)).text,
      'Hej Bob',
    );
  });

  test('Bob polls the mailbox Alice sends to', () async {
    final sent = await aliceSide.seal(contact: bobAsSeenByAlice, text: 'x');
    final inbox = await bobSide.inboxMailboxes(
      aliceAsSeenByBob,
      DateTime.now(),
    );
    expect(inbox.first, WireFormat.mailboxIdOf(sent.packet));
  });

  test('replayed packets are stored only once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(messageStoreProvider.notifier);
    final sent = await aliceSide.seal(
      contact: bobAsSeenByAlice,
      text: 'en gång',
    );
    for (var i = 0; i < 3; i++) {
      final received = await bobSide.receive(
        contact: aliceAsSeenByBob,
        packet: sent.packet,
      );
      store.add(received!);
    }
    expect(store.forContact(aliceAsSeenByBob.id), hasLength(1));
  });

  test('tampered packets and swapped records do not decrypt', () async {
    final sent = await aliceSide.seal(contact: bobAsSeenByAlice, text: 'hej');
    final tampered = Uint8List.fromList(sent.packet)..[40] ^= 1;
    expect(
      await bobSide.receive(contact: aliceAsSeenByBob, packet: tampered),
      isNull,
    );

    final relabelled = EncryptedMessage(
      id: 'another-id',
      contactId: sent.contactId,
      outgoing: true,
      storedAt: sent.storedAt,
      packet: sent.packet,
    );
    expect(
      (await aliceSide.open(
        contact: bobAsSeenByAlice,
        message: relabelled,
      )).text,
      isNull,
    );
  });

  test('rejects overlong messages', () {
    expect(
      () => aliceSide.seal(
        contact: bobAsSeenByAlice,
        text: 'x' * (MessagingService.maxTextLength + 1),
      ),
      throwsA(isA<MessageTooLongException>()),
    );
  });
}
