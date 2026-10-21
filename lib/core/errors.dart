import '../crypto/crypto.dart';

/// User-facing (Swedish) text for a failure. Never includes error details.
String describeError(Object error) {
  if (error is CryptoException) {
    return switch (error.kind) {
      CryptoErrorKind.deviceLocked =>
        'Telefonen är låst. Lås upp den och försök igen.',
      CryptoErrorKind.keyInvalidated =>
        'Nyckeln i telefonens säkra lagring är inte längre giltig.',
      CryptoErrorKind.corrupt => 'Krypterad data kunde inte verifieras.',
      CryptoErrorKind.entropy =>
        'Telefonens slumpkälla gav ett ogiltigt resultat. Försök igen.',
      CryptoErrorKind.invalidInput => 'Ogiltig nyckel eller data.',
      CryptoErrorKind.unavailable => 'Telefonens säkra lagring svarar inte. Lås upp telefonen och försök igen.',
    };
  }
  return 'Något gick fel.';
}
