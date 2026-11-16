import 'dart:typed_data';

import 'types.dart';

/// Packet format version 3 (0004 §5 (a)), as handed to the relay:
///
///     version 3 (1) || mailbox ID (16) || Olm type (1) || Olm message
///
/// - The Olm type is `0` for a pre-key message (every message before the
///   session has read a reply) and `1` for a normal one.
/// - The last two fields are exactly the packet [OlmService.encrypt] gives
///   and [OlmService.receive] takes. The mailbox ID is added when the
///   packet is sent, so a resend after midnight uses the same encryption.
/// - The relay sees only the mailbox ID and the size.
///
/// OGRANSKAT (0004 §5): the header is not protected. Olm has no associated
/// data, so a packet moved to another mailbox is noticed only when it
/// cannot be read. Olm version 1 (8-byte MAC) is used.
abstract final class PacketV3 {
  static const int version = 3;
  static const int mailboxIdLength = 16;

  /// Version, mailbox ID and Olm type.
  static const int headerLength = 1 + mailboxIdLength + 1;

  /// The largest packet (0004 §5): 18 + 65 692 (bucket 65 536, type 0) + 2
  /// (a chain index of up to 3 bytes). The relay's limit in
  /// `relay/limits.go` is the same.
  static const int maxPacketSize = 65712;

  /// [olmPacket] is `[Olm type] || Olm message` from [OlmService.encrypt].
  static Uint8List wrap(Uint8List mailboxId, Uint8List olmPacket) {
    if (mailboxId.length != mailboxIdLength) {
      throw const CryptoException('Bad mailbox ID');
    }
    if (olmPacket.length < 2 || !_knownType(olmPacket[0])) {
      throw const CryptoException('Bad Olm packet');
    }
    if (1 + mailboxIdLength + olmPacket.length > maxPacketSize) {
      throw const CryptoException('Message too long');
    }
    return Uint8List.fromList([version, ...mailboxId, ...olmPacket]);
  }

  /// The routing pseudonym the relay delivers on.
  static Uint8List mailboxIdOf(Uint8List packet) {
    _check(packet);
    return Uint8List.fromList(packet.sublist(1, 1 + mailboxIdLength));
  }

  /// `[Olm type] || Olm message`, for [OlmService.receive].
  static Uint8List unwrap(Uint8List packet) {
    _check(packet);
    return Uint8List.fromList(packet.sublist(1 + mailboxIdLength));
  }

  static bool _knownType(int type) => type == 0 || type == 1;

  static void _check(Uint8List packet) {
    if (packet.length <= headerLength || packet.length > maxPacketSize) {
      throw const CryptoException('Bad packet size', CryptoErrorKind.corrupt);
    }
    if (packet[0] != version) {
      throw const CryptoException(
        'Unsupported packet version',
        CryptoErrorKind.corrupt,
      );
    }
    if (!_knownType(packet[headerLength - 1])) {
      throw const CryptoException(
        'Unknown Olm message type',
        CryptoErrorKind.corrupt,
      );
    }
  }
}
