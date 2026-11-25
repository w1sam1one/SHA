# 0014 – Utdelning utan Google Play: hemsida, GitHub Releases, fingeravtryck och uppdateringskontroll

Status: **Beslutat av ägaren 2026-11-25** (se "Ägarens beslut" nedan).
Skrivet 2026-11-23, omskrivet samma dag efter ägarens önskemål. Det här är
inte juridisk rådgivning.

## Ägarens beslut (2026-11-25)

1. **Utdelning: (1a)**, hemsidan och GitHub Releases, samma signerade APK.
   F-Droid efter G8, med ägarens nyckel om det går. Google Play skjuts upp.
2. **Fingeravtryck: (2b)**: certifikatets fingeravtryck på alla fyra
   ställen, och APK:ns SHA-256 bara i releasen och på hemsidan. **(2c)**:
   appen visar sitt fingeravtryck, med texten om vad det inte bevisar.
   `SHA256SUMS` signeras inte nu.
3. **Uppdateringskontroll: (3b)**, med versionsfilen på GitHub Pages.
   Texterna i appen är godkända som de står i avsnittet "Texten i appen"
   nedan.
4. **Utvecklarverifiering:** ADB eller (V2), ett begränsat konto, under
   testfasen. Beslut om (V1) eller (V3) tas 2027.
5. **`applicationId`** byts till `io.github.w1sam1one.sha` före första
   utdelningen. **`minSdk`** höjs till 28 (Android 9).

Paketen F13–F15 nedan byggs i den ordningen, efter F12.

**Öppen fråga till ägaren:** hemsidans adress, som också blir den fasta
länken i appen (punkt 3). Förslaget är GitHub Pages,
`https://w1sam1one.github.io/SHA/`, samma värd som versionsfilen. Det
behöver bekräftas före F15.

Källorna lästes 2026-11-23 och står sist med adress. Det som inte gick att
läsa eller pröva är märkt **ej läst** eller **ej provat**.

## Ägarens önskemål (2026-11-23)

1. **Utdelning:** samma signerade APK på hemsidan och i GitHub Releases.
   F-Droid när koden är AGPL. Google Play skjuts upp.
2. **Fingeravtryck:**
   - Signeringscertifikatets SHA-256-fingeravtryck och APK:ns SHA-256
     publiceras i README, i SECURITY.md, i varje GitHub Release och på
     hemsidan.
   - Appen visar sitt eget fingeravtryck under "Teknisk information".
   - Den privata nyckeln finns aldrig i repot eller i CI.
3. **Uppdateringskontroll:**
   - Den är frivillig och avstängd från början.
   - Den hämtar bara en versionsfil, med samma anrop för alla och utan id.
   - Den körs bara när appen är öppen, och högst en gång om dagen.
   - Den visar bara "ny version finns" och laddar inte ner något. Länken
     är fast i appen.
   - Texten om att GitHub ser IP-adressen, och om VPN, skrivs enligt 0002.

Nedan jämförs alternativen för varje punkt. Sedan kommer Googles
utvecklarverifiering, signeringsnyckeln och paketen i färdplanen.

## Det som gäller oavsett val

- **Grindarna står kvar.**
  - Ingen utdelning till någon annan än ägaren före G6 (kryptoexperten).
  - `LICENSE` byts till AGPL-3.0 före första utdelningen (G8, 0012).
- **Bara ägaren delar ut.** Claude bygger ingen release, laddar inte upp,
  skapar inga konton och rör inga nycklar (`CLAUDE.md`, "Aldrig").
- **Samma nyckel för alla uppdateringar.** Android installerar en
  uppdatering bara om den är signerad med samma nyckel som appen på
  telefonen. Det är Androids vanliga regel; **ej provat här**. Den första
  installationen avgör alltså vilken nyckel telefonen litar på.
- **Ett byte av nyckel eller kanal raderar data.** Användaren måste då
  avinstallera appen. SHA har ingen säkerhetskopia (`allowBackup="false"`
  i manifestet), så identiteten, kontakterna och historiken försvinner, och
  alla måste träffas och skanna på nytt.
