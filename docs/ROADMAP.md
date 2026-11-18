# Färdplan: från prototyp till version 1.0

Den här filen styr vad Claude bygger härnäst, enligt [`CLAUDE.md`](../CLAUDE.md).
Paketen görs i ordning, fas för fas, utom enligt sista punkten nedan. En
grind betyder att ägaren måste göra något innan arbetet med det som beror på
grinden fortsätter. "Klart när" i `CLAUDE.md` ("Målet") betyder fas 1.

Arbetssätt (ägarens instruktion 2026-11-16, utöver `CLAUDE.md`):
- `CLAUDE.md` gäller i allt. Inget här ändrar "Aldrig", utom PR:en vid G8,
  som Claude förbereder när ägaren ber om det och som bara ägaren mergar.
- PR:er som rör utdelning, till exempel butikstexter och versionsnummer i
  fas 3, mergar bara ägaren (`CLAUDE.md`, "Aldrig").
- Vid varje grind skriver Claude steg för steg, på enkel svenska, vad ägaren
  ska göra.
- Nya val som ändrar säkerheten blir beslutsunderlag och grindar, som
  hittills.
- Medan Claude väntar på ägaren vid en grind får Claude göra andra paket som
  inte beror på den.

## Fas 1 – Intern prototyp

### Klart när

Prototypen är klar när allt detta gäller:

1. Två appinstanser som har skannat varandras QR-koder kan skicka och ta
   emot krypterade meddelanden via relayn.
2. Identitet, kontakter och Olm-sessioner finns kvar efter att appen har
   startats om.
3. Testplanen i 0004 §11 är grön i CI, även på Android-emulatorn. Körning på
   en riktig telefon ingår inte här, se G3.
4. Ägaren bygger själv en debug-APK enligt `docs/prototyp.md` och
   installerar den (0007 (b)). CI laddar inte upp någon APK. Punkten är
   uppfylld först när ägaren har byggt den.
5. `docs/prototyp.md` beskriver hur ägaren sätter upp relayn och provar med
   två telefoner.

### Paket

- [x] **P0 – Styrning.** `CLAUDE.md` och den här filen.
- [x] **P1 – 0004 godkänd.** Merga PR #8. Skriv in ägarens beslut i 0004:
  status, merge-reglerna i §12 enligt `CLAUDE.md`, och listan över
  OGRANSKAT-punkter under "Före första utdelning" nedan.
- [x] **P2 – Olm i bygget.** `flutter_vodozemac` med exakt samma version som
  spiken i appens `pubspec.yaml`. Rust i CI. Ett Android-emulatorjobb för
  appen, som `spike-android.yml`. Ingen funktion i appen ändras.
- [x] **P3 – Olm bakom `CryptoService`.** Konto, sessioner och pickles, med
  pickle-nyckeln i `KeyVault` (0003 R6, 0004 §6). Ordningen vid krascher
  enligt §6, OGRANSKAT. `resetIdentity()` raderar allt. Spikens R1–R7 som
  tester mot appens klasser. Enligt 0005 (A) och (i):
  - Först görs valvet säkert: skrivningen ger fel om fsync eller namnbytet
    misslyckas, mappen fsyncas, och `reset()` raderar nyckeln först.
  - Valvet får ett emulatortest: skriva, läsa, återställa och en stor post.
    En misslyckad skrivning ger fel, och poster som blev kvar efter en
    avbruten återställning går inte att läsa.
  - Hela tillståndet sparas som en enda valvpost, och meddelanden bara
    tills de har visats.
  - Tester: krasch efter varje steg i §6, och att `resetIdentity()` lämnar
    inget kvar.
  - Skrivning och läsning mäts på emulatorn. Tar en skrivning mer än
    300 ms stannar Claude och frågar ägaren.
