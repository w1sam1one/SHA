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

Utan kamera (t.ex. emulator): tryck kopiera-ikonen på **Min QR** på den ena
enheten och använd **Ange kod manuellt** på skannerskärmen på den andra.

## Struktur

```
lib/
├── crypto/            All kryptografi – se lib/crypto/README.md
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
Meddelanden lagras endast som AES-256-GCM-kuvert; klartext finns bara i minnet
medan en chatt är öppen (`chatProvider` är `autoDispose`).

## QR-format

```
shaid:1:<identitetshash, 64 hex>:<X25519 publik nyckel, base64url>
```

Allt i koden är publikt. Skannern kontrollerar att hashen är SHA-256 av nyckeln,
avvisar din egen kod och visar en gemensam sexsiffrig kontrollkod som båda ska
jämföra innan kontakten läggs till.

## Android-härdning

- Privat nyckel i Android Keystore-skyddad lagring (`flutter_secure_storage`).
- `allowBackup="false"` och `data_extraction_rules.xml` – ingen moln-backup
  eller enhetsöverföring.
- `FLAG_SECURE` – inga skärmdumpar eller förhandsvisning i "senaste appar".
- Release-bygget begär bara `CAMERA`, inte `INTERNET`.
- Typsnitten (Manrope, JetBrains Mono, SIL OFL) är inbäddade i `assets/fonts/`,
  så appen hämtar ingenting från nätet.

## Nästa steg

- Transport/backend och mottagna meddelanden.
- Ratchet för forward secrecy och nyckelrotation.
- Persistent, krypterad lagring av kontakter och meddelanden.
- Nyckelavtal helt inne i Keystore/StrongBox via plattformskanal.
