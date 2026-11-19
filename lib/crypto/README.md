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
| `src/olm_service.dart` | `OlmService` – Olm bakom `CryptoService` (P3). |
| `src/sha_olm_service.dart` | Standardimplementationen: tillståndet i en valvpost. |
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
  fsyncas mappen. Misslyckas något steg ger `write` felet `WRITE_FAILED`
  (0005). Androids `AtomicFile`, som användes förut, loggar bara ett
  misslyckat fsync eller namnbyte.
  - **Efter `WRITE_FAILED`** kan antingen det gamla eller det nya värdet
    läsas: har bara fsync av mappen misslyckats, är namnbytet redan gjort.
    Båda är hela och går att verifiera. Den som anropar måste läsa om i
    stället för att anta något av dem.
- **`reset()` raderar nyckeln först** och filerna sedan. Avbryts det, går
  filerna som blev kvar inte att läsa (0004 §6, 0005).
- **Testat på emulatorn** i `integration_test/vault_test.dart`:
  - en skrivning i en mapp som inte går att skriva i ger fel, och det gamla
    värdet finns kvar;
  - ett namnbyte som misslyckas ger fel, och ingen tillfällig fil blir kvar;
  - en återställning som avbryts efter att nyckeln är raderad lämnar filer
    som inte går att läsa.
  - Ett misslyckat fsync går inte att framkalla i testet och är inte testat.
- **Data från äldre byggen** (`AtomicFile`, `.bin.bak`) läses inte. Appen
  har inte delats ut. `delete` och `reset()` raderar sådana filer.

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

## Olm (P3)

Appen når Olm (vodozemac, 0003) bara via `CryptoService.olm`. Koden är märkt
**OGRANSKAT (0004 §6)** och ska granskas av en kryptoexpert före första
utdelningen.

- **En valvpost, `olm.state.v1`,** innehåller hela tillståndet (0005 (A)):
  kontots pickle, sessionernas pickles per kontakt med sitt nummer (0006
  (b)), hashar av behandlade paket i 72 timmar, utkorgen, mottagna meddelanden
  som inte har visats (0005 (i)) och räknarna för fel. Varje ändring är en
  enda skrivning av hela posten.
- **Pickle-nyckeln** är 32 byte från den blandade slumpkällan, i en egen post
  `olm.pickle-key.v1` (0004 §6). Pickles krypteras av vodozemac med den, och
  valvposten krypteras dessutom av Keystore.
- **Ordningen i 0004 §6:**
  - **Mottagning:** hoppa över ett paket vars hash finns. Försök sedan med
    sessionerna, högst nummer först, och för typ 0 till sist
    `createInboundSession` med kontaktens identitetsnyckel. Spara allt i en
    skrivning, och lämna ut meddelandet först därefter.
  - **Sändning:** kryptera, spara sessionen och paketet i utkorgen i en
    skrivning, och skicka först därefter.
  - **QR-koden:** den nya engångsnyckeln sparas innan den visas.
- **Varje försök börjar från den sparade pickeln.** Ett misslyckat försök
  kastas och sparas aldrig, så det kan inte ändra det som är sparat.
- **Bibliotekets feltext sparas, visas eller loggas aldrig**, eftersom den kan
  innehålla nycklar. Fel blir en fast `OlmReceiveFailure` eller ett fast
  `CryptoException`.
- **Testat:**
  - R1–R7 från spiken mot appens klasser, krascher enligt §6 och
    `resetIdentity()`: `test/crypto/olm_service_cases.dart`;
  - samma tester på Android, plus mätningen i 0005:
    `integration_test/olm_service_test.dart`;
  - för värdtesterna bygger `tool/build_native_host.sh` biblioteket.

### Kontakter och engångsnycklar (P4)

- **QR-koden `shaid:2`** (`lib/features/qr/contact_code.dart`) har
  Olm-identitetsnyckeln, en ny engångsnyckel och adresseringsnyckeln, 32 byte
  var: 136 tecken (0004 §1). Varje visning har en ny engångsnyckel, och den
  sparas innan koden visas.
