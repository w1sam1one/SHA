# 0014 – Utdelning: egen hemsida, F-Droid, Obtainium eller Google Play

Status: **Proposed – owner decides.** Skrivet 2026-11-23. **Inget byggs
förrän ägaren har beslutat.** Det här är inte juridisk rådgivning.

Källorna lästes 2026-11-23 och står sist med adress. Det som inte gick att
läsa eller pröva är märkt **ej läst** eller **ej provat**.

## Varför ett beslut behövs

- Ägaren vill dela ut appen som APK från en hemsida i stället för via
  Google Play.
- Fas 3 i färdplanen är byggd kring Google Play:
  - F9 gäller Plays krav;
  - F10 gäller Data safety;
  - F11 gäller butikstexter med Plays längder;
  - G9 är ett utvecklarkonto hos Google;
  - G11 är internt och stängt test i Play Console.
- Några val går inte att ändra efteråt utan att användarna förlorar sina
  data. Det gäller vem som signerar appen, med vilken nyckel, och appens
  `applicationId`. Se "Det som gäller oavsett kanal".
- Googles utvecklarverifiering påverkar alla kanaler från 2027, också
  hemsidor och F-Droid.

## Det som gäller oavsett kanal

- **Grindarna står kvar.**
  - Ingen utdelning till någon annan än ägaren före G6 (kryptoexperten).
  - `LICENSE` byts till AGPL-3.0 före första utdelningen (G8, 0012).
- **Bara ägaren delar ut.** Claude bygger inte release, laddar inte upp,
  skapar inga konton och rör inga nycklar (`CLAUDE.md`, "Aldrig").
- **Samma nyckel för alla uppdateringar.** Android installerar en
  uppdatering bara om den är signerad med samma nyckel som appen som redan
  finns på telefonen. Det är Androids vanliga regel; **ej provat här**.
  Den första installationen avgör alltså vilken nyckel telefonen litar på.
- **Nyckelbyte betyder att data försvinner.** Byter appen nyckel eller
  kanal måste användaren avinstallera den. SHA har ingen säkerhetskopia
  (`allowBackup="false"` i manifestet), så identiteten, kontakterna och historiken
  försvinner. Användarna måste då träffas och skanna varandras QR-koder
  igen.
- **`applicationId` är `se.sha.sha`** (`android/app/build.gradle.kts`).
  - F-Droid råder till ett id från en domän som utvecklaren äger.
  - Google kan vägra registrera ett paketnamn som redan används av någon
    annan (FAQ, se nedan).
  - Vem som äger domänen `sha.se` är **ej kontrollerat**.
  - Ett annat id blir en annan app för telefonen, så det måste bestämmas
    före första utdelningen.

## Googles utvecklarverifiering

Det här står på Googles egna sidor för utvecklare
(developer.android.com/developer-verification och dess FAQ, med datum per
svar).

### Tidsplan

- **Augusti 2026:** konton för begränsad utdelning ("limited distribution
  accounts") och det avancerade flödet för användare ("advanced flow")
  lanseras.
- **30 september 2026:** "Protections begin for users installing apps from
  participating stores in select regions on certified Android devices".
  Det gäller Brasilien, Indonesien, Singapore och Thailand.
- **2027:** "Verification capability will be expanded globally for all
  apps on certified Android devices in 2027." Tidningar skriver januari
  2027, men Googles egen sida säger bara 2027.
- **Hemsidor och andra butiker gäller inte än** (FAQ, 15 juli 2026): "If
  you distribute your app through other stores, or if users sideload your
  app directly, these new verification requirements won't apply to your
  app yet." Google rekommenderar ändå att man registrerar sig före den
  globala starten 2027.
- **Vilka telefoner:** "all certified Android devices running Android 8
  (API level 26) or higher", levererat via Google Play-tjänster (FAQ, 10
  november 2026).

### Vad utvecklaren registrerar

