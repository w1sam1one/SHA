# Färdplan: intern prototyp

Den här filen styr vad Claude bygger härnäst, enligt [`CLAUDE.md`](../CLAUDE.md).
Paketen görs i ordning. En grind betyder att ägaren måste göra något innan
arbetet fortsätter.

## Klart när

Prototypen är klar när allt detta gäller:

1. Två appinstanser som har skannat varandras QR-koder kan skicka och ta
   emot krypterade meddelanden via relayn.
2. Identitet, kontakter och Olm-sessioner finns kvar efter att appen har
   startats om.
3. Testplanen i 0004 §11 är grön i CI, även på Android-emulatorn. Körning på
   en riktig telefon ingår inte här, se G3.
4. CI bygger en debug-APK som ägaren kan ladda ner och installera.
5. `docs/prototyp.md` beskriver hur ägaren sätter upp relayn och provar med
   två telefoner.

## Paket

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
- [ ] **P5 – Paketformat version 3.** Format och utfyllnad (§4, §5). Relayns
  största paketstorlek i `relay/limits.go` och dess tester.
- [ ] **P6 – Transport.** En relay-klient utan nytt beroende (`dart:io`).
  Hämtning enligt §9 (b). Intervallet 1, 5, 15 eller 60 minuter i
  inställningarna. Felfall och texter enligt §10 (godkända 2026-11-16) och
  0002. I allt användaren ser heter relayn "servern", även i
  `lib/ui/technical_info_sheet.dart` ("reläer", "Ett relä"). `INTERNET` i
  release-manifestet, med motivering i README. Serverns adress går att
  ställa in.
- [ ] **P7 – Hela kedjan i CI.** Två klienter mot en riktig relay: svaren
  204, 507 och 429, dubbletter, krascher och mutationer (§11).
- [ ] **P8 – Leverans till ägaren.** Debug-APK som CI-artefakt och
  `docs/prototyp.md`.

## Grindar (bara ägaren)

- **G1 – Aktivera.** Merga PR:en med `CLAUDE.md`. Innan dess gör den
  schemalagda körningen ingenting.
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
- En raderingsregel för gamla sessioner (0004 §2, 0006; (i) är
  utgångspunkten). I prototypen raderas inga sessioner, och utan en regel
  ligger gamla sessioners nycklar kvar i riktiga användares telefoner.
- Flutter/Dart-lagret och bygget är granskade.
- Planen för säkerhetsuppdateringar (0004 §12) är godkänd, och Dependabot
  alerts och security updates är påslagna.
- `LICENSE` är bytt till AGPL-3.0.
- Spiken och appen är körda på en riktig arm64-telefon.
- Rust i Android-bygget är låst och cargo körs med `--locked`, eller så har
  ägaren, efter granskningen av bygget, godtagit att det inte är det (0004
  §12, §13). I
  dag bygger cargokit med CI-maskinens `stable`, och att ändra det kräver
  ett ändrat plugin.

## Efter prototypen (inte nu)

- Historik i appen (0004 §7).
- En raderingsregel för gamla sessioner (0006). Den måste vara klar före
  första utdelningen, se ovan.
- Internt test på Google Play.
- Tor eller liknande, flera relays.

## Logg

Nyast först. En rad per paket eller körning som ändrar något.

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
