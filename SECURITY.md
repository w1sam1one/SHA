# Säkerhet

SHA är en **ogranskad prototyp**. Kryptot är inte granskat av en
kryptoexpert än, och appen ska inte användas för riktiga hemligheter (se
README). Punkterna som väntar på granskning är märkta `OGRANSKAT` i koden
och listas i [`docs/ROADMAP.md`](docs/ROADMAP.md) under "Före första
utdelning".

## Kontrollera appen

När appen delas ut (0014) är varje APK signerad med ägarens nyckel. Jämför
signeringscertifikatets fingeravtryck med det här innan du installerar.
Den första raden är i den form som `keytool` och de flesta verktyg visar,
den andra som `apksigner verify --print-certs SHA-x.y.z.apk` visar den
("SHA-256 digest", gemener utan kolon).

Signeringscertifikatets SHA-256: inte skapat än (G9)

Samma värde som apksigner visar det: inte skapat än (G9)

APK-filens egen SHA-256 står i varje release:
https://github.com/w1sam1one/SHA/releases

## Rapportera en säkerhetsbugg

Rapportera **privat** via GitHub:

1. Gå till fliken **Security** i repot.
2. Välj **Report a vulnerability**
   (<https://github.com/w1sam1one/SHA/security/advisories/new>).
3. Beskriv felet. Bara du, ägaren och de som ägaren bjuder in till
   rapporten ser den.

Finns inte knappen **Report a vulnerability**: öppna ett issue med bara
rubriken "Säkerhetsbugg – vill rapportera privat", utan några detaljer. Då
ordnar ägaren en privat kanal.

**Skriv ingenting om själva säkerhetsbuggen i öppna issues, pull requests
eller diskussioner.** Allt där syns för alla.

Ta gärna med:

- vad felet är och vad en angripare kan göra med det;
- hur man återskapar det, steg för steg;
- vilken commit eller version det gäller.

## Vad som händer sedan

- Ägaren svarar i samma rapport.
- Felet rättas privat, i en tillfällig privat fork som GitHub skapar för
  rapporten, inte i en vanlig PR som alla kan se. Rapporten och rättningen
  görs publika när rättningen är klar.
- Det finns ingen belöning för rapporter.

## Vad som omfattas

- Appen (`lib/`, `android/`), servern (`relay/`), bygget och CI
  (`tool/`, `.github/`) och hur de använder kryptot.
- Det som dokumenten lovar om säkerhet och integritet, till exempel i
  [`docs/granskning/`](docs/granskning/) och README.
- Punkterna märkta `OGRANSKAT` är kända och väntar på granskning. Rapportera
  gärna ändå om du hittar ett konkret fel i dem.

Fel i bibliotek från andra rapporteras till dem i första hand, till exempel
Rust-biblioteket vodozemac (Matrix.org) och Dart-paketen vodozemac och
flutter_vodozemac (Famedly). Säg gärna till här
också, om felet påverkar SHA.

## In English

SHA is an **unreviewed prototype**; do not use it for real secrets. To
report a security issue, use GitHub's private **Report a vulnerability**
form (Security tab, or
<https://github.com/w1sam1one/SHA/security/advisories/new>). If that button
is missing, open an issue titled only "Security bug – want to report
privately", with no details. Please do not describe the issue in a public
issue, pull request or discussion. There is no bug bounty.