- **`applicationId` är `se.sha.sha`** (beslut 5: byts till
  `io.github.w1sam1one.sha` i F13).
  - F-Droid råder till ett id från en domän som utvecklaren äger.
  - Google kan kräva en extra granskning av ett paketnamn som redan
    används.
  - Vem som äger domänen `sha.se` är **ej kontrollerat**.
  - Ett annat id blir en annan app för telefonen, så det måste bestämmas
    före första utdelningen.
- **Appen pratar i dag bara med servern.** `docs/data-safety.md` säger att
  `INTERNET` i appens egen kod används "bara för servern". En
  uppdateringskontroll (punkt 3) ändrar det, och då ändras också Data
  safety-underlaget, integritetspolicyn och "Teknisk information".

## 1. Utdelning

### Alternativ

- **(1a) Hemsidan och GitHub Releases, samma APK.** Ägarens önskemål.
  - Ägaren bygger och signerar APK:n på sin egen dator (0007 (b)).
  - Ägaren laddar upp den till en GitHub Release med versionen som tagg,
    tillsammans med fingeravtrycken.
  - Hemsidan visar samma fil, eller länkar till releasen, och visar samma
    fingeravtryck. Integritetspolicyn (G10) ligger på hemsidan.
- **(1b) Bara GitHub Releases.** Hemsidan är då README eller GitHub Pages.
  Det är mindre att hålla i ordning, men GitHub blir den enda platsen.
- **(1c) Bara en egen hemsida.** Ingen GitHub-släpp, så GitHub ser inte
  nedladdningarna. Det kräver en egen server, som ägaren står för (ingen
  för Claude, `CLAUDE.md`). Obtainium kan läsa en vanlig sida med APK-länkar,
  men det är skörare.
- **(1d) F-Droid nu.** Det går inte förrän koden är fri programvara (G8).
- **(1e) Google Play nu.** Ägaren skjuter upp det.

### F-Droid senare

- **Krav** (F-Droids "Inclusion Policy"):
  - Koden måste vara fri programvara, till exempel GPL.
  - F-Droid bygger själv från källkoden, med fria verktyg. Flutters och
    Androids SDK, Rust/Rustup och Google Maven godtas som färdiga binärer.
  - Spårning och reklam är förbjudet. SHA har ingen sådan kod sedan 0012
    (C1).
  - Appen ska ha utvecklats aktivt i minst 3 månader.
  - Appar får inte ladda ner kod eller uppdateringar utan tydligt samtycke.
- **Signering**, två vägar:
  - F-Droid signerar med en egen nyckel. Då kan användaren inte byta
    mellan F-Droids APK och hemsidans utan att avinstallera och förlora
    sina data.
  - Med reproducerbara byggen kan F-Droid publicera APK:er med ägarens
    egen signatur (`Binaries` och `AllowedAPKSigningKeys`). Då är det samma
    app och samma nyckel i alla kanaler. Det kräver att F-Droids bygge blir
    byte för byte samma som ägarens. Om det går med Flutter och Rust via
    cargokit är **ej provat**.

### Google Play senare

- Play App Signing krävs för nya appar. "Google manages and protects your
  app's signing key for you and uses it to sign your APKs for
  distribution."
- Ägaren kan lämna sin egen nyckel till Google, så att samma nyckel gäller
  överallt. Det måste väljas när Play App Signing sätts upp. Google har
  därefter en kopia och kan signera uppdateringar.

### Uppdateringar utan appens hjälp

- **Obtainium**, en app på användarens telefon, kan följa GitHub Releases
  och installera nya versioner. README: "Obtainium allows you to install
  and update apps directly from their releases pages".
- Obtainium kontrollerar inte själv signaturen enligt diskussioner hos
  GrapheneOS. Det är **ej kontrollerat i koden**. Androids regel om samma
  nyckel gäller ändå för varje uppdatering.
- Det kräver ingen ändring i SHA, och kan rekommenderas på hemsidan
  oavsett punkt 3.

### Jämförelse

| | (1a) Hemsida + GitHub | (1b) Bara GitHub | (1c) Bara egen hemsida |
| --- | --- | --- | --- |
| Vem ser nedladdningen | GitHub och hemsidans värd | GitHub | Hemsidans värd |
| Arbete för ägaren | Två ställen att uppdatera | Ett ställe | Ett ställe, plus en server |
| Obtainium | Fungerar med GitHub | Fungerar | Skörare (läser webbsidan) |
| Om GitHub stänger kontot | Hemsidan finns kvar | Allt borta | Påverkas inte |

