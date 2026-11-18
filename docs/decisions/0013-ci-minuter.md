# 0013 – Färre Actions-minuter i CI

Status: **Godkänd av ägaren** 2026-11-17, när ägaren mergade PR #39 (kl.
16:26 UTC), och bekräftad av ägaren 2026-11-18. Ägaren hade bett om ändringen samma dag, efter att CI stoppades
av Actions-budgeten. Mergen godkände underlaget och det nya beroendet nedan.
PR #39 mergades innan CI hade kört och innan den oberoende granskningen var
klar. Granskningens fynd rättas i en egen PR, som ägaren också mergar.

## Bakgrund

Sedan 2026-11-17 10:04 UTC startar inga jobb: "The job was not started
because recent account payments have failed or your spending limit needs to
be increased". Varje PR körde alla fyra jobben, även när den bara ändrade
dokument, och emulatorjobbet tar ungefär en kvart. Minuterna per jobb, före
och efter, står i en kommentar på PR #39.

## Ägarens beslut (2026-11-17)

1. Emulatorjobbet och spike-jobbet körs bara när koden de provar ändras. En
   PR som bara ändrar dokument kör bara en snabb kontroll.
2. `concurrency` med `cancel-in-progress` per gren.
3. Gradle, Cargo och pub cachas.
4. `permissions:` ändras inte.

## Så görs det

- **Ett nytt jobb, `changes`**, räknar ut vilka filer som ändrats
  (`.github/scripts/changed-files.sh`: `git diff` mot basgrenen, eller mot
  `before` vid en push) och vilka jobb som behövs
  (`.github/scripts/changed-jobs.sh`). En flyttad fil räknas med både sin
  gamla och sin nya sökväg, och namn med å, ä och ö skrivs som de är. Jobbet
  kör också den snabba kontrollen:
  - testerna av skripten (`.github/scripts/test-ci-scripts.sh`);
  - `git diff --check`: blanktecken i slutet av rader och konfliktmarkörer,
    men inte i licenstexterna under `assets/`;
  - att relativa länkar i ändrade Markdown-filer pekar på filer som finns
    (`.github/scripts/check-docs.py`).
- **Vilka jobb som körs:**

  | Ändrat | flutter | emulatorn | spike | relay |
  | --- | --- | --- | --- | --- |
  | bara `*.md` och `docs/` | – | – | – | – |
  | `lib/`, `test/`, `integration_test/`, `android/`, `pubspec.*` | ja | ja | – | – |
  | `spike/` | ja | – | ja | – |
  | `relay/` | ja | – | – | ja |
  | Rust-filer (`*.rs`, `Cargo.*`, `rust-toolchain*`) | ja | ja | ja | – |
  | `ci.yml`, `.github/scripts/` | ja | ja | ja | ja |
  | allt annat | ja | – | – | – |

  - Flutter-jobbet körs för allt som inte är dokument, eftersom dess tester
    också läser filer utanför `lib/` och `test/`
    (`android/app/src/main/kotlin`, `spike/vodozemac/pubspec.yaml`, och
    relayn i kedjetesterna).
  - Emulatorn behöver `test/`, eftersom `integration_test/` importerar
    därifrån.
  - Spikens egen emulatorkörning (`spike-android.yml`) har redan ett
    filter på `spike/`.
  - `LICENSE` räknas inte som ett dokument: Flutter lägger den i appens
    licenstexter (NOTICES), så Flutter-jobbet körs.
  - En PR som ändrar `ci.yml` eller `.github/scripts/` kör alla jobb. En
    ändring av reglerna kan alltså inte hoppa över sina egna tester.
  - Om diffen inte går att ta fram körs allt.
  - **Smalare än ägarens regel:** spike-jobbet körs bara för `spike/` och
    Rust-filer, och emulatorjobbet inte för `spike/`. Spikens kod påverkar
    inte appen, och spikens emulatortest har en egen fil. Att spikens och
    appens Olm-versioner är lika provas av Flutter-jobbet
    (`test/security/olm_versions_test.dart`).
- **`concurrency`:** fanns redan på `main`, med gruppen `github.ref` och
  `cancel-in-progress: true` även på `main`.
  - Nu har en PR en grupp, sitt nummer, och en ny commit avbryter den gamla
    körningen.
  - Varje push till `main` har en egen grupp och avbryts aldrig. Det skiljer
    sig från ägarens ordalydelse ("per gren"). `changes` tittar bara på vad
    varje push förde in, så en körning på `main` som avbröts eller ersattes
    skulle lämna den pushen oprovad där. GitHub ersätter dessutom en
    väntande körning i samma grupp även utan `cancel-in-progress`. Det kostar
    några minuter mer när flera PR:er mergas tätt.
- **Cacharna** (`actions/cache` 6.1.0):
  - pub: `~/.pub-cache`, med nyckeln från `pubspec.lock`;
  - Cargo: nedladdningarna (`~/.cargo/registry/index`, `registry/cache`,
    `git/db`) och Rust-byggena, `build/rust` för datorn och cargokits
    katalog för Android (`build/flutter_vodozemac/build`). Nyckeln är
    Rust-versionen, för Android även NDK:n, och `pubspec.lock`.
  - Gradle: `~/.gradle/caches/modules-2` och `~/.gradle/wrapper/dists`,
    med nyckeln från Flutter-versionen, Gradle-filerna och `pubspec.lock`.

## Det nya beroendet

`actions/cache` **6.1.0**, låst till commit
`55cc8345863c7cc4c66a329aec7e433d2d1c52a9` (2026-06-23), MIT. Det används
som `actions/cache/restore` och `actions/cache/save`, från samma commit.
Det är GitHubs egen action, som `actions/checkout` och `actions/setup-go`
som redan används. Dependabot följer den (ekosystemet `github-actions` i
`.github/dependabot.yml`) och öppnar en PR när en ny version kommer.

## Säkerheten

- **Bara pushar till `main` sparar cacharna.** En PR läser dem men skriver
  inget, så en PR kan inte ändra det som `main` och andra PR:er får.
  GitHub låter dessutom bara en PR själv läsa en cache som PR:en har
  skapat.
- Cargo kontrollerar en nedladdad crate mot kontrollsumman i `Cargo.lock`,
  även utan `--locked`, och pub kontrollerar paketen mot `pubspec.lock`
  (`--enforce-lockfile`). Men det som redan ligger i en cache, och de byggda
  Rust-filerna, litar de på. Repot är stängt. Till `main` pushar bara
  ägaren, och Claude när Claude mergar sina egna PR:er enligt `CLAUDE.md`.
- **CI bygger inget som delas ut**, bara debug-APK:er för testerna. Ett
  release-bygge får inte göras från CI:s cacher.
- Nycklar och lösenord ligger inte i cacharna. `~/.gradle/gradle.properties`
  skrivs av CI-steget och cachas inte.

## Ej verifierat

- Inget av detta har kört på GitHub än, eftersom budgeten är slut.
- Hur mycket cacharna sparar är **ej mätt**. Siffrorna i PR:en är
  uppskattningar från stegens tider i tidigare körningar.
- Att cargo återanvänder de cachade byggena (filtider och sökvägar) är
  **ej verifierat**. Gör det inte det blir resultatet bara långsammare,
  inte fel.

Första körningen efter mergen mäts, och siffrorna skrivs in i PR:en eller
i en ny PR.
