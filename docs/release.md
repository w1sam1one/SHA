# Släppa SHA på Google Play – checklista

För dig som släpper för första gången. Dokumentet skrevs 2026-10-21 i en
miljö där inget Android-paket kunde byggas: Android SDK och Google Maven var
blockerade. Allt som inte gick att kontrollera då är märkt **ej verifierat**
med orsak. Inget här har körts mot Play Console eller med en riktig nyckel.

> **Viktigt först:** detta är en förhandsversion. Meddelanden skickas inte
> till någon än, och kontakter och meddelanden försvinner när appen stängs
> (se punkt 6 och 7). Butikstexten får inte lova något annat.

## 0. Innan du börjar

- **Målnivå (targetSdk).**
  - Google Play kräver Android 16 (API 36) för nya appar och uppdateringar
    från 31 augusti 2026. Källa: developer.android.com/google/play/requirements/target-sdk,
    läst 2026-10-21.
  - Bygget tar värdet från Flutter (`flutter.targetSdkVersion` i
    `android/app/build.gradle.kts`). Flutter 3.47.7 ger **36**, enligt
    `packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`.
  - Kontrollera *din* installation. Mappen visas som `flutterRoot` i
    `flutter --version --machine`:
    ```sh
    grep -n "targetSdkVersion: Int" "$(dirname "$(readlink -f "$(command -v flutter)")")/../packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
    ```
  - Står det lägre än 36: uppgradera Flutter (`flutter upgrade`) i stället för
    att ändra filen.
- **Behörigheter.**
  - Appens eget manifest (`android/app/src/main/AndroidManifest.xml`) begär
    bara `CAMERA` och `INTERNET`. Kameran tas via `camera` (CameraX), och
    koden läses av `zxing2` i ren Dart (0012 (C1)). `camera` lägger till
    `RECORD_AUDIO` och `WRITE_EXTERNAL_STORAGE` (och `READ_EXTERNAL_STORAGE`
    följer med), och CameraX videodel drar in media3, som lägger till
    `ACCESS_NETWORK_STATE`. Appens manifest tar bort alla fyra; skannern
    använder varken video, lagring eller nätverksstatus. CI kontrollerar debug-APK:ns färdiga manifest
    (`.github/scripts/check-manifest.py`).
  - `INTERNET` finns i debug- och profilmanifesten. Flutter behöver den där
    för utvecklingsverktygen.
  - Vilka behörigheter det **färdiga release-manifestet** får är **ej
    verifierat**. CI kontrollerar bara debug-APK:n. Biblioteken som slås
    ihop in i det, bland annat CameraX och Guava via `camera` samt
    androidx-biblioteken som Flutter använder, kan lägga till egna poster.
    Deras manifest gick inte att hämta.
  - Kontrollera efter ditt första release-bygge. Sammanslagningsrapporten
    visar vilket bibliotek som lagt till varje post (sökvägen är ej verifierad):
    ```sh
    grep -n "uses-permission" build/app/outputs/logs/manifest-merger-release-report.txt
    ```
    Eller öppna AAB-filen i Android Studio (Build › Analyze APK) och läs
    manifestet.
  - Allt utöver `CAMERA` och `INTERNET` påverkar punkt 6. En post som slutar på
    `.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` brukar komma från androidx.core
    och är intern för appen (ej verifierat).
- **App-ikonen** är fortfarande Flutters standardikon (byte för byte samma
  som Flutters mall). Byt den i `android/app/src/main/res/mipmap-*/` innan
  du släpper.

## 1. Skapa uppladdningsnyckeln (en gång)

Kommandot är det från Flutters guide (docs.flutter.dev/deployment/android):

```sh
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
```

- Guidens sida gick inte att hämta när detta skrevs. Flaggorna finns i
  keytool (`keytool -genkeypair -help`), men jämför kommandot med sidan.
- keytool frågar efter lösenord och efter namn och organisation. Skriv
  lösenorden bara i terminalen, aldrig i en chatt eller ett ärende.
- Med nyare Java blir nyckelfilen PKCS12, och då används ett och samma
  lösenord för fil och nyckel (ej verifierat här).