- [x] **P4 – Mötet och kontakten.** QR-koden `shaid:2` och kontrollkoden
  (§1, OGRANSKAT). Adresseringsnyckel och brevlåde-ID enligt §3 (A), OGRANSKAT.
  Sessionsregeln enligt 0006 (b) och (iii): den senast aktiva sessionen,
  ordnad med en räknare, och inga sessioner raderas. En engångsnyckel som
  redan har gett en session med kontakten ger aldrig en till. Testerna och
  de två mutationerna i 0006, plus en mutation som låter samma
  engångsnyckel ge en andra session. P4 mäter också en skrivning med många
  sessioner för en kontakt; tar den mer än 300 ms stannar Claude och frågar
  ägaren. Texterna i §10 är godkända (2026-11-16).
  Engångsnycklar (§8), med 30 dagar för oanvända nycklar tills ägaren
  väljer antal dagar. Kontakterna sparas i tillståndets valvpost (0005 (A)).
- [x] **P5 – Paketformat version 3.** Format och utfyllnad (§4, §5). Relayns
  största paketstorlek i `relay/limits.go` och dess tester.
- [x] **P6 – Transport.** En relay-klient utan nytt beroende (`dart:io`).
  Hämtning enligt §9 (b). Intervallet 1, 5, 15 eller 60 minuter i
  inställningarna. Felfall och texter enligt §10 (godkända 2026-11-16) och
  0002. I allt användaren ser heter relayn "servern", även i
  `lib/ui/technical_info_sheet.dart` ("reläer", "Ett relä"). `INTERNET` i
  release-manifestet, med motivering i README. Serverns adress går att
  ställa in.
- [x] **P7 – Hela kedjan i CI.** Två klienter mot en riktig relay: svaren
  204, 507 och 429, dubbletter, krascher och mutationer (§11).
- [x] **P8 – Leverans till ägaren.** `docs/prototyp.md`, med hur ägaren
  bygger debug-APK:n själv (0007 (b)) och sätter upp relayn. Stegen för
  bygget är **ej provade**: appen har aldrig byggts för en riktig telefon.

### Grindar (bara ägaren)

- **G1 – Aktivera.** Merga PR:en med `CLAUDE.md`. Innan dess gör den
  schemalagda körningen ingenting.
- **G-P8 – Hur APK:n når ägaren. Klar 2026-11-18.** Ägaren valde (b) i
  [0007](decisions/0007-debug-apk-som-ci-artefakt.md): ägaren bygger APK:n
  själv, och CI laddar inte upp någon.
- **G2 – Relayn på riktigt.** Efter P8: hyr en VPS i EU och sätt upp relayn
  enligt `relay/README.md`. Claude kan hjälpa till steg för steg.
- **G3 – Två riktiga telefoner.** Prova prototypen. Kör även spiken på en
  arm64-telefon (villkor 1 i 0003).
- **G4 – Lagring (före P3). Klar 2026-11-14.** Ägaren valde (A) och (i) i
  [0005](decisions/0005-lagring-i-prototypen.md): hela tillståndet i en enda
  valvpost, meddelanden sparas bara tills de har visats, och gränsen 300 ms
  för en skrivning.
- **G5 – Sessionsregeln (före P4). Klar 2026-11-16.** Ägaren valde (b) och
  (iii) i [0006](decisions/0006-sessionsregeln.md): appen skickar på den
  senast aktiva sessionen, ordnad med en räknare, och inga sessioner raderas
  i prototypen.

## Fas 2 – Klar för första utdelning (bara till testare)

### Klart när

Fas 2 är klar när allt detta gäller:

1. Alla OGRANSKAT-punkter är granskade av en kryptoexpert (G6), och fynden är
   rättade (F8).
2. Telefontesterna (G3, med protokollet i F6) är godkända av ägaren.
3. `LICENSE` är AGPL-3.0 (G8).
4. CI är grön.

Allt under "Före första utdelning" nedan ska då också vara gjort.

### Paket

- [x] **F1 – Granskningspaket.** `docs/granskning/` med:
  - en hotmodell;
  - alla OGRANSKAT-punkter, med fil och rad;
  - vad som är testat och hur;
  - öppna frågor till kryptoexperten.

  Ett motsvarande paket för granskningen av Flutter/Dart-lagret och bygget.
- [ ] **F2 – Radering av gamla sessioner** enligt (iv) i
  [0009](decisions/0009-radering-av-gamla-sessioner.md), märkt
  `OGRANSKAT (0009)`. Beslutsunderlaget och grinden är klara.
