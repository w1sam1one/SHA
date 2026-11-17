// 0004 §4 (A) and §5 (a): with real Olm messages, every row of the size
// table, the padding and the chain index. Needs the native library
// (tool/build_native_host.sh).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

import 'olm_service_cases.dart';

/// 0004 §4, "Nya storlekar med (A)": bucket → (Olm type 1, Olm type 0,
/// packet type 1, packet type 0), chain index under 128.
const Map<int, (int, int, int, int)> table = {
  256: (304, 410, 322, 428),
  1024: (1072, 1178, 1090, 1196),
  4096: (4144, 4250, 4162, 4268),
  16384: (16433, 16540, 16451, 16558),
  65536: (65585, 65692, 65603, 65710),
};

final Uint8List mailbox = Uint8List.fromList(List.generate(16, (i) => i));

/// Olm's own message: the packet from [OlmService.encrypt] less its type
/// byte.
int olmSize(OlmOutgoing out) => out.packet.length - 1;

String textOf(int bytes) => 'a' * bytes;

void main() {
  test(
    'type 0: every row of the table, for B − 1 bytes and for 1 byte',
    () async {
      final alice = await Person().start();
      final bob = await Person().start();
      await scan(alice, bob);
      for (final MapEntry(key: b, value: row) in table.entries) {
        for (final n in [b == 256 ? 1 : b ~/ 4, b - 1]) {
          final out = await alice.olm.encrypt(bob.key, textOf(n));
          expect(out.packet[0], 0);
          expect(olmSize(out), row.$2, reason: 'B=$b, $n bytes');
          final packet = PacketV3.wrap(mailbox, out.packet);
          expect(packet.length, row.$4, reason: 'B=$b, $n bytes');
          final read = await bob.olm.receive(
            alice.key,
            PacketV3.unwrap(packet),
          );
          expect(read.message?.text, textOf(n), reason: 'unpadded on receipt');
        }
      }
    },
  );

  test(
    'type 1: every row of the table, for B − 1 bytes and for 1 byte',
    () async {
      final (alice, bob) = await established();
      for (final MapEntry(key: b, value: row) in table.entries) {
        for (final n in [b == 256 ? 1 : b ~/ 4, b - 1]) {
          final out = await alice.olm.encrypt(bob.key, textOf(n));
          expect(out.packet[0], 1);
          expect(olmSize(out), row.$1, reason: 'B=$b, $n bytes');
          expect(PacketV3.wrap(mailbox, out.packet).length, row.$3);
          expect(await deliver(bob, alice, out), textOf(n));
        }
      }
    },
  );

  test(
    'B bytes go to the next bucket; more than 65 535 bytes are refused',
    () async {
      final (alice, bob) = await established();
      final at = await alice.olm.encrypt(bob.key, textOf(256));
      expect(olmSize(at), table[1024]!.$1);
      await expectLater(
        alice.olm.encrypt(bob.key, textOf(65536)),
        throwsA(isA<CryptoException>()),
      );
      expect(await deliver(bob, alice, at), textOf(256));
    },
  );

  test('å and emoji near the limit come through unchanged', () async {
    final (alice, bob) = await established();
    for (final text in [
      'å' * 127, // 254 bytes
      '${'a' * 251}😀', // 255 bytes
      '${'a' * 252}😀', // 256 bytes: the next bucket
      jsonEncode({'v': 3, 'm': 'hej på dig 😀'}),
    ]) {
      final out = await alice.olm.encrypt(bob.key, text);
      final bytes = utf8.encode(text).length;
      expect(
        olmSize(out),
        bytes < 256 ? table[256]!.$1 : table[1024]!.$1,
        reason: text,
      );
      expect(await deliver(bob, alice, out), text);
    }
  });

  test('the text kept in the outbox and the inbox is not padded', () async {
    final (alice, bob) = await established();
    final out = await alice.olm.encrypt(bob.key, 'kort');
    expect(out.text, 'kort');
    expect((await alice.olm.outbox()).last.text, 'kort');
    await deliver(bob, alice, out);
    expect((await bob.olm.inbox()).last.text, 'kort');
  });

  test('chain index: 127 gives the same size, 128 one byte more and 16 384 '
      'another one (0004 §4, "Ej verifierat")', () async {
    final (alice, bob) = await established();
    final sizes = <int>[];
    for (var i = 0; i <= 16384; i++) {
      final out = await alice.olm.encrypt(bob.key, 'm');
      expect(out.packet[0], 1);
      sizes.add(olmSize(out));
      await alice.olm.markSent(out.id);
    }
    expect(sizes.first, table[256]!.$1);
    expect(sizes[127], sizes.first);
    expect(sizes[128], sizes.first + 1);
    expect(sizes[16383], sizes.first + 1);
    expect(sizes[16384], sizes.first + 2);
    // So the largest packet is 18 + 65 692 + 2 = 65 712 bytes (0004 §5).
    expect(18 + table[65536]!.$2 + 2, PacketV3.maxPacketSize);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
