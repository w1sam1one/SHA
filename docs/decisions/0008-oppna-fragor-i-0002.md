# 0008 – De öppna frågorna i 0002 inför version 1

Status: **Proposed – owner decides.** Skrivet 2026-11-17 (F7).

Svar på de öppna frågorna i [0002](0002-transport-v1.md) som påverkar
version 1. De flesta är redan besvarade av koden; två behöver ägarens
beslut (markerade **Ägaren beslutar**).

| Fråga i 0002 | Läget nu | Förslag för version 1 |
| --- | --- | --- |
| **(a)** Flera brevlådor från samma IP | Appen hämtar varje brevlåda vid en egen slumpad tid, med en egen anslutning (0004 §9 (b), P6). Samma IP kopplar ändå ihop dem. | Godta för version 1. **Ägaren beslutar** om VPN-rekommendationen i appen, se nedan. |
| **(b)** Leverantören och proxyn ser IP | nginx utan åtkomstlogg och med felloggen avstängd (`relay/README.md`). Leverantören kan ändå se trafiken. | Godta. Säg det ärligt i appen (F5) och i integritetspolicyn (fas 3). |
| **(c)** Brevlåde-ID:t är nyckeln | En full brevlåda (507) stoppar bara den kontakten i appen (P6). Den som vet ID:t kan fylla den i 48 timmar. | Godta för version 1. Relayn har tak per brevlåda (`relay/limits.go`). |
| **(d)** Inga loggar kan inte kontrolleras | Koden blir öppen vid G8. | Godta. Ingen text får lova "inga loggar" (0002). |
| **(e)** Delad IP-adress | Gränsen är 120 anrop per minut och IP (/64). Appen håller sig under cirka 100 och väntar enligt `Retry-After`. | Godta. Följ `rejected_rate` (`relay/DRIFT.md`) och höj gränsen om det behövs. |
| **(f)** Endast RAM | En omstart raderar paket som inte har hämtats, utan besked till avsändaren. | **Ägaren beslutar:** godta för version 1, eller kräv att relayn sparar till disk (en ny grind, med kryptering i vila). |
| **(g)** Flera servrar | Version 1 har en server. | Inte i version 1. |
| **(h)** Metadata hos servern | Dokumenterat i `relay/README.md` och `docs/granskning/hotmodell.md`. | Godta. |
| **(i)** Ingen behörighetskontroll | Relayn kontrollerar bara längden. Skräp som inte är paketformat 3 räknas som "felaktigt" och visar inget. Skräp i format 3 kan däremot visa en rad i chatten (0004 §10; `docs/granskning/fragor.md`, fråga 12). Typ 0, och oftast typ 1, ger "Ett meddelande från … kunde inte läsas …". Olm kontrollerar avståndet i kedjan före MAC:en (vodozemac 0.11.2, `receiver_chain.rs`, `MAX_MESSAGE_GAP` = 2000). Typ 1 med ett kedjeindex mer än 2000 fram ger därför "Några meddelanden från … saknas", med vilken ratchet-nyckel som helst. Typ 1 med en ratchet-nyckel som redan har synts i brevlådan (Olm skickar den i klartext) och ett gammalt index ger "… kom fram för sent …". Den som kan en brevlådes ID kan alltså få de tre raderna att visas. | Godta för version 1, med raderna som de är. Kryptoexperten tar ställning till råden i raderna (fråga 12). |

## Ägaren beslutar

1. **VPN-rekommendationen.** Förslaget i 0002 är inte beslutat: "Vi
   rekommenderar VPN om du inte vill att servern ska se din IP-adress."
   - [ ] Använd texten (den visas då under Inställningar och i "Teknisk
     information", F5).
   - [ ] Använd den inte.
   - [ ] En annan text: ______________________
2. **Paket som försvinner vid en omstart (f).**
   - [ ] Godta för version 1 (rekommenderas: inget sparas på disk, vilket
     också betyder att inget kan läsas av den som tar disken).
   - [ ] Relayn ska spara till disk (blir ett nytt beslutsunderlag).
