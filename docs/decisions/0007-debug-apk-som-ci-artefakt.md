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
  till repot. Vilka som har läsrätt här är **ej verifierat**. Ägaren ser det
  under Settings › Collaborators.
- **Bygget:**
  - Emulatorjobbet bygger i dag en APK med testet
    `integration_test/olm_build_test.dart` som startpunkt, inte appen.
  - Appen måste byggas för sig: `flutter build apk --debug`.
  - Den APK:n är för arm64-telefoner och x86_64-emulatorer, eller för alla
    ABI:er om inget anges. **Ej provat i CI.**
- **Signering:** en debug-APK signeras med den debugnyckel som Gradle skapar
  på runnern. Ingen signeringsnyckel, `key.properties` eller lösenord
  hanteras.
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
  - Fördel: ägaren hämtar APK:n från körningen med ett klick.
  - Nackdel: ett nytt beroende från samma utgivare som `actions/checkout`
    och `actions/setup-go`. Dependabot följer det när G7 är klar.
  - Det kostar också några minuter CI per merge.
- **(b) Ingen artefakt. Ägaren bygger själv** med `flutter build apk --debug`
  på sin dator.
  - Fördel: inget nytt beroende.
  - Nackdel: det kräver Flutter, Android SDK, NDK och Rust på ägarens dator,
    eftersom `flutter_vodozemac` bygger Rust från källkod.
  - "Klart när" punkt 4 säger att CI bygger APK:n, så punkten måste då
    ändras av ägaren.
- **(c) En GitHub Release med APK:n.**
  - Avråds: en release ser ut som en utdelning och syns för alla med
    läsrätt.

**Rekommendation: (a).**

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
- `docs/prototyp.md` får en rad om var APK:n hämtas.

## Ägaren beslutar

- [ ] (a), (b) eller (c).
