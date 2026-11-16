import '../../crypto/crypto.dart';

/// The texts in 0004 §10, approved by the owner 2026-11-16. "Servern",
/// never "relayn". The library's own error text is never shown.
abstract final class NoticeTexts {
  static const String meetAgain =
      'Händer det igen, träffas och skanna varandras QR-koder på nytt.';

  static const String serverFull =
      'Meddelandet väntar. Servern har inte plats för det just nu. Appen '
      'försöker igen.';

  static const String serverBusy =
      'Servern är upptagen. Appen försöker igen om en stund.';

  /// One line per kind of failure from [name], collected (0004 §10).
  /// Malformed packets show nothing.
  static List<String> failures(String name, OlmFailureCounts counts) => [
    if (counts.unreadable == 1)
      'Ett meddelande från $name kunde inte läsas. $meetAgain',
    if (counts.unreadable > 1)
      '${counts.unreadable} meddelanden från $name kunde inte läsas. '
          '$meetAgain',
    if (counts.tooLate > 0)
      'Ett äldre meddelande från $name kom fram för sent och kan inte läsas.',
    if (counts.gapTooBig > 0)
      'Några meddelanden från $name saknas. Be $name skriva igen.',
  ];
}
