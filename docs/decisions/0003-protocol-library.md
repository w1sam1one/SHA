# 0003 – Protokollbibliotek: flutter_vodozemac (Olm)

Status: **Accepted by owner with conditions, 2026-11-13.** Skrivet
2026-11-13.

Underlag för D3 i [0001](0001-protocol-storage-transport.md). Prototypen
finns i [`spike/vodozemac/`](../../spike/vodozemac/README.md). Appen är
inte ändrad.

## Beslut

Beslutat av ägaren 2026-11-13. Avsnittet skriver ner beslutet; inget är
tillagt.

- **D3 godkänns med villkor.** `flutter_vodozemac` (Olm) är SHA:s
  protokollbibliotek.
- **Licens:** `LICENSE` byts till **AGPL-3.0** senast före första
  utdelningen av appen, även till testare via Google Play (se 0002,
  "Licens").
- **Villkor före första utdelningen:**
  1. spiken körd på en riktig telefon (arm64);
  2. granskning av Flutter/Dart-lagret och bygget;
  3. en plan för säkerhetsuppdateringar av beroenden.
- **Ordning:** inkopplingen av Olm i appen får börja först när
  [0004](0004-olm-integration-design.md) är godkänd av ägaren. (0004
  godkändes för en intern prototyp 2026-11-14.)

Resten av dokumentet är underlaget som beslutet bygger på, oförändrat.

## Vad som utreds och varför

Ägarens beslut: utred **flutter_vodozemac** (Olm, samtal mellan två personer).
- **libsignal** utreds inte nu. Dess README säger "Use outside of Signal is
  unsupported" och att "All APIs and implementations are subject to change
  without notice" (läst 2026-10-21, se 0001).
- **Egna bindningar** till Rust-craten utreds inte nu. De ger mer arbete och
  ett nytt lager att granska.

## Fakta (källa, hämtat 2026-11-13)

| Vad | Version | Licens | Källa |
| --- | --- | --- | --- |
| `flutter_vodozemac` (Flutter-plugin, famedly.com) | **0.9.1**, publicerad 2026-11-12 | **AGPL-3.0** (`LICENSE` i arkivet) | pub.dev API; arkivets SHA-256 `9a3503ce…` stämmer |
| `vodozemac` (Dart-paket, famedly.com) | **0.9.1**, publicerad 2026-11-12 | **AGPL-3.0** (`LICENSE` i arkivet) | pub.dev API; SHA-256 `4099e870…` stämmer |
| `flutter_rust_bridge` | 2.13.0 | MIT | pub.dev API |
| `vodozemac` (Rust-crate, matrix-org) | **0.11.2**, 2026-11-05 | **Apache-2.0** | crates.io API; GitHub `Cargo.toml`, `LICENSE` |

- **Craten i pluginet.** Pluginets `rust/Cargo.lock` låser craten till
  0.11.2. Pluginet slår på funktionerna `libolm-compat`, `wasm_js`,
  `insecure-pk-encryption`, `low-level-api` och `experimental-session-config`
  (pluginets `rust/Cargo.toml`). SHA behöver inga av dem.
- **Säkerhetsrättelser i 0.11.2:**
  - panik vid felaktig Ed25519-nyckel;
  - nyckelmaterial som inte nollställdes.

  `flutter_vodozemac` CHANGELOG hänvisar till GHSA-pqp6-f7wc-6498 och
  GHSA-v27v-f96q-qhjq, och craten listar rättelserna i sin CHANGELOG.
  Själva GHSA-sidorna är inte lästa (ej verifierat).
- **Granskning:** cratens README säger "one security audit by Least
  Authority, with no significant findings".
  - Meningen lades till 2024-08-09 (commit `d592dda` i
    matrix-org/vodozemac), så granskningen gjordes före det datumet.
  - Kod från 0.8.0 till 0.11.2 omfattas alltså inte.
  - **Vilken version som granskades är ej verifierat:** rapporten ligger
    på matrix.org, som inte gick att nå.
- **Bygge:**
  - Android och Linux kompilerar Rust-delen från källkod vid bygget, via
    pluginets cargokit. Det kräver Rust.
  - iOS via Swift Package Manager använder en färdigbyggd binär.

## Spikens resultat

Kommandon (Flutter 3.47.7, Rust 1.97.0, Linux x86_64):

