# 0009 – Radering av gamla sessioner (F2)

Status: **Beslutat av ägaren 2026-11-18: (iv), med 24 h marginal för
klockor.** Skrivet 2026-11-17. **Kräver
granskning av kryptoexpert** (gamla nycklar i telefonen och regeln för när
de får raderas).

Underlag för F2 i [`docs/ROADMAP.md`](../ROADMAP.md). I prototypen raderas
inga sessioner (0006 (iii)). Före första utdelningen behövs en regel, annars
ligger gamla sessioners nycklar kvar i riktiga användares telefoner
("Före första utdelning"). 0006 (i) är utgångspunkten.

## Krav

1. **Inget meddelande får gå förlorat** för att en session raderas (0006,
   krav 3).
2. Gamla sessioners nycklar ska bort så fort det går utan att bryta krav 1.
3. Ingen ny kryptografi och ingen ändring av Olm (`CLAUDE.md`, "Aldrig").

## Fakta

- **Sessionsregeln (0006 (b)):** varje session får ett nummer när den skapas
  och när den läser ett meddelande. Appen skickar på den med högst nummer.
  Kontakten gör likadant med sina egna nummer.
- **En session kan bli högst igen hos kontakten** bara genom att läsa ett
  meddelande på den, alltså ett paket som vi har skickat på den sessionen.
- **Relayn sparar ett paket i 48 timmar** (`relay/limits.go`, `packetTTL`).
  Ett paket som relayn tog emot vid tiden T kan inte läsas efter T + 48 h.
- **Vår utkorg** kan hålla ett paket i flera dagar (ingen server, 507). Det
  räknas som skickat först när relayn har svarat 204 (`markSent`).
- **Vi vet inte när kontakten skrev ett meddelande**, bara när vi läste det.
  Tiden i JSON-texten (`t`) är kontaktens klocka (`MessagePayload`).
- I dag sparas för varje session bara id, pickle och nummer
  (`lib/crypto/src/sha_olm_service.dart`, `_Session`).

## Alternativ

- **(i) Högst 5 sessioner per kontakt, med ett skydd** (0006 (i)): radera
  den med lägst nummer, men aldrig en som har skapats, läst eller skickat de
  senaste 48 timmarna, och aldrig den som senast läste ett meddelande.
  - Enkelt.
  - Men det är inte bevisat att inget går förlorat: någon som skannar flera
    gånger medan kontakten är tyst i mer än 48 timmar kan få den session
    kontakten skickar på raderad (0006).
- **(ii) Radera en session som har varit inaktiv i 30 dagar** om en annan
  har högre nummer (0006 (ii)).
  - Har kontakten varit tyst längre och har den sessionen som sin senaste,
    går nästa meddelande förlorat.
