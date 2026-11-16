# 0006 – Vilken session som används (sessionsregeln)

Status: **Proposed – owner decides.** Skrivet 2026-11-16.

Underlag för grinden G5 i [`docs/ROADMAP.md`](../ROADMAP.md) och den öppna
frågan i [0004](0004-olm-integration-design.md) §2. P4 väntar på det här
beslutet. Ingen kod är ändrad.

## Problemet

- **Det blir flera sessioner per kontakt.** När båda skannar varandra
  startar båda en session, så varje kontakt får två (spiken R5,
  `spike/vodozemac/test/olm_spike_test.dart:335-401`). Varje ny skanning
  ger en till.
- **Dagens regel:** skicka på sessionen med minsta sessions-id (0004 §2,
  `spike/vodozemac/lib/olm_spike.dart:78-92`).
- **Felet:** en session vars första meddelande aldrig kan läsas hos
  kontakten väljs aldrig bort. Det händer till exempel när kontaktens
  engångsnyckel har städats (0004 §8).
  - Sessionen tar aldrig emot något, så raderingsregeln i §2 tar inte bort
    den.
  - Har den minsta id fortsätter appen att skicka på den.
  - En ny skanning hjälper bara om den nya sessionen råkar få lägre id.
    Sessions-id är SHA-256 av sessionens nycklar
    (`vodozemac-0.11.2/src/olm/session_keys.rs:46-56`), alltså slumpmässigt.

## Krav

1. Appen skickar på en session som kontakten kan läsa, så fort det går att
   veta.
2. En död session överges utan att användarna behöver göra något mer än att
   skriva till varandra, eller skanna igen.
3. Inga fler meddelanden går förlorade, inte heller paket som ligger kvar
   på relayn (48 timmar, `relay/limits.go:27`). Meddelanden som redan
   skickats på en död session går inte att rädda.
4. Regeln är deterministisk och använder ingen egen kryptografi.

## Fakta

- **Olm skickar typ 0** tills sessionen har tagit emot ett meddelande från
  kontakten (`vodozemac-0.11.2/src/olm/session/mod.rs:377-399`). Dart-API:t
  visar det som `hasReceivedMessage` (`vodozemac-0.9.1/lib/src/api.dart:257`).
- **Ett mottaget meddelande visar att kontakten har sessionen.** Har en
  session tagit emot och läst ett meddelande från kontakten, har kontakten
  sessionen och kan läsa det som skickas på den.
- **Matrix-klienten matrix-js-sdk** (v30.0.0, `src/crypto/OlmDevice.ts`,
  hämtad från GitHub 2026-11-16, SHA-256 `41db12a1…`):
  - skickar på den session som senast tog emot ett meddelande; vid lika
    tid väljs minsta sessions-id (rad 642-670);
  - räknar en ny utgående session som "tog emot nu" när den skapas, "annars
    används den inte" (rad 521-527);
  - räknar en ny inkommande session och varje läst meddelande som "tog
    emot nu" (rad 570-580, 804-806).

## Alternativ

- **(a) Behåll minsta sessions-id.**
  - Fördelar: testad i spiken (R5), och båda sidor väljer samma session.
  - Nackdelar: löser inte felet ovan.
- **(b) Senast aktiva sessionen, som i Matrix.** Varje session får en tid.
  Tiden sätts när appen skapar den som utgående session, när den skapas
  som inkommande, och varje gång den läser ett meddelande från kontakten.
  Appen skickar på sessionen med senast tid. Vid lika tid väljs minsta
  sessions-id.
  - Fördelar:
    - Så fort kontakten skriver på en session byter appen till den, och
      den sessionen vet appen att kontakten har.
    - En död session överges så fort kontakten skriver på en annan.
    - En ny skanning hjälper alltid: den nya sessionen är nyast och väljs.
    - Samma regel används i Matrix-klienten.
    - Ingen kryptografi: appen jämför bara tider och text.
  - Nackdelar:
    - Sidorna kan skicka på olika sessioner en kort stund. Det gör inget,
      eftersom båda kan läsa båda, och efter ett svar väljer båda samma.
    - Det är en ny regel som måste testas (spikens R5 testar (a)).
    - Tiden måste sparas per session i tillståndet (0005, punkt 2).
- **(c) En ny skanning ersätter de gamla sessionerna.** Båda telefonerna
  raderar kontaktens gamla sessioner vid en ny skanning.
  - Fördelar: enkel att förstå.
  - Nackdelar:
    - Paket som ligger kvar på relayn för de gamla sessionerna går
      förlorade (krav 3).
    - En död session kräver alltid ett nytt möte.

**Rekommendation: (b).**

## Radering av sessioner med (b)

Raderingsregeln i 0004 §2 bygger på att båda sidor väljer samma session.
Med (b) gäller det inte alltid, så regeln byts.

- **(i) Radera inget, men högst 5 sessioner per kontakt.** Blir det fler
  raderas den som varit inaktiv längst.
  - Fördelar: enkelt, och en session som kontakten kan skicka på raderas
    nästan aldrig.
  - Nackdelar: en kontakt som skannats om många gånger har 5 sparade
    sessioner. En pickle är några kilobyte, så det ryms i tillståndet.
- **(ii) Radera en session som varit inaktiv i 30 dagar**, om en annan
  session för kontakten har senare tid.
  - Fördelar: färre sessioner.
  - Nackdelar: har kontakten varit tyst längre än så, och den nya sessionen
    aldrig tagit emot något hos kontakten, kan kontakten skicka på den
    raderade. Då går meddelandet förlorat (krav 3).

**Rekommendation: (i).**

## Om ägaren väljer (b) och (i)

- **0004 §2:** rekommendationen blir (b), och raderingsregeln blir (i). Den
  öppna frågan stängs.
- **0004 §8:** stycket om att en ny skanning inte säkert hjälper ändras: med
  (b) väljs alltid den nya sessionen.
- **0005, punkt 2:** varje session sparar sin tid, i stället för "när den
  först tog emot ett meddelande".
- **P4 testar:**
  - båda skannar och skickar innan någon har svarat;
  - efter det första svaret väljer båda samma session;
  - en död utgående session, där kontaktens engångsnyckel är städad,
    överges när kontakten skriver;
  - en ny skanning väljs direkt;
  - den sjätte sessionen raderar den som varit inaktiv längst;
  - tiderna finns kvar efter en omstart.
- **Mutation:** att välja minsta id i stället för senast tid ska få minst
  ett test att falla.

## Ägaren beslutar

1. (a), (b) eller (c).
2. Med (b): (i) eller (ii).