- [ ] **F3 – Historik i version 1** (0004 §7, 0005 (C) eller (ii)). Först ett
  beslutsunderlag och en grind, sedan bygget om ägaren vill ha det.
- [ ] **F4 – App-lås med PIN eller biometri** (README, "Nästa steg"). Först
  ett beslutsunderlag och en grind, sedan bygget.
- [ ] **F5 – Ärliga texter för en fungerande app:**
  - förhandsvarningen (`lib/features/chat/chat_screen.dart`, "Förhandsversion")
    tas bort när transporten fungerar, liksom de andra texterna som då
    inte stämmer: "Finns inte än" i `lib/ui/technical_info_sheet.dart` och
    §7 i `docs/release.md`;
  - en enkel förklaring i appen av vad servern ser, och rekommendationen om
    VPN (0002, "Formuleringar i appen");
  - en licenssida med alla tredjepartslicenser: typsnitten, AGPL- och
    Apache-paketen.
- [x] **F6 – Testprotokoll för två riktiga telefoner** (`docs/testprotokoll.md`):
  steg, förväntat resultat och en ruta för ägarens resultat. Med en mätning
  av farten i StrongBox och ett test med TalkBack.
- [x] **F7 – Relayn i drift:**
  - härdning och driftinstruktioner för en riktig VPS: förnyelse av TLS,
    uppdateringar och övervakning utan IP-adresser;
  - svar eller beslutsunderlag för de öppna frågorna i 0002 som påverkar
    version 1.
- [ ] **F8 – Rätta alla fynd** från granskningarna (G6) och telefontesterna
  (G3).

### Grindar (bara ägaren)

- **G6 – Kryptoexperten.** Hitta en kryptoexpert och låt hen granska F1.
  Fynden blir F8.
- **G7 – Säkerhetsuppdateringar.** Slå på Dependency graph, Dependabot alerts
  och security updates, och godkänn planen i 0004 §12.
- **G8 – AGPL och öppen källkod.** Repot görs publikt för insyn (ägarens
  beslut 2026-11-18), men koden är "All rights reserved" och får inte
  kopieras eller delas ut. `LICENSE` byts till AGPL-3.0 före första
  utdelningen av appen. När ägaren säger till förbereder Claude en PR som
  byter `LICENSE`, uppdaterar README och 0002, och lägger till CONTRIBUTING
  med ett förslag på CLA. Bara ägaren mergar den.
- **Besluten i F2, F3 och F4. Klara 2026-11-18.**
  - F2: (iv) i [0009](decisions/0009-radering-av-gamla-sessioner.md), med
    24 h marginal för klockor.
  - F3: (B) i [0010](decisions/0010-historik-i-version-1.md), 30 dagar som
    standard, med valen Spara inte, 7 dagar, 30 dagar och 1 år.
  - F4: (B) i [0011](decisions/0011-app-las.md). Steg 1 i version 1, med 5
    minuter i bakgrunden. Steg 2 först efter telefontester och G6.
- **Besluten i F7. Klara 2026-11-18.** Ägaren valde i
  [0008](decisions/0008-oppna-fragor-i-0002.md) att VPN-texten används (den
  behövs för F5) och att paket som försvinner vid en omstart godtas för
  version 1.
- **QR-skannern och AGPL (F5). Klar 2026-11-18.** Ägaren valde (C1) i
  [0012](decisions/0012-qr-skannern-och-agpl.md): `zxing2` med `camera`
  ersätter `mobile_scanner` och ML Kit. Bygget görs i en egen PR inom F5,
  och licenserna för Android-biblioteken på licenssidan tas fram efter
  det.

## Före första utdelning

Inget av detta behövs för prototypen, men allt behövs innan appen ges till
någon annan än ägaren (0003, 0004 §13):