**Rekommendation: (1a)**, som ägaren vill. F-Droid efter G8, helst med
reproducerbart bygge och ägarens nyckel. Om F-Droid bara kan signera med
sin egen nyckel, bör F-Droid-versionen tydligt sägas vara en egen app som
inte kan uppdateras från hemsidan, eller vänta.

## 2. Fingeravtryck

### Två olika värden

1. **APK:ns SHA-256:** till exempel `sha256sum SHA-1.0.0.apk`. Det ändras
   vid varje release och visar att filen inte har ändrats på vägen.
2. **Certifikatets SHA-256-fingeravtryck:** `apksigner verify --print-certs
   SHA-1.0.0.apk`, eller `keytool -list -v` på nyckelfilen. Det är samma för
   alla releaser, och det är det värde telefonen litar på. Exakt vad
   `apksigner` skriver ut är **ej provat här**.

### Var de publiceras

| Ställe | Certifikatets fingeravtryck | APK:ns SHA-256 |
| --- | --- | --- |
| README | Ja | (2a) Ja, för senaste versionen; (2b) länk till releasen |
| SECURITY.md | Ja | (2a) Ja, för senaste versionen; (2b) länk till releasen |
| Varje GitHub Release | Ja | Ja, plus en fil `SHA256SUMS` |
| Hemsidan | Ja | Ja |

- **(2a) Ägarens önskemål:** båda värdena på alla fyra ställen. Den
  nackdelen är att README och SECURITY.md måste uppdateras i en commit
  efter varje release, eftersom APK:n byggs från den taggade koden. Är
  commiten glömd, visar de ett gammalt värde.
- **(2b) Alternativ:** certifikatets fingeravtryck på alla fyra ställen.
  APK:ns SHA-256 bara i releasen och på hemsidan, och README och
  SECURITY.md länkar dit. Färre kopior som kan bli fel.
- **I båda fallen** bör ett fingeravtryck som skiljer sig mellan ställena
  ses som ett larm. Ett test i CI kan kontrollera att certifikatets
  fingeravtryck är detsamma i README och SECURITY.md (ett eget paket).
- **Signera fillistan (valfritt):** `SHA256SUMS` kan signeras med
  `ssh-keygen -Y sign`, som finns i OpenSSH. Den offentliga nyckeln står i
  repot. Det skyddar mot en ändrad fil på GitHub, men certifikatets
  fingeravtryck är det viktiga.
- **Kontroll av första installationen:** med `apksigner` på en dator, eller
  med en app på telefonen som "Verified Apps" (**ej läst** här).
  Instruktionen står på hemsidan.

### Appens eget fingeravtryck i "Teknisk information"

- **Så går det till:** appen frågar Android (`PackageManager`) vilket
  certifikat den är signerad med, och visar dess SHA-256. Det kräver lite
  Kotlin i `android/`, men inget nytt beroende. Från Android 9 finns
  `signingInfo`, och med `minSdk` 28 (beslut 5) behövs bara det. Det är
  **ej provat**.
- **Debug-byggen** är signerade med en debugnyckel och visar därför ett
  annat fingeravtryck. Appen bör skriva tydligt att det är ett debug-bygge.
- **Vad det inte bevisar:** en ändrad, falsk app kan skriva vilket
  fingeravtryck som helst på skärmen. Värdet i appen är bra för att
  upptäcka misstag och för att jämföra när man träffas, men det är ingen
  kontroll. Den riktiga kontrollen görs utanför appen, med `apksigner`
  eller ett verifieringsverktyg, före installationen.
- **Alternativ:**
  - (2c) visa fingeravtrycket, med texten ovan om vad det betyder;
  - (2d) visa det inte, och bara hänvisa till hemsidan.

### Den privata nyckeln finns aldrig i repot eller CI

- Redan i dag ignoreras `*.jks`, `*.keystore` och `key.properties`
  (`docs/release.md`, punkt 1–2).
- Ett test kan dessutom stoppa en commit som innehåller en nyckelfil eller
  `key.properties` (ett eget paket).