```sh
cd spike/vodozemac
flutter pub get --enforce-lockfile
./tool/build_native_host.sh   # pluginets Rust-del, --locked
flutter test                  # 14 tester: All tests passed
```

### Krav för krav

**R1 – QR-innehåll.**
- **Storlek:** 64 byte, Curve25519-identitetsnyckel (32) och en
  engångsnyckel (32). Som text blir det `shaid:2:<base64url>` = **94 tecken**,
  mot `shaid:1` = 116 tecken (som bär 32 byte nyckel plus hashen som
  kontroll).
- **Vad som inte behövs:** Ed25519-nyckeln. Den låter Matrix signera
  enhetsnycklar mot en server; här gör det fysiska mötet det jobbet.
  Engångsnyckelns id behövs inte heller, eftersom mottagaren hittar nyckeln
  i meddelandet.
- **Ny engångsnyckel varje gång:** varje visning av QR-koden behöver en ny
  engångsnyckel, eftersom första meddelandet förbrukar den.

**R2 – Start.**
- Alice skapar en utgående session från Bobs 64 byte och skickar ett
  pre-key-meddelande (typ 0).
- Bob skapar en inkommande session med Alices identitetsnyckel från hennes
  QR och svarar (typ 1).
- Båda läser rätt text, och sessions-id:t är detsamma på båda sidor.

**R3 – 100 meddelanden åt båda håll.**
- **Fungerar:** 2 × 99 meddelanden omkastade inom block om 20, med ett
  meddelande per riktning som aldrig kommer fram. Rätt text kommer ut, och
  det tappade stoppar inget. Ett sent meddelande från en äldre kedja går att
  läsa efter två ratchet-varv.
- **Bibliotekets gränser** (egna tester):
  - Högst **40 överhoppade nycklar per kedja.** Kommer meddelande 41 först
    kan meddelande 0 aldrig läsas: `The message key with the given key can't
    be created, message index: 0`.
  - En lucka på **mer än 2000** avvisas: `The message gap was too big, got
    2001, max allowed 2000`.
  - En helt slumpmässig omkastning av 100 meddelanden gav **44 oläsbara**.
- **Följd för SHA:** relayn lämnar ut paket i ankomstordning (0002), och
  appen måste avkryptera i den ordningen. Omkastning inom 40 meddelanden
  klarar Olm.

**R4 – Det som ska avvisas** (exakt felet från biblioteket, ett
`AnyhowException`):

| Fall | Vad biblioteket gör |
| --- | --- |
| Ändrad ciffertext (byte mitt i eller sist) | `Failed decrypting Olm message, invalid MAC: MAC tag mismatch`. Sessionen fungerar sedan som vanligt. |
| Samma meddelande två gånger | `The message key with the given key can't be created, message index: 0`. |
| Samma första meddelande igen, som ny session | `The pre-key message contained an unknown one-time key: <nyckel>`. |
| Samma första meddelande igen, i befintlig session | `The message key with the given key can't be created, message index: 0`. |
| Första meddelandet från någon annan än den skannade nyckeln | `The given identity key doesn't match the one in the pre-key message: expected <nyckel>, got <nyckel>`. |

Bibliotekets feltexter innehåller nycklar. Appen får aldrig logga eller visa
dem, vilket redan gäller enligt `test/security/no_logging_test.dart`.

**R5 – Båda skannar samtidigt.**
- **Vad som händer:** båda skapar en utgående session och skickar var sitt
  första meddelande. Resultatet blir **två olika sessioner**, och var och en
  finns på båda sidor. Båda fungerar.
- **Regel:** skicka på sessionen med **minsta sessions-id**. Id:t är
  detsamma på båda sidor, så båda väljer samma. Behåll den andra för att
  läsa meddelanden som redan skickats med den.
- **Test:** båda sidor väljer samma session oavsett listans ordning, och
  meddelanden fungerar åt båda håll. Ett meddelande på den andra sessionen
  går fortfarande att läsa.
- **Ingen kryptografi:** regeln jämför bara strängar.

**R6 – Lagring.**
- **Det som fungerar:**
  - Konto och sessioner sparas som krypterade pickles med en 32-byte-nyckel,
    läses in igen och fortsätter skicka (10 meddelanden åt varje håll).
  - Engångsnyckeln från QR-koden överlever en omstart.
- **Fel nyckel eller ändrad pickle:** `The pickle couldn't be decrypted: The
  MAC of the ciphertext didn't pass validation MAC tag mismatch`.
