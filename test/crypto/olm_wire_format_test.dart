// 0004 §5 (a): packet format version 3. No native library.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';

Uint8List bytes(int n, [int fill = 7]) =>
    Uint8List.fromList(List.filled(n, fill));

void main() {
  final mailbox = Uint8List.fromList(List.generate(16, (i) => 200 + i));

  test('the header is version 3, the mailbox ID and the Olm type', () {
    final olm = Uint8List.fromList([1, ...bytes(303)]);
    final packet = PacketV3.wrap(mailbox, olm);
    expect(packet.length, 18 + 303);
    expect(packet[0], 3);
    expect(packet.sublist(1, 17), mailbox);
    expect(packet[17], 1);
    expect(PacketV3.headerLength, 18);
    expect(PacketV3.mailboxIdOf(packet), mailbox);
    expect(PacketV3.unwrap(packet), olm);
  });

  test('type 0 is read as well', () {
    final olm = Uint8List.fromList([0, ...bytes(409)]);
    final packet = PacketV3.wrap(mailbox, olm);
    expect(packet[17], 0);
    expect(PacketV3.unwrap(packet), olm);
  });

  test('the largest packet is 65 712 bytes (0004 §5) and one more is '
      'refused', () {
    expect(PacketV3.maxPacketSize, 65712);
    final largest = Uint8List.fromList([0, ...bytes(65712 - 18)]);
    expect(PacketV3.wrap(mailbox, largest).length, 65712);
    final tooLarge = Uint8List.fromList([0, ...bytes(65713 - 18)]);
    expect(
      () => PacketV3.wrap(mailbox, tooLarge),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => PacketV3.unwrap(
        Uint8List.fromList([3, ...mailbox, 0, ...bytes(65713 - 18)]),
      ),
      throwsA(
        isA<CryptoException>().having(
          (e) => e.kind,
          'kind',
          CryptoErrorKind.corrupt,
        ),
      ),
    );
  });

  test('too short, unknown version and unknown type are refused', () {
    final good = PacketV3.wrap(mailbox, Uint8List.fromList([1, 9, 9]));
    for (final bad in <Uint8List>[
      Uint8List(0),
      Uint8List.fromList([3]),
      Uint8List.fromList([3, ...mailbox]),
      Uint8List.fromList([3, ...mailbox, 1]), // a type but no message
      Uint8List.fromList([2, ...good.sublist(1)]),
      Uint8List.fromList([4, ...good.sublist(1)]),
      Uint8List.fromList([...good.sublist(0, 17), 2, 9, 9]),
      Uint8List.fromList([...good.sublist(0, 17), 255, 9, 9]),
    ]) {
      expect(
        () => PacketV3.unwrap(bad),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.kind,
            'kind',
            CryptoErrorKind.corrupt,
          ),
        ),
        reason: '$bad',
      );
      expect(
        () => PacketV3.mailboxIdOf(bad),
        throwsA(isA<CryptoException>()),
        reason: '$bad',
      );
    }
  });

  test('wrap refuses a wrong mailbox ID, an empty Olm packet and an unknown '
      'type', () {
    final olm = Uint8List.fromList([1, 9]);
    expect(
      () => PacketV3.wrap(Uint8List(15), olm),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => PacketV3.wrap(Uint8List(17), olm),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => PacketV3.wrap(mailbox, Uint8List.fromList([1])),
      throwsA(isA<CryptoException>()),
    );
    expect(
      () => PacketV3.wrap(mailbox, Uint8List.fromList([2, 9])),
      throwsA(isA<CryptoException>()),
    );
  });

  test('unwrap and mailboxIdOf give copies', () {
    final packet = PacketV3.wrap(mailbox, Uint8List.fromList([1, 9, 9]));
    final id = PacketV3.mailboxIdOf(packet)..[0] ^= 1;
    final olm = PacketV3.unwrap(packet)..[1] ^= 1;
    expect(packet[1], mailbox[0]);
    expect(packet[18], 9);
    expect(id[0], isNot(mailbox[0]));
    expect(olm[1], isNot(9));
  });
}
