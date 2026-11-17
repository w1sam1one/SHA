# 0009 – Radering av gamla sessioner (F2)

Status: **Proposed – owner decides.** Skrivet 2026-11-17. **Kräver
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
  4. vi har läst ett meddelande från K på en annan session, och K skrev det
     enligt dess egen tid `t` senare än `sentS` + 48 h + en marginal på
     24 h för klockor som går fel.
  - **Varför det håller krav 1:** när K skrev det meddelandet hade den
    andra sessionen högst nummer hos K. Efter `sentS` + 48 h kan inget av
    våra paket på S nå K, och utkorgen har inga fler. S kan därför aldrig
    bli högst hos K igen, och K skickar aldrig mer på S.
  - **Luckan:** villkor 4 bygger på K:s klocka. Går den mer än 24 h fel
    framåt kan S raderas för tidigt, och ett meddelande gå förlorat.
  - Behöver två nya fält: `sentS` per session (sätts vid `markSent`), och
    K:s tid för det senast lästa meddelandet per session. Tiden ligger i
    JSON-texten, så appen måste lämna den till Olm-tjänsten; det ändrar
    API:t men inte kryptot.
  - Sessioner raderas aldrig för en kontakt som är tyst, hur gamla de än är.
- **(v) (iv), och dessutom (i) som tak:** som (iv), men har en kontakt fler
  än 20 sessioner raderas också den äldsta enligt (i). Det begränsar
  tillståndets storlek om någon skannar ofta och kontakten aldrig skriver.

## Rekommendation: (iv)

Den enda regeln där det går att argumentera för att inget meddelande går
förlorat, med en känd lucka (en klocka som går mer än 24 h fel). Taket i
(v) kan läggas till senare om mätningar visar att tillståndet växer.

## Testa

- Varje villkor i (iv) för sig: en session raderas inte om ett av dem
  saknas.
- Fallet i 0006 (i): fem nya skanningar medan kontakten är tyst; inget
  raderas, och kontaktens nästa meddelande läses.
- Ett försenat paket på S som når kontakten efter bytet: S raderas inte
  förrän 72 h har gått.
- Utkorgen med ett paket på S: S raderas inte.
- Omstart: `sentS` och tiderna finns kvar.
- Mutationer för varje villkor.

## Ägaren beslutar

- [ ] (i), (ii), (iv) eller (v).
- [ ] Marginalen för klockor (förslag: 24 h).

Bygget (F2) börjar först efter beslutet, och regeln märks
`OGRANSKAT (0009)` tills kryptoexperten har granskat den (G6).
