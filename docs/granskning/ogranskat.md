# OGRANSKAT-punkterna

Varje punkt är byggd med det rekommenderade alternativet i 0004 och märkt
`OGRANSKAT (0004 §N)` i koden (`CLAUDE.md`, "Ägarens beslut"). Nedan: vad
som är valt, var det finns, och vad granskaren ska ta ställning till.

## §1 – Kontrollkoden på Olm-nycklarna

- **Valt:** appens befintliga funktion (fyra grupper om fem siffror ur
  SHA-256 av de två nycklarna sorterade och sammanslagna), med de två
  Olm-identitetsnycklarna som indata.
- **Var:**
  - `lib/crypto/src/sha_olm_service.dart:628-640` (`verificationDigits`)
  - `lib/crypto/src/olm_service.dart:199`
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
  - `lib/crypto/src/sha_olm_service.dart:273` (`encrypt`), `:320` (`receive`)
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
  - `lib/crypto/src/sha_olm_service.dart:34` (översikt), `:273` (`encrypt`:
    spara före sändning), `:320` (`receive`: hash först, sessioner efter
    nummer, typ 0 sist mot `createInboundSession`, allt sparat i en
    skrivning innan meddelandet lämnas ut), `:548` (pickle-nyckeln), `:561`
    (`_save`), `:603` (feltexten blir en fast typ)
  - `lib/crypto/src/olm_service.dart:149`
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

## Byggs inte i prototypen, men står i listan sist i 0004

- §4 alternativ C (utfyllnad utanför Olm).
- §7: krypteringen av historiken (F3).
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