- **(iv) Radera bara när kontakten bevisligen har gått vidare.** Radera
  session S hos kontakten K när allt detta gäller:
  1. S har inte högst nummer;
  2. inget i utkorgen är krypterat på S;
  3. relayn tog emot vårt senaste paket på S vid tiden `sentS` (eller S
     skapades då, om vi aldrig skickade på den);
  4. vi har läst ett meddelande M från K på en annan session, och K skrev
     det enligt dess egen tid `t` senare än `sentS` + 48 h + en marginal på
     24 h för klockor som går fel;
  5. det har gått minst 48 h + 24 h på vår egen klocka sedan vi läste det
     första M som uppfyllde villkor 4 (`qualifiedAt`, se "Behöver nya
     fält").
  - **Varför det håller krav 1, i två delar:**
    - *K skickar aldrig mer på S.* När K skrev M hade den andra sessionen
      högst nummer hos K. Efter `sentS` + 48 h kan inget av våra paket på S
      nå K, och vår utkorg har inga fler (villkor 2 och 3). S kan därför
      aldrig bli högst hos K igen.
    - *Inget som K redan har skickat på S är kvar.* K:s utkorg skickar i
      ordning per kontakt, så allt K skickade på S före bytet låg hos relayn
      före M. Efter villkor 5 har vi antingen hämtat det eller så har relayn
      tagit bort det efter 48 h.
    - Argumentet gäller för varje M som uppfyller villkor 4, så det räcker
      att räkna från det första. Räknar vi i stället från det senast lästa
      meddelandet raderas S aldrig så länge K skriver minst var 72:a timme
      (granskningen av PR #35), och det bryter krav 2.
  - **Motexemplet som villkor 5 stoppar** (granskningen av F2): K skriver m1
    på S strax före midnatt och m2 på den nya sessionen strax efter. Appen
    hämtar dagens brevlåda före gårdagens, läser m2 först, och utan villkor
    5 raderas S innan m1 har lästs.
  - **Luckorna:**
    - Villkor 4 bygger på skillnaden mellan K:s klocka och vår. Går K:s
      klocka mer än 24 h fel framåt mot vår kan S raderas för tidigt.
    - Villkor 3 och 5 mäts med vår egen väggklocka. Hoppar den fram mer än
      24 h efter att vi läste M (någon ställer tiden för hand) kan villkor 5
      gälla för tidigt. Ställs den sedan tillbaka medan ett gammalt paket på
      S fortfarande finns hos relayn, hämtas det när S redan är raderad.
    - Det antas att relayn aldrig håller ett paket längre än 48 h. Den som
      driver relayn kan fördröja paket (hotmodellen); ett paket från oss på
      S som når K mycket sent gör S högst hos K igen.
  - **Behöver nya fält:**
    - `sentS` per session (sätts vid `markSent`);
    - sessionens id för varje paket i utkorgen (`_Outgoing` har i dag bara
      id, kontakt, paket och text), för villkor 2 och för att sätta `sentS`;
    - `qualifiedAt` per session: när vi, enligt vår klocka, första gången
      läste ett meddelande från K som uppfyller villkor 4 för S. Det
      nollställs om `sentS` ändras. S raderas när det har gått 72 h sedan
      `qualifiedAt` och villkor 1–3 fortfarande gäller.
    - För villkor 4 behöver Olm-tjänsten K:s tid `t` för varje läst
      meddelande. Tiden ligger i JSON-texten, så appen måste lämna den till
      Olm-tjänsten; det ändrar API:t men inte kryptot.
  - Sessioner raderas aldrig för en kontakt som är tyst, hur gamla de än är.
- **(v) (iv), och dessutom (i) som tak:** som (iv), men har en kontakt fler
  än 20 sessioner raderas också den äldsta enligt (i). Det begränsar
  tillståndets storlek om någon skannar ofta och kontakten aldrig skriver.

## Rekommendation: (iv)

Den enda regeln där det går att argumentera för att inget meddelande går
förlorat. Luckorna är kända: en klocka, K:s eller vår, som går mer än 24 h
fel, och en relay som fördröjer paket. Taket i (v) kan läggas till senare om
mätningar visar att tillståndet växer.

## Testa

- Varje villkor i (iv) för sig: en session raderas inte om ett av dem
  saknas.
- Fallet i 0006 (i): fem nya skanningar medan kontakten är tyst; inget
  raderas, och kontaktens nästa meddelande läses.
- Ett försenat paket på S som når kontakten efter bytet: S raderas inte
  förrän 72 h har gått.
- Motexemplet ovan: m2 läses före m1; S raderas inte förrän villkor 5
  gäller, och m1 läses.
- En aktiv chatt: K skriver var 12:e timme på den nya sessionen. S raderas
  72 h efter det första meddelandet som uppfyller villkor 4, inte senare.
- Ett paket på S i utkorgen som skickas efter `qualifiedAt`: `qualifiedAt`
  nollställs, och S raderas inte förrän villkoren gäller igen.
- Utkorgen med ett paket på S: S raderas inte.
- Omstart: `sentS`, `qualifiedAt` och tiderna finns kvar.
- Mutationer för varje villkor.

## Ägaren beslutar

- [x] **(iv)**, beslutat 2026-11-18.
- [x] Marginalen för klockor: **24 h**, beslutat 2026-11-18.

Bygget (F2) börjar först efter beslutet, och regeln märks
`OGRANSKAT (0009)` tills kryptoexperten har granskat den (G6).
