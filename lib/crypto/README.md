# lib/crypto – SHA:s kryptomodul

All kryptografi i appen finns här. Resten av appen når den bara via
`package:sha/crypto/crypto.dart`, som exporterar gränssnittet `CryptoService`,
datatyperna och lagringsabstraktionen. Modulen importerar inget från Flutter-UI,
Riverpod eller app-koden (det kontrolleras av `test/security/no_logging_test.dart`),
så den kan granskas fristående.

Endast välgranskade bibliotek används: [`cryptography`](https://pub.dev/packages/cryptography)
för alla primitiver och [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
för Android Keystore. Inga primitiver är egenimplementerade.

## Filer

| Fil | Innehåll |
| --- | --- |
| `crypto.dart` | Publikt gränssnitt (barrel). Det enda appen importerar. |
| `src/crypto_service.dart` | `CryptoService` – gränssnittet. |
| `src/sha_crypto_service.dart` | Standardimplementationen. |
| `src/aes_gcm.dart` | AES-256-GCM och kuvertformatet. |
| `src/key_agreement.dart` | X25519 + HKDF-SHA256. |
| `src/hashing.dart` | SHA-256. |
| `src/secure_key_storage.dart` | Lagring av privat nyckel i Android Keystore. |
| `src/types.dart` | `IdentityHash`, `PublicIdentity`, `ConversationKey`, `CryptoException`. |

## Konstruktion

**Identitet.** Vid första start skapas ett X25519-nyckelpar.
Identitetshash = `SHA-256(publik nyckel)` (32 byte, visas som 64 hex-tecken).
Den privata nyckeln (32 byte) skrivs bara till `SecureKeyStorage`; ingen metod
returnerar den. `createIdentity()` vägrar skriva över en befintlig identitet.

**Lagring.** `AndroidKeystoreStorage` krypterar värdet med AES-256-GCM under en
nyckel som i sin tur är inslagen av en RSA-nyckel som skapas *i* Android Keystore
(hårdvarubaserad där enheten stöder det) och aldrig kan exporteras. Bara den
krypterade blobben hamnar i appens lagring. `resetOnError` är avstängt så att
identiteten aldrig raderas tyst. Backup och enhetsöverföring är avstängda i
`AndroidManifest.xml`.

**Konversationsnyckel.** `X25519(egen privat, kontaktens publika)` →
HKDF-SHA256 med salt = de två publika nycklarna i sorterad ordning och
info = `"SHA/v1/conversation-key"` → 256-bitars AES-nyckel. Båda sidor får samma
nyckel. Delade hemligheter som blir noll (low-order points, RFC 7748 §6.1)
avvisas. Nyckeln lämnas ut som ett ogenomskinligt `ConversationKey`-handtag –
nyckelbytes lämnar aldrig modulen.

**Meddelanden.** AES-256-GCM. Kuvert:

```
version (1) || nonce (12) || ciphertext || GCM-tagg (16)
```

Varje `seal` hämtar en ny 96-bitars nonce från en CSPRNG (`Random.secure`).
API:t tar aldrig emot en nonce utifrån, så återanvändning kan inte ske av misstag.
Associerad data (meddelande-id, avsändarens och mottagarens hash, tidsstämpel)
autentiseras, så metadata inte kan ändras utan att dekrypteringen misslyckas.

**Kontrollkod.** Sex siffror från `SHA-256("SHA/v1/verification-code" || sorterade publika nycklar)`.
Båda telefonerna visar samma kod om – och bara om – de har skannat varandras rätta nycklar.

**Loggning.** Inga nycklar, klartexter, nonces eller chiffertexter skrivs till
loggar. `toString()` på nyckeltyper visar bara publik information och
`CryptoException` har fasta meddelanden. `avoid_print` är påslaget och ett test
underkänner `print`/`debugPrint`/`log` i `lib/`.

## Kända begränsningar (MVP)

- Samma nyckel används i båda riktningarna utan ratchet: ingen forward secrecy.
  Slumpmässiga 96-bitars nonces är säkra upp till ~2³² meddelanden per nyckel;
  nyckelrotation (t.ex. Double Ratchet) behövs innan riktig trafik.
- Dart kan inte garantera att minne nollställs. Privata nyckelbytes skrivs över
  där det går, men kopior kan finnas kvar i heapen tills GC.
- Den privata X25519-nyckeln lever i appens minne när den används; Keystore
  skyddar den i vila, inte under körning. Ett nästa steg är att låta nyckelavtalet
  ske i Keystore/StrongBox via en plattformskanal.
- Sexsiffrig kontrollkod (~20 bitar) räcker för jämförelse ansikte mot ansikte,
  men en längre "safety number" bör läggas till.
