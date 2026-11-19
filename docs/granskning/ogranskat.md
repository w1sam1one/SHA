# OGRANSKAT-punkterna

Varje punkt är byggd med det rekommenderade alternativet i 0004, eller med
ägarens val i ett senare beslut, och märkt `OGRANSKAT (0004 §N)` eller
`OGRANSKAT (0009)` i koden (`CLAUDE.md`, "Ägarens beslut", och 0009). Nedan: vad
som är valt, var det finns, och vad granskaren ska ta ställning till.

## §1 – Kontrollkoden på Olm-nycklarna

- **Valt:** appens befintliga funktion (fyra grupper om fem siffror ur
  SHA-256 av de två nycklarna sorterade och sammanslagna), med de två
  Olm-identitetsnycklarna som indata.
- **Var:**
  - `lib/crypto/src/sha_olm_service.dart:937-949` (`verificationDigits`)
  - `lib/crypto/src/olm_service.dart:229`
- **Granska:** att 20 siffror (cirka 66 bitar) räcker mot en angripare som
  tar fram nycklar som ger samma kod, och att funktionen är identisk med den
  gamla (`ShaCryptoService.verificationCode`). Det sista är läst, inte testat
  med en fast testvektor (0004 §11.3).

## §3 (A) – En statisk X25519-nyckel för brevlådorna

- **Valt:** brevlåde-ID tas fram ur en egen X25519-nyckel bredvid Olm, med
  den befintliga HKDF-härledningen. Nyckeln står i QR-koden.
- **Var:**
  - `lib/features/qr/contact_code.dart:35`
  - `lib/crypto/src/key_agreement.dart:93-96`
  - `lib/crypto/src/sha_crypto_service.dart:117`, `:165`
- **Granska:**
  - kontrollkoden omfattar inte adresseringsnyckeln;
  - en ny skanning av en känd kontakt kräver samma adresseringsnyckel
    (`lib/features/qr/scan_screen.dart`);
  - räcker det, eller ska koden omfatta båda?

## §4 – Utfyllnad och vad storleken visar

- **Valt (A):** texten fylls ut med mellanslag till exakt B − 1 byte UTF-8
  innanför Olm, så att chiffertexten blir exakt B.
- **Var:**
  - `lib/crypto/src/olm_padding.dart:18`, `:27`, `:37`
  - `lib/crypto/src/sha_olm_service.dart:289` (`encrypt`), `:355` (`receive`)
- **Storleken visar ändå** hinken, typ 0 (allt före det första svaret, cirka
  106 byte större) och kedjeindex (1 byte till vid 128 och vid 16 384).
  Mätt med riktiga Olm-meddelanden (`test/crypto/olm_sizes_test.dart`).
- **Granska:** är det godtagbart att servern ser typ 0 och långa kedjor utan
  svar?

## §5 – Paketformat 3

- **Valt (a):** `[3][brevlåde-ID 16][Olm-typ 1][Olm-meddelande]`, största
  paket 65 712 byte, Olm version 1 (8 byte MAC).
- **Var:**
  - `lib/crypto/src/olm_wire_format.dart:16`, `:32`, `:52`
  - `relay/limits.go`
- **Granska:**
  - huvudet är inte bundet till innehållet: ett paket kan flyttas till en
    annan brevlåda och märks först när det inte går att läsa;
  - Olm version 1 eller 2 (32 byte MAC).

## §6 – Tillstånd, ordning och krascher

- **Valt (c på valvet, 0005 (A)):** hela tillståndet i en valvpost, skriven
  hel vid varje ändring. Varje försök börjar från den sparade pickeln.
- **Var:**
  - `lib/crypto/src/sha_olm_service.dart:34` (översikt), `:289` (`encrypt`:
    spara före sändning), `:355` (`receive`: hash först, sessioner efter
    nummer, typ 0 sist mot `createInboundSession`, allt sparat i en
    skrivning innan meddelandet lämnas ut), `:856` (pickle-nyckeln), `:869`
    (`_save`), `:912` (feltexten blir en fast typ)
  - `lib/crypto/src/olm_service.dart:175`
  - `android/app/src/main/kotlin/se/sha/sha/keystore/KeystoreVault.kt:76`
    (skrivningen: temporär fil, `fsync`, `rename`, `fsync` av mappen) och
    `:138` (återställningen raderar nyckeln först)
- **Granska:**
  - att ordningen hindrar att ett gammalt läge läses in och att en
    meddelandenyckel används två gånger;
  - att typ 0 först provas mot sparade sessioner;
  - hanteringen av pickle-nyckeln;
  - att en misslyckad skrivning kan ha landat på disk (`KeyVault.write`) och
    att anroparen då läser om.

## 0009 (iv) – Radering av gamla sessioner (F2)

