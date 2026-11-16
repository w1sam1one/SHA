# 0006 – Vilken session som används (sessionsregeln)

Status: **Accepted by owner, 2026-11-16.** Skrivet 2026-11-16, rättat samma
dag efter en oberoende granskning.

Underlag för grinden G5 i [`docs/ROADMAP.md`](../ROADMAP.md) och den öppna
frågan i [0004](0004-olm-integration-design.md) §2. Ingen kod är ändrad
här; beslutet byggs i P4.

## Beslut

Beslutat av ägaren 2026-11-16. Avsnittet skriver ner beslutet.

- **Vilken session: (b).** Appen skickar på den senast aktiva sessionen,
  ordnad med en räknare i tillståndet.
- **Radering: (iii).** Inga sessioner raderas i prototypen.
- **Allt under "Om ägaren väljer (b) och (iii)"** gäller.
- **En ändring jämfört med underlaget:** raderingsregeln för gamla
  sessioner står i färdplanen under "Före första utdelning", inte bara
  under "Efter prototypen". Annars ligger gamla sessioners nycklar kvar i
  riktiga användares telefoner.

Resten av dokumentet är underlaget som beslutet bygger på. Därifrån är
bara status, inledningen och en rad under "Ägaren beslutar" ändrade.

## Problemet

- **Det blir flera sessioner per kontakt.** När båda skannar varandra
  startar båda en session, så varje kontakt får två (spiken R5,
  `spike/vodozemac/test/olm_spike_test.dart:335-401`). Varje ny skanning
  ger fler.
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
- **Ett vanligt fall går inte att rädda utan ett nytt möte.** Skriver
  ingen av användarna inom 30 dagar efter mötet har båda engångsnycklarna
  städats (0004 §8), och båda sessionerna är döda. Då hjälper bara en ny
  skanning, oavsett alternativ nedan.

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
  - Det är sant så fort sessionen har en mottagande kedja
    (`session/mod.rs:377-379`). En session som skapas av ett inkommande
    första meddelande har en kedja från början (`session/mod.rs:339-362`).
- **Ett mottaget meddelande visar att kontakten har sessionen.** Har en
  session läst ett meddelande från kontakten, har kontakten sessionen och
  kan läsa det som skickas på den.
- **En engångsnyckel per QR-visning** (0004 §8). Skannar någon samma
  visning två gånger blir det två sessioner på samma engångsnyckel. Bara
  den som används först går att läsa hos kontakten, eftersom kontakten
  raderar engångsnyckeln när den första sessionen skapas
  (`vodozemac-0.11.2/src/olm/account/mod.rs:251,324`).
- **matrix-js-sdk v30.0.0** (`src/crypto/OlmDevice.ts`,
  <https://github.com/matrix-org/matrix-js-sdk/blob/v30.0.0/src/crypto/OlmDevice.ts>,
  hämtad 2026-11-14, SHA-256 `41db12a1…`), Matrix äldre kryptokod:
  - skickar på den session som senast tog emot ett meddelande; vid lika
    tid väljs minsta sessions-id (rad 642-670);
  - räknar en ny utgående session som att den tog emot nu när den skapas,
    eftersom den annars aldrig skulle väljas (rad 521-527);
  - räknar en ny inkommande session och varje läst meddelande som att den
    tog emot nu (rad 570-580, 804-806).
  - Ej verifierat: om nyare Matrix-klienter gör likadant.
- **Hur stor en sessions pickle är** är inte mätt. Den växer med antalet
  mottagande kedjor (högst 5, `session/mod.rs:55`) och överhoppade nycklar
  (högst 40 per kedja, `session/receiver_chain.rs:50`).

## Vilken session appen skickar på

- **(a) Behåll minsta sessions-id.**
  - Fördelar: testad i spiken (R5), och båda sidor väljer samma session.
  - Nackdelar: löser inte felet ovan.
