# 0005 – Lagring i prototypen

Status: **Accepted by owner, 2026-11-14.** Skrivet 2026-11-14.

Underlag för grinden G4 i [`docs/ROADMAP.md`](../ROADMAP.md). Ingen kod är
ändrad här; beslutet byggs i P3.

## Beslut

Beslutat av ägaren 2026-11-14. Avsnittet skriver ner beslutet; inget är
tillagt.

- **Lagring: (A).** Hela tillståndet sparas i en enda valvpost, med kraven
  under "Om ägaren väljer (A) och (i)".
- **Meddelanden: (i).** De sparas bara tills de har visats.
- **Gränsen 300 ms** för en skrivning gäller. Tar en skrivning längre tid i
  mätningen stannar Claude och tar frågan tillbaka till ägaren.

Resten av dokumentet är underlaget som beslutet bygger på. Därifrån är
bara status, inledningen och en rad under "Ägaren beslutar" ändrade, och
efter G5 ([0006](0006-sessionsregeln.md), 2026-11-16) punkterna 2 och 3
och mätningen.

## Varför ett beslut behövs

- **0004 §6 rekommenderar en lokal databas** med transaktioner, alternativ
  (a), men beroendet valdes inte där ("väljs senare").
- **§6 sparar mottagna meddelanden och utkorgen**, och de måste vara
  krypterade i vila. Det är 0004 §7 (a), som står under "Efter prototypen"
  i färdplanen.
- **`CLAUDE.md` tillåter inga nya beroenden** som inte står i ett godkänt
  beslutsunderlag.

## Vad som måste sparas i prototypen

Från "Klart när" i färdplanen (punkt 2), 0004 §2, §6, §8 och §10, och P6 i
färdplanen (punkt 9):

1. Olm-kontot, som pickle.
2. Sessionerna per kontakt, som pickles. För varje session: dess nummer
   från räknaren, som sessionsregeln i 0004 §2 behöver (0006 (b)).
   Räknaren sparas också.
3. Kontakterna: identitetsnyckel, adresseringsnyckel (0004 §3), namn och
   när ni träffades. För varje kontakt också de engångsnycklar från
   kontaktens QR-koder som har gett en session, så att samma nyckel inte
   ger en till (0006).
4. Visade engångsnycklar och när de visades (0004 §8).
5. Hashar av behandlade paket, i minst 48 timmar (0004 §6).
6. Utkorgen: paketens byte, texten och om paketet är skickat (0004 §6).
7. Mottagna meddelanden, i alla fall tills appen har visat dem (0004 §6,
   steg 3 och 4).
8. Räknarna för "kunde inte läsas" och "för sent" per kontakt (0004 §10).
   De sparas i samma skrivning som paketets hash, annars kan ett fel
   försvinna tyst vid en omstart.
9. Inställningarna från P6: hämtningsintervallet och relayns adress.

Pickle-nyckeln ska ligga som egen post i valvet (0004 §6). Det finns ingen
sådan kod än.