- En kryptoexpert har granskat alla OGRANSKAT-punkter och listan sist i
  0004. OGRANSKAT-punkterna, som byggs i prototypen med det rekommenderade
  alternativet och märks `OGRANSKAT (0004 §N)` i koden:
  - **§1** – kontrollkoden räknas med dagens funktion på
    Olm-identitetsnycklarna (P4).
  - **§3 (A)** – en separat statisk X25519-nyckel för brevlåde-ID:n.
    Kontrollkoden omfattar inte adresseringsnycklarna (P4).
  - **§4** – storleken visar typ 0 (allt före det första svaret) och
    kedjeindex (P5).
  - **§5** – paketets huvud är inte bundet till innehållet, och Olm version
    1 med 8 byte MAC används (P5).
  - **§6** – ordningen vid krascher, pickles och pickle-nyckeln, att typ 0
    först provas mot sparade sessioner, och att varje försök börjar från den
    sparade pickeln (P3). Prototypen använder §6 (c) på valvet: hela
    tillståndet i en enda valvpost (0005).
  - Byggs inte i prototypen men står också i listan sist i 0004: §4
    alternativ C, §7 (historiken) och ett yttre lager.
- En raderingsregel för gamla sessioner (0004 §2, F2): (iv) i 0009, märkt
  `OGRANSKAT (0009)` och granskad av kryptoexperten (G6). I prototypen
  raderas inga sessioner, och utan en regel ligger gamla sessioners nycklar
  kvar i riktiga användares telefoner.
- Flutter/Dart-lagret och bygget är granskade (F1, G6).
- Planen för säkerhetsuppdateringar (0004 §12) är godkänd, och Dependabot
  alerts och security updates är påslagna (G7).
- `LICENSE` är bytt till AGPL-3.0 (G8).
- Varje bibliotek i APK:n går att dela ut under AGPL-3.0 tillsammans med
  `flutter_vodozemac`, och licenssidan visar dem alla (0012).
- Spiken och appen är körda på en riktig arm64-telefon (G3, F6).
- Rust i Android-bygget är låst och cargo körs med `--locked`, eller så har
  ägaren, efter granskningen av bygget, godtagit att det inte är det (0004
  §12, §13). I
  dag bygger cargokit med CI-maskinens `stable`, och att ändra det kräver
  ett ändrat plugin.

## Fas 3 – Version 1.0 på Google Play

### Klart när

Version 1.0 är publicerad i produktion på Google Play.

### Paket

- [ ] **F9 – Play-kraven.** Kontrollera kraven mot Googles egna sidor, med
  datum:
  - målnivån (target SDK);
  - testkraven för nya konton;
  - Data safety och integritetspolicyn.

  Höj Flutter-versionen i en egen PR om det behövs.
- [ ] **F10 – Integritetspolicy och Data safety.** Ett utkast till
  integritetspolicy på svenska och engelska, och svaren till Data safety.
  Bara det koden faktiskt gör, med fil som källa.
- [ ] **F11 – Butikstexter och skärmbilder.** Butikstexter som inte lovar mer
  än appen gör. Ett sätt att ta skärmbilder som bara finns i debug och aldrig
  i release, där `FLAG_SECURE` alltid gäller.
- [ ] **F12 – Version och ändringslogg.** Versionsnummer, ändringslogg och
  `docs/release.md` uppdaterade.

### Grindar (bara ägaren)

- **G9 – Utvecklarkonto och nyckel.** Skapa utvecklarkontot,
  uppladdningsnyckeln och `key.properties`.
- **G10 – Integritetspolicyn på webben.** Publicera integritetspolicyn på en
  webbadress.
- **G11 – Släppet.** Internt test, sedan stängt test (med kraven från F9),
  sedan ansökan om produktion och släpp.

## Efter version 1

- iOS.
- Tor eller liknande, och flera relays.
- Gruppchattar.
- Ett kvantsäkert lager (frågan till kryptoexperten i 0003).

## Logg

Nyast först. En rad per paket eller körning som ändrar något.

- 2026-11-18 – Inför att ägaren gör repot publikt: en varning överst i
  README (ogranskad prototyp, All rights reserved), `SECURITY.md` om att
  rapportera säkerhetsbuggar privat, och samma sak om licensen i
  `CLAUDE.md` ("Målet"), G8 och 0002. Den schemalagda körningen litar bara
  på ägarens egna PR:er och kommentarer, och 0007 säger att CI-artefakter
  inte används. `LICENSE` är oförändrad. Ägaren mergar.