- **(b) Senast aktiva sessionen, som i matrix-js-sdk v30.** Tillståndet
  har en räknare. En session får nästa nummer från räknaren när den skapas,
  som utgående eller inkommande, och när den har läst ett meddelande från
  kontakten. Appen skickar på sessionen med högst nummer.
  - Vid mottagning sätts numret bara efter en lyckad avkryptering, bara för
    den session som lyckades, och i samma skrivning som sessionens pickle
    (0004 §6, steg 3). Ett paket som ingen session kan läsa ändrar alltså
    inget. Annars skulle vem som helst som lägger ett paket på relayn kunna
    flytta valet.
  - Matrix använder klockan. Här används en räknare, så ordningen blir rätt
    även om klockan ställs om, och två sessioner får aldrig samma nummer.
  - Fördelar:
    - Så fort kontakten skriver på en session byter appen till den, och den
      sessionen vet appen att kontakten har.
    - En död session överges så fort kontakten skriver på en annan.
    - En ny skanning väljs direkt, eftersom den nya sessionen får högst
      nummer. Undantaget är samma QR-visning skannad två gånger (se
      Fakta). Därför får appen aldrig skapa en ny session från en
      engångsnyckel som redan har gett en session med kontakten.
    - Ingen kryptografi: appen jämför bara nummer.
  - Nackdelar:
    - **Sidorna kan skicka på olika sessioner länge.** Skriver båda innan
      de har läst den andras senaste meddelande, byter båda till den session
      som den andra skrev på. Det kan upprepas så länge användarna skriver
      samtidigt, vilket är vanligt när appen bara hämtar med 1–60 minuters
      mellanrum.
      Sidorna väljer samma session först när ett meddelande har lästs innan
      den andra skriver igen. Inget går förlorat, eftersom båda kan läsa
      båda sessionerna.
    - En ny regel som måste testas (spikens R5 testar (a)).
    - Numret måste sparas per session i tillståndet (0005, punkt 2).
- **(c) En ny skanning ersätter de gamla sessionerna.** Båda telefonerna
  raderar kontaktens gamla sessioner vid en ny skanning.
  - Fördelar: enkel att förstå.
  - Nackdelar:
    - Paket som ligger kvar på relayn för de gamla sessionerna går
      förlorade (krav 3).
    - En död session kräver alltid ett nytt möte.
- **(d) Minsta sessions-id bland sessioner som har tagit emot ett
  meddelande** (`hasReceivedMessage`), annars den nyaste.
  - Fördelar:
    - Sidorna väljer samma session så fort var och en har läst ett
      meddelande på båda sessionerna, oavsett när användarna skriver.
    - En död utgående session tar aldrig emot något, så den väljs bort så
      fort kontakten skriver på en annan.
  - Nackdelar:
    - En ny skanning ändrar inte valet så länge en äldre session har tagit
      emot något. Kan kontakten av någon anledning inte längre läsa den
      sessionen, till exempel efter ett fel som har gett kontakten ett
      äldre läge, hjälper en ny skanning bara om den nya sessionen råkar få
      lägre id. Det är samma svaghet som i (a), i ett ovanligare fall.
    - Ingen klient som använder regeln är hittad.
    - "Den nyaste" behöver ändå en räknare, som i (b).

**Rekommendation: (b).** Bland alternativen som håller krav 3 är (b) det
enda där en ny skanning alltid väljs direkt. (d) får sidorna att välja
samma session snabbare, men det spelar ingen roll för om meddelanden kommer
fram.

## Radering av sessioner

Raderingsregeln i 0004 §2 bygger på att båda sidor väljer samma session.
Med (b) gäller det inte alltid, så regeln byts. Det svåra är att appen inte
kan veta vilken session kontakten skickar på just nu.

- **(i) Högst 5 sessioner per kontakt, med ett skydd.** Blir det fler
  raderas den med lägst nummer, men aldrig en session som har skapats,
  läst ett meddelande eller skickat ett meddelande de senaste 48 timmarna,
  och aldrig den som senast läste ett meddelande. Finns ingen sådan får
  kontakten ha fler än 5 tills vidare.
  - Fördelar: färre sessioner och mindre nyckelmaterial i telefonen.
  - Nackdelar:
    - Utan skyddet kan meddelanden gå förlorade: om den ena skannar den
      andra fem gånger utan att skicka något på de nya sessionerna raderas
      den session kontakten skickar på (granskningens exempel).
    - Med skyddet är det inte bevisat att inget går förlorat. Kvar finns
      fall där någon skannar flera gånger medan kontakten är tyst i mer än
      48 timmar.
    - Behöver klockan, och en tid per session utöver numret.