- **Fynd – återställning av gammalt läge:** en kontopickle sparad *innan*
  engångsnyckeln användes godtar samma första meddelande igen. Appen måste
  därför spara kontot direkt efter `createInboundSession` och aldrig läsa in
  ett äldre läge. Backup är redan avstängd.
- **Nyckeln från Keystore-valvet (beskrivning, inte gjort):**
  - Appen skapar 32 slumpbyte med den blandade slumpkällan
    (`MixedEntropy`) och sparar dem som en egen post i `KeyVault`, t.ex.
    `olm.pickle-key.v1`.
  - Posten krypteras av Keystore-nyckeln (StrongBox eller TEE) och fungerar
    bara när telefonen är upplåst.
  - Pickles sparas krypterade med den nyckeln. `resetIdentity()` raderar
    den tillsammans med allt annat.

**R7 – Storlek** (vanligt meddelande, typ 1):

| Tecken | Olm-meddelande | Base64 | SHA i dag: utfyllnad / paket |
| --- | --- | --- | --- |
| 1 | 63 byte (+62) | 84 | 256 / 301 |
| 100 | 159 byte (+59) | 212 | 256 / 301 |
| 1 000 | 1 056 byte (+56) | 1 408 | 1 024 / 1 069 |
| 10 000 | 10 064 byte (+64) | 13 419 | 16 384 / 16 429 |

- **Pre-key-meddelandet** med ett tecken är 168 byte.
- **Olm döljer inte längden:** ciffertexten växer med texten. Tillägget
  var 56–64 byte i mätningen.
- **Utfyllnaden måste ligga kvar i SHA:** antingen utfylld text före Olm,
  eller utfyllnad av Olm-meddelandet i det yttre paketet.
- **API:t tar text (`String`)**, så binär utfyllnad måste kodas som text.
- **1 000 tecken får inte plats i hinken 1 024** med Olms extra 56 byte.
  Hinkstorlekarna måste räknas om.

**R8 – Android.**
- **Värddatorn:** `linux_x64`, Dart 3.13.5, 14 av 14 gröna.
- **Android-emulator i CI:** `.github/workflows/spike-android.yml`,
  körning 43378865772 på commit `bb65d69`, 2026-11-13.
  - ABI **x86_64**, Android **15** (API 35), systemavbild
    `google_apis;x86_64`.
  - Samma 14 tester via `integration_test`: **14 av 14 gröna**
    (`flutter test integration_test/olm_spike_test.dart -d emulator-5554`).
  - Pluginet byggde Rust-delen från källkod för `x86_64-linux-android` och
    `i686-linux-android` ("Precompiled binaries are disabled"). Bygget
    (`assembleDebug`) tog 595 sekunder.
- **Inte visat på Android:** raderna `SPIKE-REPORT` syns inte i CI-loggen.
  Storlekarna i R7 är därför bara mätta på datorn. På emulatorn kördes
  testernas kontroller, till exempel att ciffertexten växer med texten och
  att tillägget ligger mellan 16 och 96 byte.
- **Ej verifierat:** riktig telefon (arm64) och prestanda. Emulatorn kör
  x86_64, och arm64-bygget är inte provat.

### Mutationer

Fyra fel lades med avsikt i `lib/olm_spike.dart`, och alla fångades. Koden
återställdes, och efteråt var 14 av 14 gröna.

| Fel | Föll |
| --- | --- |
| QR-byte i fel ordning | R1, R2, R3 (alla fyra), R4 (två), R7 |
| Sessionsvalet följer listans ordning | R5 |
| Inläsning ignorerar sparat konto | R6 |
| QR-längden kontrolleras inte | R1 |

## Vad som måste ändras i appen om D3 godkänns

Bara beskrivning, ingen kod.

- **QR `shaid:2`:**
  - Identitetsnyckeln (Curve25519) och en ny engångsnyckel per visning,
    64 byte. Identitetshashen kan som i dag vara SHA-256 av
    identitetsnyckeln.
  - Kontakter sparas inte i dag, så det finns inget att migrera. Alla
    måste däremot skanna varandra igen med den nya versionen (D1).
- **Paketformat:**
  - Versionsbyte 3 i stället för 2.
  - Innehållet blir Olm-meddelandets typ och byte i stället för
    AES-GCM-kuvertet.
  - Utfyllnaden (R7) läggs innanför eller utanför Olm, och hinkarna räknas
    om.