- **Fullt konto ("Full Distribution"):** 25 dollar (FAQ, 25 mars 2026).
  Det kräver id-kontroll med legitimation, och för en organisation ett
  D-U-N-S-nummer.
- **Konto för begränsad utdelning:** gratis och utan legitimation. FAQ:n
  (18 juni 2026) säger att appen kan delas "with up to 20 specific devices
  for testing and personal use". Sidan om kontotypen säger "up to 50
  devices". **Sidorna säger emot varandra.** Kontot kräver ett
  Google-konto, tvåstegsverifiering och en betalprofil hos Google.
- **Paketnamn och nyckel:**
  - Varje paketnamn registreras med SHA-256-fingeravtrycket för
    signeringsnyckelns certifikat.
  - Flera nycklar per paket går att lägga till (FAQ, 23 mars 2026).
  - "If you lose your signing key you won't be able to register your
    packages." (FAQ, 23 mars 2026)
  - Ett paketnamn som någon annan redan använder kräver en extra granskning
    (FAQ, 19 mars 2026).
- **Appar i Play App Signing** registreras automatiskt (FAQ, 3 september
  2025).
- **Om integriteten:** "Developers who want to remain unverified can use a
  limited distribution account, which requires no ID verification. Or you
  can distribute your unregistered app to users who have activated
  advanced flow." (FAQ, 18 juni 2026)

### Det avancerade flödet och ADB

- **Det avancerade flödet** är en engångsinställning på telefonen (FAQ, 23
  mars 2026). Användaren
  1. slår på utvecklarläget;
  2. går igenom en kontroll att ingen styr hen;
  3. startar om telefonen och loggar in igen;
  4. väntar ett dygn ("a one-time, one-day wait");
  5. bekräftar med fingeravtryck eller PIN.

  Därefter kan appar från overifierade utvecklare installeras, med en
  varning, i 7 dagar eller tills vidare.
- **Uppdateringar:** "Unregistered apps can only be installed or updated
  when the advanced flow is enabled or by using ADB." (FAQ)
- **ADB:** "there are no changes to how ADB works". Väntetiden gäller inte
  ADB (FAQ, 23 mars 2026). Ägarens egen installation med `adb install` i
  `docs/prototyp.md` påverkas alltså inte.

### F-Droids hållning

F-Droids öppna brev från 24 februari 2026:

- Registreringen gäller enligt F-Droid all utdelning, "even by offering
  your app as a direct download from a web page".
- Enligt F-Droid kontaktar telefonen Google vid installationen för att
  kontrollera utvecklaren och appen. **Det är F-Droids påstående**; Googles
  sidor beskriver inte hur kontrollen görs.
- F-Droid skriver: "We unequivocally advise against signing up for this
  program, now or ever."

### Ej läst eller oklart

- Googles blogginlägg om det avancerade flödet (goo.gle/advance-flow) är
  **ej läst**.
- Hur telefoner utan Googles certifiering, till exempel GrapheneOS,
  behandlas står inte på sidorna som lästes.

### Vad det betyder för SHA

- **Hemsida och F-Droid:** från 2027 behöver användare med vanliga
  Android-telefoner något av tre saker. Antingen har ägaren registrerat
  SHA (fullt konto, eller begränsat konto för högst 20 eller 50
  telefoner), eller så slår användaren på det avancerade flödet med ett
  dygns väntan, eller så installerar hen med ADB.
- **Google Play:** registreringen sker automatiskt.

## Alternativen

### (A) Egen hemsida och GitHub Releases

- **Så går det till:**
  - Ägaren bygger och signerar release-APK:n på sin egen dator (0007 (b)
    säger redan att ägaren bygger själv).
  - Ägaren laddar upp den till en GitHub Release med versionen som tagg,
    tillsammans med en fil med SHA-256 för APK:n.
  - Hemsidan länkar till releasen och visar fingeravtrycken. Den kan ligga
    på GitHub Pages, som inte kräver någon egen server, eller på en egen
    server som ägaren står för.
  - Integritetspolicyn (G10) kan ligga på samma sida.
