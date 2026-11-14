# 0005 – Lagring i prototypen

Status: **Proposed – owner decides.** Skrivet 2026-11-14.

Underlag för grinden G4 i [`docs/ROADMAP.md`](../ROADMAP.md). P3 väntar på
det här beslutet. Ingen kod är ändrad.

## Varför ett beslut behövs

- **0004 §6 rekommenderar en lokal databas** med transaktioner, alternativ
  (a), men beroendet valdes inte där ("väljs senare").
- **§6 sparar mottagna meddelanden och utkorgen**, och de måste vara
  krypterade i vila. Det är 0004 §7 (a), som står under "Efter prototypen"
  i färdplanen.
- **`CLAUDE.md` tillåter inga nya beroenden** som inte står i ett godkänt
  beslutsunderlag.

## Vad som måste sparas i prototypen

Från "Klart när" i färdplanen (punkt 2) och 0004 §6 och §8:

1. Olm-kontot, som pickle.
2. Sessionerna per kontakt, som pickles.
3. Kontakterna: identitetsnyckel, adresseringsnyckel (0004 §3), namn och
   när ni träffades.
4. Visade engångsnycklar och när de visades (0004 §8).
5. Hashar av behandlade paket, i minst 48 timmar (0004 §6).
6. Utkorgen: paketens byte och om de är skickade (0004 §6).
7. Mottagna meddelanden, i alla fall tills appen har visat dem (0004 §6,
   steg 3 och 4).

Pickle-nyckeln ligger redan som egen post i valvet (0004 §6).

**Krav:**
- **Atomiskt:** flera av sakerna ovan ändras i samma skrivning (0004 §6).
- **Krypterat i vila, och inte i backup.**
- **Raderas helt** av `resetIdentity()`.
- **Ingen ny egen kryptografi** (`CLAUDE.md`, "Aldrig").

## Fakta

- **Valvet** krypterar varje post med Keystore-nyckeln (AES-GCM, med
  postens namn som associerad data) och skriver den atomiskt med
  `AtomicFile` (`android/app/src/main/kotlin/se/sha/sha/keystore/KeystoreVault.kt:64-88`).
  - Det är atomiskt för en post, inte för flera.
  - Filerna ligger i `noBackupFilesDir` (`lib/crypto/README.md:40,50-52`).
  - `reset()` raderar alla poster och valvets nyckel
    (`lib/crypto/src/key_vault.dart:17-19`).
- **Ej verifierat:** hur snabbt valvet krypterar en stor post. Ligger
  Keystore-nyckeln i StrongBox, som är ett separat chip, kan det vara
  långsamt. Det är inte mätt.
- **SQLite-paket på pub.dev** (pub.dev API, läst 2026-11-14):
  - `sqlite3` 3.9.1, publicerad 2026-11-08, publisher simonbinder.eu, MIT;
  - `sqflite` 2.4.6, publicerad 2026-11-10, publisher tekartik.com,
    BSD-2-Clause.
  - `sqlite3_flutter_libs` och `sqlcipher_flutter_libs` är markerade som
    avvecklade: "update to version 3.x of package:sqlite3".

## Alternativ

- **(A) Hela tillståndet i en enda valvpost.** Allt i listan ovan sparas
  som en struktur och skrivs om helt vid varje ändring, med
  `KeyVault.write`. Det är 0004 §6, alternativ (c), byggt på valvet.
  - Inget nytt beroende.
  - Ingen ny kryptografi: valvet finns och är testat.
  - Atomiskt, eftersom allt är en `AtomicFile`.
  - `resetIdentity()` raderar det redan.
  - Men allt skrivs om vid varje meddelande, så posten måste vara liten.
  - Farten i StrongBox är inte mätt (se ovan).
  - Det räcker inte för en riktig historik senare.
- **(B) En krypterad tillståndsfil i Dart, med en nyckel i valvet.**
  Tillståndet krypteras med dagens `Aes256Gcm` (`lib/crypto/src/aes_gcm.dart`)
  och en slumpad nyckel som sparas som valvpost. Filen skrivs till en
  tillfällig fil och döps sedan om.
  - Inget nytt beroende, och snabbt.
  - Men det är en ny användning av AES-GCM, alltså 0004 §7 (a). **Kräver
    granskning av kryptoexpert** och märks OGRANSKAT.
  - Den atomiska skrivningen blir egen kod i Dart.
- **(C) SQLite med transaktioner** (`sqlite3` eller `sqflite`), där varje
  rads innehåll krypteras med `Aes256Gcm`.
  - Den räcker för historik senare.
  - Men det är ett nytt beroende med inbyggd kod, som måste godkännas och
    granskas.
  - Det är också 0004 §7 (a), alltså **Kräver granskning av kryptoexpert**,
    och mest kod.

**Rekommendation för prototypen: (A).**
- I P3 mäter Claude hur lång tid en skrivning tar på emulatorn, med ett
  tillstånd för 20 kontakter.
- Tar en skrivning mer än 300 ms stannar Claude och föreslår (B).
- (C) tas upp igen när historiken byggs, efter prototypen.

## Hur mycket av meddelandena som sparas

- **(i) Bara tills de har visats.** Ett mottaget meddelande sparas i
  tillståndet tills appen har visat det, ett skickat tills relayn har tagit
  emot det. Efter en omstart är chatten tom.
- **(ii) De senaste 7 dagarna,** i samma tillstånd.
  - Mer användbart.
  - Men tillståndet blir större, och det är en början på historik.

**Rekommendation för prototypen: (i).** Det uppfyller "Klart när" och 0004
§6, och historiken står under "Efter prototypen".

## Om ägaren väljer (A) och (i)

- **0004 §6:** alternativ (c) gäller för prototypen i stället för (a).
- **0004 §7 och §7 (a):** behövs inte i prototypen. Raden om §7 (a) under
  "Före första utdelning" i färdplanen tas bort.
- **P3** bygger tillståndet. Testerna är krasch efter varje steg (0004 §6),
  `resetIdentity()` och mätningen av farten.

## Ägaren beslutar

1. (A), (B) eller (C) för prototypen.
2. (i) eller (ii).
