# lib/crypto – SHA:s kryptomodul

All kryptografi i appen finns här, plus den native Keystore-koden i
`android/app/src/main/kotlin/se/sha/sha/keystore/`. Resten av appen når den
bara via `package:sha/crypto/crypto.dart`. Modulen importerar inget UI,
Riverpod eller app-kod – enda Flutter-importen är `services.dart` för
plattformskanalen (kontrolleras av `test/security/no_logging_test.dart`).

Bibliotek: [`cryptography`](https://pub.dev/packages/cryptography) för alla
primitiver i Dart, `javax.crypto` + Android Keystore i Kotlin. Inga primitiver
är egenimplementerade.

## Filer

| Fil | Innehåll |
| --- | --- |
| `crypto.dart` | Publikt gränssnitt – det enda appen importerar. |
| `src/crypto_service.dart` | `CryptoService` – gränssnittet. |
| `src/sha_crypto_service.dart` | Standardimplementationen. |
| `src/key_vault.dart` | `KeyVault` – lagring av hemligheter + plattformens slumpkälla. |
| `src/android_keystore_vault.dart` | `KeyVault` via plattformskanalen `se.sha/keystore`. |
| `src/entropy.dart` | Blandad slumpkälla för långlivade nycklar. |
| `src/key_agreement.dart` | X25519 + HKDF-SHA256, riktningsnycklar. |
| `src/aes_gcm.dart` | AES-256-GCM. |
| `src/padding.dart` | Utfyllnad till fasta storlekar. |
| `src/wire_format.dart` | Paketformatet som skickas till reläerna. |
| `src/hashing.dart`, `src/wipe.dart` | SHA-256/HMAC, nollställning av minne. |
| `kotlin/.../KeystoreVault.kt` | Keystore-nyckel och krypterade filer. |
| `kotlin/.../KeystoreChannel.kt` | Kanal mellan Dart och `KeystoreVault`. |

## Hur nycklarna sparas

```
Dart: privat X25519-nyckel (32 byte)
  │  plattformskanal, bara inom appens process
  ▼
Kotlin: AES-256-GCM med Keystore-nyckeln "se.sha.vault.wrap.v1"
  │  AAD = "SHA/vault/v1/<namn>", IV väljs av Keystore
  ▼
noBackupFilesDir/sha_keys/<namn>.bin   (atomisk skrivning)
```

- **Skrivningen är klar eller ger fel.** Posten skrivs till en tillfällig
  fil, som fsyncas och sedan döps om över den gamla med `rename(2)`. Sist
  fsyncas mappen. Misslyckas något steg ger `write` felet `WRITE_FAILED`, och
  den gamla posten finns kvar (0005). Androids `AtomicFile`, som användes
  förut, loggar bara ett misslyckat fsync eller namnbyte.
- **`reset()` raderar nyckeln först** och filerna sedan. Avbryts det, går
  filerna som blev kvar inte att läsa (0004 §6, 0005).
- **Testat på emulatorn** i `integration_test/vault_test.dart`.

- **Omslagsnyckeln skapas inne i Android Keystore** och kan aldrig exporteras.
  Den hamnar i **StrongBox** (separat säkerhetschip) om telefonen har det,
  annars i **TEE**. Den är bunden till appens UID, så andra appar och tjänster
  kan inte använda den.
- **`setUnlockedDeviceRequired(true)`** (Android 9+): nyckeln fungerar inte
  medan telefonen är låst, så en låst telefon som stjäls ger inte ut nyckeln
  ens om någon tar sig förbi Android.
- **Filerna** ligger i appens privata katalog `noBackupFilesDir`: andra appar
  har ingen läsrätt, och katalogen tas aldrig med i backup eller vid
  enhetsöverföring. Backup är dessutom avstängt i manifestet.
- **Namnet är associerad data**, så en krypterad blob kan inte flyttas till en
  annan post.
- **Inget exporterat**: ingen ContentProvider, Service eller Receiver – kanalen
  finns bara inne i appens process.
- **Skyddsnivån redovisas ärligt** (`KeyInfo.securityLevel`): appen visar om
  nyckeln ligger i StrongBox, TEE eller bara i mjukvara, och varnar om
  skärmlås saknas.
- Den privata nyckeln packas upp **bara när den behövs** (när en kontakts
  nycklar tas fram) och nollställs direkt efteråt. Vid start läses bara den
  publika nyckeln.

## Slumptal

Långlivade nycklar (identiteten) tas från två oberoende CSPRNG:er:

```
seed = HKDF-SHA256(ikm = DartRandom.secure(64) || Android SecureRandom(64),
                   info = "SHA/v2/rng/<syfte>")
```

Resultatet är oförutsägbart så länge **någon** av källorna fungerar – det
skyddar mot en bugg i en av implementationerna (som Androids SecureRandom-bugg
2013). Båda källorna seedas av kärnan; detta ger robusthet, inte ”mer
entropi”. Källorna kontrolleras (fel längd, konstant värde eller identiska
utdata ger fel). Nonces för AES-GCM tas från `Random.secure` för varje
meddelande. Keystore väljer själv IV för omslagsnyckeln.

## Konversationer

```
shared = X25519(egen privat, kontaktens publika)      (noll-resultat avvisas)
salt   = min(pkA, pkB) || max(pkA, pkB)
nyckel = HKDF(shared, salt, "SHA/v2/<message-key|mailbox-key>/<L2H|H2L>")
```

Varje riktning har egen meddelandenyckel och egen brevlådenyckel. Ett paket
som ett relä skickar tillbaka till avsändaren går därför inte att dekryptera
(reflektionsattack).

## Paket till reläerna

```
version (1) || brevlåde-id (16) || nonce (12) || chiffertext || GCM-tagg (16)
AAD = version || brevlåde-id
klartext (före kryptering) = padding( {"v":2,"id","t","m"} )
```

- **Brevlåde-id** = `HMAC-SHA256(brevlådenyckel, "SHA/v2/mailbox" || dag)[0..16]`.
  Det är en pseudonym per konversation, riktning och UTC-dygn. Reläet ser
  aldrig identitetshashar eller publika nycklar och kan inte koppla ihop
  brevlådor mellan dagar eller konversationer.
- **Allt annat är krypterat**: meddelande-id, tidsstämpel och text.
- **Utfyllnad** till 256 B, 1 KiB, 4 KiB, 16 KiB eller 64 KiB, så längden inte
  avslöjar innehållet. Utfyllnaden tas bort först efter att GCM-taggen
  verifierats (inget padding-orakel).
- **Repris**: meddelande-id inne i chiffertexten; samma id lagras bara en gång.

## Kontrollkod

20 siffror (4 × 5, ~66 bitar) från
`SHA-256("SHA/v2/verification-code" || sorterade publika nycklar)`.
Med sex siffror kunde en angripare som byter ut en QR-kod ”prova fram” en
nyckel som ger samma kod på några sekunder; med 66 bitar är det inte möjligt.

## Kända begränsningar

- **Ingen forward secrecy än.** Nycklarna bygger på två långlivade
  identitetsnycklar. Om en identitetsnyckel läcker kan alla paket som ett relä
  sparat dekrypteras. Innan riktig trafik bör en granskad Double Ratchet
  (t.ex. libsignal) användas – inte en egen implementation.
- **Nyckelavtalet sker i appens minne.** Keystore skyddar nyckeln i vila men
  stöder inte X25519 på alla Android-versioner, så den packas upp kort i Dart.
- **Dart kan inte garantera nollställning.** Vi skriver över de buffertar vi
  äger, men `cryptography`-paketet och GC kan ha kopior kvar en stund.
- **Brevlåde-id är stabilt under ett dygn**, så reläet kan se att paket under
  samma dygn hör till samma konversation och riktning.
- **Rootad eller komprometterad telefon** kan läsa appens minne. Keystore
  hindrar att nyckeln *exporteras*, men inte att skadlig kod med root-behörighet
  använder appen.