- **Uppdateringar:**
  - Appen letar inte själv efter uppdateringar. Relayn är den enda server
    appen pratar med (0002). En egen uppdateringskontroll skulle avslöja
    för GitHub eller hemsidan vem som har appen och när den används, och
    den kräver ett eget beslut.
  - Användaren tittar själv på hemsidan, eller följer releaserna med
    Obtainium (B).
- **Vem ser nedladdningen:**
  - Med GitHub ser GitHub (Microsoft) IP-adressen hos den som laddar ner,
    och kan spara den.
  - Med en egen server ser den som driver servern samma sak.
- **Signering:** ägarens egen nyckel. Den lämnar aldrig ägarens dator, och
  ingen annan kan signera en uppdatering.
- **Fördelar:**
  - Ägaren har full kontroll över nyckeln.
  - Inget konto hos Google krävs för själva utdelningen.
  - Inga krav på Data safety eller stängt test.
  - Passar med AGPL-3.0 och öppen källkod.
- **Nackdelar:**
  - Användaren måste tillåta "installera okända appar".
  - Det finns inga automatiska uppdateringar.
  - Från 2027 tillkommer utvecklarverifieringen (se ovan).
  - Den som har fel APK, till exempel från en falsk sida, märker det bara om
    hen kontrollerar fingeravtrycket.

### (B) Obtainium, ihop med (A)

- **Vad det är:**
  - Obtainium är ingen egen kanal. Det är en app på användarens telefon som
    följer releaser och installerar uppdateringar.
  - README: "Obtainium allows you to install and update apps directly from
    their releases pages, and receive notifications when new releases are
    made available."
  - Den kan följa GitHub, GitLab, Codeberg, F-Droid och IzzyOnDroid, och
    även en vanlig webbsida med APK-länkar.
- **Kontrollen av nyckeln:**
  - Obtainium själv kontrollerar inte signaturen, enligt diskussioner hos
    GrapheneOS. Det är **ej kontrollerat i koden**.
  - Androids regel om samma nyckel gäller ändå för varje uppdatering.
  - För den första installationen rekommenderar README verktyget "Verified
    Apps" (github.com/privacyguides/verified-apps-android). Verktyget är
    **ej läst** här.
- **Vem ser vad:** Obtainium frågar GitHub om nya releaser, så GitHub ser
  telefonens IP-adress och när den frågar.
- **Nackdel:** användaren måste först installera Obtainium. Det är ett
  extra steg för den som inte är van.

### (C) F-Droid

- **Krav för att komma med** (F-Droids "Inclusion Policy"):
  - Koden måste vara fri programvara, till exempel GPL. Det är möjligt
    först efter G8, för i dag är koden "All rights reserved".
  - F-Droid bygger appen själv från källkoden, med fria verktyg.
  - Flutters och Androids SDK får användas som färdiga binärer, liksom
    Rust/Rustup och bibliotek från Google Maven.
  - Spårning och reklam är förbjudet. SHA har ingen sådan kod sedan 0012
    (C1).
  - Appen ska ha utvecklats aktivt i minst 3 månader.
- **Signering:**
  - F-Droid signerar som standard med en egen nyckel. Då kan användaren
    inte byta mellan F-Droids och hemsidans APK utan att avinstallera och
    förlora sina data.
  - Med reproducerbara byggen kan F-Droid i stället publicera APK:er med
    utvecklarens egen signatur (`Binaries` och `AllowedAPKSigningKeys`).
    Det kräver att F-Droids bygge blir byte för byte samma som ägarens.
  - Om SHA:s bygge går att reproducera, med Flutter och Rust via cargokit,
    är **ej provat**.
- **Uppdateringar:** via F-Droid-appen. Hur lång tid F-Droids bygge tar är
  **ej kontrollerat**.
- **Uppdateringskontroll:** F-Droid förbjuder appar som laddar ner kod
  eller uppdateringar utan att användaren tydligt har gått med på det.
  Det stämmer med att SHA inte har någon uppdateringskontroll.
