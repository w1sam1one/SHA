# Släppa SHA på hemsidan och i GitHub Releases – checklista

För ägaren. Appen delas ut som en signerad APK på hemsidan och i GitHub
Releases (0014, ägarens beslut 2026-11-25). Google Play är uppskjutet; se
"Om Google Play blir aktuellt" sist. Bara ägaren bygger release, signerar,
laddar upp och delar ut (`CLAUDE.md`, "Aldrig"). Det som inte har gått att
pröva är märkt **ej verifierat**.

> **Viktigt först:** detta är en förhandsversion. Kryptot är inte granskat
> av en kryptoexpert (G6), och appen får inte delas ut till någon annan än
> ägaren förrän det är gjort, `LICENSE` är AGPL-3.0 (G8) och allt under
> "Före första utdelning" i [`ROADMAP.md`](ROADMAP.md) är klart. Appen
> hämtar aldrig i bakgrunden (0002; se punkt 7). App-låset döljer bara
> skärmen. Hemsidan och releasen får inte lova något annat.

## 0. Innan du börjar

- **Målnivå (targetSdk).**
  - Appen delas inte ut på Google Play (0014), men målnivån behålls som
    Play kräver: Android 16 (API 36) för nya appar och uppdateringar från
    31 augusti 2026. Källa: developer.android.com/google/play/requirements/target-sdk,
    läst 2026-10-21.
  - Lägsta nivån är Android 9 (`minSdk` 28, 0014).
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
    bara `CAMERA`, `INTERNET` och `USE_BIOMETRIC` (app-låset, 0011 (B)).
    Kameran tas via `camera` (CameraX), och
    koden läses av `zxing2` i ren Dart (0012 (C1)). `camera` lägger till
    `RECORD_AUDIO` och `WRITE_EXTERNAL_STORAGE` (och `READ_EXTERNAL_STORAGE`
    följer med), och CameraX videodel drar in media3, som lägger till
    `ACCESS_NETWORK_STATE`. Appens manifest tar bort alla fyra. Skannern
    använder varken video, lagring eller nätverksstatus.
  - `INTERNET` finns i debug- och profilmanifesten. Flutter behöver den där
    för utvecklingsverktygen.
  - **Det färdiga release-manifestet** kontrolleras i CI. Emulatorjobbet
    slår ihop det med `processReleaseMainManifest`, utan att bygga en
    release-APK. Steget faller om manifestet begär något annat än `CAMERA`,
    `INTERNET`, `USE_BIOMETRIC` och appens egen
    `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`,
    eller kräver någon hårdvara (`.github/scripts/check-manifest.py`). Hur
    ditt eget release-bygge slår ihop manifestet är **ej verifierat**.
  - Kontrollera efter ditt första release-bygge. Sammanslagningsrapporten
    visar vilket bibliotek som lagt till varje post. CI hittar den där
    (`find build/app/outputs/logs`):
    ```sh
    grep -n "uses-permission" build/app/outputs/logs/manifest-merger-release-report.txt
    ```
    Eller öppna APK-filen i Android Studio (Build › Analyze APK) och läs
    manifestet.
  - Allt utöver `CAMERA`, `INTERNET` och `USE_BIOMETRIC` ska stå i
    `docs/data-safety.md` och integritetspolicyn. En post som slutar på
    `.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` kommer från androidx.core
    (`androidx.core:core:1.13.1` i CI:s sammanslagningsrapport) och är
    intern för appen.
- **App-ikonen** är fortfarande Flutters standardikon (byte för byte samma
  som Flutters mall). Byt den i `android/app/src/main/res/mipmap-*/` innan
  du släpper.

## 1. Skapa signeringsnyckeln (en gång, G9)

Utanför Play är den här nyckeln **appens egen signeringsnyckel**. Varje
version måste signeras med den, annars installerar telefonerna den inte som
en uppdatering. Försvinner den måste alla användare avinstallera och
förlorar sin identitet och sina kontakter (0014, "Signeringsnyckeln").

Kommandot är det från Flutters guide (docs.flutter.dev/deployment/android):

```sh
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
```

- Namnet `upload` och filnamnet är kvar från Play-planen, så att
  `key.properties` fungerar som förut. De spelar ingen roll för
  användarna.
- keytool frågar efter lösenord och efter namn och organisation. Skriv
  lösenorden bara i terminalen, aldrig i en chatt eller ett ärende.
- Med nyare Java blir nyckelfilen PKCS12, och då används ett och samma
  lösenord för fil och nyckel (**ej verifierat** här).
- Saknas `keytool`, använd den Java som `flutter doctor -v` visar.
- Lägg aldrig nyckelfilen i repot. `*.jks` och `*.keystore` är ignorerade,
  och `test/security/no_keys_test.dart` stoppar en nyckelfil eller
  `key.properties` som ändå läggs till.

**Säkerhetskopia** (0014):

1. Två krypterade kopior offline, på olika platser, till exempel två
   USB-minnen.
2. Lösenordet för sig, på papper eller i en lösenordshanterare, inte med
   kopiorna.
3. Prova en återställning en gång: signera ett test-APK med en kopia och
   jämför fingeravtrycket.
4. Skriv ner fingeravtrycket på papper med kopiorna.

**Fingeravtrycket.** Läs certifikatets SHA-256:

```sh
keytool -list -v -keystore ~/upload-keystore.jks -alias upload | grep "SHA256:"
```

Skriv in värdet, med versaler och kolon, i stället för "inte skapat än
(G9)" på raden `Signeringscertifikatets SHA-256:` i `README.md`,
`SECURITY.md` och `docs/hemsida.md`, i backticks:

```text
Signeringscertifikatets SHA-256: `AB:CD:…`
```

`test/release/fingerprint_test.dart` stoppar ett värde som skiljer sig
mellan filerna eller inte ser ut som ett fingeravtryck.

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
   Siffran efter `+` (versionCode) måste öka för **varje** version som
   delas ut. Lägg samtidigt till ett avsnitt överst i
   [`CHANGELOG.md`](../CHANGELOG.md) med samma rubrik, och byt "inte
   släppt" mot dagens datum när versionen släpps.
   `test/release/changelog_test.dart` stoppar en version som inte stämmer
   med `pubspec.yaml` eller som går bakåt.
2. Bygg från den commit som ska släppas, med en ren arbetskopia:
   ```sh
   git status --short        # ska vara tomt
   flutter clean && flutter build apk --release
   ```
3. Utfil: `build/app/outputs/flutter-apk/app-release.apk`, med alla
   processortyper i samma fil. Byt namn till `SHA-<version>.apk`, till
   exempel `SHA-1.0.0.apk`.
4. Kontrollera signaturen. Certifikatets SHA-256 ska vara exakt det som
   står i README:
   ```sh
   apksigner verify --print-certs SHA-1.0.0.apk
   ```
   `apksigner` finns i Android SDK:s `build-tools`. Står det `CN=Android
   Debug`, eller skiljer sig fingeravtrycket: **dela inte ut filen**.
   Utskriften är **ej verifierad** här.
5. Räkna ut filens SHA-256:
   ```sh
   sha256sum SHA-1.0.0.apk > SHA256SUMS
   ```

**Utan `android/key.properties`** (följer av `android/app/build.gradle.kts`
och Flutters Gradle-plugin; **ej verifierat** i ett riktigt bygge):
- Gradle skriver `VARNING: android/key.properties saknas …`.
- Release-paketet blir **osignerat**. Det signeras aldrig med
  debugnyckeln, och ett osignerat paket går inte att installera.
- Är `key.properties` ofullständig eller oläslig stoppas release-bygget med
  ett meddelande som bara nämner fältnamnen. Debug- och profilbyggen
  påverkas inte.

## 4. Prova på dina egna telefoner

Installera med ADB, som inte påverkas av Googles utvecklarverifiering
(0014):

```sh
adb install -r SHA-1.0.0.apk
```

- En release-APK med din nyckel är en annan signatur än debug-byggena i
  `docs/prototyp.md`. Telefonen godtar den inte som en uppdatering av ett
  debug-bygge: avinstallera debug-bygget först, och skanna varandra igen.
- Gå igenom `docs/testprotokoll.md`.

## 5. Publicera (G11)

1. **Tagga** den commit du byggde från: `git tag v1.0.0 && git push origin
   v1.0.0`.
2. **GitHub Release** för taggen, med:
   - texten från versionens avsnitt i `CHANGELOG.md`;
   - certifikatets SHA-256 (samma som i README) och APK-filens SHA-256;
   - `SHA-1.0.0.apk` och `SHA256SUMS` som filer.
3. **Hemsidan** (`docs/hemsida.md`, adressen bestäms i G12): lägg till
   versionen, datumet, APK-filens SHA-256 och en länk till releasen under
   "Versioner".
4. **`CHANGELOG.md`:** byt "inte släppt" mot datumet, i en commit efter
   releasen.
5. **Skärmbilder** till hemsidan tas **bara på en emulator** (testet
   avinstallerar SHA och raderar dess data), enligt
   [`docs/butikstexter.md`](butikstexter.md), "Skärmbilder".

## 6. Googles utvecklarverifiering

- Fram till 2027 gäller den inte för APK:er från en hemsida (0014, Googles
  FAQ 15 juli 2026).
- Under testfasen: ADB, eller ett gratis konto för begränsad utdelning
  (V2) med högst 20 eller 50 telefoner (Googles sidor säger emot varandra).
- Fullt konto (V1) eller ingen registrering (V3) beslutas 2027. Läs då
  Googles sidor igen (F9).

## 7. Lova inget som saknas

Hemsidan, releasens text, skärmbilder och butikstexter får inte påstå att raderad
historik inte går att läsa, att app-låset skyddar nyckeln eller
meddelandena på lagringen, att appen hämtar i bakgrunden eller att den har
forward secrecy (0010 (B), F4, 0002; brevlåde-ID:n har ingen forward
secrecy enligt 0004 §3 (A), och kryptot är ogranskat till G6). Det som
saknas står i appens "Teknisk information" (`lib/ui/technical_info_sheet.dart`)
och i `docs/granskning/`. Orden i 0002, "Formuleringar i appen", gäller
också hemsidan och releasen. `test/security/wording_test.dart` kontrollerar appens
egna texter, och `test/security/store_texts_test.dart` butikstexterna i
[`docs/butikstexter.md`](butikstexter.md): förbjudna ord, längder och
inget löfte om öppen källkod före G8, men inte om innehållet stämmer.

## Om Google Play blir aktuellt

- Kraven för Play står i [`docs/play-krav.md`](play-krav.md) och
  underlaget till Data safety i [`docs/data-safety.md`](data-safety.md).
- Play kräver Play App Signing. Lämna då **din egen** signeringsnyckel till
  Google (PEPK) i stället för att låta Google skapa en ny, så att samma app
  kan uppdateras både från Play och från hemsidan (0014).
- Butikstexterna finns i [`docs/butikstexter.md`](butikstexter.md).
