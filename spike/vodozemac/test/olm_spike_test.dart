// Requirement tests for the D3 spike. R1–R7 map to the numbered requirements
// in docs/decisions/0003-protocol-library.md; R8 is this file run on Android
// (integration_test/olm_spike_test.dart).
//
// Two people, Alice and Bob, without server or network: "sending" means
// handing a ciphertext string from one object to the other.

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha_vodozemac_spike/olm_spike.dart';
import 'package:vodozemac/vodozemac.dart';

/// Findings go to stdout with a fixed prefix so they can be collected from
/// `flutter test` and from device logs.
void report(String requirement, String line) =>
    stdout.writeln('SPIKE-REPORT $requirement: $line');

typedef Olm = ({int messageType, String ciphertext});

String decrypt(Session s, Olm m) =>
    s.decrypt(messageType: m.messageType, ciphertext: m.ciphertext);

/// The first line of whatever the library threw, for the report (the full
/// text also carries a Rust backtrace).
String failureOf(void Function() f) {
  try {
    f();
  } catch (e) {
    return '${e.runtimeType}: ${e.toString().split('\n').first}';
  }
  return 'NO ERROR';
}

/// Olm ciphertexts are unpadded standard base64.
Uint8List b64(String s) => base64.decode(base64.normalize(s));
String unb64(List<int> bytes) => base64.encode(bytes).replaceAll('=', '');

/// A pair with an established session: Alice started it from Bob's QR,
/// Bob answered once, so both sides now send normal (type 1) messages.
({Account alice, Account bob, Session a, Session b}) establish() {
  final alice = Account();
  final bob = Account();
  final bobQr = ContactBundle.fromBytes(publishContactBundle(bob).toBytes());
  final a = alice.createOutboundSession(
    identityKey: bobQr.identityKey,
    oneTimeKey: bobQr.oneTimeKey,
  );
  final first = a.encrypt('hej');
  final inbound = bob.createInboundSession(
    theirIdentityKey: alice.curve25519Key,
    preKeyMessageBase64: first.ciphertext,
  );
  final b = inbound.session;
  decrypt(a, b.encrypt('hej tillbaka'));
  return (alice: alice, bob: bob, a: a, b: b);
}

Uint8List randomKey(Random rng) =>
    Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));

