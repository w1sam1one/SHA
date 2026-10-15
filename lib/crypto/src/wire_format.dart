import 'dart:typed_data';

import 'aes_gcm.dart';
import 'padding.dart';
import 'types.dart';

/// Layout of an encrypted packet as handed to the relay pool:
///
///     version (1) || mailbox id (16) || nonce (12) || ciphertext || tag (16)
///
/// AAD = version || mailbox id. The relay sees only the mailbox id (a
/// per-conversation, per-direction, per-day pseudonym), the padded size and
/// arrival time. Sender, recipient identity, message id and timestamp are all
/// inside the ciphertext.
abstract final class WireFormat {
  static const int version = 2;
  static const int mailboxIdLength = 16;
  static const int headerLength = 1 + mailboxIdLength;

  /// Possible packet sizes (one per padding bucket).
  static List<int> get packetSizes => [
    for (final b in MessagePadding.buckets)
      headerLength + Aes256Gcm.overhead + b,
  ];

  /// The routing pseudonym a relay delivers on.
  static Uint8List mailboxIdOf(Uint8List packet) {
    checkHeader(packet);
    return Uint8List.fromList(packet.sublist(1, headerLength));
  }

  static void checkHeader(Uint8List packet) {
    if (!packetSizes.contains(packet.length)) {
      throw const CryptoException('Bad packet size', CryptoErrorKind.corrupt);
    }
    if (packet[0] != version) {
      throw const CryptoException(
        'Unsupported packet version',
        CryptoErrorKind.corrupt,
      );
    }
  }

  /// Day number (UTC) used to rotate mailbox ids.
  static int epochOf(DateTime time) =>
      time.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}