- **Brevlåde-ID:n:**
  - I dag kommer de från den statiska X25519-hemligheten (`key_agreement.dart`).
    Olm ger ingen sådan gemensam hemlighet.
  - Antingen behålls dagens härledning bara för adressering, eller så byts
    ett slumpmässigt brevlådefrö i QR-koden.
  - Valet ska granskas som kryptografi.
- **Historik:**
  - Olm raderar meddelandenycklar efter användning. Sparade paket kan
    därför inte läsas igen, och egna skickade meddelanden går aldrig att
    avkryptera.
  - Historiken måste sparas som klartext, krypterad i vila med en egen
    Keystore-skyddad nyckel. Det är D2:s skäl 1 i 0001.
- **20-siffriga kontrollkoden:** samma metod som i dag, men räknad på båda
  Curve25519-identitetsnycklarna. Engångsnyckeln ingår inte.
- **Tillstånd:**
  - Konto och sessioner ändras vid varje meddelande. De måste sparas efter
    varje skickat och mottaget meddelande, och direkt efter en ny session
    (R6).
  - Oanvända engångsnycklar behöver städas.
- **Licens:** `LICENSE` byts till AGPL-3.0 före första utdelningen (0002,
  "Licens").

## Kända brister

- **Inget skydd mot kvantdatorer.** Olm bygger på Curve25519 (X25519). Den
  som spelar in trafik nu kan avkryptera den med en framtida kvantdator.
- **Under 1.0.** Pluginet är 0.9.1 och craten 0.11.2. Cratens CHANGELOG
  har redan nya **BREAKING**-ändringar under "Unreleased".
- **Granskningen gällde Rust-kärnan** och gjordes före 2024-08-09. Den
  omfattar inte:
  - Flutter/Dart-lagret (`flutter_rust_bridge`-koden);
  - bygget (cargokit);
  - de extra funktionerna pluginet slår på;
  - versionerna efter 0.8.0.
- **AGPL-3.0** för båda Dart-paketen (se 0002, "Licens").
- **Leverantörskedjan:** Rust-beroendena hämtas från crates.io vid varje
  bygge, låsta av pluginets `Cargo.lock`.
- **40 överhoppade nycklar per kedja** (R3).

## Öppen fråga för kryptoexpert (implementera inte)

Kan en slumpmässig gemensam hemlighet, utbytt i QR-koden vid det fysiska
mötet, användas i ett **yttre AEAD-lager ovanpå Olm**? Syftet vore att
skydda mot inspelning nu och avkryptering med kvantdator senare.

Risker att bedöma:
- **Statisk hemlighet:** hemligheten ger ingen forward secrecy i det yttre
  lagret. Om telefonen komprometteras faller båda lagren.
- **Mötet:** den som fotograferar QR-koden får hemligheten. Det skyddet
  är inte sämre än i dag, men inte bättre heller.
- **Nonce och nyckelbyte:** hanteringen av nonces och byte av hemligheten
  över tid.
- **Lagring:** hemligheten måste sparas tillsammans med Olm-tillståndet.
- **Egen sammansättning:** konstruktionen är egen kryptografi och måste
  granskas.
- **Brevlåde-ID:n:** hur lagret samverkar med brevlåde-ID:n.
- **QR-kodens storlek:** minst 32 byte till.
- **Vad Olm redan ger:** kontroll av vad Olm skyddar och inte skyddar i
  kombinationen.

## Innan D3 kan godkännas

1. **Licensen:** ägaren godkänner AGPL-3.0 enligt planen i 0002.
2. **Android på riktigt:**
   - körning på en riktig telefon (arm64), inte bara emulator;
   - prestanda på en enkel telefon.
3. **Granskning av Flutter/Dart-lagret och bygget**, eftersom Least
   Authority-granskningen inte omfattar dem.
4. **Beslut om utfyllnad, brevlåde-ID:n och historik** (avsnittet ovan).
   Brevlåde-ID:n och ett eventuellt yttre lager granskas av en
   kryptoexpert.
5. **Uppdateringsplan:** hur biblioteket följs och uppdateras när
   säkerhetsbrister rättas, och hur GHSA-meddelanden bevakas.
6. **Felfall:** vad appen gör när en engångsnyckel saknas, en QR-kod visas
   igen eller ett meddelande inte går att läsa.
