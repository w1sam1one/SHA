# Säkerhet

SHA är en **ogranskad prototyp**. Kryptot är inte granskat av en
kryptoexpert än, och appen ska inte användas för riktiga hemligheter (se
README). Punkterna som väntar på granskning är märkta `OGRANSKAT` i koden
och listas i [`docs/ROADMAP.md`](docs/ROADMAP.md) under "Före första
utdelning".

## Rapportera en säkerhetsbugg

Rapportera **privat** via GitHub:

1. Gå till fliken **Security** i repot.
2. Välj **Report a vulnerability**
   (<https://github.com/w1sam1one/SHA/security/advisories/new>).
3. Beskriv felet. Bara du och ägaren ser rapporten.

**Skriv inte om säkerhetsbuggar i öppna issues, pull requests eller
diskussioner.** Allt där syns för alla.

Ta gärna med:

- vad felet är och vad en angripare kan göra med det;
- hur man återskapar det, steg för steg;
- vilken commit eller version det gäller;
- om du vill nämnas när felet är rättat, och med vilket namn.

## Vad som händer sedan

- Ägaren bekräftar att rapporten har kommit fram och svarar i samma
  rapport.
- Felet rättas i en vanlig PR. Rapporten görs publik först när rättningen
  finns, om ägaren och du inte kommer överens om något annat.
- Det finns ingen belöning för rapporter.

## Vad som omfattas

- Appen (`lib/`, `android/`), servern (`relay/`) och hur de använder
  kryptot.
- Det som dokumenten lovar om säkerhet och integritet, till exempel i
  [`docs/granskning/`](docs/granskning/) och README.
- Punkterna märkta `OGRANSKAT` är kända och väntar på granskning. Rapportera
  gärna ändå om du hittar ett konkret fel i dem.

Fel i bibliotek från andra rapporteras till dem i första hand, till exempel
vodozemac (Matrix.org) och flutter_vodozemac (Famedly). Säg gärna till här
också, om felet påverkar SHA.

## In English

SHA is an **unreviewed prototype**; do not use it for real secrets. To
report a security issue, use GitHub's private **Report a vulnerability**
form (Security tab, or
<https://github.com/w1sam1one/SHA/security/advisories/new>). Please do not
open a public issue, pull request or discussion about it. There is no bug
bounty.