- **Kontrollkoden** räknas med appens befintliga funktion på de två
  Olm-identitetsnycklarna (OGRANSKAT, 0004 §1).
- **Adresseringsnyckeln** är den statiska X25519-nyckeln och används bara för
  brevlåde-ID (OGRANSKAT, 0004 §3 (A)).
- **Kontakten** sparas i samma valvpost som Olm: identitetsnyckel,
  adresseringsnyckel, namn, när ni träffades, och vilka av kontaktens
  engångsnycklar som redan har gett en session. En engångsnyckel ger högst en
  session (0006).
- **Visade engångsnycklar** som ingen har använt tas bort efter 30 dagar
  (0004 §8 (a)).
- **Gamla sessioner** raderas enligt (iv) i 0009, med 24 h marginal för
  klockor (OGRANSKAT, 0009). En session raderas först när kontakten har
  skrivit på en annan session mer än 72 h efter vårt senaste paket på den,
  och 72 h till har gått. Den vi skickar på, och en med ett paket i
  utkorgen, raderas aldrig. En kontakt som är tyst behåller alla sina
  sessioner. Appen lämnar kontaktens tid `t` till `receive` (`writtenAt`),
  och varje runda anropar `removeOldSessions`.
- **Testat:** `test/crypto/olm_contacts_test.dart` (0006:s tester och
  mutationer), `test/crypto/olm_session_removal_test.dart` (0009:s tester
  och mutationer) och `test/features/contact_code_test.dart`.

### Paketformat 3 och utfyllnad (P5)

```
paket  = 3 (1) || brevlåde-id (16) || Olm-typ (1) || Olm-meddelande
klartext i Olm = utfyllnad( {"v":3,"id","t","m"} )
```

- **Utfyllnad innanför Olm** (`OlmPadding`, 0004 §4 (A)): texten fylls ut
  med mellanslag till exakt B − 1 byte UTF-8, där B är 256, 1 024, 4 096,
  16 384 eller 65 536. Då blir Olms chiffertext exakt B. `encrypt` fyller ut
  och `receive` tar bort mellanslagen i slutet, efter att Olm har kontrollerat
  MAC. Texten i utkorgen och inkorgen är inte utfylld.
- **Paketet** (`PacketV3`, 0004 §5 (a)): `[Olm-typ] || Olm-meddelande` är
  precis det som `encrypt` ger och `receive` tar. Brevlåde-ID:t läggs till när
  paketet skickas. Största paket är 65 712 byte, samma som relayns gräns.
- **JSON-texten** (`lib/features/chat/message_payload.dart`) är version 3 och
  slutar alltid med `}`, så utfyllnaden går att ta bort.
- **OGRANSKAT (0004 §4 och §5):** storleken visar hinken, ett första
  meddelande (typ 0) och långa kedjor utan svar, och huvudet är inte skyddat.
- **Testat:**
  - varje rad i storlekstabellen i 0004 §4 med riktiga Olm-meddelanden, och
    kedjeindex 127, 128 och 16 384: `test/crypto/olm_sizes_test.dart`;
  - utfyllnaden med å och emoji vid gränsen:
    `test/crypto/olm_padding_test.dart`;
  - paketets fält, för korta paket och okänd version eller typ:
    `test/crypto/olm_wire_format_test.dart`;
  - R7 med exakta storlekar körs också på Android.
- **Appen skickar paketformat 3 sedan P6.** Det gamla formatet 2
  (`WireFormat`, `seal`, `open`) används inte längre av appen.

### Inställningar och felräknare (P6)

- **Inställningarna** (serverns adress och intervallet) sparas i samma
  valvpost som allt annat (0005 (A), punkt 9): `appSettings` och
  `saveAppSettings`. De raderas av `resetIdentity()`.
- **Felräknarna** visas samlade i chatten (0004 §10) och tas sedan bort med
  `clearFailureCounts`. Den drar bara av det som visades, så ett fel som
  kom under tiden finns kvar.

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
