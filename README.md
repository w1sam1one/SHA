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
hämtar Rust-paket från crates.io, så bygget behöver nät.

`flutter test` behöver två saker som byggs först (som i CI):
- `./tool/build_native_host.sh`: Olm-biblioteket för datorn (Rust), för
  Olm-testerna;
- `./tool/build_relay.sh`: relayn (Go), för testerna av hela kedjan i
  `test/chain/`.

`flutter analyze` behöver inget av det.

Så provar du prototypen med två telefoner: [`docs/prototyp.md`](docs/prototyp.md).

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
│   ├── contacts/      Kontaktlistan (sparas i Olm-tillståndet)
│   ├── chat/          Chattlista, chatt, meddelandets JSON-text, felraderna
│   ├── transport/     Servern: klienten, hämtningen och inställningarna
│   ├── settings/      Serverns adress och hur ofta appen hämtar
│   └── home/          Bottennavigering
└── ui/                Delade widgets (avatar, identicon) och formatering
```

Appen pratar bara med kryptot via `CryptoService` (`lib/crypto/crypto.dart`).
Meddelanden krypteras med Olm. På disk finns ett meddelande bara tills det
har skickats eller visats (0005 (i)); sedan finns texten bara i minnet tills
appen stängs.

Säkerhetsgranskning, hotmodell och nästa steg: [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md).

## QR-format

```
shaid:2:<96 byte, base64url utan "=">
```

De 96 byten är Olm-identitetsnyckeln, en ny engångsnyckel och
X25519-nyckeln för brevlådorna (0004 §1). Allt i koden är publikt. Båda
jämför en 20-siffrig kontrollkod innan kontakten läggs till.

## Paket till servern

Ett paket är `3 || brevlåde-id || Olm-typ || Olm-meddelande` (0004 §5).
Brevlåde-id:t är en pseudonym som byts varje dygn och skiljer sig per
konversation och riktning; servern ser aldrig vem som skickar till vem.
Texten fylls ut till fem fasta storlekar innan Olm krypterar den. Detaljer i
`lib/crypto/README.md` och `relay/README.md`.

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
- Release-bygget begär `CAMERA` och `INTERNET`, inget annat i appens eget
  manifest.
  - `CAMERA` behövs bara för att skanna QR-koder.
  - `INTERNET` behövs bara för servern som du själv ställer in under
    Inställningar (P6, 0002). Appen lämnar och hämtar krypterade paket där,
    bara över `https` och bara medan appen är öppen. Inga notiser, inga
    konton. Ingen annan kod i appen använder nätet.
- Typsnitten (Manrope, JetBrains Mono, SIL OFL) är inbäddade i `assets/fonts/`,
  så appen hämtar ingenting från nätet.

## Nästa steg

- Se [`docs/ROADMAP.md`](docs/ROADMAP.md). Olm, kontakter som sparas och
  servern finns sedan P3–P6.
- Tor/mixnät och täcktrafik mot servern.
- App-lås med biometri/PIN.

## Licens

Copyright © 2026 Wisam Husein. Alla rättigheter förbehållna. Ingen del får
användas, kopieras, ändras eller spridas utan skriftligt tillstånd. Se
[`LICENSE`](LICENSE). Typsnitt och paket från andra behåller sina egna licenser.