- **Utvecklarverifieringen:**
  - F-Droid avråder från registrering.
  - Googles guide för öppen källkod säger att man kan registrera
    fingeravtrycket för butikens nyckel.
  - Hur F-Droid fungerar för användarna efter 2027 är oklart.

### (D) Google Play

Det är dagens plan.

- **Signering:**
  - Play App Signing krävs för nya appar. "Google manages and protects your
    app's signing key for you and uses it to sign your APKs for
    distribution."
  - Ägaren kan välja att lämna sin egen nyckel till Google, så att samma
    nyckel gäller i andra kanaler. Det måste väljas när Play App Signing
    sätts upp, och nyckeln går inte att få tillbaka från Google.
- **Uppdateringar** sker automatiskt genom Play Butik, och installationen
  är enklast för användaren.
- **Utvecklarverifieringen** sköts automatiskt.
- **Krav:**
  - ett utvecklarkonto med legitimation och avgift (G9);
  - stängt test med 12 testare i 14 dagar för nya personliga konton, vilket
    är **ej verifierat** (`docs/play-krav.md`);
  - Data safety (F10), målnivå (F9) och Googles regler i övrigt.
- **Förtroende:**
  - Google har en nyckel som kan signera uppdateringar till SHA. För en
    säkerhetsapp betyder det att användarna också litar på Google.
  - Googles "code transparency" kan visa att koden är ägarens. Den är **ej
    läst** här.

## Jämförelse

| | (A) Hemsida + GitHub | (B) Obtainium (med A) | (C) F-Droid | (D) Google Play |
| --- | --- | --- | --- | --- |
| Vem signerar | Ägaren | Ägaren | F-Droid, eller ägaren med reproducerbart bygge | Google, eller ägarens egen nyckel hos Google |
| Uppdateringar | Användaren hämtar själv | Obtainium meddelar och installerar | F-Droid-appen | Automatiskt |
| Vem ser nedladdningen | GitHub eller hemsidans server | GitHub (eller sidan) | F-Droid | Google |
| Krav före start | G6, G8, nyckel | Som (A) | G6, G8, att F-Droid tar med appen | G6, G8, konto, stängt test, Data safety |
| Utvecklarverifiering 2027 | Ägaren registrerar, eller användaren använder det avancerade flödet | Som (A) | Oklart; F-Droid avråder | Automatiskt |
| Svårt för användaren | Okända appar tillåts, fingeravtryck kontrolleras | Som (A), plus Obtainium | F-Droid-appen | Lätt |
| Arbete för ägaren | Bygga, signera, ladda upp | Som (A) | Byggrecept, vänta på F-Droid | Mest: konto, test, formulär |
| Går att ändra senare | Ja, om nyckeln är densamma | Ja | Bara med reproducerbart bygge | Bara med egen nyckel hos Google |

## Fingeravtryck och SHA-256

Det finns två olika värden.

1. **SHA-256 för APK-filen:** till exempel `sha256sum SHA-1.0.0.apk`. Det
   ändras vid varje release och visar att filen inte har ändrats på
   vägen.
2. **SHA-256 för signeringscertifikatet:** `apksigner verify --print-certs
   SHA-1.0.0.apk`, eller `keytool -list -v` på nyckelfilen. Det är
   detsamma för alla releaser, och det är det värde som telefonen litar på.
   Exakt vad `apksigner` skriver ut är **ej provat här**.

Förslag:

- **Certifikatets fingeravtryck publiceras på flera oberoende ställen:**
  README i repot, hemsidan, varje GitHub Release och `docs/release.md`.
  Den som vill fejka det måste då ändra alla ställen.
- **Fingeravtrycket kan jämföras när man träffas.** SHA:s idé är förtroende
  som skapas när man ses. Appen kan visa sitt eget fingeravtryck under
  "Teknisk information", så att två användare kan jämföra det när de
  skannar varandras QR-koder. Det kräver inget nytt beroende, eftersom
  Android ger appen sin egen signatur. Det blir i så fall ett eget paket
  efter beslutet.
