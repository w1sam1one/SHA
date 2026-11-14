# SHA – Secure Human Authentication

Säker meddelandeapp där två personer först **träffas fysiskt** och skannar
varandras QR-koder. Först då kan de skriva till varandra, end-to-end-krypterat.

Det här är MVP-skelettet: Flutter, Android, Riverpod, lokal lagring i minnet
och ingen backend än. Designen följer skisserna i SHA-canvasen
(Identitet · Min QR · Skanna · Kontakter · Chatt).

## Kom igång

```bash
flutter pub get
flutter test          # krypto-, protokoll- och widgettester
flutter analyze
flutter run           # Android-enhet eller emulator (API 24+)
```

Att bygga appen för Android kräver också Rust via `rustup`: Olm-pluginet
`flutter_vodozemac` kompilerar sin Rust-del från källkod vid bygget.
Pluginet bygger med `rustup run stable`, lägger själv till Android-målen och
hämtar Rust-paket från crates.io, så bygget behöver nät. `flutter test` och
`flutter analyze` behöver inte Rust.

Utan kamera (t.ex. emulator), i **debug-bygge**: tryck kopiera-ikonen på
**Min QR** på den ena enheten och använd **Ange kod manuellt** på
skannerskärmen på den andra. I release finns inte dessa – kontakter läggs bara
till genom att man träffas och skannar.

## Struktur

```
lib/
├── crypto/            All kryptografi – se lib/crypto/README.md
│                      (+ android/.../kotlin/se/sha/sha/keystore/)
├── core/              Riverpod-providers för krypto och lagring, id-generator
├── app/               MaterialApp, tema (färger och typsnitt från designen)
├── features/
│   ├── onboarding/    Skapar identiteten vid första start
│   ├── qr/            Min QR, Skanna, QR-formatet, "lägg till kontakt"
│   ├── contacts/      Kontaktlista (i minnet)
│   ├── chat/          Chattlista, chatt, kryptering av meddelanden (i minnet)
│   └── home/          Bottennavigering
└── ui/                Delade widgets (avatar, identicon) och formatering
```

Appen pratar bara med kryptot via `CryptoService` (`lib/crypto/crypto.dart`).
Meddelanden lagras endast som färdiga relä-paket (AES-256-GCM); klartext finns
bara i minnet medan en chatt är öppen (`chatProvider` är `autoDispose`).

Säkerhetsgranskning, hotmodell och nästa steg: [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md).

## QR-format

```
shaid:1:<identitetshash, 64 hex>:<X25519 publik nyckel, base64url>
```

Allt i koden är publikt. Skannern kontrollerar att hashen är SHA-256 av nyckeln,
avvisar din egen kod och ogiltiga nycklar, och visar en gemensam 20-siffrig
kontrollkod som båda ska jämföra innan kontakten läggs till.

## Relä-paket

Meddelanden skickas (i nästa steg) till en pool av relä-servrar. Ett paket är
`version || brevlåde-id || nonce || chiffertext || tagg`. Brevlåde-id:t är en
pseudonym som byts varje dygn och skiljer sig per konversation och riktning;
reläet ser aldrig vem som skickar till vem. Paketen fylls ut till fem fasta
storlekar. Detaljer i `lib/crypto/README.md`.

## Android-härdning

- Privat nyckel krypterad av en icke-exporterbar Keystore-nyckel (StrongBox om
  telefonen har det, annars TEE) som bara fungerar när telefonen är upplåst.
  Filerna ligger i `noBackupFilesDir`, som andra appar inte kan läsa.
- Appen visar var nyckeln skyddas och varnar om skärmlås eller
  säkerhetshårdvara saknas.
- Tangentbordet ombeds att inte lära sig av det du skriver (inkognitoläge).
- `network_security_config.xml`: ingen okrypterad trafik, bara systemets CA:er.
- `allowBackup="false"` och `data_extraction_rules.xml` – ingen moln-backup
  eller enhetsöverföring.
- `FLAG_SECURE` – inga skärmdumpar eller förhandsvisning i "senaste appar".
- Release-bygget begär bara `CAMERA`, inte `INTERNET`.
- Typsnitten (Manrope, JetBrains Mono, SIL OFL) är inbäddade i `assets/fonts/`,
  så appen hämtar ingenting från nätet.

## Nästa steg

- Transport/backend och mottagna meddelanden.
- Double Ratchet (libsignal) för forward secrecy.
- Tor/mixnät och täcktrafik mot reläerna.
- Persistent, krypterad lagring av kontakter och meddelanden.
- App-lås med biometri/PIN.

## Licens

Copyright © 2026 Wisam Husein. Alla rättigheter förbehållna. Ingen del får
användas, kopieras, ändras eller spridas utan skriftligt tillstånd. Se
[`LICENSE`](LICENSE). Typsnitt och paket från andra behåller sina egna licenser.
