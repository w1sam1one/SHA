# SHA – regler för Claude

Den här filen styr allt arbete som Claude gör i repot, både i vanliga
sessioner och i schemalagda körningar i bakgrunden. Ägaren är Wisam Husein
(@w1sam1one). Färdplanen finns i [`docs/ROADMAP.md`](docs/ROADMAP.md).

Avsnitten **Målet**, **Ägarens beslut** och **Aldrig** får bara ägaren
ändra. Claude får föreslå ändringar i dem i en PR, men aldrig merga en sådan
PR själv.

## Målet

SHA är en Android-app för säkra meddelanden där förtroendet skapas när två
personer möts och skannar varandras QR-koder. Säkerhet och anonymitet går
före bekvämlighet.

Målet för den här fasen är en **intern prototyp**: två telefoner som har
mötts kan skicka krypterade meddelanden till varandra via relayn. Exakt vad
"klar" betyder står i `docs/ROADMAP.md` under "Klart när".

Ägarens fasta val (källa inom parentes):

- Android först. Inga telefonnummer, inga konton.
- En kontakt betyder "verifierad i person" (0001, D1).
- Protokoll: Olm via `flutter_vodozemac` (0003).
- Relay v1: bara lämna och hämta, inga konton, ingen push, ingen FCM. IP
  sparas aldrig på disk eller i loggar. Appen hämtar själv, bara när den är
  öppen, med 1, 5, 15 eller 60 minuter. VPN är en rekommendation (0002).
- Repot är stängt nu ("All rights reserved"). `LICENSE` byts till AGPL-3.0
  före första utdelningen av appen (0002, "Licens"). Öppen källkod senare.
- AI får aldrig hitta på kryptografi. Bara granskade bibliotek och redan
  testad kod i `lib/crypto/`.

## Ägarens beslut

Gäller från och med att den här filen finns på `main`.

1. **0004 godkänns för en intern prototyp**, med det rekommenderade
   alternativet i varje punkt.
   - Punkter märkta "Kräver granskning av kryptoexpert" får byggas med
     det rekommenderade alternativet. Koden märks `OGRANSKAT (0004 §N)`,
     och punkten listas i `docs/ROADMAP.md` under "Före första utdelning".
   - Ingen utdelning av appen till någon annan än ägaren förrän en
     kryptoexpert har granskat de punkterna.
2. **Claude får merga sina egna PR:er** enligt "Merge" nedan. Det ersätter
   "assistenten mergar aldrig" i 0004 §12.

## Aldrig

Claude gör aldrig följande. Behövs det, stannar Claude och säger till.

- Delar ut appen: Google Play (även internt test), release-bygge eller APK
  till någon annan än ägaren.
- Byter `LICENSE`, gör repot publikt eller ändrar repots inställningar och
  behörigheter.
- Betalar, skapar konton, hyr servrar eller hanterar signeringsnycklar,
  `key.properties` eller lösenord.
- Hittar på kryptografi: nya primitiver, egna ratchet-steg eller egen
  nyckelhärledning utöver det 0004 rekommenderar.
- Lägger till ett beroende som inte står i ett godkänt beslutsunderlag.
- Force-pushar till `main`, skriver om historiken på `main`, stänger av
  eller hoppar över tester, eller sänker kraven i ett test för att få grönt.
- Mergar en PR som ändrar `LICENSE`, avsnitten ovan i den här filen,
  `permissions:` i `.github/workflows/`, signering i Android-bygget eller
  något som rör utdelning. De lämnas till ägaren.

## Vad Claude bestämmer själv

- Ordningen och uppdelningen inom ett godkänt paket i färdplanen.
- Kodstruktur, namn, tester och testmetod.
- Rättning av rött CI, buggar och fel i dokumentationen.
- Små tekniska val som inte ändrar säkerheten, licensen eller vad
  användaren får se och lova.

Ett nytt val som ändrar säkerheten eller inte går att ångra blir ett
beslutsunderlag (`docs/decisions/NNNN-…md`, status "Proposed – owner
decides") och en grind i färdplanen. Arbetet stannar där tills ägaren har
bestämt.

## Så arbetar Claude

1. **Ett paket i taget** från `docs/ROADMAP.md`, i ordning. Egen gren
   `pm/<paket>` från `main`, och en draft-PR.
2. **Regler som alltid gäller:**
   - Inga nycklar, klartext eller nonces i loggar
     (`test/security/no_logging_test.dart`). Bibliotekets feltexter från
     Olm innehåller nycklar och visas eller loggas aldrig.
   - Texter i appen på vardaglig svenska och enligt 0002, "Formuleringar i
     appen".
   - Inga nya `Color(0x` utanför temat.
   - Appen når kryptot bara via `CryptoService`.
   - Exakta versioner för nya beroenden, och lockfilen incheckad.
3. **Tester först** där det går. Nya regler får minst en mutation som visar
   att ett test faller.
4. **CI ska vara grön** på PR:ens senaste commit, i alla jobb som körs.
   Flutter går ofta inte att installera i molnsessionen. Då är CI på GitHub
   beviset, och Claude väntar på det i stället för att gissa.
5. **Oberoende granskning:** innan merge granskar en separat agent, som
   inte har skrivit koden, diffen mot paketet, 0004 och den här filen.
   Allvarliga fynd rättas. Övriga skrivs i PR:en.
6. **Ärlighet:** rapporten skiljer på kört, läst och ej verifierat. Claude
   påstår aldrig att något är testat om det inte är det.
7. **Färdplanen uppdateras** i samma PR: paketets status och en rad i
   loggen.

## Merge

Claude får merga en egen PR när allt detta gäller:

- CI är grön på senaste commit.
- Den oberoende granskningen är gjord och har inga öppna allvarliga fynd.
- PR:en håller sig inom ett godkänt beslut och ett paket i färdplanen.
- Den rör inget av det som står sist under **Aldrig**.

Vanlig merge commit, ingen squash och ingen force-push. Sedan raderas
grenen.

## När Claude stannar

- Vid en grind i färdplanen.
- När samma fel finns kvar efter två försök utan framsteg.
- När något är oklart och påverkar säkerheten.

Då skriver Claude kort vad som blockerar och vad ägaren behöver göra.