- Release-bygget sker på ägarens dator, och inget CI-jobb får nyckeln.
  Ett CI-jobb som bygger en release får bara ägaren merga (`CLAUDE.md`).

**Rekommendation:**
- **Fingeravtryck:** (2a), som ägaren vill, med ett test som jämför
  certifikatets fingeravtryck i README och SECURITY.md. Om ägaren hellre vill
  ha färre kopior som kan bli fel: (2b).
- **Appens fingeravtryck:** (2c), med texten om vad det inte bevisar.

## 3. Uppdateringskontroll

### Alternativ

- **(3a) Ingen kontroll**, som i dag. Användaren tittar på hemsidan eller
  använder Obtainium. Appen pratar bara med servern.
- **(3b) Ägarens förslag:** frivillig, avstängd från början, hämtar bara en
  versionsfil och visar bara "ny version finns" med en fast länk.
- **(3c) Bara Obtainium**, utanför appen. Det fungerar redan med (1a).
- **(3d) Appen laddar ner och installerar själv.** **Rekommenderas inte.**
  - Det kräver behörigheten `REQUEST_INSTALL_PACKAGES`, som CI:s kontroll
    av manifestet stoppar i dag.
  - F-Droid kräver ett tydligt samtycke för sådant.
  - Den som tar över versionsfilen eller nedladdningen kan få appen att
    hämta något annat.

### Hur (3b) skulle fungera

- **Avstängd från början**, med ett eget val under Inställningar. Ingenting
  hämtas förrän användaren slår på det.
- **Bara en versionsfil**, med en fast adress i appen. Filen innehåller
  bara versionsnumret, till exempel `{"versionCode": 2}`. Appen jämför det
  med sitt eget versionCode, som den kan få från Android (`PackageManager`),
  utan nytt beroende.
- **Samma anrop för alla:**
  - en vanlig `GET` utan parametrar, utan cookies och utan `User-Agent`,
    precis som relay-klienten redan gör (`lib/features/transport/relay_client.dart`:
    "No `User-Agent` header, and no cookies or other state");
  - inget id, ingen version och inget om telefonen i anropet.
- **Bara när appen är öppen och högst en gång om dagen.** Tiden för den
  senaste kontrollen sparas på telefonen. Ett misslyckat anrop försöks
  inte igen samma dag.
- **Visar bara "Ny version finns"**, med en fast länk i appen till
  hemsidan. Länken kommer aldrig från versionsfilen.
- **Laddar aldrig ner** APK:er eller något annat än versionsfilen.

**Vad en falsk eller ändrad versionsfil kan göra:**

- visa "ny version finns" när det inte finns någon;
- dölja en ny version.

Den kan inte styra användaren till en annan sida eller få appen att hämta
något. Det är skälet till att länken är fast.

**Vem som ser vad:**

- Värden för versionsfilen ser telefonens IP-adress och när den frågar,
  högst en gång om dagen.
- Den kan se ungefär hur många som har kontrollen påslagen.
- Ligger filen på GitHub ser GitHub (Microsoft) detta.
- Samma IP-adress syns också för servern vid hämtningar. Om två
  operatörer jämför sina listor kan de koppla ihop dem. Med VPN ser ingen av
  dem den riktiga IP-adressen.

### Var versionsfilen ligger

| Alternativ | Vem ser IP-adressen | Kommentar |
| --- | --- | --- |
| En fil i repot eller på GitHub Pages | GitHub | Enklast. Samma värd som releaserna |
| GitHub:s API för releaser | GitHub | Svaret är stort och kan ändras. Gränsen är 60 anrop i timmen per IP-adress (**ej kontrollerat** här) |
| Egen hemsida | Hemsidans värd | Ägaren står för servern |
| Servern (relayn) | Servern, som redan ser IP-adressen | Ingen ny part, men relayn är "bara lämna och hämta" (0002). Den som driver en annan server kan ljuga om versionen |

### Texten i appen (godkänd av ägaren 2026-11-25, 0002)

Under Inställningar, vid valet "Sök efter ny version":

> När det här är på frågar appen GitHub högst en gång om dagen, medan
> appen är öppen, om det finns en ny version. Frågan är likadan för alla
> och innehåller inga uppgifter om dig eller dina kontakter. GitHub ser din
> IP-adress och när du frågar. Vi rekommenderar VPN om du inte vill att
> GitHub ska se din IP-adress.