- **Valt (iv), med 24 h marginal för klockor:** en session S hos kontakten
  K raderas bara när
  1. S inte har högst nummer;
  2. inget i utkorgen är krypterat på S;
  3. och 4. K har skrivit ett meddelande på en annan session, enligt K:s
     klocka mer än 48 h + 24 h efter att relayn tog emot vårt senaste paket
     på S (eller efter att S skapades);
  5. det har gått minst 48 h + 24 h på vår klocka sedan vi läste det
     första sådana meddelandet.

  Ett paket som skickas på S efter det nollställer villkor 4. Sessioner
  och paket i utkorgen som sparades före F2 saknar tiderna. De räknas
  försiktigt. För en sådan session räknas vårt senaste paket som skickat
  när tillståndet läses från disken, tills tillståndet sparas igen. Ett paket utan session håller kvar alla
  kontaktens sessioner tills det är skickat.
- **Var:**
  - `lib/crypto/src/sha_olm_service.dart:54` och `:58` (48 h och 24 h), `:328`
    (`markSent`: villkor 3), `:479` (`_markOld`: villkor 4), `:501`
    (`_removeOld`: alla villkor), `:740` (`removeOldSessions`), `:830`
    (tillstånd från före F2), `:872` (varje skrivning kör regeln)
  - `lib/crypto/src/olm_service.dart:189`, `:266`
  - Appen lämnar K:s tid `t` från JSON-texten
    (`lib/features/chat/messaging_service.dart:76`,
    `lib/features/transport/transport.dart:256`), och varje runda kör regeln
    (`transport.dart:286`).
- **Granska:**
  - argumentet i 0009 för att inget meddelande går förlorat;
  - luckorna: en klocka som går mer än 24 h fel, vår egen klocka som
    ställs om, och en relay som håller kvar paket längre än 48 h;
  - att tiden `t` kommer från kontakten själv och bara är skyddad av Olm.
- **Argumentet bygger också på** två saker i appen, som inte får ändras
  utan att regeln ses över:
  - utkorgen skickar i ordning per kontakt: en full brevlåda (507) hoppar
    över resten för den kontakten, och andra fel stoppar allt
    (`lib/features/transport/transport.dart:193`);
  - tiden `t` sätts innan texten krypteras
    (`lib/features/chat/messaging_service.dart:40`), så den är aldrig
    senare än krypteringen.
- **En raderad session** försvinner ur valvposten, men äldre kopior av
  posten kan finnas kvar på flashminnet. De är krypterade med samma
  Keystore-nyckel, och pickle-nyckeln finns kvar, så den som kan använda
  nycklarna kan läsa en sådan kopia fram till `resetIdentity()`. Skyddet i
  0004 §7, att nyckeln är borta, gäller alltså inte här.

## §7 – Historiken (F3, 0010 (B))

- **Valt (B), ägarens beslut, inte det rekommenderade (a) i 0004:**
  historiken ligger i egna valvposter med slumpade namn och valvets egen
  nyckel, inte en nyckel per konversation. Märkt `OGRANSKAT (0004 §7)`.
- **Var:** `lib/crypto/src/sha_olm_service.dart:609` (`_keepInHistory`:
  tillståndet först, posten sedan, ingen dubblett), `:658` (`_pruneHistory`:
  posten raderas först, tillståndet sparas sedan), `:692` (`_readEntry`: en
  skadad post hoppas över).
- **Granska:**
  - en raderad post kan finnas kvar på flashminnet och läsas med valvets
    nyckel tills `resetIdentity()` eller avinstallation; appen lovar bara
    att historiken tas bort ur appen;
  - posterna är per kontakt, så filernas tider och storlekar visar ungefär
    när och hur mycket man skrivit med varje (namnlös) kontakt, och hur
    många kontakter som har historik;
  - ett inkommande meddelandes id i historiken är hashen av paketet, som
    sparas så länge historiken finns (`seen` sparar den bara 72 h).

## Byggs inte i prototypen, men står i listan sist i 0004

- §4 alternativ C (utfyllnad utanför Olm).
- §7 (a): en egen nyckel per konversation för historiken (se ovan).
- Ett yttre AEAD-lager med en hemlighet från QR-koden (0003).

## Annat som granskaren bör känna till

- **Det gamla formatet 2** (AES-256-GCM med X25519 + HKDF, `seal`/`open` i
  `CryptoService`, `WireFormat`) finns kvar i `lib/crypto/`. `seal`, `open`
  och AES-GCM används inte längre av appen, men X25519 + HKDF från samma kod
  tar fram brevlådenycklarna (§3 (A)), och `WireFormat.epochOf` ger dagens
  nummer.
- **Slumptal för långlivade nycklar:** `lib/crypto/src/entropy.dart:44`
  blandar Dart och Android med HKDF-SHA256.
- **`seen`** (hashar av behandlade paket) är gemensam för alla kontakter och
  rensas efter 72 timmar efter väggklockan (granskningen av P3).
