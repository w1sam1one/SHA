# 0012 – QR-skannern och AGPL (F5)

Status: **Proposed – owner decides.** Skrivet 2026-11-17. Det här är inte
juridisk rådgivning. Licensfrågan bör kontrolleras av någon som kan
upphovsrätt innan appen delas ut.

Underlag för licenssidan i F5 och för bytet till AGPL-3.0 (0002, "Licens";
G8). Frågan hittades när licenserna för Android-biblioteken skulle läggas
på licenssidan.

## Problemet

Appen ska ha AGPL-3.0 senast före första utdelningen, även till testare
(0002, "Licens"). Två saker i appen drar då åt olika håll:

- `flutter_vodozemac` och `vodozemac` (Dart-paketen från Famedly) har
  AGPL-3.0, utan något undantag.
- QR-skannern `mobile_scanner` bygger in Googles ML Kit i APK:n. ML Kit är
  inte öppen källkod.

AGPL-3.0 kräver att den som delar ut programmet kan dela ut hela
programmet under AGPL, med källkod. Undantaget för systembibliotek (§1)
gäller delar av operativsystemet, inte ett bibliotek som ligger i APK:n.
Det ser alltså ut som en konflikt, och den gäller redan vid första
utdelningen till testare. SHA:s ägare kan ge ett undantag för sin egen
kod, men inte för Famedlys.

ML Kit väcker också en fråga om integriteten: appen har `INTERNET` sedan P6,
så ML Kit kan nå nätet.

## Fakta

**Läst här (2026-11-17):**

- `mobile_scanner` 7.4.2, `android/build.gradle.kts`: som standard
  `com.google.mlkit:barcode-scanning:17.3.0` inbyggt i appen. Med
  `dev.steenbakker.mobile_scanner.useUnbundled=true` används i stället
  `com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1`, och
  modellen hämtas via Google Play-tjänster. Dessutom CameraX 1.6.1 och
  kotlinx-coroutines 1.11.0.
- `flutter_vodozemac` 0.9.1 och `vodozemac` 0.9.1 (Dart, Famedly): filen
  `LICENSE` är AGPL-3.0, utan tilläggstillstånd. Rust-biblioteket
  `vodozemac` 0.11.2 under dem har Apache-2.0.
- `android/app/src/main/AndroidManifest.xml` begär `CAMERA` och `INTERNET`.
- pub.dev: `flutter_zxing` 3.1.1 har MIT och bygger in zxing-cpp
  (Apache-2.0). Paketet drar in `camera`, `ffi`, `image` och
  `image_picker`. `zxing2` 0.2.4 är ZXing i ren Dart (BSD-3-Clause).
  `camera` 0.12.2 har BSD-3-Clause och använder CameraX på Android.

**Inte läst här: från minnet, måste kontrolleras.** Googles sidor är
blockerade i molnsessionen.

- ML Kit omfattas av Google APIs Terms of Service och ML Kit:s egna villkor
  (`https://developers.google.com/ml-kit/terms`).
- ML Kit kan kontakta Googles servrar och skicka mätvärden om hur
  API:erna används (`https://developers.google.com/ml-kit/android-data-disclosure`).
  Det påverkar i så fall Data safety (`docs/release.md` §6).

## Alternativ

- **(A) Behåll ML Kit inbyggt.**
  - Ingen ny kod.
  - Men konflikten finns kvar. Utdelning kräver i så fall ett skriftligt
    undantag från Famedly för ML Kit, eller att en jurist säger att det
    inte behövs.
  - Mätvärdena till Google finns kvar och måste stå i Data safety.
- **(B) ML Kit via Google Play-tjänster** (`useUnbundled=true`).
  - En mindre APK.
  - Men Googles klientbibliotek ligger kvar i APK:n, så licensfrågan är
    troligen densamma.
  - Skanningen kräver Google Play-tjänster. Telefoner utan dem kan inte
    skanna.
- **(C) Byt till en skanner med öppen licens**, byggd på ZXing:
  `flutter_zxing` (MIT, med zxing-cpp under Apache-2.0) eller `zxing2` med
  `camera` (BSD-3-Clause). Apache-2.0, MIT och BSD går att kombinera med
  AGPL-3.0.
  - Ingen stängd kod från Google i skannern. CameraX har Apache-2.0.
  - Nya beroenden. Det här beslutet godkänner dem (`CLAUDE.md`, "Aldrig"),
    med exakta versioner och lockfilen incheckad.
  - Licensen kontrolleras för varje beroende som paketet drar in, även de
    i Android-bygget.
  - Nya tester:
    - `shaid:2`-koden läses rätt;
    - kameran stängs när fliken lämnas;
    - emulatortestet går igenom.
  - Måste provas på riktiga telefoner (G3), eftersom ZXing kan skanna
    sämre än ML Kit i dåligt ljus.

## Rekommendation: (C), med `flutter_zxing`

Säkerhet och anonymitet går före bekvämlighet (`CLAUDE.md`, "Målet"). (C)
tar bort Googles stängda kod och dess mätvärden från appen, och löser
licensfrågan utan att någon annan behöver ge ett undantag.

`flutter_zxing` kör zxing-cpp som maskinkod och är därför troligen
snabbare än `zxing2` i ren Dart (ej mätt). Men det drar in `image_picker`,
som appen inte behöver. Visar
licenskontrollen i bygget att något av dess beroenden inte går att kombinera
med AGPL, stannar Claude och frågar om `zxing2` med `camera` i stället.

Skannar (C) för dåligt i telefontestet blir det en ny grind.

## Testa

- Den nya skannern läser en `shaid:2`-kod från en bild i ett test på datorn.
- Emulatortestet bygger appen med den nya skannern.
- Att licenssidan visar alla Android-bibliotek i APK:n. Listan tas fram ur
  Gradle i CI och jämförs med det som visas.
- En mutation: ett bibliotek som tas bort ur listan får testet att falla.

## Ägaren beslutar

- [ ] (A), (B) eller (C).
- [ ] Med (C): `flutter_zxing` (rekommenderas) eller `zxing2` med `camera`.
- [ ] Läs de två sidorna om ML Kit ovan, eller låt Claude läsa dem
  (`developers.google.com` måste då tillåtas i miljöns nätverk).
- [ ] Fråga någon som kan upphovsrätt om licensfrågan, om du väljer (A) eller
  (B).

Bygget börjar först efter beslutet. Licenserna för Android-biblioteken på
licenssidan (F5) väntar på det här beslutet, eftersom listan beror på vilken
skanner appen har.
