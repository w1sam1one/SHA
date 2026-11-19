# Play-kraven (F9)

Kraven kontrolleras mot Googles egna sidor, med datum. **Bara en av sex
sidor gick att läsa 2026-11-17.** De andra fem ligger på
`support.google.com`, som inte är tillåten i den molnmiljö där Claude
arbetar. De står nedan med adress och är **ej lästa**. Ägaren kan läsa dem
själv, eller tillåta `support.google.com` så att Claude kan läsa dem.

Adresserna till sidorna på `support.google.com` är inte kontrollerade. Två
av dem (11926878 och 10787469) länkas från Googles sidor för utvecklare;
de andra tre kan vara fel.

## 1. Målnivå (target SDK) – läst

- **Källa:** https://developer.android.com/google/play/requirements/target-sdk,
  läst 2026-11-17. Sidfoten säger "Last updated 2026-10-28 UTC".
- **Från 31 augusti 2026:** "New apps and app updates must target Android 16
  (API level 36) or higher to be submitted to Google Play …". Undantagen i
  samma mening gäller Wear OS, Android Automotive OS, Android TV och Android
  XR, inte en app för telefoner. Befintliga appar måste ha minst API 35 för
  att vara tillgängliga för nya användare på nyare Android. Förlängning
  kunde begäras till 1 november 2026.
- **SHA:** `android/app/build.gradle.kts` använder `flutter.targetSdkVersion`,
  som är **36** i Flutter 3.47.7
  (`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`), och
  CI bygger med Flutter 3.47.7. Kravet är uppfyllt enligt källkoden. Det är
  inte kontrollerat i en byggd APK: CI:s kontroll av manifestet läser inte
  målnivån. Hur du kontrollerar din egen installation står i
  [`docs/release.md`](release.md), punkt 0.
- **Ej läst:** Googles egen supportsida om kravet
  (https://support.google.com/googleplay/android-developer/answer/11926878)
  och om det finns en senare tidsgräns.

## 2. Testkrav för nya konton – ej läst

- https://support.google.com/googleplay/android-developer/answer/14151465
- Hur många testare och hur många dagar ett stängt test måste pågå innan
  produktion: **ej läst**. Behövs för G11.

## 3. Data safety – ej läst

- https://support.google.com/googleplay/android-developer/answer/10787469
- Om data som är krypterad från telefon till telefon räknas som insamlad,
  och reglerna för tillfällig behandling: **ej läst**. Svaren i
  [`docs/data-safety.md`](data-safety.md) ska kontrolleras mot den här sidan.

## 4. Radering av data utan konton – ej läst

- https://support.google.com/googleplay/android-developer/answer/13327111
- SHA har inga konton och ingen egen knapp för att radera allt i vanlig
  användning ([`docs/data-safety.md`](data-safety.md)). Om Play kräver en
  raderingsfunktion: **ej läst**.

## 5. Integritetspolicyn – ej läst

- https://support.google.com/googleplay/android-developer/answer/9859455
- Om en webbadress krävs och hur sidan ska se ut: **ej läst**. Utkastet
  finns i [`docs/integritetspolicy.md`](integritetspolicy.md); att
  publicera det är G10.

## Så läses resten

Antingen läser ägaren sidorna ovan, eller så tillåts `support.google.com` i
molnmiljöns nät (miljöns inställningar, "Network access", "Allowed
domains"), och Claude läser dem och fyller i det här dokumentet med citat
och datum.