När det finns en ny version:

> Det finns en ny version av SHA. Hämta den från [hemsidans adress] och
> kontrollera fingeravtrycket innan du installerar den.

Den sista meningen i inställningstexten följer formen i den godkända
VPN-meningen (0008), med "GitHub" i stället för "servern". Ord som 0002
förbjuder, som "anonym" och "inga loggar", används inte.
`test/security/wording_test.dart` kontrollerar det när texten finns.

**Det här skulle också ändras:**

- `docs/data-safety.md` och `docs/integritetspolicy.md`: att GitHub, eller
  den värd som väljs, får IP-adressen när kontrollen är på;
- "Teknisk information": ett eget avsnitt om kontrollen.

**Rekommendation: (3b) med versionsfilen på GitHub Pages** (samma värd som
hemsidan om den ligger där), plus Obtainium på hemsidan för den som vill
ha automatiska uppdateringar. Om ägaren hellre vill att appen bara pratar
med servern: (3a).

## Googles utvecklarverifiering 2027

Från Googles sidor för utvecklare (developer.android.com/developer-verification
och dess FAQ, med datum per svar):

### Tidsplan

- **Augusti 2026:** konton för begränsad utdelning ("limited
  distribution") och det avancerade flödet för användare ("advanced flow").
- **30 september 2026:** bara utvalda butiker i Brasilien, Indonesien,
  Singapore och Thailand.
- **2027:** "Verification capability will be expanded globally for all
  apps on certified Android devices in 2027."
- **Hemsidor och andra butiker omfattas inte än** (FAQ, 15 juli 2026): "If
  you distribute your app through other stores, or if users sideload your
  app directly, these new verification requirements won't apply to your
  app yet."
- **Telefoner:** "all certified Android devices running Android 8 (API
  level 26) or higher" (FAQ, 10 november 2026).

### Registrering

- **Fullt konto:** 25 dollar och id-kontroll med legitimation (FAQ, 25
  mars 2026).
- **Konto för begränsad utdelning:** gratis och utan legitimation. Enligt
  FAQ:n (18 juni 2026) gäller det "up to 20 specific devices", men sidan om
  kontot säger "up to 50 devices". **Sidorna säger emot varandra.**
- **Paketnamn:** varje paketnamn registreras med certifikatets SHA-256.
  Flera nycklar per paket går att lägga till. "If you lose your signing key
  you won't be able to register your packages." (FAQ, 23 mars 2026)

### Det avancerade flödet och ADB

- Användaren gör en engångsinställning (FAQ, 23 mars 2026):
  1. slår på utvecklarläget;
  2. går igenom en kontroll att ingen styr hen;
  3. startar om telefonen och loggar in igen;
  4. väntar ett dygn;
  5. bekräftar med fingeravtryck eller PIN.
- "Unregistered apps can only be installed or updated when the advanced
  flow is enabled or by using ADB." Det gäller också uppdateringar.
- **ADB** påverkas inte (FAQ, 23 mars 2026).

### F-Droid

F-Droid (öppet brev, 24 februari 2026) avråder: "We unequivocally advise
against signing up for this program, now or ever."

### Ej läst eller oklart

- Hur telefoner utan Googles certifiering, som GrapheneOS, behandlas.
- Googles blogginlägg om det avancerade flödet.

### Vad det betyder för (1a)

- **Fram till 2027:** inget ändras för den som installerar från hemsidan.
- **Från 2027** finns tre vägar:
  - **(V1)** Ägaren registrerar SHA med ett fullt konto: legitimation och
    25 dollar. Google får ägarens identitet och appens paketnamn och
    fingeravtryck.
  - **(V2)** Ägaren registrerar med ett gratis begränsat konto, för högst
    20 eller 50 telefoner. Det räcker för testfasen.
  - **(V3)** Ingen registrering. Användarna slår på det avancerade flödet
    med ett dygns väntan, eller installerar med ADB. Det gäller också varje
    uppdatering.
- **Rekommendation:** (V2) eller ADB för testfasen. Ett beslut om (V1)
  eller (V3) före en öppen utdelning 2027, när Googles sidor har lästs igen.