- **Fillistan med SHA-256 kan signeras,** till exempel med
  `ssh-keygen -Y sign`, som finns i OpenSSH på de flesta datorer. Den
  offentliga nyckeln står då i repot. Det skyddar mot en ändrad fillista
  på GitHub, men det viktiga är certifikatets fingeravtryck. Ägaren
  avgör.
- **Användaren kontrollerar den första installationen:** med `apksigner`
  på en dator, eller med en app på telefonen som "Verified Apps"
  (**ej läst** här). Instruktionen står på hemsidan.

## Signeringsnyckeln

- **Bara ägaren** skapar, förvarar och använder nyckeln (`CLAUDE.md`,
  "Aldrig"). Nyckelfilen och lösenorden förs aldrig in i repot, CI,
  GitHub-hemligheter, en chatt eller en molnmapp som synkas.
- **Med (A), (B) eller (C) med reproducerbart bygge** är ägarens nyckel
  appens egen signeringsnyckel, inte bara en uppladdningsnyckel som i
  Play. Den är då ännu viktigare än det `docs/release.md`, punkt 1,
  beskriver.
- **Signering** sker på ägarens dator. Ett release-bygge i CI är något
  bara ägaren får merga (`CLAUDE.md`), och det rekommenderas inte här.
- **Säkerhetskopia:**
  - två krypterade kopior av nyckelfilen offline, på olika platser, till
    exempel två USB-minnen;
  - lösenordet förvarat för sig, till exempel på papper eller i en
    lösenordshanterare;
  - en provad återställning en gång.
- **Om nyckeln försvinner:**
  - Inga fler uppdateringar under samma nyckel.
  - Google: "you won't be able to register your packages".
  - Alla användare måste avinstallera, och då försvinner identiteten och
    kontakterna.
- **Om nyckeln läcker** kan vem som helst signera "uppdateringar" som
  telefonerna godtar.
  - Android kan byta nyckel med APK Signature Scheme v3 och ett bevis för
    bytet, men bara från Android 9 (API 28), enligt Androids
    dokumentation. Den är **ej läst här**.
  - SHA stöder Android 7 och senare (`minSdk` är minst 24 i
    `android/app/build.gradle.kts`), och äldre telefoner godtar då inte den
    nya nyckeln.
  - Att höja `minSdk` till 28 före första utdelningen är en fråga för
    ägaren.
- **En hårdvarunyckel**, till exempel PKCS#11, är kanske möjlig med
  `apksigner`. Det är **ej kontrollerat**, och kan bli ett senare val.
- **Om (D) väljs senare:** ladda upp den egna nyckeln till Play App Signing
  i stället för att låta Google skapa en ny. Då gäller samma nyckel
  överallt.

## Vilka paket i färdplanen som ändras

Om ägaren väljer (A)+(B), som rekommenderas nedan. Inget av detta görs
förrän ägaren har beslutat.

| Paket | I dag | Med (A)+(B) |
| --- | --- | --- |
| Fas 3, "Klart när" | Publicerad i produktion på Google Play | Version 1.0 publicerad som signerad APK på hemsidan och i GitHub Releases, med fingeravtryck |
| F9 | Plays krav: målnivå, stängt test, Data safety, integritetspolicy | Krav för utdelning utanför Play: utvecklarverifieringen (läs Googles sidor igen före släppet), Androids installationsflöde och, om (C) väljs, F-Droids krav. Målnivån behålls |
| F10 | Integritetspolicy och Data safety (klart) | Data safety behövs inte. Integritetspolicyn behålls och ligger på hemsidan |
| F11 | Butikstexter med Plays längder, skärmbilder | Texterna blir hemsidans och releasens texter, och Plays längder gäller inte. Skärmbilderna behålls. Vid (C): F-Droids metadata |
| F12 | Version och ändringslogg | Behålls. Ändringsloggen blir releasens text, och versionCode ska fortfarande öka |
| G9 | Utvecklarkonto och uppladdningsnyckel | Signeringsnyckeln skapas och förvaras enligt ovan. Ägaren beslutar om kontot för utvecklarverifiering: fullt, begränsat eller inget |
| G10 | Integritetspolicyn på webben | Samma, på hemsidan |
| G11 | Internt test, stängt test och produktion i Play | Ägaren bygger, signerar och kontrollerar fingeravtrycket, installerar först på egna telefoner, delar ut till testare efter G6 och publicerar sedan releasen |
| `docs/release.md` | Checklista för Play | Skrivs om för den valda kanalen, i ett eget paket |
| `CLAUDE.md`, "Ägarens beslut" punkt 3 | Nämner Play-kraven | Ägarens avsnitt; Claude föreslår bara en ändring |

