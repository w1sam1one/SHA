# 0012 – QR-skannern och AGPL (F5)

Status: **Beslutat av ägaren 2026-11-18: (C1)**, `zxing2` 0.2.4 med
`camera` 0.12.2. Skrivet 2026-11-17. Det här är inte
juridisk rådgivning. Licensfrågan bör kontrolleras av någon som kan
upphovsrätt innan appen delas ut, vilket alternativ som än väljs.

Underlag för licenssidan i F5 och för bytet till AGPL-3.0 (0002, "Licens";
G8). Frågan dök upp när licenserna för Android-biblioteken skulle läggas på
licenssidan.

## Problemet

- `flutter_vodozemac` och `vodozemac` (Famedly) har AGPL-3.0, utan några
  tilläggstillstånd. Det gäller både Dart-koden och pluginets egen
  Rust-kod.
- QR-skannern `mobile_scanner` bygger som standard in Googles ML Kit i
  APK:n. ML Kit är, så vitt vi vet, inte öppen källkod (se "Inte läst
  här").

Den som delar ut APK:n, även till testare, måste följa Famedlys AGPL-3.0.
Det gäller oavsett vad SHA:s egen `LICENSE` säger, så att skjuta upp G8
löser inget. AGPL-3.0 kräver att hela programmet som delas ut kan delas
under AGPL, med källkod. Licensen undantar "systembibliotek" (§1), men ett
bibliotek som ligger i APK:n räknas troligen inte som ett. Det ser alltså
ut som en konflikt redan vid första utdelningen. SHA:s ägare kan ge
tilläggstillstånd för sin egen kod, men inte för Famedlys.

ML Kit väcker också en fråga om integriteten: appen har `INTERNET` sedan P6,
så ML Kit kan nå nätet.

## Fakta

**Läst här (2026-11-17):**

- `mobile_scanner` 7.4.2, `android/build.gradle.kts`: som standard byggs
  `com.google.mlkit:barcode-scanning:17.3.0` in i appen. Med
  `dev.steenbakker.mobile_scanner.useUnbundled=true` används i stället
  `com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1`, och
  modellen hämtas via Google Play-tjänster (paketets README). Appens
  `android/gradle.properties` sätter inte det valet. Dessutom CameraX 1.6.1
  och kotlinx-coroutines 1.11.0.
- `flutter_vodozemac` 0.9.1 och `vodozemac` 0.9.1 (Dart, Famedly), och
  pluginets Rust-kod (`rust/LICENSE`): AGPL-3.0, utan tilläggstillstånd.
  Rust-biblioteket `vodozemac` 0.11.2 under dem har Apache-2.0.
- `android/app/src/main/AndroidManifest.xml` begär `CAMERA` och `INTERNET`.
- Skannern är en egen skärm (`ScanScreen.open`,
  `lib/features/qr/scan_screen.dart`).
- Kandidaterna för (C), lästa på pub.dev och i paketens källkod:
  - `zxing2` 0.2.4: ZXing i ren Dart, BSD-3-Clause, fyra små beroenden och
    en verifierad utgivare. README kallar paketet en översättning av ZXing
    för Java, som har Apache-2.0.
  - `flutter_zxing` 3.1.1: MIT, ingen verifierad utgivare. Det bygger in
    zxing-cpp (Apache-2.0, maskinkod i C++) och zint (BSD-3-Clause, med
    typsnitten Arimo och OCR-B), och drar in `camera`, `ffi`, `image` och
    `image_picker`. Version 4.0.0-rc.1 kom 2026-11-16.
  - `camera` 0.12.2: BSD-3-Clause. På Android används
    `camera_android_camerax` 0.7.6+1, som drar in CameraX och Guava.
  - Licenserna för allt som (C) drar in är MIT, BSD-3-Clause eller
    Apache-2.0, och ingen av dem krockar med AGPL-3.0. Det bygger på de
    senaste versionerna på pub.dev och Maven Central, inte på en riktig
    `flutter pub get`. Ingen ML Kit och ingen kod från Play-tjänster finns
    i (C).
- **Behörigheter i (C):**
  - `camera_android_camerax` lägger till `RECORD_AUDIO`,
    `WRITE_EXTERNAL_STORAGE` (till API 28) och kravet
    `android.hardware.camera.any` i appens manifest.
  - `image_picker_android` (via `flutter_zxing`) lägger till en
    FileProvider och en post som ber Google Play-tjänster installera en
    bildväljare (`com.google.android.gms.metadata.ModuleDependencies`).
  - `flutter_zxing` visar som standard en knapp för att välja en bild ur
    galleriet (`showGallery = true`).

**Inte läst här: från minnet, måste kontrolleras.** Googles sidor och
Googles Maven-arkiv är blockerade i molnsessionen.

- ML Kit är inte öppen källkod. Det omfattas av Google APIs Terms of
  Service och ML Kit:s egna villkor
  (`https://developers.google.com/ml-kit/terms`).
- ML Kit kan kontakta Googles servrar och skicka mätvärden om hur API:erna
  används (`https://developers.google.com/ml-kit/android-data-disclosure`).
  Det påverkar i så fall Data safety (`docs/data-safety.md`).
- CameraX och AndroidX har Apache-2.0, och vilka beroenden de drar in.

## Alternativ

- **(A) Behåll ML Kit inbyggt.**
  - Ingen ny kod.
  - Men konflikten finns kvar. Utdelning kräver i så fall skriftliga
    tilläggstillstånd för ML Kit från alla som har upphovsrätt i Famedlys
    paket, eller att en jurist säger att det inte behövs.
  - Om ML Kit skickar mätvärden till Google gör det det fortfarande, och
    det måste stå i Data safety.
- **(B) ML Kit via Google Play-tjänster** (`useUnbundled=true`).
  - En mindre APK.
  - Men Googles klientbibliotek ligger kvar i APK:n, så licensfrågan är
    troligen densamma.
  - Skanningen kräver Google Play-tjänster, och modellen hämtas genom dem.
    Det är det sämsta alternativet för integriteten, och telefoner utan
    Play-tjänster kan inte skanna.
- **(C) Byt till en skanner med öppen licens, byggd på ZXing.**
  - **(C1) `zxing2` 0.2.4 med `camera` 0.12.2.**
    - Ren Dart: avkodningen av kamerabilden, som en angripare styr över,
      sker i minnessäker kod.
    - Få beroenden, ingen `image_picker` och ingen post för Play-tjänster.
    - Hur snabb avkodningen är på en telefon: **ej mätt**.
  - **(C2) `flutter_zxing` 3.1.1.**
    - zxing-cpp körs som maskinkod och är troligen snabbare (ej mätt).
    - Men det är C++ som läser kamerabilden, och den koden syns inte för
      Dependabot (samma sak som Rust-koden i 0004 §12). Paketet bygger
      också kod för att skriva streckkoder, som appen inte behöver.
    - Det drar in `image_picker`, med posten för Play-tjänster ovan.
  - **För båda:**
    - Ingen ML Kit och ingen kod från Play-tjänster i skannern.
    - `RECORD_AUDIO` och `WRITE_EXTERNAL_STORAGE` från `camera` tas bort
      med `tools:node="remove"` i appens manifest. Med (C2) tas även
      posten för Play-tjänster bort, och galleriknappen stängs av
      (`showGallery: false`).
    - Nya beroenden. Beslutet godkänner bara den valda kandidatens exakta
      versioner ovan, och de paket de drar in enligt lockfilen
      (`CLAUDE.md`, "Aldrig"). Inget Gradle-plugin för licenser ingår:
      Googles `oss-licenses` hör till Play-tjänsterna.
    - Måste provas på riktiga telefoner (G3), eftersom ZXing kan skanna
      sämre än ML Kit i dåligt ljus.

## Rekommendation: (C1), `zxing2` med `camera`

Säkerhet och anonymitet går före bekvämlighet (`CLAUDE.md`, "Målet").

- (C) tar bort Googles stängda kod från appen, och bör lösa licensfrågan
  utan att någon annan behöver ge tilläggstillstånd.
- (C1) läser kamerabilden i minnessäker kod och har färre beroenden än
  (C2). (C2) är bara bättre i fart, och den är inte mätt.

Är (C1) för långsam i telefontestet blir det en ny grind, med (C2) som
alternativ.

## Testa

- Den nya skannern läser en `shaid:2`-kod från en bild i ett test på datorn.
- Kameran stängs när skärmen stängs och när appen går i bakgrunden.
- Emulatortestet bygger appen med den nya skannern.
- Release-manifestet efter sammanslagningen begär bara `CAMERA` och
  `INTERNET`. Ett test i CI läser det, och en mutation som tar bort
  `tools:node="remove"` får testet att falla.
- Licenssidan visar varje bibliotek i APK:n, med en licens som går att
  kombinera med AGPL-3.0, och ZXing:s Apache-2.0-text. Listan jämförs med
  Gradles egen lista över beroenden i CI, utan något nytt plugin. En
  mutation: ett bibliotek som tas bort ur listan får testet att falla.

## Ägaren beslutar

- [x] **(C1)**, beslutat 2026-11-18. Det godkänner `zxing2` 0.2.4 och
  `camera` 0.12.2, med de Dart-paket som de drar in enligt låsfilen och de
  Android-bibliotek som Gradle drar in för dem (CameraX och Guava).
  `mobile_scanner` tas bort.
- [ ] Läs de två sidorna om ML Kit ovan, eller låt Claude läsa dem
  (`developers.google.com` måste då tillåtas i miljöns nätverk). Behövs
  inte med (C1): ML Kit tas bort.
- [ ] Låt någon som kan upphovsrätt kontrollera licensfrågan före första
  utdelningen, oavsett alternativ.

Bygget börjar först efter beslutet. Licenserna för Android-biblioteken på
licenssidan (F5) väntar på det här beslutet, eftersom listan beror på vilken
skanner appen har.