## Signeringsnyckeln: skydd och säkerhetskopia

### Skydd

- **Bara ägaren** skapar, förvarar och använder nyckeln (`CLAUDE.md`,
  "Aldrig"). Nyckelfilen och lösenorden förs aldrig in i repot, CI,
  GitHub-hemligheter, en chatt eller en molnmapp som synkas.
- Med (1a) är ägarens nyckel **appens egen signeringsnyckel**, inte bara en
  uppladdningsnyckel som i Play. Den är viktigare än det
  `docs/release.md`, punkt 1, beskriver i dag.
- Nyckelfilen är krypterad (PKCS12) med ett långt lösenord, och ligger
  på ägarens dator eller, bättre, på ett krypterat USB-minne som bara sitter
  i när en release signeras.
- **Signering** sker på ägarens dator, och fingeravtrycket kontrolleras
  före varje uppladdning.

### Säkerhetskopia

- **Två krypterade kopior offline**, på olika platser, till exempel två
  USB-minnen, ett hemma och ett annat ställe.
- **Lösenordet förvaras för sig**, på papper eller i en
  lösenordshanterare, inte med kopiorna.
- **Prova en återställning en gång:** signera ett test-APK med kopian och
  jämför fingeravtrycket.
- **Skriv ner fingeravtrycket på papper** med kopiorna, så att det går att
  se att det är rätt nyckel.

### Om nyckeln försvinner eller läcker

- **Försvinner den:**
  - inga fler uppdateringar under samma nyckel;
  - Google: "you won't be able to register your packages";
  - alla användare måste avinstallera och förlorar då identiteten och
    kontakterna.
- **Läcker den** kan vem som helst signera "uppdateringar" som telefonerna
  godtar.
  - Android kan byta nyckel med APK Signature Scheme v3, men bara från
    Android 9 (API 28), enligt Androids dokumentation. Den är **ej läst
    här**.
  - SHA stödde Android 7 och senare (`minSdk` minst 24), och äldre
    telefoner godtar inte den nya nyckeln.
  - Beslut 5: `minSdk` höjs till 28 före första utdelningen (F13).
- **En hårdvarunyckel**, till exempel PKCS#11, är kanske möjlig med
  `apksigner`. Det är **ej kontrollerat**, och kan bli ett senare val.

## Vilka paket i färdplanen som ändras

Efter ägarens beslut 2026-11-25.

| Paket | I dag | Efter beslutet |
| --- | --- | --- |
| Fas 3, "Klart när" | Publicerad i produktion på Google Play | Version 1.0 publicerad som signerad APK på hemsidan och i GitHub Releases, med certifikatets fingeravtryck på alla fyra ställen och APK:ns SHA-256 i releasen och på hemsidan |
| F9 | Plays krav: målnivå, stängt test, Data safety, integritetspolicy | Krav för utdelning utanför Play: utvecklarverifieringen (läs Googles sidor igen före släppet), Androids installationsflöde och, senare, F-Droids krav. Målnivån behålls |
| F10 | Integritetspolicy och Data safety (klart) | Data safety behövs inte för Play. Underlaget behålls som en beskrivning av datan. Integritetspolicyn får ett stycke om uppdateringskontrollen om (3b) väljs |
| F11 | Butikstexter med Plays längder, skärmbilder | Texterna blir hemsidans och releasens texter, och Plays längder gäller inte. Skärmbilderna behålls. Senare: F-Droids metadata |
| F12 | Version och ändringslogg | Behålls. Ändringsloggen blir releasens text, och versionCode ska fortfarande öka |
| G9 | Utvecklarkonto i Play och uppladdningsnyckel | Signeringsnyckeln skapas, förvaras och säkerhetskopieras enligt ovan. Ägaren beslutar om utvecklarverifieringen (V1, V2 eller V3) |
| G10 | Integritetspolicyn på webben | Samma, på hemsidan |
| G11 | Internt test, stängt test och produktion i Play | Ägaren bygger och signerar, kontrollerar fingeravtrycket, installerar först på egna telefoner, delar ut till testare efter G6, G8 och allt under "Före första utdelning", och publicerar sedan releasen med fingeravtrycken |
| `docs/release.md` | Checklista för Play | Skrivs om för hemsidan och GitHub Releases |
| `CLAUDE.md`, "Ägarens beslut" punkt 3 | Nämner Play-kraven | Ägarens avsnitt; Claude föreslår bara en ändring |

