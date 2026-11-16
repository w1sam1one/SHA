// 0004 §10: every row gives the approved text.
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/notice_texts.dart';

void main() {
  const again =
      'Händer det igen, träffas och skanna varandras QR-koder på '
      'nytt.';

  test('nothing to show', () {
    expect(NoticeTexts.failures('Jonas', const OlmFailureCounts()), isEmpty);
  });

  test('"kunde inte läsas" with one and with several messages', () {
    expect(
      NoticeTexts.failures('Jonas', const OlmFailureCounts(unreadable: 1)),
      ['Ett meddelande från Jonas kunde inte läsas. $again'],
    );
    expect(
      NoticeTexts.failures('Jonas', const OlmFailureCounts(unreadable: 3)),
      ['3 meddelanden från Jonas kunde inte läsas. $again'],
    );
  });

  test('too late, and a gap that is too big', () {
    expect(NoticeTexts.failures('Jonas', const OlmFailureCounts(tooLate: 2)), [
      'Ett äldre meddelande från Jonas kom fram för sent och kan inte läsas.',
    ]);
    expect(
      NoticeTexts.failures('Jonas', const OlmFailureCounts(gapTooBig: 1)),
      ['Några meddelanden från Jonas saknas. Be Jonas skriva igen.'],
    );
  });

  test('malformed packets show nothing', () {
    expect(
      NoticeTexts.failures('Jonas', const OlmFailureCounts(malformed: 9)),
      isEmpty,
    );
  });

  test('the server texts', () {
    expect(
      NoticeTexts.serverFull,
      'Meddelandet väntar. Servern har inte plats för det just nu. Appen '
      'försöker igen.',
    );
    expect(
      NoticeTexts.serverBusy,
      'Servern är upptagen. Appen försöker igen om en stund.',
    );
  });
}