void main() {
  setUpAll(initOlm);

  test('R1 QR content: identity key + one one-time key, 64 bytes', () {
    final bob = Account();
    final bytes = publishContactBundle(bob).toBytes();
    expect(bytes.length, 64);

    // Only the 64 bytes travel: Alice starts a session from the parsed copy.
    final qr = ContactBundle.fromBytes(bytes);
    expect(qr.identityKey.toBase64(), bob.curve25519Key.toBase64());
    final alice = Account();
    final first = alice
        .createOutboundSession(
          identityKey: qr.identityKey,
          oneTimeKey: qr.oneTimeKey,
        )
        .encrypt('från QR');
    expect(first.messageType, 0, reason: 'first message is a pre-key message');
    final inbound = bob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: first.ciphertext,
    );
    expect(inbound.plaintext, 'från QR');

    expect(() => ContactBundle.fromBytes(Uint8List(63)), throwsFormatException);
    expect(() => ContactBundle.fromBytes(Uint8List(65)), throwsFormatException);

    // shaid:1 (lib/features/qr/contact_code.dart): "shaid:1:" + 64 hex
    // (identity hash) + ":" + 43 base64url (32-byte key) = 116 characters,
    // carrying 32 bytes of key (the hash is a check, derivable from the key).
    const shaid1Chars = 8 + 64 + 1 + 43;
    final shaid2 = 'shaid:2:${base64Url.encode(bytes).replaceAll('=', '')}';
    report(
      'R1',
      'payload ${bytes.length} bytes (32 identity + 32 one-time key)',
    );
    report(
      'R1',
      'as text "shaid:2:<base64url>" = ${shaid2.length} chars; '
          'shaid:1 = $shaid1Chars chars carrying 32 bytes of key',
    );
    report(
      'R1',
      'Ed25519 key and one-time key id are not needed to start a session',
    );
    expect(shaid2.length, 8 + 86);
  });

  test('R2 start: Alice sends first, Bob answers, both read the text', () {
    final alice = Account();
    final bob = Account();
    final bobQr = ContactBundle.fromBytes(publishContactBundle(bob).toBytes());

    final aliceSession = alice.createOutboundSession(
      identityKey: bobQr.identityKey,
      oneTimeKey: bobQr.oneTimeKey,
    );
    final first = aliceSession.encrypt('Hej Bob, vi sågs nyss.');
    expect(first.messageType, 0);

    // Bob knows Alice's identity key from her QR code.
    final inbound = bob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: first.ciphertext,
    );
    expect(inbound.plaintext, 'Hej Bob, vi sågs nyss.');
    final bobSession = inbound.session;
    expect(bobSession.sessionId, aliceSession.sessionId);

    final reply = bobSession.encrypt('Hej Alice!');
    expect(reply.messageType, 1);
    expect(decrypt(aliceSession, reply), 'Hej Alice!');
    expect(
      aliceSession.encrypt('igen').messageType,
      1,
      reason: 'after a reply Alice stops sending pre-key messages',
    );
    report(
      'R2',
      'pre-key message type 0, replies type 1, same session id on both sides',
    );
  });

  group('R3 100 messages each way', () {
    // Reordering within blocks of 20 keeps every message within the 40
    // skipped keys Olm stores per chain (see the limit tests below).
    List<T> reorderWithin<T>(List<T> items, int block, Random rng) => [
      for (var i = 0; i < items.length; i += block)
        ...(items.sublist(i, min(i + block, items.length))..shuffle(rng)),
    ];

    test('reordered, one lost, across ratchet turns', () {
      final p = establish();
      final rng = Random(20261113);

      void oneWay(Session from, Session to, String tag, int lost) {
        final sent = [
          for (var i = 0; i < 100; i++) (i, from.encrypt('$tag$i')),
        ];
        final delivered = reorderWithin(
          sent.where((m) => m.$1 != lost).toList(),
          20,
          rng,
        );
        expect(
          delivered.map((m) => m.$1).toList(),
          isNot(orderedEquals([...delivered.map((m) => m.$1)]..sort())),
          reason: 'the test must actually reorder',
        );
        for (final (i, m) in delivered) {
          expect(decrypt(to, m), '$tag$i');
        }
        // The lost message never comes; later messages are unaffected.
        expect(decrypt(to, from.encrypt('$tag-after')), '$tag-after');
      }

      oneWay(p.a, p.b, 'a', 37);
      oneWay(p.b, p.a, 'b', 63);

      // A late message from an older chain, delivered after two ratchet turns.
      final early = p.a.encrypt('tidig');
      final next = p.a.encrypt('nästa');
      expect(decrypt(p.b, next), 'nästa');
      expect(decrypt(p.a, p.b.encrypt('svar 1')), 'svar 1');
      expect(decrypt(p.b, p.a.encrypt('ny kedja')), 'ny kedja');
      expect(decrypt(p.a, p.b.encrypt('svar 2')), 'svar 2');
      expect(decrypt(p.b, early), 'tidig');
      report(
        'R3',
        '2 x 99 messages decrypted, reordered within blocks of 20, 1 lost each '
            'way did not block; a message from an older chain decrypted after '
            'two ratchet turns',
      );
    });

    test('limit: only the 40 most recent skipped keys are kept', () {
      final p = establish();
      final sent = [for (var i = 0; i < 42; i++) p.a.encrypt('m$i')];
      expect(decrypt(p.b, sent.last), 'm41'); // 41 messages skipped
      final oldest = failureOf(() => decrypt(p.b, sent.first));
      report('R3', 'limit: message 0 after 41 skipped keys: $oldest');
      expect(oldest, isNot('NO ERROR'));
      for (var i = 1; i < 41; i++) {
        expect(decrypt(p.b, sent[i]), 'm$i');
      }
    });

    test('limit: a gap of more than 2000 messages is rejected', () {
      final p = establish();
      final sent = [for (var i = 0; i < 2002; i++) p.a.encrypt('m$i')];
      final tooFar = failureOf(() => decrypt(p.b, sent.last));
      report('R3', 'limit: message 2001 as the first one received: $tooFar');
      expect(tooFar, isNot('NO ERROR'));
      expect(decrypt(p.b, sent.first), 'm0', reason: 'the session is unharmed');
    });

    test(
      'a full random shuffle of 100 loses messages (documents the limit)',
      () {
        final p = establish();
        final sent = [for (var i = 0; i < 100; i++) (i, p.a.encrypt('m$i'))]
          ..shuffle(Random(7));
        var failed = 0;
        for (final (i, m) in sent) {
          if (failureOf(() => expect(decrypt(p.b, m), 'm$i')) != 'NO ERROR') {
            failed++;
          }
        }
        report(
          'R3',
          'full random shuffle of 100: $failed could not be decrypted',
        );
        expect(failed, greaterThan(0));
      },
    );
  });

  group('R4 must be rejected', () {
    test('changed ciphertext', () {
      final p = establish();
      final m = p.a.encrypt('orört');
      final bytes = b64(m.ciphertext);
      for (final at in [bytes.length ~/ 2, bytes.length - 1]) {
        final changed = Uint8List.fromList(bytes)..[at] ^= 0x01;
        final error = failureOf(
          () => p.b.decrypt(messageType: 1, ciphertext: unb64(changed)),
        );
        report('R4', 'changed byte $at of ${bytes.length}: $error');
        expect(error, isNot('NO ERROR'));
      }
      expect(
        decrypt(p.b, m),
        'orört',
        reason: 'rejections must not break the session',
      );
    });

    test('same message delivered twice', () {
      final p = establish();
      final m = p.a.encrypt('en gång');
      expect(decrypt(p.b, m), 'en gång');
      final error = failureOf(() => decrypt(p.b, m));
      report('R4', 'duplicate normal message: $error');
      expect(error, isNot('NO ERROR'));
      expect(decrypt(p.b, p.a.encrypt('sedan')), 'sedan');
    });

    test(
      'first message (PreKeyMessage) reused after its one-time key was used',
      () {
        final alice = Account();
        final bob = Account();
        final qr = publishContactBundle(bob);
        final first = alice
            .createOutboundSession(
              identityKey: qr.identityKey,
              oneTimeKey: qr.oneTimeKey,
            )
            .encrypt('första');
        final inbound = bob.createInboundSession(
          theirIdentityKey: alice.curve25519Key,
          preKeyMessageBase64: first.ciphertext,
        );
        expect(inbound.plaintext, 'första');

        final asNewSession = failureOf(
          () => bob.createInboundSession(
            theirIdentityKey: alice.curve25519Key,
            preKeyMessageBase64: first.ciphertext,
          ),
        );
        report(
          'R4',
          'replayed pre-key message, new inbound session: $asNewSession',
        );
        expect(asNewSession, isNot('NO ERROR'));

        final onExisting = failureOf(() => decrypt(inbound.session, first));
        report('R4', 'replayed pre-key message, existing session: $onExisting');
        expect(onExisting, isNot('NO ERROR'));
      },
    );

    test('pre-key message checked against the identity key from the QR', () {
      final alice = Account();
      final bob = Account();
      final carol = Account();
      final qr = publishContactBundle(bob);
      final first = alice
          .createOutboundSession(
            identityKey: qr.identityKey,
            oneTimeKey: qr.oneTimeKey,
          )
          .encrypt('från Alice');
      final error = failureOf(
        () => bob.createInboundSession(
          theirIdentityKey: carol.curve25519Key, // Bob expects Carol
          preKeyMessageBase64: first.ciphertext,
        ),
      );
      report(
        'R4',
        'pre-key message from someone other than the scanned key: $error',
      );
      expect(error, isNot('NO ERROR'));
    });
  });

  test('R5 both scan at once: two sessions, both pick the same one', () {
    final alice = Account();
    final bob = Account();
    final aliceQr = publishContactBundle(alice);
    final bobQr = publishContactBundle(bob);

    final aliceOut = alice.createOutboundSession(
      identityKey: bobQr.identityKey,
      oneTimeKey: bobQr.oneTimeKey,
    );
    final bobOut = bob.createOutboundSession(
      identityKey: aliceQr.identityKey,
      oneTimeKey: aliceQr.oneTimeKey,
    );
    final fromAlice = aliceOut.encrypt('Alice först');
    final fromBob = bobOut.encrypt('Bob först');

    final bobIn = bob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: fromAlice.ciphertext,
    );
    final aliceIn = alice.createInboundSession(
      theirIdentityKey: bob.curve25519Key,
      preKeyMessageBase64: fromBob.ciphertext,
    );
    expect(bobIn.plaintext, 'Alice först');
    expect(aliceIn.plaintext, 'Bob först');

    final aliceSessions = [aliceOut, aliceIn.session];
    final bobSessions = [bobIn.session, bobOut]..shuffle(Random(5));
    expect(
      aliceOut.sessionId,
      isNot(bobOut.sessionId),
      reason: 'two different sessions',
    );
    expect(
      aliceSessions.map((s) => s.sessionId).toSet(),
      bobSessions.map((s) => s.sessionId).toSet(),
    );

    final aliceUses = chooseSession(aliceSessions);
    final bobUses = chooseSession(bobSessions);
    expect(
      aliceUses.sessionId,
      bobUses.sessionId,
      reason: 'same rule, same session',
    );
    for (var i = 0; i < 5; i++) {
      expect(decrypt(bobUses, aliceUses.encrypt('a$i')), 'a$i');
      expect(decrypt(aliceUses, bobUses.encrypt('b$i')), 'b$i');
    }

    // A message already sent on the other session still decrypts there.
    final otherAlice = aliceSessions.firstWhere(
      (s) => s.sessionId != aliceUses.sessionId,
    );
    final otherBob = bobSessions.firstWhere(
      (s) => s.sessionId == otherAlice.sessionId,
    );
    expect(decrypt(otherBob, otherAlice.encrypt('i luften')), 'i luften');
    report(
      'R5',
      'two sessions (${aliceOut.sessionId.substring(0, 8)}…, '
          '${bobOut.sessionId.substring(0, 8)}…); rule: send on the smallest session id, '
          'keep the other for receiving; both sides chose the same one',
    );
  });

  test('R6 encrypted pickles survive a restart; a wrong key fails', () {
    final rng = Random.secure();
    final key = randomKey(rng);
    final wrongKey = randomKey(rng);

    // Bob shows his QR, then the app restarts before Alice's first message.
    var bob = Account();
    final qr = publishContactBundle(bob);
    bob = StoredState.save(bob, const [], key).restore(key).account;

    final alice = Account();
    var aliceSession = alice.createOutboundSession(
      identityKey: qr.identityKey,
      oneTimeKey: qr.oneTimeKey,
    );
    final first = aliceSession.encrypt('efter omstart');
    final inbound = bob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: first.ciphertext,
    );
    expect(
      inbound.plaintext,
      'efter omstart',
      reason: 'the one-time key survived the pickle',
    );
    var bobSession = inbound.session;

    // Both restart again and keep talking.
    final bobStored = StoredState.save(bob, [bobSession], key);
    final aliceStored = StoredState.save(alice, [aliceSession], key);
    final bobBack = bobStored.restore(key);
    bobSession = bobBack.sessions.values.single;
    aliceSession = aliceStored.restore(key).sessions.values.single;
    for (var i = 0; i < 10; i++) {
      expect(decrypt(aliceSession, bobSession.encrypt('b$i')), 'b$i');
      expect(decrypt(bobSession, aliceSession.encrypt('a$i')), 'a$i');
    }

    final wrongAccount = failureOf(() => bobStored.restore(wrongKey));
    report('R6', 'wrong pickle key: $wrongAccount');
    expect(wrongAccount, isNot('NO ERROR'));
    final tampered = StoredState(
      account: bobStored.account.replaceRange(
        20,
        21,
        bobStored.account[20] == 'A' ? 'B' : 'A',
      ),
      sessions: const {},
    );
    final tamperedError = failureOf(() => tampered.restore(key));
    report('R6', 'changed pickle: $tamperedError');
    expect(tamperedError, isNot('NO ERROR'));

    // Rollback: an account pickle saved BEFORE the one-time key was used still
    // holds that key, so the same first message opens a session again.
    var oldBob = Account();
    final oldQr = publishContactBundle(oldBob);
    final beforeUse = StoredState.save(oldBob, const [], key);
    final replayable = alice
        .createOutboundSession(
          identityKey: oldQr.identityKey,
          oneTimeKey: oldQr.oneTimeKey,
        )
        .encrypt('en gång');
    oldBob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: replayable.ciphertext,
    );
    oldBob = beforeUse.restore(key).account;
    final again = oldBob.createInboundSession(
      theirIdentityKey: alice.curve25519Key,
      preKeyMessageBase64: replayable.ciphertext,
    );
    expect(again.plaintext, 'en gång');
    report(
      'R6',
      'rollback: restoring an account pickle from before the one-time key was '
          'used accepts the same first message again; the app must save the account right '
          'after createInboundSession',
    );
  });

  test('R7 ciphertext size versus the app padding buckets', () {
    final p = establish();
    // lib/crypto/src/padding.dart and wire_format.dart.
    const buckets = [256, 1024, 4096, 16384, 65536];
    const packetOverhead = 1 + 16 + 12 + 16;
    var previous = 0;
    final sizes = <int, int>{};
    for (final n in [1, 100, 1000, 10000]) {
      final text = 'x' * n;
      final m = p.a.encrypt(text);
      expect(m.messageType, 1);
      expect(decrypt(p.b, m), text);
      final bytes = b64(m.ciphertext).length;
      final overhead = bytes - n;
      final bucket = buckets.firstWhere((b) => n < b);
      report(
        'R7',
        'n=$n chars ($n UTF-8 bytes): Olm message $bytes bytes '
            '(${m.ciphertext.length} base64 chars, +$overhead); SHA today: '
            'bucket $bucket, packet ${bucket + packetOverhead} bytes',
      );
      expect(
        bytes,
        greaterThan(previous),
        reason: 'Olm does not hide the length',
      );
      expect(overhead, inInclusiveRange(16, 96));
      previous = bytes;
      sizes[n] = bytes;
    }
    final preKey = Account();
    final q = publishContactBundle(p.bob);
    final firstBytes = b64(
      preKey
          .createOutboundSession(
            identityKey: q.identityKey,
            oneTimeKey: q.oneTimeKey,
          )
          .encrypt('x')
          .ciphertext,
    ).length;
    report(
      'R7',
      'pre-key message for 1 char: $firstBytes bytes '
          '(normal message: ${sizes[1]} bytes)',
    );
    expect(
      firstBytes,
      greaterThan(sizes[1]!),
      reason: 'a pre-key message also carries the keys to start the session',
    );
  });

  test('R8 platform', () {
    report(
      'R8',
      'os=${Platform.operatingSystem} '
          'version="${Platform.operatingSystemVersion}" abi=${Abi.current()} '
          'dart=${Platform.version.split(' ').first}',
    );
    expect(isInitialized(), isTrue);
  });
}