- Saknas `keytool`, använd den Java som `flutter doctor -v` visar.
- Lägg aldrig `upload-keystore.jks` i repot. `*.jks` och `*.keystore` är
  ignorerade, men flytta den ändå inte dit.
- Spara filen **och** lösenorden på minst två säkra ställen utanför repot,
  t.ex. en lösenordshanterare och en krypterad USB-sticka.
- **Play App Signing:** du signerar med *uppladdningsnyckeln*. Google byter
  den mot appens egen signeringsnyckel, som Google förvarar, innan appen når
  användarna. Uppladdningsnyckeln bevisar bara för Google att uppladdningen
  kommer från dig.

## 2. Skapa `android/key.properties`

```sh
cp android/key.properties.example android/key.properties
```

Fyll i kopian:

| Fält | Värde |
| --- | --- |
| `storeFile` | Hela sökvägen till .jks-filen, t.ex. `/home/<namn>/upload-keystore.jks` eller `C:/Users/<namn>/upload-keystore.jks`. `~` fungerar inte. Använd `/`, inte `\`, även på Windows. |
| `storePassword` | Lösenordet till nyckelfilen. Ett `\` i lösenordet skrivs `\\`. |
| `keyAlias` | `upload` |
| `keyPassword` | Lösenordet till nyckeln. Ett `\` i lösenordet skrivs `\\`. |

Filen ignoreras av git (`android/.gitignore`). Kontrollera innan du
committar något:

```sh
git check-ignore -v android/key.properties   # ska visa en .gitignore-rad
git status --short                           # key.properties får inte synas
```

## 3. Bygg

1. Höj versionen i `pubspec.yaml`: `version: 1.0.0+1` → `1.0.0+2` osv.
   Siffran efter `+` (versionCode) måste öka för **varje** uppladdning.
2. Bygg:
   ```sh
   flutter clean && flutter build appbundle
   ```
3. Utfil: `build/app/outputs/bundle/release/app-release.aab`. Det namnet
   anger Flutter-verktygets egen kod; Flutters guide kan skriva `app.aab`.
4. Kontrollera att paketet är signerat med **din** nyckel. Jämför
   `SHA256:`-raderna från de två `keytool`-kommandona; de ska vara lika:
   ```sh
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   keytool -list -v -keystore ~/upload-keystore.jks -alias upload
   jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab | grep -m3 -E "CN=|unsigned"
   ```
   Står det `CN=Android Debug`, eller skiljer sig fingeravtrycken: ladda
   inte upp. Kommandona är **ej verifierade**, eftersom inget paket gick att
   bygga.

**Utan `android/key.properties`** (följer av `android/app/build.gradle.kts`
och Flutters Gradle-plugin; **ej verifierat** i ett riktigt bygge):
- Gradle skriver `VARNING: android/key.properties saknas …`. Den raden och
  felmeddelandena nedan har provats i ett fristående Gradle-projekt, utan
  Android-pluginet.
- Release-paketet blir **osignerat**. Det signeras aldrig med
  debugnyckeln.
- Är `key.properties` ofullständig eller oläslig stoppas release-bygget med
  ett meddelande som bara nämner fältnamnen. Debug- och profilbyggen
  påverkas inte.
- Ett osignerat paket går inte att installera, så `flutter run --release`
  fungerar inte utan nyckel. `flutter run --profile` signeras med
  debugnyckeln, som tidigare, och går att använda på telefonen.

## 4. Play Console

Uppgifterna i punkt 4 och 5 har inte kontrollerats mot Googles hjälpsidor
(**ej verifierat**). Följ det Play Console visar.

1. Skapa appen. Paketnamnet `se.sha.sha` kan inte ändras efteråt. Vill du
   ha ett annat måste `applicationId` ändras före första uppladdningen.
2. Godkänn Play App Signing vid första uppladdningen.
3. **Intern testning** först: ladda upp AAB-filen och installera via Play på
   din egen telefon.
4. **Stängt test.** För nya personliga utvecklarkonton: minst 12 testare i
   minst 14 dagar i följd innan du kan ansöka om produktion.
5. Ansök om produktion och släpp därefter i **produktion**.

## 5. Det Play kräver av butikssidan

- **Integritetspolicy:** en publik URL i Play Console. Kontrollera om
  policyn även måste nås inifrån appen; i dag finns ingen sådan länk i appen.
- **Data safety-formuläret:** se punkt 6.
- **Skärmbilder.** Appen sätter `FLAG_SECURE` i alla byggtyper
  (`android/app/src/main/kotlin/se/sha/sha/MainActivity.kt`), så
  skärmdumpar blockeras eller blir svarta (ej verifierat på telefon).
  Planera hur du tar dem. Bilderna ska visa den riktiga appen.
- **Ikon:** byt app-ikonen (punkt 0). Butikssidan har dessutom en egen ikon
  som laddas upp i Play Console; storlekskraven står där.

## 6. Underlag till Data safety – vad koden visar i dag

**Du måste själv kontrollera varje svar innan du skickar in.** Listan visar
bara vad SHA:s egen kod gör. Den säger inte hur Googles definitioner ska
tolkas och täcker inte vad Googles bibliotek (CameraX) gör.

- **Nätverk:**
  - Appens egen kod gör inga nätverksanrop. Varken `lib/` eller
    `pubspec.yaml` innehåller `dart:io`, `http` eller något nätverkspaket.
  - Appens eget manifest begär inte `INTERNET`
    (`android/app/src/main/AndroidManifest.xml`), och
    `android/app/src/main/res/xml/network_security_config.xml` stänger av
    okrypterad trafik.
  - Om CameraX skickar något: **ej verifierat** (punkt 0).
- **Kamera:**
  - Används bara för att skanna QR-koder (`lib/features/qr/qr_camera.dart`,
    via `camera` och CameraX), och bara medan skannern är öppen och appen
    syns.
  - Bilderna läses i appen av `zxing2` (`lib/features/qr/qr_decoder.dart`),
    i minnet. Inga bilder sparas eller skickas, och inget ljud spelas in
    (`enableAudio: false`, och `RECORD_AUDIO` är borttagen ur manifestet).
  - Hur CameraX behandlar kamerabilden: **ej verifierat**.
- **På telefonen sparas** bara identitetens nyckelpar.
  - Det krypteras med en Android Keystore-nyckel och ligger i appens privata
    `noBackupFilesDir`
    (`android/app/src/main/kotlin/se/sha/sha/keystore/KeystoreVault.kt`).
  - Backup och enhetsöverföring är avstängda (`allowBackup="false"` och
    `res/xml/data_extraction_rules.xml`).
- **Kontakter** (namnet du skriver och kontaktens offentliga nyckel) och
  **meddelanden** finns bara i minnet och försvinner när appen stängs
  (`lib/features/contacts/contacts_store.dart`,
  `lib/features/chat/message_store.dart`).
- **Meddelanden skickas inte** (`lib/features/chat/chat_controller.dart`,
  `transportAvailableProvider` är `false` i `lib/core/providers.dart`).
- **Inga konton**, inget telefonnummer och ingen e-post. Identiteten skapas
  lokalt (`lib/features/onboarding/identity_controller.dart`,
  `lib/crypto/src/sha_crypto_service.dart`).
- **Dart-paket:** inga för analys, kraschrapporter eller annonser
  (`pubspec.yaml`: `flutter_riverpod`, `cryptography`, `qr_flutter`,
  `camera`, `zxing2`). ML Kit är borttaget (0012 (C1)).
- **Ingen loggning** i appkoden (`test/security/no_logging_test.dart`).
- **Urklipp:** appens egna kopieringsknappar finns bara i debugbyggen
  (`kDebugMode` i `lib/features/onboarding/identity_screen.dart` och
  `lib/features/qr/my_qr_screen.dart`). Vanliga textfält har systemets
  kopiera och klistra in.

## 7. Förhandsversion – lova inget som saknas

Chatten visar själv att meddelanden inte skickas än
(`lib/features/chat/chat_screen.dart`). Butikstext, skärmbilder och
beskrivning får inte påstå att appen skickar meddelanden, sparar historik,
har app-lås eller forward secrecy. Det som saknas står i
`docs/SECURITY_REVIEW.md` och i appens "Teknisk information".