- 2026-11-18 – Ägarens beslut inskrivna: 0007 (b), ägaren bygger APK:n
  själv, så "Klart när" punkt 4 är ändrad och P8 är klar. 0008: VPN-texten
  används (även i 0002), och paket som försvinner vid en omstart godtas.
  0009 (iv) med 24 h marginal, 0010 (B) med 30 dagar som standard, och 0011
  (B) med steg 1 i version 1 (5 minuter) och steg 2 efter telefontester och
  G6. Stegen för att bygga APK:n är ej provade.
- 2026-11-18 – Ägaren valde (C1) i 0012: `zxing2` 0.2.4 med `camera`
  0.12.2 ersätter `mobile_scanner`.
- 2026-11-17 – CI använder färre Actions-minuter
  ([0013](decisions/0013-ci-minuter.md)), efter att budgeten tog slut kl.
  10:04 UTC. Ett nytt jobb, `changes`, väljer jobb efter de ändrade
  filerna: en PR med bara dokument kör bara en snabb kontroll. `concurrency`
  per gren, och cacher för pub, Cargo och Gradle med `actions/cache` 6.1.0
  (ett nytt beroende). Ägaren mergar.
- 2026-11-17 – Rättningar efter den andra oberoende granskningen av fas 2
  (PR #35): villkor 5 i 0009 räknas från det första meddelandet som
  uppfyller villkor 4 (`qualifiedAt`), så att en aktiv chatt inte stoppar
  raderingen, och vår egen klocka står bland luckorna. Steg 3.8 i
  testprotokollet går nu att göra (B väntar med adressen). Skräp i format 3
  kan visa tre olika rader (0008 (i), hotmodellen, fråga 12). nginx-loggen
  högst upp i filen, `sudo -i` och `--run-deploy-hooks` i `relay/DRIFT.md`;
  `docs/prototyp.md` pekar dit. API 28 och `FingerprintManager` i 0011,
  och antagandet om Keystore i 0010.
- 2026-11-17 – Rättningar efter den oberoende granskningen av fas 2:
  TLS och minnet i `relay/DRIFT.md` (port 80 för certbot, `GOMEMLIMIT`),
  rad (i) i 0008, ett femte villkor i 0009 efter ett motexempel, (B2) med
  en nyckel per post i 0010, API-nivåer och minSdk i 0011, och mindre fel i
  F1, F6 och F5.
- 2026-11-17 – F5: beslutsunderlaget
  [0012](decisions/0012-qr-skannern-och-agpl.md) om QR-skannern. ML Kit i
  `mobile_scanner` är inte öppen källkod, och `flutter_vodozemac` har
  AGPL-3.0 utan undantag, så det ser ut som en konflikt redan vid första
  utdelningen. Rekommendation: (C1), `zxing2` med `camera`, en skanner i
  ren Dart, med `RECORD_AUDIO` och `WRITE_EXTERNAL_STORAGE` borttagna ur
  manifestet. En ny grind och en ny punkt under "Före första utdelning".
- 2026-11-17 – F5, första delen: en licenssida under Inställningar ›
  Licenser, med Dart-paketen (bland dem AGPL-3.0 för flutter_vodozemac och
  vodozemac), de två typsnitten (SIL OFL) och de 129 Rust-paketen för
  Olm-biblioteket för Android (`tool/rust_licenses.py`; några används bara
  vid bygget). Förhandsvarningen och "Finns inte än" rättades redan i P6.
  Kvar: VPN-texten (väntar på 0008), §7 i `docs/release.md` (en PR som
  ägaren mergar), och licenserna för Android-biblioteken som
  `mobile_scanner` drar in (ML Kit med Googles villkor, CameraX,
  kotlinx-coroutines, AndroidX), som Flutter inte samlar in.
- 2026-11-17 – F4, första steget: beslutsunderlaget
  [0011](decisions/0011-app-las.md) om app-lås. Rekommendation: (B),
  telefonens eget lås med plattformens `BiometricPrompt`, utan nytt
  beroende. Bygget väntar på ägarens beslut.
- 2026-11-17 – F3, första steget: beslutsunderlaget
  [0010](decisions/0010-historik-i-version-1.md) om historik i version 1.
  Rekommendation efter granskningen: (B2), egna valvposter med en egen
  nyckel per post och en gräns som användaren väljer. Bygget väntar på
  ägarens beslut.
- 2026-11-17 – F2, första steget: beslutsunderlaget
  [0009](decisions/0009-radering-av-gamla-sessioner.md) om när gamla
  sessioner får raderas. Rekommendation: (iv), radera bara när kontakten
  bevisligen har gått vidare. Bygget väntar på ägarens beslut.
- 2026-11-17 – F7 klar: `relay/DRIFT.md` (härdning, systemd, TLS med
  certbot, uppdateringar och övervakning utan IP-adresser; ej provat på en
  riktig server) och beslutsunderlaget 0008 med svar på de öppna frågorna i
  0002. Två beslut väntar på ägaren.
- 2026-11-17 – F6 klar: `docs/testprotokoll.md` med steg, förväntat
  resultat och en ruta för ägarens resultat, inklusive TalkBack och farten i
  valvet på en riktig telefon. Ägaren fyller i det vid G3.
- 2026-11-17 – F1 klar: granskningspaketet i `docs/granskning/`
  (hotmodell, alla OGRANSKAT-punkter med fil och rad, vad som är testat,
  frågor till kryptoexperten, och underlaget för granskningen av
  Flutter/Dart-lagret och bygget). Det används vid G6.
- 2026-11-16 – P8, första delen: `docs/prototyp.md` (servern, APK:n, två
  telefoner) och beslutsunderlaget 0007 om att ladda upp debug-APK:n från
  CI. Ny grind G-P8: P8 väntar på ägarens beslut.
- 2026-11-16 – P7 klar: `test/chain/relay_chain_test.dart` kör två appar
  mot den riktiga relayn i CI (`tool/build_relay.sh`, Go i Flutter-jobbet):
  204, 507 och 429, dubbletter, en krasch efter att relayn tog paketet och
  en misslyckad skrivning hos mottagaren. Mutationer: fel brevlåda och ingen
  kontroll av dubbletter fångas.
- 2026-11-16 – P6 klar: appen skickar och hämtar via servern. En
  relay-klient med `dart:io`, varje brevlåda vid en egen slumpad tid i
  intervallet (§9 (b)), bara när appen är öppen, och `Retry-After` vid 429.
  Chatten använder Olm, paketformat 3 och texterna i §10. Serverns adress
  och intervallet (1, 5, 15 eller 60 minuter) ställs in i appen och sparas i
  Olm-tillståndets valvpost (0005, punkt 9). `INTERNET` i release-manifestet.
- 2026-11-16 – P5 klar: paketformat 3 och utfyllnad innanför Olm
  (OGRANSKAT, 0004 §4 (A) och §5 (a)). Alla rader i storlekstabellen stämmer
  med riktiga Olm-meddelanden, och kedjeindex 16 384 är nu mätt. Relayns
  största paket är 65 712 byte, provat även bakom nginx. Appen kopplas om
  i P6.
- 2026-11-16 – P4 klar: QR-koden `shaid:2` (136 tecken), kontrollkoden på
  Olm-nycklarna och adresseringsnyckeln (OGRANSKAT, §1 och §3 (A)).
  Kontakterna sparas i Olm-tillståndets valvpost. Sessionsregeln enligt
  0006 (b) och (iii), med en engångsnyckel per session, och oanvända
  engångsnycklar tas bort efter 30 dagar. 0006:s tester och fyra mutationer.
  En session väger 3,8 kB efter 30 meddelanden. Mätningen med 50 sessioner
  för en kontakt skrivs ut av emulatortestet.
- 2026-11-16 – P3 klar: Olm bakom `CryptoService.olm` (OGRANSKAT, 0004 §6).
  Hela tillståndet i valvposten `olm.state.v1` och pickle-nyckeln i en egen
  post. Ordningen vid mottagning, sändning och QR-koden följer §6. R1–R7 som
  tester mot appens klasser, krascher och `resetIdentity()`, på datorn och
  på emulatorn. Mätningen i 0005 skrivs ut av emulatortestet.
- 2026-11-16 – P3, första delen: valvet görs säkert enligt 0005. Skrivningen
  fsyncar filen och mappen och ger fel i stället för att bara logga, och
  `reset()` raderar nyckeln först. Nytt emulatortest
  `integration_test/vault_test.dart`. P3 fortsätter med Olm-tillståndet.
- 2026-11-16 – Färdplanen utökad enligt ägarens instruktion: fas 2 (F1–F8,
  G6–G8) och fas 3 (F9–F12, G9–G11) med "Klart när", och "Efter version 1".
  Historiken (F3), raderingen av sessioner (F2) och det interna testet (G11)
  har flyttats från "Efter prototypen". Inget är bockat som inte är gjort.
  Ägaren skrev README "Saknas" för app-låset; avsnittet heter "Nästa steg".
  `docs/schemalagd-korning.md` följer de nya faserna.
- 2026-11-16 – G5 klar: ägaren valde (b) och (iii) i 0006, som har status
  "Accepted by owner". Raderingsregeln för gamla sessioner står under "Före
  första utdelning". Texterna i 0004 §10 är godkända, med antal meddelanden
  i raden "kunde inte läsas" och "servern" i allt användaren ser. 0004
  "Beslut", §2, §6, §8, §10 och §13, 0005 och P4 och P6 här är uppdaterade.
- 2026-11-16 – G5: beslutsunderlag 0006 (sessionsregeln) skrivet och
  rättat efter granskning. Rekommendation: senast aktiva sessionen, som i
  matrix-js-sdk v30, och ingen radering av sessioner i prototypen. P4
  väntar på G5.
- 2026-11-16 – CI: emulatorjobben föll för att runnern fick slut på minne
  (Gradle-daemonen upp till 3,8 GB samtidigt som emulatorn och rustc, 235 MB
  ledigt före avbrottet). APK:n byggs nu innan emulatorn startar, Gradle får
  2 GB och lämnar ingen daemon kvar. Minst 2,7 GB ledigt i mätningen efteråt.
- 2026-11-14 – G4 klar: ägaren valde (A) och (i) i 0005, med gränsen
  300 ms. 0005 har status "Accepted by owner". 0004 §6 och §7 och P3 här
  är uppdaterade.
- 2026-11-14 – G4: beslutsunderlag 0005 (lagring i prototypen) skrivet.
  Ny grind G5 för den öppna frågan i 0004 §2. P3 väntar på G4.
- 2026-11-14 – Rättelser efter granskningarna av P1 och P2 (PR #11, #12):
  0004 "Beslut", §2, §6, §8, §12 och §13. Android-bygget använder
  CI-maskinens stabila Rust, inte 1.97.0 (cargokit kör `rustup run stable`
  utan `--locked`); versionen skrivs nu i loggen. Nytt test att appen och
  spiken har samma Olm-versioner. Ny öppen fråga till ägaren i 0004 §2,
  före P4.
- 2026-11-14 – P2: `flutter_vodozemac` 0.9.1, `vodozemac` 0.9.1 och
  `flutter_rust_bridge` 2.13.0 i appens `pubspec.yaml`, samma versioner och
  SHA-256 som spiken. Nytt CI-jobb `app-android` i `ci.yml`: Rust (se
  rättelsen ovan), appens APK på en Android-emulator och
  `integration_test/olm_build_test.dart`.
  Ingen funktion i appen ändrad. Pluginet lägger inte till några
  Android-behörigheter.
- 2026-11-14 – P1: PR #8 mergad (0899c76). 0004 har status "Accepted by
  owner for an internal prototype" och ett avsnitt "Beslut", §12 följer
  merge-reglerna i `CLAUDE.md`, och OGRANSKAT-punkterna står ovan. 0004 är
  också rättad efter flera oberoende granskningar: typ 0 gäller allt före det
  första svaret, ett misslyckat försök kan ändra en session i minnet, ett
  ändrat typ 0-meddelande får inte leda till "träffas igen", en utträngd
  kedja ger `invalid MAC`, och två märkningar saknades. Ny grind G4
  (lagring) före P3.
- 2026-11-14 – G1: PR #9 mergad av ägaren (edb983d).
- 2026-11-14 – P0: regler och färdplan skrivna. Väntar på G1.