**Krav:**
- **Atomiskt:** flera av sakerna ovan ändras i samma skrivning (0004 §6).
  En skrivning som misslyckas får aldrig rapporteras som lyckad, för då kan
  ett gammalt läge läsas in igen (0004 §6, "Varför sparandet måste komma
  före nätet").
- **Krypterat i vila, och inte i backup.**
- **Raderas helt** av `resetIdentity()`, och nycklarna först (0004 §6).
- **Ingen ny egen kryptografi** (`CLAUDE.md`, "Aldrig").

## Fakta

- **Valvet** krypterar varje post med Keystore-nyckeln (AES-GCM, med
  postens namn som associerad data) och skriver den med Androids
  `AtomicFile` (`android/app/src/main/kotlin/se/sha/sha/keystore/KeystoreVault.kt:64-88`).
  - Filerna ligger i `noBackupFilesDir` (`lib/crypto/README.md:40,50-52`).
  - `reset()` raderar först alla filer och sist nyckeln
    (`KeystoreVault.kt:99-111`). Det är omvänt mot vad 0004 §6 kräver.
- **`AtomicFile` säger inte till när något går fel.** `finishWrite` loggar
  bara ett misslyckat fsync och ett misslyckat namnbyte, och kastar inget
  fel. Mappen fsyncas inte heller. Källa: AOSP `main`,
  `core/java/android/util/AtomicFile.java:172-188,338-353` (GitHub-spegeln
  av `platform_frameworks_base`, läst 2026-11-14).
  - Valvets `write()` kan därför rapportera att det lyckades fast det gamla
    innehållet ligger kvar, och ett strömavbrott kan göra namnbytet ogjort.
  - Ej verifierat: att API 35 beter sig som `main`.
- **Valvets Kotlin-kod har inget test på en enhet.**
  `test/crypto/android_keystore_vault_test.dart` testar Dart-sidan mot en
  låtsad kanal, och det finns ingen `androidTest`.
- **Storlek:** koden har ingen gräns för en post, varken i Dart
  (`lib/crypto/src/android_keystore_vault.dart:31-32`) eller i Kotlin.
- **Ej verifierat:**
  - hur stor post Keystore klarar med AES-GCM;
  - hur snabbt det går, särskilt i StrongBox, som är ett separat chip.
  - CI:s emulator har troligen ingen StrongBox (allmän kunskap, inte
    kontrollerat här), så en mätning där säger inget om StrongBox.
- **SQLite-paket på pub.dev** (pub.dev API, läst 2026-11-14):
  - `sqlite3` 3.9.1, publicerad 2026-11-08, utgivare simonbinder.eu, MIT.
    Paketet bygger in SQLite och kan använda SQLCipher eller
    SQLite3MultipleCiphers för att kryptera databasen (README i arkivet,
    rad 8 och 131-132).
  - `sqflite` 2.4.6, publicerad 2026-11-10, utgivare tekartik.com,
    BSD-2-Clause.
  - De äldre paketen `sqlite3_flutter_libs` och `sqlcipher_flutter_libs`
    säger "update to version 3.x of package:sqlite3".

## Alternativ

- **(A) Hela tillståndet i en enda valvpost.** Allt i listan ovan sparas
  som en struktur och skrivs om helt vid varje ändring, med
  `KeyVault.write`. Det är 0004 §6, alternativ (c), byggt på valvet.
  - Inget nytt beroende.
  - Ingen ny kryptografi: valvets AES-GCM med Keystore-nyckeln finns redan.
  - Men valvets skrivning måste göras säker först: fsync och namnbyte
    måste ge fel om de misslyckas, och mappen måste fsyncas. Det är en
    ändring i valvets Kotlin-kod (se "Om ägaren väljer (A) och (i)").
  - Allt skrivs om vid varje meddelande, så posten måste vara liten.
  - Går posten sönder försvinner allt på en gång: kontot, kontakterna och
    sessionerna.
  - Storlek och fart i Keystore är inte mätta (se ovan).
  - Det räcker inte för en riktig historik senare.
- **(B) En krypterad tillståndsfil i Dart, med en nyckel i valvet.**
  Tillståndet krypteras med dagens `Aes256Gcm` (`lib/crypto/src/aes_gcm.dart`)
  och en slumpad nyckel som sparas som valvpost.
  - Inget nytt beroende.
  - Men det är en ny användning av AES-GCM för hela tillståndet, alltså
    0004 §6 (c) gjort i Dart. **Kräver granskning av kryptoexpert**, och
    koden märks OGRANSKAT.
  - Dart behöver sökvägen till `noBackupFilesDir`. Det finns ingen
    `path_provider` i lockfilen, så det kräver en ny metod i den inbyggda
    kanalen.
  - Den atomiska skrivningen blir egen kod, med samma krav på fsync som i
    (A).
  - Farten är inte mätt: `Aes256Gcm` är skriven i ren Dart
    (`lib/crypto/src/aes_gcm.dart:3,21`).
  - Går filen sönder försvinner allt på en gång, som i (A).
- **(C) SQLite med transaktioner** (`sqlite3` eller `sqflite`).
  - SQLite kan själv se till att en transaktion överlever en krasch eller
    ett strömavbrott, men bara med rätt inställningar (till exempel
    `synchronous=FULL`). Ej verifierat här.
  - Den räcker för historik senare.
  - Kryptering antingen per rad med `Aes256Gcm`, eller hela databasen med
    SQLCipher via `sqlite3` (0004 §7 (b)). Båda **kräver granskning av
    kryptoexpert**. Att SQLCipher fungerar på Android här är inte provat.
  - Men det är ett nytt beroende med inbyggd kod, som måste godkännas och
    granskas, och det blir mest kod.

**Rekommendation för prototypen: (A)**, med kraven under "Om ägaren väljer
(A) och (i)".
- **Mätning i P3:** på CI:s emulator mäter Claude både skrivning och
  läsning vid start. Tillståndet har 20 kontakter med 3 sessioner var, 5
  paket i utkorgen på största storlek (cirka 65 kB) och 20 mottagna
  meddelanden.
- **Efter G5** raderas inga sessioner i prototypen (0006 (iii)), så det
  finns ingen övre gräns per kontakt. P4 mäter därför också en skrivning
  med många sessioner för en kontakt, med samma gräns.
- **Gräns:** tar en skrivning mer än 300 ms stannar Claude och tar frågan
  tillbaka till ägaren. 300 ms är vald så att det ska kännas omedelbart att
  skicka; ägaren kan ändra gränsen.
- **StrongBox** har troligen inte emulatorn, så farten där går inte att mäta
  i CI. Den kan visa sig först när prototypen körs på riktiga telefoner
  (G3).
- **(C)** tas upp igen när historiken byggs, efter prototypen.

## Hur mycket av meddelandena som sparas

- **(i) Bara tills de har visats.** Ett mottaget meddelande sparas tills
  appen har visat det, ett skickat tills relayn har tagit emot det. Efter
  en omstart är chatten tom.
- **(ii) De senaste 7 dagarna,** i samma tillstånd.
  - Mer användbart.
  - Men tillståndet blir större, och det är en början på historik.

**Rekommendation för prototypen: (i).** Det uppfyller "Klart när" och 0004
§6, och historiken står under "Efter prototypen".

## Om ägaren väljer (A) och (i)

- **Valvet ändras i P3:**
  - skrivningen ger fel om fsync eller namnbytet misslyckas, och mappen
    fsyncas;
  - `reset()` raderar nyckeln först och filerna sedan;
  - ett nytt emulatortest för valvet: skriva, läsa, återställa, en stor
    post, att en misslyckad skrivning ger fel, och att poster som blev kvar
    efter en avbruten återställning inte går att läsa.
- **0004 §6:** alternativ (c) gäller för prototypen i stället för (a).
  Raden om §6 under "Före första utdelning" i färdplanen säger då att
  prototypen använder §6 (c) på valvet, så att kryptoexperten granskar
  det.
- **0004 §7 och §7 (a)** behövs inte i prototypen. Raden om §7 (a) under
  "Före första utdelning" tas bort.
- **P3** bygger tillståndet. Testerna är:
  - krasch efter varje steg (0004 §6);
  - att `resetIdentity()` lämnar inget kvar;
  - mätningen ovan.

## Ägaren beslutar

1. (A), (B) eller (C) för prototypen.
2. (i) eller (ii).

Beslutat 2026-11-14: (A) och (i), se "Beslut" överst.