Ett nytt paket kan läggas till: **appens eget fingeravtryck i "Teknisk
information"** (se ovan), om ägaren vill.

## Rekommendation

**(A)+(B)**, med F-Droid (C) som ett senare val efter G8.

- **(A):** APK:n i GitHub Releases, med en hemsida som visar
  fingeravtrycken. Ägarens egen nyckel. Ingen uppdateringskontroll i appen.
- **(B):** Obtainium rekommenderas som sättet att få uppdateringar.
- **(C) senare:** helst med reproducerbart bygge och ägarens egen
  signatur, så att nyckeln blir densamma.
- **(D) inte nu.** Vägen dit hålls öppen genom att den egna nyckeln
  sparas, så att den kan lämnas till Play App Signing.

Varför:

- Ägaren vill det.
- Ingen annan än ägaren kan signera SHA.
- Färre beroenden av Google: inget stängt test, ingen Data safety och
  inget konto för själva utdelningen.
- Det passar med öppen källkod efter G8.

Nackdelarna är tydliga:

- installationen och uppdateringarna blir krångligare;
- GitHub ser vem som laddar ner;
- från 2027 krävs registrering, det avancerade flödet eller ADB.

För testfasen, med ägaren och några testare efter G6, räcker troligen ADB
eller ett gratis konto för begränsad utdelning. Det skulle i så fall vara
ägarens val. Före en öppen utdelning 2027 behöver ägaren välja mellan ett
fullt konto (legitimation, 25 dollar) och att be användarna slå på det
avancerade flödet.

## Ägaren beslutar

- [ ] **Kanal:** (A), (A)+(B), (C), (D) eller en kombination.
- [ ] **Utvecklarverifiering:** registrera med fullt konto, registrera
  med begränsat konto, eller inte registrera. Utan registrering
  installerar användarna med det avancerade flödet eller med ADB.
- [ ] **`applicationId`:** behåll `se.sha.sha`, eller byt före första
  utdelningen till ett id från en domän som ägaren äger.
- [ ] **Hemsidan:** GitHub Pages, eller en egen server som ägaren står
  för.
- [ ] **Fillistan med SHA-256:** signera den med `ssh-keygen -Y sign`, eller
  inte.
- [ ] **Appens eget fingeravtryck i "Teknisk information":** ett nytt
  paket, ja eller nej.
- [ ] **`minSdk`:** behåll 24 (Android 7), eller höj till 28 (Android 9)
  så att ett nyckelbyte fungerar på alla telefoner.

## Ej läst eller ej provat

- Googles blogginlägg om det avancerade flödet, och Googles hjälpsidor på
  support.google.com, som är spärrade i molnmiljön.
- Hur telefoner utan Googles certifiering, som GrapheneOS, påverkas.
- Om SHA:s bygge går att reproducera (Flutter och Rust via cargokit), och
  hur lång tid F-Droids bygge tar.
- Androids dokumentation om nyckelbyte (APK Signature Scheme v3).
- Play "code transparency".
- Vem som äger domänen `sha.se`.
- Verktyget "Verified Apps".
- Utskriften från `apksigner verify --print-certs`.

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
