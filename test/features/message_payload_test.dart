// 0004 §5: the text inside an Olm message, before padding, is
// {"v":3,"id":…,"t":…,"m":…}.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/message_payload.dart';
import 'package:sha/features/chat/messaging_service.dart';

void main() {
  final sentAt = DateTime.utc(2026, 11, 16, 12, 30, 1, 2, 3);

  test('encodes v 3 with id, time in microseconds and the text', () {
    final json = MessagePayload(
      id: 'abc',
      sentAt: sentAt,
      text: 'hej å 😀',
    ).encode();
    expect(jsonDecode(json), {
      'v': 3,
      'id': 'abc',
      't': sentAt.microsecondsSinceEpoch,
      'm': 'hej å 😀',
    });
    expect(json, endsWith('}'), reason: 'padding removes spaces at the end');
  });

  test('round-trips, also after padding', () {
    final payload = MessagePayload(id: 'x', sentAt: sentAt, text: 'slut  ');
    final read = MessagePayload.decode(OlmPadding.pad(payload.encode()))!;
    expect(read.id, 'x');
    expect(read.sentAt, sentAt);
    expect(read.sentAt.isUtc, isTrue);
    expect(read.text, 'slut  ');
  });

  test('a time given in local time is sent as UTC', () {
    final local = sentAt.toLocal();
    final read = MessagePayload.decode(
      MessagePayload(id: 'x', sentAt: local, text: '').encode(),
    )!;
    expect(read.sentAt, sentAt);
  });

  test('anything else gives null', () {
    String j(Map<String, Object?> m) => jsonEncode(m);
    final t = sentAt.microsecondsSinceEpoch;
    for (final raw in [
      '',
      'inte json',
      '[]',
      '"text"',
      j({'v': 2, 'id': 'x', 't': t, 'm': 'a'}),
      j({'v': '3', 'id': 'x', 't': t, 'm': 'a'}),
      j({'id': 'x', 't': t, 'm': 'a'}),
      j({'v': 3, 't': t, 'm': 'a'}),
      j({'v': 3, 'id': 1, 't': t, 'm': 'a'}),
      j({'v': 3, 'id': 'x', 't': '$t', 'm': 'a'}),
      j({'v': 3, 'id': 'x', 't': 1.5, 'm': 'a'}),
      j({'v': 3, 'id': 'x', 't': t}),
      j({'v': 3, 'id': 'x', 't': t, 'm': null}),
    ]) {
      expect(MessagePayload.decode(raw), isNull, reason: raw);
    }
  });

  test('the longest allowed text fits in the largest bucket, even when every '
      'character is escaped', () {
    final worst = MessagePayload(
      id: 'x' * 64,
      sentAt: sentAt,
      text: '\u0001' * MessagingService.maxTextLength,
    ).encode();
    expect(utf8.encode(worst).length, lessThanOrEqualTo(OlmPadding.maxBytes));
  });
}
