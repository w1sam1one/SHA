# 0002 – Transport v1: relay-servern

Status: **Accepted by owner**, 2026-11-13.

Beslutet fattades av repots ägare. Det här dokumentet skriver ner det;
inga beslut har lagts till. Allt under "Förslag" och "Öppna frågor" är
inte beslutat.

Bakgrund: [0001](0001-protocol-storage-transport.md) (protokoll, lagring,
transport). Paketformatet finns i `lib/crypto/src/wire_format.dart`.

## Beslut

**D1 i 0001 godkänns.** En kontakt betyder "verifierad i person".

**D2 i 0001 ändras.** Relay-servern får byggas nu, som en fristående del av
repot (`relay/`). Skälet är att den bara lagrar ogenomskinliga paket som den
inte kan läsa. Lagring i appen och appens koppling till servern väntar
fortfarande på D3.

**D3 i 0001 är fortfarande obestämt.**

*Senare beslut: D3 godkändes 2026-11-13 ([0003](0003-protocol-library.md),
"Beslut"), och [0004](0004-olm-integration-design.md) godkändes för en intern
prototyp 2026-11-14. Lagring i appen och appens koppling till servern görs
nu enligt 0004 och [`docs/ROADMAP.md`](../ROADMAP.md).*

**Transport v1:**

- Servern har bara två funktioner: **lämna** ett paket och **hämta** paket.
- Inga konton, ingen inloggning, inga pushnotiser och ingen FCM.
- Appen ska senare hämta själv, bara medan den är öppen, med ett fast val
  av intervall: 1, 5, 15 eller 60 minuter.
- VPN är en rekommendation till användaren, inte en funktion i appen.
- Tor eller liknande är uppskjutet.

**IP-adresser:** servern får aldrig spara IP-adresser på disk eller i
loggar. En IP-adress får bara finnas i RAM för spamgränser och ska glömmas
inom några minuter.

## Licens

Beslutat av ägaren 2026-11-13.

- Repot är publikt för insyn sedan 2026-11-18 (ägarens beslut), men koden
  är "All rights reserved" (`LICENSE`) och får inte kopieras eller delas ut.
  Före det var repot stängt.
- Om ett AGPL-bibliotek väljs för protokollet (D3, se
  [0003](0003-protocol-library.md)) byts `LICENSE` till **AGPL-3.0**. Det
  sker senast före första utdelningen av appen, även till testare via
  Google Play.
- **D3 är nu godkänd** (2026-11-13, 0003 "Beslut"): `flutter_vodozemac`
  har licensen AGPL-3.0, så bytet till AGPL-3.0 gäller.

## Formuleringar i appen

Beslutat av ägaren:

- Får användas: **"Servern sparar inte din IP-adress."**
- Får inte användas: **"Servern kan inte se din IP-adress"** och **"anonym"**.

Förslag (inte beslutat, ägaren avgör):

- Får användas: "Servern lagrar bara krypterade meddelanden som den inte
  kan läsa." "Meddelanden raderas från servern efter 48 timmar." "Vi
  rekommenderar VPN om du inte vill att servern ska se din IP-adress."
- Får inte användas: varianter av "anonym" ("anonymt", "helt anonym"),
  "spårlöst", "ingen kan se att du använder SHA" och "inga loggar". Den
  sista gäller för att leverantören och en omvänd proxy kan logga även när
  vårt program inte gör det (fråga b nedan).

## Öppna frågor

- **(a) Flera brevlådor från samma IP.** Brevlåde-ID:n går inte att koppla
  ihop kryptografiskt. Men om appen hämtar flera brevlådor från samma
  IP-adress, och vid samma tid, kan servern koppla ihop dem. Den kan då se
  att de troligen tillhör samma användare. Appen hämtar i dag dagens och
  gårdagens brevlåda för varje kontakt (`inboxMailboxes` i
  `lib/features/chat/messaging_service.dart`). Med fast intervall syns
  mönstret tydligt. Hur appen ska hämta för att minska detta är inte
  bestämt.
- **(b) Leverantören och en omvänd proxy ser IP.** Även om vårt program inte
  sparar IP-adressen ser serverleverantören och en omvänd proxy den, liksom
  allt som ligger på vägen. TLS avslutas i proxyn, så proxyn ser också
  brevlåde-ID:t i URL:en. Om de loggar kan vi inte styra från programmet.
- **(c) Brevlåde-ID:t är nyckeln.** Den som kan ett brevlåde-ID kan hämta
  brevlådans krypterade paket och fylla den till taket. Paketen går inte att
  läsa utan nycklarna. Men en fylld brevlåda avvisar nya paket tills de
  gamla har gått ut (48 timmar). Servern själv känner alla ID:n den tar emot.
- **(d) Löftet om inga loggar kan inte kontrolleras.** Användarna kan inte
  själva se att servern gör det den säger. De kan inte se vilken kod som
  faktiskt körs eller hur proxyn och leverantören är inställda.
- **(e) Delad IP-adress.** Spamgränsen räknas per IP-adress (per /64 för
  IPv6). Användare bakom samma VPN-utgång, operatörs-NAT eller arbetsplatsnät
  delar gräns. VPN-rekommendationen gör detta vanligare.
- **(f) Endast RAM.** Paketen finns bara i minnet. Startas servern om
  försvinner alla paket som inte har hämtats. Avsändaren får inget besked om
  det.
- **(g) Flera servrar.** Version 1 är en enda server. Hur appen väljer bland
  flera servrar ("en pool av reläer") är inte bestämt.
- **(h) Metadata hos servern.** Servern ser för varje paket brevlåde-ID,
  storlek (en av fem), tid och avsändarens IP. För varje hämtning ser den
  brevlåde-ID, tid och hämtarens IP. Den sparar inget av detta utom paketet
  och dess utgångstid, men den ser det.
- **(i) Ingen behörighetskontroll.** Version 1 kontrollerar inte att ett
  paket har rätt format eller att avsändaren är en SHA-app. Den kontrollerar
  bara storleken och brevlåde-ID:ts längd (se `relay/README.md`).
