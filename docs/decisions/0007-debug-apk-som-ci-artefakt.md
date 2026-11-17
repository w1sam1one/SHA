# 0007 – Debug-APK till ägaren som CI-artefakt

Status: **Proposed – owner decides.** Skrivet 2026-11-16.

Underlag för grinden G-P8 i [`docs/ROADMAP.md`](../ROADMAP.md). Ingen kod
är ändrad här.

## Varför ett beslut behövs

- P8 och "Klart när" punkt 4 i fas 1: "CI bygger en debug-APK som ägaren
  kan ladda ner och installera."
- I dag laddar CI inte upp några filer. Workflowen använder bara
  `actions/checkout` och `actions/setup-go`.
- Att ladda upp en fil kräver `actions/upload-artifact`. Det är ett nytt
  beroende, och `CLAUDE.md` ("Aldrig") tillåter inte ett beroende som inte
  står i ett godkänt beslutsunderlag.

## Fakta

- **Vem kan hämta en artefakt:** i ett privat repo den som har läsrätt
  till repot, och appar och tokens med läsrätt till Actions (till exempel
  GitHub-appen som Claude-sessionerna använder). Vilka som har läsrätt här
  är **ej verifierat**. Ägaren ser det under Settings › Collaborators.
  `CLAUDE.md` ("Aldrig") tillåter ingen APK till någon annan än ägaren, så
  (a) går bara om ägaren är den enda med åtkomst.
- **Bygget:**
  - Emulatorjobbet bygger i dag en APK med testet
    `integration_test/olm_build_test.dart` som startpunkt, inte appen.
  - Appen måste byggas för sig: `flutter build apk --debug`.
  - Utan `--target-platform` bygger Flutter för arm, arm64 och x86_64, och
    Rust-delen byggs en gång för varje. Förslaget är bara arm64
    (`--target-platform android-arm64`), som riktiga telefoner har. **Ej
    provat i CI.**
- **Signering:** en debug-APK signeras med den debugnyckel som Gradle skapar
  på runnern. Ingen signeringsnyckel, `key.properties` eller lösenord
  hanteras.
  - Runnern är en ny maskin varje gång, så varje körning gör troligen en ny
    debugnyckel (**ej verifierat**). Android installerar inte en
    uppdatering med en annan nyckel: appen måste avinstalleras först, och
    då försvinner identiteten, kontakterna och sessionerna. Båda telefonerna
    måste skanna varandra igen.
  - En fast debugnyckel som hemlighet i CI vore att hantera en
    signeringsnyckel, och det gör bara ägaren (`CLAUDE.md`, "Aldrig").
- **En debug-APK är svagare än en release-APK:** den går att felsöka
  (`run-as`, JDWP och Darts VM-tjänst).
- **Debug-läget har utvecklarhjälp:**
  - kopiera koden på Min QR;
  - ange en kod för hand på skannerskärmen (`kDebugMode`).
  - Det går alltså att lägga till en kontakt utan att mötas. Bra för att
    prova med en emulator, men det är inte "verifierad i person".
- **Ägaren delar inte APK:n vidare** (`CLAUDE.md`, "Aldrig": ingen APK till
  någon annan än ägaren).

## Alternativ

- **(a) `actions/upload-artifact`, låst till en full commit-SHA** som de
  andra actions, i ett eget jobb.
  - Det körs bara vid push till `main` och vid `workflow_dispatch`, inte på
    PR:er.
  - Det bygger `flutter build apk --debug` och laddar upp den med
    `retention-days: 7`.
  - Fördel: ägaren hämtar APK:n från körningen med ett klick (en .zip som
    packas upp; efter 7 dagar är den borta och jobbet körs igen).
  - Nackdelar:
    - ett nytt beroende från samma utgivare som `actions/checkout` och
      `actions/setup-go`. Dependabot följer det redan för versioner
      (`.github/dependabot.yml`);
    - en ny APK från CI kräver troligen att appen avinstalleras först (se
      "Signering"), så data går förlorad vid varje uppdatering;
    - CI-minuter och lagring räknas mot repots gratiskvot. Tiden är **ej
      mätt**; ett bygge för en ABI tog 344 s från kallstart i
      emulatorjobbet. Förslaget är att bara köra vid `workflow_dispatch`.
  - **Bara om ägaren är den enda med åtkomst till repot.**
- **(b) Ingen artefakt. Ägaren bygger själv** med `flutter build apk --debug`
  på sin dator.
  - Fördelar: inget nytt beroende, och samma debugnyckel varje gång, så en
    uppdatering behåller data.
  - Nackdel: det kräver Flutter, Android SDK, NDK och Rust på ägarens dator,
    eftersom `flutter_vodozemac` bygger Rust från källkod.
  - "Klart när" punkt 4 säger att CI bygger APK:n, så punkten måste då
    ändras av ägaren.
- **(c) En GitHub Release med APK:n.**
  - Avråds: en release ser ut som en utdelning och syns för alla med
    läsrätt, och den kräver `contents: write` i `permissions:` (`CLAUDE.md`,
    "Aldrig").

**Rekommendation: (a), bara vid `workflow_dispatch` och bara för arm64,
om ägaren är den enda med åtkomst till repot.** Annars (b).

## Om ägaren väljer (a)

- Claude lägger till jobbet i `.github/workflows/ci.yml`. Den exakta
  SHA:n och versionen väljs i PR:en, från den senaste versionen av
  `actions/upload-artifact`, och skrivs i kommentaren som för de andra
  actions.
- `permissions:` ändras inte. Uppladdningen använder körningens egen
  token, inte `GITHUB_TOKEN`, så `contents: read` bör räcka (**ej provat
  här**).
- PR:en mergas av ägaren, eftersom den rör hur appen kommer till ägaren
  (färdplanen: "PR:er som rör utdelning … mergar bara ägaren").
## Ägaren beslutar

Steg för steg:
1. Öppna repot på GitHub › Settings › Collaborators och kontrollera vem som
   har åtkomst.
2. Välj nedan och skriv in valet i den här filen (eller säg det till Claude).

- [ ] Jag har kontrollerat Settings › Collaborators: bara jag har åtkomst.
- [ ] (a), (b) eller (c).