- **(ii) Radera en session som varit inaktiv i 30 dagar**, om en annan
  session för kontakten har högre nummer.
  - Fördelar: färre sessioner.
  - Nackdelar:
    - Har kontakten varit tyst längre än så, och har kontakten fortfarande
      den raderade som sin senaste, går nästa meddelande förlorat (krav 3).
    - Behöver klockan, och en tid per session utöver numret.
- **(iii) Radera inga sessioner i prototypen.**
  - Fördelar:
    - Inget meddelande går förlorat genom att en session raderas.
    - Minst kod, och ingen klocka behövs.
  - Nackdelar:
    - Tillståndet växer med varje nytt möte, med högst två sessioner per
      möte där båda skannar. Med två telefoner som sällan skannar om är det
      lite, men storleken är inte mätt (se Fakta).
    - Gamla sessioners nycklar ligger kvar i telefonen.
    - En raderingsregel måste tas fram efter prototypen.

**Rekommendation för prototypen: (iii).** Det är det enda alternativet som
säkert håller krav 3. (i) är utgångspunkten när raderingen tas upp igen.

## Om ägaren väljer (b) och (iii)

- **0004 §2:**
  - rekommendationen blir 0006 (b), i stället för §2 (a);
  - raderingsregeln och "minsta id av alla" vid en ny skanning byts mot
    0006 (b) och (iii);
  - "regeln jämför bara text" blir "regeln jämför bara nummer";
  - testet "radering efter 48 timmar" byts mot testerna nedan;
  - den öppna frågan stängs.
- **0004, "Beslut":** att det är förtydligat när den andra sessionen får
  raderas (§2) byts mot att inga sessioner raderas i prototypen (0006).
- **0004 §6, steg 3:** sessionens nummer sparas i samma skrivning som dess
  pickle.
- **0004 §8 (a):** meningarna om att kontaktens meddelanden inte går att
  läsa och att en ny skanning inte säkert hjälper ändras: med (b) byter
  kontakten så fort appen skriver på en session som kontakten kan läsa,
  och en ny skanning väljs direkt.
- **0004 §10, "QR-koden visas igen":** skannar någon samma visning två
  gånger blir det ingen ny session. Användaren ser inget särskilt, som
  förut.
- **0005, punkt 2:** varje session sparar sitt nummer, i stället för "när
  den först tog emot ett meddelande".
- **0005, punkt 3:** för varje kontakt sparas också de engångsnycklar från
  kontaktens QR-koder som har gett en session, så att samma nyckel inte
  ger en till.
- **Mätning:** mätningen i P3 (3 sessioner per kontakt) gäller som förut.
  Med (iii) finns ingen övre gräns per kontakt, så P4 mäter också en
  skrivning med många sessioner för en kontakt. Tar den mer än 300 ms
  stannar Claude, som i 0005.
- **Färdplanen:** G5 bockas av. P4 bygger sessionsregeln enligt 0006 (b)
  och (iii). Under "Efter prototypen" läggs en raderingsregel för gamla
  sessioner till.
- **P4 testar:**
  - båda skannar och skriver samtidigt i flera omgångar: inget går
    förlorat, och efter ett meddelande som lästs innan den andra skrev
    väljer båda samma session;
  - en död utgående session, där kontaktens engångsnyckel är städad,
    överges när kontakten skriver;
  - båda sessionerna döda: en ny skanning väljs direkt och fungerar;
  - samma QR-visning skannad två gånger ger ingen ny session;
  - ett paket som ingen session kan läsa ändrar inget nummer;
  - numren finns kvar efter en omstart, och en krasch före skrivningen
    ändrar inget (0004 §6);
  - ingen session raderas;
  - storleken på en sessions pickle mäts.
- **Mutationer:**
  - att välja minsta id i stället för högst nummer ska få minst ett test
    att falla;
  - att sätta numret innan avkrypteringen har lyckats ska få minst ett
    test att falla.

## Ägaren beslutar

1. (a), (b), (c) eller (d).
2. Med (b) eller (d): radering (i), (ii) eller (iii).

Beslutat 2026-11-16: (b) och (iii), se "Beslut" överst.