### Nya paket

- **F13 – Utdelning utan Play.** Nytt `docs/release.md` med stegen för
  att bygga, signera, kontrollera och publicera. Plats för certifikatets
  fingeravtryck i README och SECURITY.md (värdet skrivs in i G9), en länk
  därifrån till releasen för APK:ns SHA-256, och ett test som jämför
  fingeravtrycken. Ett test som stoppar
  nyckelfiler i repot. Texter till hemsidan och releasen.
- **F14 – Appens fingeravtryck i "Teknisk information"** (2c).
- **F15 – Frivillig uppdateringskontroll** (3b): valet, texterna,
  versionsfilen, tester för att den aldrig körs när den är av, högst en
  gång om dagen och utan något i anropet, och ändringar i Data
  safety-underlaget och integritetspolicyn.

Ordningen blir F12, F13, F14, F15, och sedan G9–G11.

## Ägaren beslutar

1. **Utdelning:**
   - [x] (1a) hemsidan och GitHub Releases;
   - [ ] (1b) bara GitHub;
   - [ ] (1c) bara en egen hemsida.

   F-Droid efter G8, med ägarens nyckel om det går. Google Play skjuts
   upp.
2. **Fingeravtryck:**
   - [x] (2b): APK:ns SHA-256 bara i releasen och på hemsidan;
   - [x] (2c): appen visar sitt eget fingeravtryck, med texten om vad det
     inte bevisar;
   - [x] `SHA256SUMS` signeras inte nu.
3. **Uppdateringskontroll:**
   - [x] (3b) frivillig enligt ovan;
   - [x] versionsfilen ligger på GitHub Pages;
   - [x] texterna i appen enligt förslaget ovan.
4. **Utvecklarverifiering:**
   - [x] ADB eller (V2) under testfasen; (V1) eller (V3) beslutas 2027.
5. **Övrigt:**
   - [x] `applicationId` byts till `io.github.w1sam1one.sha` före första
     utdelningen;
   - [x] `minSdk` höjs till 28.

## Ej läst eller ej provat

- Googles blogginlägg om det avancerade flödet, och Googles hjälpsidor på
  support.google.com, som är spärrade i molnmiljön.
- Hur telefoner utan Googles certifiering, som GrapheneOS, påverkas.
- Om SHA:s bygge går att reproducera (Flutter och Rust via cargokit).
- Androids dokumentation om nyckelbyte (APK Signature Scheme v3).
- Vem som äger domänen `sha.se`.
- Verktyget "Verified Apps".
- Utskriften från `apksigner verify --print-certs`.
- Att läsa appens eget certifikat med `PackageManager` på Android 7–14.
- GitHub:s gräns för anrop mot API:t.

## Källor (lästa 2026-11-23)

- Google, utvecklarverifiering:
  https://developer.android.com/developer-verification, FAQ:
  https://developer.android.com/developer-verification/guides/faq.md.txt
  (datum per svar, senast 10 november 2026), konto för begränsad
  utdelning:
  https://developer.android.com/developer-verification/guides/limited-distribution.md.txt
  och registrering av appar med öppen källkod:
  https://developer.android.com/developer-verification/guides/open-source-app-registration.md.txt
- Google, Play App Signing:
  https://developer.android.com/studio/publish/app-signing
- Google, apksigner: https://developer.android.com/tools/apksigner
- F-Droid, Inclusion Policy och Reproducible Builds, lästa i F-Droids repo
  för webbplatsen (f-droid.org var spärrad):
  https://gitlab.com/fdroid/fdroid-website/-/raw/master/_docs/Inclusion_Policy.md
  och
  https://gitlab.com/fdroid/fdroid-website/-/raw/master/_docs/Reproducible_Builds.md
- F-Droid, "An Open Letter Opposing Android Developer Verification", 24
  februari 2026:
  https://gitlab.com/fdroid/fdroid-website/-/raw/master/_posts/2026-02-24-open-letter-opposing-developer-verification.md
- Obtainium, README: https://github.com/ImranR98/Obtainium
