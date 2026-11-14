# 0004 – Så ska appen använda Olm

Status: **Proposed – owner decides.** Skrivet 2026-11-13.

Underlag för hur appen kopplar in Olm. Bygger på
[0003](0003-protocol-library.md), där D3 godkändes med villkor 2026-11-13.
Ingen appkod är ändrad. Inkopplingen får börja först när ägaren har godkänt
det här dokumentet (0003, "Beslut").

## Så läses dokumentet

- **Varje punkt** har krav, alternativ med för- och nackdelar, en
  rekommendation och vad som måste testas.
- **"Kräver granskning av kryptoexpert"** betyder att förslaget sätter
  ihop kryptografiska byggstenar på ett nytt sätt. Det är inte färdigt och
  får inte byggas innan en expert har granskat det. Alla sådana punkter
  står samlade sist.
- **Källor** står inom parentes: fil och rad i repot, eller URL och datum.
  - `crate/…` betyder vodozemac-craten 0.11.2, som pluginets `Cargo.lock`
    hämtar.
  - `api.dart` betyder Dart-paketet `vodozemac` 0.9.1, `lib/src/api.dart`.
  - Båda är lästa 2026-11-13.
- **"Ej verifierat"** betyder att det inte är kört eller läst.

## Utgångsläge

- **Identiteten** i dag är en statisk X25519-nyckel i valvet, och hashen
  är SHA-256 av den publika nyckeln (`lib/crypto/src/crypto_service.dart:7-9`).
- **QR-koden** är `shaid:1:<hash, 64 hex>:<nyckel, 43 base64url>`, 116
  tecken (`lib/features/qr/contact_code.dart:17`,
  `spike/vodozemac/test/olm_spike_test.dart:97`).
- **Brevlåde-ID:t** är HMAC-SHA256(brevlådenyckel, "SHA/v2/mailbox" ‖ dag),
  de första 16 byten. Brevlådenyckeln kommer från X25519 och HKDF, en per
  riktning (`lib/crypto/src/sha_crypto_service.dart:150-166`,
  `lib/crypto/src/key_agreement.dart:91-104`).
- **Paketet** är `version (1) ‖ brevlåde-ID (16) ‖ nonce (12) ‖ ciffertext ‖
  tagg (16)`, version 2 (`lib/crypto/src/wire_format.dart:9,16`).
- **Kontakter och meddelanden** finns bara i minnet
  (`lib/features/contacts/contacts_store.dart:21-24`,
  `lib/features/chat/message_store.dart:24-27`).
- **Relayn:**
  - största paket 65 581 byte (`relay/limits.go:20`);
  - paket lever i 48 timmar (`relay/limits.go:27`);
  - hämtning raderar inget (`relay/README.md:66`);
  - 120 anrop per minut och klient (`relay/limits.go:33`).
- **Olm-API:t i Dart** tar och ger text, `String` (`api.dart:263,275`).

## 1. QR-koden `shaid:2`

**Krav.** Koden ska innehålla det den andra personen behöver för att starta
en Olm-session, och inget hemligt. Varje visning har en ny engångsnyckel.
Kontrollkoden (20 siffror) räknas på båda identitetsnycklarna.

**Innehåll** (spiken, R1):
- **Grunden:** Olm-identitetsnyckeln (Curve25519, 32 byte) och en ny
  engångsnyckel (32 byte), alltså 64 byte
  (`spike/vodozemac/lib/olm_spike.dart:32-63`).
- **Som text:** `shaid:2:<base64url utan =>` = 8 + 86 = **94 tecken**
  (`olm_spike_test.dart:112`).
- **Med alternativ A i punkt 3:** en adresseringsnyckel till, 32 byte. Det
  blir 96 byte, alltså 8 + 128 = **136 tecken**. Det ryms i dagens gräns på
  160 tecken (`contact_code.dart:24`).

**Alternativ för att upptäcka en felläst kod:**
- **(a) Ingen hash i koden.**
  - Kortast, och QR-koder har inbyggd felkorrigering (standarden ISO/IEC
    18004, inte läst här).
  - Men ett läsfel i engångsnyckeln märks först när det första
    meddelandet inte går att öppna.
- **(b) Identitetshashen som i dag** (64 hex).
  - Samma kontroll som i `shaid:1`.
  - Men koden blir 159 eller 201 tecken och tätare.
- **(c) En kort kontrollsumma**, några byte av SHA-256.
  - Fångar läsfel direkt.
  - Men det är ett nytt format, och det ger ingen säkerhet, bara
    läskontroll.

**Rekommendation: (a).** Säkerheten kommer från att båda jämför
kontrollkoden, inte från hashen.

**Hash och kontrollkod:**
- **Identitetshashen** är SHA-256 av Olm-identitetsnyckeln, som i dag fast
  på den nya nyckeln. `Contact.id` blir den hashen (`contacts_store.dart:18`).
- **Kontrollkoden** räknas med dagens funktion, oförändrad:
  SHA-256("SHA/v2/verification-code" ‖ min(nyckel A, nyckel B) ‖ max(…)),
  fyra grupper om fem siffror (`sha_crypto_service.dart:131-148`,
  `key_agreement.dart:110-114`).
  - Indata är de två Olm-identitetsnycklarna.
  - Engångsnyckeln ingår inte.
- **Med alternativ A i punkt 3:** frågan om kontrollkoden också ska
  omfatta adresseringsnycklarna står i punkt 3. **Kräver granskning av
  kryptoexpert.**

**Ny engångsnyckel per visning.** Appen skapar en ny nyckel varje gång
QR-koden visas och markerar den som publicerad. Kontot sparas **innan**
koden visas (punkt 6 och 8).

**Koder i formatet `shaid:1`:**
- Appen är inte utdelad och sparar inga kontakter
  (`contacts_store.dart:21`), så inget behöver flyttas.
- Den nya appen läser bara `shaid:2`.
- En `shaid:1`-kod ger texten "Koden kommer från en äldre version av SHA.
  Be din kontakt uppdatera appen." Dagens text för okänd version finns i
  `contact_code.dart:39-43`.

**Testa:**
- längden 94 (eller 136) tecken;
- fel version och skadad kod (63 och 65 byte, som i spiken,
  `olm_spike_test.dart:91-92`);
- kontrollkoden är lika på båda telefonerna och ändras om en nyckel byts;
- en ny engångsnyckel vid varje visning;
- kontot är sparat innan koden visas.

## 2. Vilken session som används

**Krav:**
- Båda skannar varandra (D1), så båda kan starta en session.
- Båda måste till slut skicka på samma session utan att prata om det.
- Inget meddelande får gå förlorat vid bytet.

**Vad som händer** (spiken, R5, `olm_spike_test.dart:335-401`):
- Båda skapar en utgående session och skickar ett första meddelande. Det
  blir två sessioner.
- När båda första meddelandena har kommit fram finns båda sessionerna på
  båda sidor, och båda fungerar.

**Alternativ:**
- **(a) Minsta sessions-id**, spikens regel (`olm_spike.dart:78-92`).
  - Varje sida skickar på den session den har. När den har båda byter den
    till den med minsta id.
  - Regeln är testad i spiken, och ingen behöver vänta: båda kan skriva
    direkt.
  - Men två sessioner per kontakt måste sparas.
- **(b) Bara en sida startar**, till exempel den med lägst
  identitetsnyckel.
  - Då finns bara en session.
  - Men den andra kan inte skriva förrän den har fått ett meddelande. Det
    kräver ett automatiskt första meddelande, och därmed nät vid mötet.
- **(c) Båda startar, och den som tar emot ett första meddelande kastar
  sin egen session.**
  - Men meddelanden som redan skickats på den kastade sessionen går
    förlorade.

**Rekommendation: (a).**
- **Den andra sessionen** behålls så länge meddelanden kan komma på den:
  minst 48 timmar efter det senaste meddelandet på den, vilket är relayns
  livslängd (`relay/limits.go:27`). Sedan raderas den.
- **Skannar någon igen** blir det en tredje session, med en ny
  engångsnyckel. Regeln gäller fortfarande: minsta id av alla.
- **Ingen kryptografi:** regeln jämför bara text.

**Testa:**
- båda skannar, och meddelanden går åt båda håll före och efter bytet;
- ett sent meddelande på den gamla sessionen;
- en tredje skanning;
- radering efter 48 timmar;
- omstart mitt i bytet.

## 3. Brevlåde-ID:n — **Kräver granskning av kryptoexpert**

**Krav:**
1. Båda sidor kommer fram till samma ID utan att prata med varandra.
2. ID:t är olika per riktning och per dag.
3. Relayn kan inte räkna ut ID:n.
4. ID:n kan inte kopplas ihop mellan dagar.
5. Gärna också: den som bara fotograferar QR-koderna kan inte räkna ut ID:n.
   Det gäller i dag, eftersom ID:t kommer från X25519 och inte från något
   som syns i koden.

**Varför frågan finns:**
- Olm ger ingen gemensam hemlighet som appen kan läsa. Dart-API:ts
  `Session` har bara sessions-id, kryptering, avkryptering och pickles
  (`api.dart:242-300`).
- Dagens ID kommer från den statiska X25519-hemligheten
  (`key_agreement.dart:91-104`).

**Alternativ:**
- **(A) Behåll en separat statisk X25519-nyckel bara för adressering**
  (dagens identitetsnyckel), med dagens härledning oförändrad
  (`key_agreement.dart`, `sha_crypto_service.dart:150-166`).
  - Det är kod som redan finns och är testad, och den uppfyller krav 1–5.
  - Men QR-koden blir 96 byte (punkt 1).
  - Adresseringen får ingen forward secrecy. Läcker nyckeln kan någon räkna
    ut alla brevlåde-ID:n, men inte läsa meddelandena.
  - En utbytt adresseringsnyckel vid mötet märks inte på kontrollkoden om
    koden bara räknas på Olm-nycklarna. Då kommer meddelandena inte fram och
    angriparen ser trafiken, men kan inte läsa den. Att ta med nycklarna i
    kontrollkoden ändrar en kryptografisk funktion.
- **(B) Ett slumpmässigt brevlådefrö i QR-koden.** Varje sida visar 32
  slumpbyte, och ID:t är HMAC(frö, etikett ‖ dag) som i dag.
  - Då behövs ingen statisk nyckel, och varje kontakt får ett nytt frö.
  - Men krav 5 uppfylls inte. Den som fotograferar koden kan räkna ut ID:n,
    hämta paketen (men inte läsa dem) och fylla brevlådan (0002, fråga c).
  - Det är en ny användning av HMAC med ett frö.
- **(C) Ett frö som skickas inuti Olm.** Det första meddelandet går till en
  startbrevlåda, och ett nytt frö skickas krypterat med Olm.
  - Fröet syns aldrig i klartext.
  - Men startbrevlådan behöver ändå A eller B. Det är också mest
    komplicerat, och det blir ett nytt protokoll ovanpå Olm.

**Rekommendation, inte färdig: (A).** Den återanvänder testad kod och
uppfyller krav 5. Två saker måste en kryptoexpert avgöra innan den byggs:
- om kontrollkoden ska omfatta adresseringsnycklarna;
- om det är rätt att behålla en statisk nyckel bredvid Olm.

**Testa:**
- samma ID på båda sidor;
- olika ID per riktning och dag;
- ID från kända testvektorer, med dagens funktion;
- datumgränsen, där dagens och gårdagens ID hämtas
  (`messaging_service.dart:122-131`).

## 4. Utfyllnad

**Krav:**
- Relayn ska inte kunna se hur långt ett meddelande är, utöver vilken av
  fem storlekar det har.
- Olm döljer inte längden: ciffertexten växer med texten (0003, R7).
- API:t tar text, `String` (`api.dart:263`).

**Så stort blir ett Olm-meddelande.** Storleken är räknad ur cratens kod och
kontrollerad mot spikens mätningar och en egen mätning (se nedan). Spiken använde Olm version 1, som är
standard i Dart-API:t (`api.dart:382-390`, `crate/src/olm/session/mod.rs:389`).
- **Ett vanligt meddelande (typ 1):**
  1 (version) + 34 (ratchet-nyckel) + 1 + v(i) (kedjeindex) + 1 + v(c)
  (längd) + c (ciffertext) + 8 (MAC) = **c + 45 + v(i) + v(c)**
  (`crate/src/olm/messages/message.rs:145-152,255-262`,
  `crate/src/utilities/mod.rs:99-108`, `crate/src/cipher/mod.rs:46`).
- **c** är texten krypterad med AES-256-CBC och PKCS7. Texten avrundas uppåt
  till nästa multipel av 16, med minst 1 byte till
  (`crate/src/cipher/mod.rs:174-175`).
- **v(x)** är antalet byte för talet x som varint: 1 under 128, 2 under
  16 384 och 3 under 2 097 152.
- **Det första meddelandet (typ 0)** är ett vanligt meddelande plus
  1 + 3 × 34 + 1 + v(vanligt), alltså **vanligt + 104 + v(vanligt)**
  (`crate/src/olm/messages/pre_key.rs:217-226`).

**Kontroll mot spikens R7** (0003):

| Fall | Uträkning | Mätt i spiken |
| --- | --- | --- |
| 1 tecken | c = 16: 16 + 45 + 1 + 1 = 63 | 63 |
| 100 tecken | c = 112: 112 + 45 + 1 + 1 = 159 | 159 |
| 1 000 tecken | c = 1 008: 1 008 + 45 + 1 + 2 = 1 056 | 1 056 |
| 10 000 tecken | c = 10 016: 10 016 + 45 + 1 + 2 = 10 064 | 10 064 |
| Första meddelandet, 1 tecken | 63 + 104 + 1 = 168 | 168 |

**Alternativ:**
- **(A) Utfyllnad innanför Olm, med mellanslag.** Appen fyller ut JSON-texten
  med mellanslag till exakt B − 1 byte (UTF-8), där B är hinken. JSON
  tillåter mellanslag efter värdet, så mottagaren läser texten som vanligt.
  - Bara Olms API och vanlig text behövs.
  - B − 1 ger resten 15 vid division med 16, så PKCS7 lägger till exakt
    1 byte. Ciffertexten blir alltså exakt B.
  - Men det är ny kod, enkel men den måste testas.
  - Storleken varierar ändå några byte (se nedan).
- **(B) Dagens `MessagePadding` innanför Olm, som base64.** Utfyllnaden görs
  som i dag (`lib/crypto/src/padding.dart:16-24`), och resultatet kodas som
  base64-text.
  - Den återanvänder testad kod.
  - Men den blir 33 % större av base64, och det blir två kodningar i rad.
- **(C) Utfyllnad utanför Olm**, alltså att Olm-meddelandet fylls ut i
  paketet. **Kräver granskning av kryptoexpert.**
  - Utfyllnaden ligger utanför krypteringen. Relayn kan ta bort den och se
    den riktiga längden, så den döljer inget för relayn.
  - Olms MAC skyddar inte utfyllnaden.
  - Den fungerar bara tillsammans med ett yttre krypterat lager, vilket är
    en öppen fråga i 0003.

**Rekommendation: (A).**

**Nya storlekar med (A).** B är dagens hinkar (`padding.dart:11`).
Kedjeindex under 128. Paketet är 18 byte plus Olm-meddelandet (punkt 5).

| Hink B | Största text (B − 1 byte) | Olm, vanligt | Olm, första | Paket, vanligt | Paket, första | Paket i dag |
| --- | --- | --- | --- | --- | --- | --- |
| 256 | 255 | 304 | 410 | 322 | 428 | 301 |
| 1 024 | 1 023 | 1 072 | 1 178 | 1 090 | 1 196 | 1 069 |
| 4 096 | 4 095 | 4 144 | 4 250 | 4 162 | 4 268 | 4 141 |
| 16 384 | 16 383 | 16 433 | 16 540 | 16 451 | 16 558 | 16 429 |
| 65 536 | 65 535 | 65 585 | 65 692 | 65 603 | 65 710 | 65 581 |

**Uträkning för hinken 256:**
- Vanligt Olm-meddelande: c = 256, v(i) = 1 och v(256) = 2, alltså
  256 + 45 + 1 + 2 = 304.
- Första meddelandet: 304 + 104 + v(304), där v(304) = 2, alltså 410.
- Paketet: 18 + 304 = 322.
- Dagens paket i sista kolumnen är 17 + 28 + B (`wire_format.dart:21-24`).

**Vad det betyder:**
- **Lika mycket text per hink som i dag.** Dagens regel är också "kortare
  än B" (`padding.dart:17-19`). Problemet i 0003, att 1 000 tecken inte
  får plats i 1 024, försvinner eftersom Olms tillägg nu ligger utanför
  hinken.
- **Vad storleken ändå visar:**
  - Det första meddelandet i en session är 106–107 byte större.
  - Kedjeindex från 128 ger 1 byte till, och från 16 384 ytterligare 1.
  - Relayn kan alltså se när en ny session börjar, och ungefär hur många
    meddelanden i rad någon har skickat utan svar.
  - Hur allvarligt det är: **Kräver granskning av kryptoexpert** (listan
    sist).
- **Mätt 2026-11-13** med en kopia av spiken utanför repot (Linux x86_64,
  samma låsta versioner). Testet är inte incheckat.
  - **Tabellen:** alla Olm-storlekar stämmer exakt, både vanligt och första
    meddelande i alla fem hinkar.
  - **Kedjeindex:** 127 gav samma storlek och 128 gav 1 byte mer.
  - **Utfyllnaden:** text med å och emoji, utfylld med mellanslag, kom
    fram oförändrad, och `jsonDecode` godtog mellanslagen.
- **Ej verifierat:**
  - kedjeindex 16 384 och högre;
  - mätningen på Android.

**Testa:**
- mät varje rad i tabellen med riktiga Olm-meddelanden;
- text på exakt B − 1 och B byte;
- flerbytestecken som å och emoji nära gränsen;
- att mottagaren tar bort utfyllnaden;
- kedjeindex 127 och 128.

## 5. Paketformat version 3

**Krav.** Relayn ska bara se brevlåde-ID och storlek. Mottagaren ska veta
vilken typ av Olm-meddelande det är.

| Fält | Byte | Innehåll |
| --- | --- | --- |
| version | 1 | `3` |
| brevlåde-ID | 16 | som i dag (punkt 3) |
| Olm-typ | 1 | `0` = första meddelandet (pre-key), `1` = vanligt |
| Olm-meddelande | resten | Olm-meddelandet som byte. Dart-API:t ger base64, som appen avkodar. |

**Texten inuti Olm-meddelandet**, före utfyllnad, är JSON
`{"v":3,"id":…,"t":…,"m":…}`. Det är samma som i dag men med `v` 3
(`messaging_service.dart:52-59`).

**Alternativ för typen:**
- **(a) Ett eget byte**, som i tabellen.
  - Enkelt.
  - Relayn ser typen, men den syns ändå på storleken (punkt 4).
- **(b) Appen provar båda typerna vid avkryptering.**
  - Det blir onödiga försök, och ett första meddelande provas mot fel sak.

**Rekommendation: (a).**

**Skillnader mot i dag:**
- **Huvudet skyddas inte.** I dag skyddar AES-GCM huvudet (version och
  brevlåde-ID) som associerad data (`wire_format.dart:11`). Olm-API:t har
  ingen associerad data (`api.dart:263`). Ett paket kan därför flyttas till
  en annan brevlåda, och det märks först när avkrypteringen misslyckas.
  - Om huvudet behöver bindas till innehållet, till exempel med
    brevlåde-ID:t inuti JSON-texten och en kontroll efter avkrypteringen:
    **Kräver granskning av kryptoexpert.**
- **Olm-version:**
  - Spiken använde version 1, med 8 byte MAC
    (`crate/src/olm/session/mod.rs:389`, `crate/src/cipher/mod.rs:46`).
  - Version 2 har 32 byte MAC (`crate/src/olm/session/mod.rs:391`,
    `crate/src/cipher/mod.rs:42`), alltså 24 byte större meddelanden.
  - Version 2 finns bara med den experimentella funktionen
    `experimental-session-config` (`crate/src/olm/session_config.rs:43-50`),
    som pluginet slår på (0003, "Fakta").
  - Valet av version: **Kräver granskning av kryptoexpert.**

**Relayn** (beskrivning, ingen ändring nu):
- **Största paket** blir 18 + 65 692 + 2 = **65 712 byte**: hinken 65 536,
  första meddelandet och kedjeindex på upp till 3 byte. I dag är det 65 581
  (`relay/limits.go:20`).
- `maxPacketSize` och raden "Största paket" i `relay/README.md` ändras i
  samma PR som inkopplingen.
- Relayn kontrollerar bara största längd (`relay/README.md`, "Gränser och
  varför"), så inget annat behöver ändras.

**Testa:**
- tolkning av varje fält;
- för kort paket;
- okänd version eller typ;
- relayn tar emot 65 712 byte och avvisar 65 713.

## 6. Tillstånd, ordning och krascher

**Krav:**
- En krasch får aldrig göra att ett meddelande försvinner tyst.
- Ett gammalt läge får aldrig läsas in igen. En kontopickle från innan
  engångsnyckeln användes godtar nämligen samma första meddelande igen
  (spiken, R6, `olm_spike_test.dart:456-482`).

**Ordningen när ett paket tas emot:**
1. **Hoppa över paket som redan behandlats.** Relayn lämnar ut samma paket
   vid varje hämtning i 48 timmar (`relay/README.md:66`). Appen sparar
   SHA-256 av varje behandlat paket (`crypto_service.dart:31-32`) i minst
   48 timmar. Utan det skulle Olm ge fel för varje dubblett (0003, R4).
2. **Avkryptera i minnet**, eller skapa en inkommande session för typ 0.
3. **Spara allt i en enda atomisk skrivning:**
   - sessionens nya pickle;
   - kontots pickle, om en engångsnyckel användes;
   - meddelandet i historiken;
   - paketets hash.
4. **Visa meddelandet** först därefter.

Vad som händer vid en krasch:
- **Före steg 3** har inget ändrats på disk. Nästa hämtning gör om allt från
  det gamla läget, som fortfarande stämmer, så inget försvinner.
- **Efter steg 3** finns meddelandet sparat, och hashen gör att paketet
  hoppas över.

**Ordningen när ett meddelande skickas:**
1. **Kryptera i minnet.**
2. **Spara atomiskt:**
   - sessionens pickle;
   - meddelandet i historiken, med status "inte skickat";
   - paketets byte i en utkorg.
3. **Skicka till relayn** först därefter. När relayn svarar `204` markeras
   meddelandet som skickat.

Vad som händer vid en krasch:
- **Före steg 2** har paketet aldrig lämnat telefonen, och läget är
  oförändrat.
- **Efter steg 2** skickar utkorgen **samma byte** igen och krypterar
  aldrig om. Kommer paketet fram två gånger tar mottagarens hash bort
  dubbletten.

**Varför sparandet måste komma före nätet:**
- Olm tar fram AES-nyckeln och IV:t ur meddelandenyckeln, utan slump
  (`crate/src/cipher/key.rs:40-63`).
- Skickas ett paket innan läget är sparat, och appen sedan startar om från
  det gamla läget, krypteras nästa meddelande med samma nyckel och samma IV
  en gång till.

**Ordningen när QR-koden visas:** skapa engångsnyckeln, spara kontot, visa
koden (punkt 1).

**Alternativ för atomisk skrivning:**
- **(a) En lokal databas med transaktioner.**
  - Flera saker sparas i en skrivning.
  - Men det blir ett nytt beroende, som väljs senare (D2).
- **(b) Filer** som skrivs till en tillfällig fil och sedan döps om, som
  valvet gör i dag (`lib/crypto/README.md:40`), plus en journal.
  - Inget nytt beroende.
  - Men det är atomiskt för en fil, inte för flera, och journalen blir egen
    kod.
- **(c) En enda krypterad tillståndsfil** som skrivs om varje gång.
  - Enkelt.
  - Men det blir långsamt med en stor historik.

**Rekommendation: (a).**

**Pickle-nyckeln:**
- **Nyckeln** är 32 byte från den blandade slumpkällan
  (`lib/crypto/README.md:66-71`), sparad som en egen post i valvet:
  `olm.pickle-key.v1` (0003, R6).
- **Skyddet:** posten skyddas av Keystore (StrongBox eller TEE) och kan bara
  läsas när telefonen är upplåst (`lib/crypto/README.md:43-49`). Det passar
  ihop med att appen bara hämtar när den är öppen (0002).
- **`resetIdentity()` raderar allt.** Först raderas valvet med alla nycklar
  (`lib/crypto/src/key_vault.dart:17-19`, `crypto_service.dart:25-29`).
  Sedan raderas databasen med pickles, historik, hashar och utkorg.
  Nycklarna raderas först, så att resten inte går att läsa även om
  raderingen av filerna avbryts. I dag raderar `resetIdentity()` bara valvet
  (`sha_crypto_service.dart:79-94`).

**Testa:**
- krasch efter varje steg, vid både mottagning och sändning;
- omstart läser in rätt läge;
- samma första meddelande avvisas efter en omstart;
- utkorgen skickar samma byte;
- `resetIdentity()` lämnar inget kvar.

## 7. Historik

**Krav:**
- Olm raderar meddelandenycklar efter användning, och egna skickade
  meddelanden går inte att avkryptera (0003, "Vad som måste ändras i
  appen").
- Historiken måste därför sparas som klartext, krypterad i vila med en egen
  nyckel som Keystore skyddar.

**Alternativ för lagringen** (inget beroende väljs nu):
- **(a) En lokal databas där varje meddelandes innehåll krypteras** med
  dagens `Aes256Gcm` (`lib/crypto/src/aes_gcm.dart`) och en
  historiknyckel i valvet.
  - Den återanvänder testad kod.
  - Men det är en ny användning. Vad som ska vara associerad data och hur
    nycklarna delas upp ska granskas. **Kräver granskning av kryptoexpert.**
  - Tider och kontakt-id syns i databasen om de inte också krypteras.
- **(b) En databas som krypterar hela filen**, till exempel SQLCipher.
  - Allt blir krypterat, även index.
  - Men det är ett nytt beroende med egen kryptografi som också måste
    granskas.
- **(c) En krypterad fil per konversation.**
  - Det är enkelt att radera en konversation.
  - Men hela filen skrivs om vid varje meddelande.

**Rekommendation: (a), med en nyckel per konversation.** Att radera en chatt
raderar då också dess nyckel, och det som kan ligga kvar på lagringen går
inte att läsa.

**Hur länge historiken sparas och hur den raderas** (ägaren väljer):
- **Förslag:** historiken sparas tills användaren raderar den.
  Användaren kan radera en chatt, och kan välja automatisk radering, till
  exempel efter 1, 7 eller 30 dagar.
- **`resetIdentity()`** raderar alla nycklar och all historik (punkt 6).
- **Flashminne:** raderade data kan ligga kvar fysiskt (allmänt känt om
  flashlagring, ej verifierat på Android här). Skyddet är att nyckeln är
  borta.

**Testa:**
- historiken finns kvar efter en omstart;
- fel nyckel avvisas;
- en raderad chatt går inte att läsa;
- automatisk radering;
- egna skickade meddelanden visas efter en omstart.

## 8. Engångsnycklar

**Fakta:**
- **Lagret:** vodozemac sparar upp till 5 000 privata engångsnycklar,
  100 × 50 (`crate/src/olm/account/one_time_keys.rs:45`,
  `crate/src/olm/account/mod.rs:50`).
- **När lagret är fullt** raderas den äldsta tyst för att ge plats åt en ny
  (`one_time_keys.rs:83-103`, `crate/src/olm/account/mod.rs:330-340`).
  Dart-API:ts `generateOneTimeKeys` returnerar inget, så appen får inte
  veta vilken som raderades (`api.dart:367-368`).
- **Dart-dokumentationen stämmer inte:** `maxNumberOfOneTimeKeys` beskrivs i
  Dart som "can be stored" (`api.dart:315-316`). Craten returnerar 50, som
  den beskriver som antalet som bör publiceras (`crate/src/olm/account/mod.rs:172-190`).
- **En använd nyckel** tar biblioteket bort när den inkommande sessionen
  skapas (`crate/src/olm/account/mod.rs:251,324`). En oanvänd nyckel kan
  tas bort med `removeOneTimeKey` (`api.dart:318-319`).

**Krav:**
- En engångsnyckel per QR-visning.
- En visad nyckel måste finnas kvar tills den andra hinner skicka sitt
  första meddelande, och det kan dröja veckor.
- Oanvända nycklar ska städas.

**Alternativ för städningen:**
- **(a) Ta bort oanvända nycklar efter en fast tid**, till exempel 30 dagar.
  Appen sparar själv när varje nyckel visades och för vilken kontakt, alltså
  den som just skannades.
  - Enkelt.
  - Men ett första meddelande som kommer senare går inte att öppna.
- **(b) Den som skannar skickar automatiskt ett första meddelande** direkt
  efter mötet, så att nyckeln används snabbt.
  - Då kan nyckeln tas bort tidigt.
  - Men det kräver nät vid mötet.
- **(c) Ingen städning**, och appen litar på taket på 5 000.
  - Nycklar ligger kvar i åratal, och vid taket raderas den äldsta tyst.

**Rekommendation: (a), plus (b) när det finns nät.**
- Ägaren väljer antalet dagar.
- Inga reservnycklar (`generateFallbackKey`, `api.dart:354-357`), eftersom
  QR-koden alltid har en ny engångsnyckel.

**Testa:**
- en ny nyckel per visning;
- nyckeln finns kvar efter en omstart;
- städning efter den valda tiden;
- ett första meddelande efter städningen ger rätt text (punkt 10);
- när en kontakt raderas tas dess nyckel bort.

## 9. Hämtning

**Krav** (0002):
- Appen hämtar själv, bara när den är öppen, med ett fast intervall på 1, 5,
  15 eller 60 minuter (`0002-transport-v1.md:27-28`). Ingen push.
- Öppen fråga (a) i 0002: flera brevlådor som hämtas från samma IP och vid
  samma tid kan kopplas ihop (`0002-transport-v1.md:67-72`).

**Fakta:**
- **Två brevlådor per kontakt.** I dag hämtar appen dagens och gårdagens
  brevlåda för varje kontakt (`messaging_service.dart:122-131`).
- **Spamgränsen räcker för cirka 60 kontakter.** Relayn tillåter 120 anrop
  per minut och klient (`relay/limits.go:33`). Med intervallet 1 minut och
  två brevlådor per kontakt räcker det för högst cirka 60 kontakter, utan
  att något skickas.

**Alternativ:**
- **(a) Alla brevlådor på en gång** vid varje intervall.
  - Enkelt.
  - Men relayn ser ett tydligt mönster: samma IP, samma sekund och samma
    lista varje gång.
- **(b) Varje brevlåda vid en slumpad tid inom intervallet**, med en egen
  anslutning.
  - Mönstret blir svagare.
  - Men samma IP kopplar ändå ihop dem, och det drar mer batteri.
- **(c) Låtsashämtningar av påhittade brevlåde-ID:n.**
  - Det döljer antalet kontakter.
  - Men det ger mer trafik, och de riktiga brevlådorna syns ändå eftersom
    de har paket.

**Rekommendation: (b), plus VPN-rekommendationen i 0002.** Ingen av dem
löser fråga (a), eftersom relayn fortfarande ser IP-adressen. Fråga (a) är
fortfarande öppen.

**Testa:**
- intervallet följs;
- ingen hämtning när appen är stängd eller telefonen låst;
- vid `429` väntar appen enligt `Retry-After`;
- många kontakter når inte spamgränsen.

## 10. Felfall och vad användaren ser

**Regler:**
- **Feltexterna innehåller nycklar** (0003, R4). De får aldrig loggas eller
  visas. Appen gör om varje fel till en fast feltyp och visar bara texterna
  nedan.
- **Dubbletter tas bort före avkrypteringen** (punkt 6), så de syns aldrig.
- **`<namn>`** i tabellen är kontaktens namn.

| Fall | Vad biblioteket säger (0003) | Vad användaren ser |
| --- | --- | --- |
| Engångsnyckeln saknas (städad, eller valvet återställt) | `unknown one-time key` | "Ett meddelande från `<namn>` kunde inte öppnas. Ni behöver träffas och skanna varandras koder igen." |
| QR-koden visas igen | inget, en ny nyckel varje gång | Inget särskilt. Skannar någon igen blir det en ny session (punkt 2). |
| Ett meddelande går inte att läsa (ändrat, eller fel session) | `invalid MAC` | Samlat per kontakt: "1 meddelande från `<namn>` kunde inte läsas." Paketet slängs. |
| Meddelandet kom för sent: fler än 40 nyare kom före (`crate/src/olm/session/receiver_chain.rs:50`), eller det är äldre än 5 nyckelbyten (`crate/src/olm/session/mod.rs:55`) | `can't be created` | Samlat: "Ett äldre meddelande från `<namn>` kom fram för sent och kan inte läsas." |
| En lucka på mer än 2 000 meddelanden (`receiver_chain.rs:31`) | `message gap was too big` | "Några meddelanden från `<namn>` saknas. Be `<namn>` skriva igen." |
| Relayn svarar `507` (brevlådan är full) | – | "Meddelandet väntar. Mottagarens brevlåda är full just nu. Appen försöker igen." |
| Relayn svarar `429` | – | "Servern är upptagen. Appen försöker igen om en stund." Appen väntar enligt `Retry-After`. |
| Felaktigt paket (fel version, typ eller längd) | – | Inget. Paketet slängs och räknas. |

**Samma feltext för två fall.** Olm ger samma fel för en dubblett som för ett
meddelande som kom för sent (0003, R3 och R4). Därför tas dubbletterna bort
först, med hashen. Det fel som då är kvar betyder "för sent".

**Varför felen samlas.** Vem som helst som kan ett brevlåde-ID kan lämna
paket där, eftersom relayn inte kontrollerar avsändaren (0002, fråga i). En
rad per trasigt paket skulle kunna fylla chatten.

**Testa:**
- varje rad i tabellen ger rätt text;
- ingen text innehåller nyckelmaterial, genom att utöka
  `test/security/no_logging_test.dart`;
- vid `507` och `429` försöker appen igen med samma byte.

## 11. Testplan för inkopplingen

Det här måste finnas och vara grönt i CI innan inkopplingen får mergas:

1. **Spikens krav i appen:** R1–R7 som enhetstester mot appens egna klasser,
   med samma kontroller som i `spike/vodozemac/test/olm_spike_test.dart`.
2. **R8:**
   - samma tester på Android-emulatorn i CI, som i
     `.github/workflows/spike-android.yml`;
   - en körning på en riktig arm64-telefon före den första utdelningen
     (0003, "Beslut").
3. **QR-kod och kontrollkod** (punkt 1): testvektorer, skadade koder och
   `shaid:1`.
4. **Brevlåde-ID** (punkt 3): testvektorer, samma ID på båda sidor, olika
   per riktning och dag.
5. **Storlekar** (punkt 4 och 5): tabellen mätt, och relayn tar emot det
   största paketet.
6. **Krascher** (punkt 6): avbrott efter varje steg vid mottagning, sändning
   och visning av QR-koden.
7. **Dubbletter:** samma paket hämtat två gånger ger ett meddelande och
   inget fel.
8. **Felfall** (punkt 10): varje rad, och inga nycklar i loggar eller texter.
9. **Hela kedjan mot en riktig relay:** två appinstanser eller testklienter
   mot relayn i CI, med svaren `204`, `507` och `429`.
10. **Mutationer** som i spiken: minst ett avsiktligt fel per regel i punkt
    2, 4 och 6, och alla ska fångas.

## 12. Plan för säkerhetsuppdateringar

**Vad Dependabot täcker** (docs.github.com, läst 2026-11-13):
- **Stöd för våra ekosystem:** versionsuppdateringar och
  säkerhetsuppdateringar stöds för `pub`, `gomod` och `github-actions`.
  `pub` underhålls av Dart-communityn, inte av GitHub
  (<https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories>).
- **Säkerhetsdatabasen:** GitHub Advisory Database omfattar bland annat Pub,
  Go, Rust (crates.io) och GitHub Actions
  (<https://docs.github.com/en/code-security/concepts/vulnerability-reporting-and-management/github-advisory-database>).
- **Rust-craten syns inte.** Beroendegrafen är "a summary of the manifest and
  lock files stored in a repository"
  (<https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/enable-dependency-graph>).
  Craten `vodozemac` och dess beroenden kommer från pluginets egen
  `Cargo.lock` i paketet, inte från en fil i repot. Dependabot varnar alltså
  inte för dem.
- **Actions låsta på SHA ger inga varningar.** Enligt dokumentationen gäller:
  "alerts are only generated for actions that use semantic versioning, not
  SHA versioning"
  (<https://docs.github.com/en/code-security/reference/supply-chain-security/dependency-graph-supported-package-ecosystems>).
  Versionsuppdateringarna fungerar ändå.
- **Verktygen följs inte.** Flutter, Go, Rust, NDK och emulatorns
  systemavbild är låsta i `.github/workflows/`, och dem följer Dependabot
  inte.

**Så följs beroendena:**
1. **Dependabot** (`.github/dependabot.yml`): versionsuppdateringar varje
   vecka. Varningar och säkerhetsuppdateringar slås på i repots
   inställningar (se PR:en).
2. **Rust-craten för hand:**
   - Bevaka säkerhetsmeddelandena för `matrix-org/vodozemac` och för
     pluginets repo hos famedly på GitHub.
   - Förslag för senare: ett CI-jobb som granskar pluginets `Cargo.lock`
     mot RustSec, till exempel med `cargo audit`. Det är inte gjort, och
     verktyget är inte provat här.
3. **Verktygen:** en gång i månaden kontrolleras om Flutter, Go eller Rust
   har nya versioner med säkerhetsrättelser.

**Hur snabbt** (förslag, ägaren bestämmer):
- **Kritisk eller hög allvarlighetsgrad** i krypto- eller lagringskedjan
  (`flutter_vodozemac`, `vodozemac`, craten, `cryptography` och
  Keystore-koden): rättelsen ute till testarna inom 72 timmar.
- **Övrigt:** inom 14 dagar, eller i nästa vanliga version.
- **Om rättelsen inte kan komma i tid:** överväg att stoppa utdelningen.

**Vem gör vad:**
- **Ägaren** slår på inställningarna, läser varningarna, beslutar och
  mergar. Bara ägaren mergar.
- **Assistenten (Claude)** förbereder PR:er (versionsbyte, CI, spiken på
  emulatorn, läsning av ändringsloggar och `BREAKING`-rader) och mergar
  aldrig.
- **Vid varje uppdatering av Olm-paketen** ska CI vara grön, även spiken på
  emulatorn, och cratens CHANGELOG ska vara läst innan ägaren mergar.

## 13. Kvar till den första utdelningen

Från 0003, "Beslut":
1. Spiken körd på en riktig telefon (arm64).
2. Granskning av Flutter/Dart-lagret och bygget.
3. En plan för säkerhetsuppdateringar: punkt 12, godkänd av ägaren och med
   inställningarna påslagna.
4. `LICENSE` bytt till AGPL-3.0.

Det här lägger 0004 till:
5. Ägaren har godkänt 0004.
6. En kryptoexpert har granskat punkterna i listan nedan.
7. Testplanen i punkt 11 är grön.
8. Relayns största paketstorlek är ändrad (punkt 5).
9. Texterna i appen följer 0002 ("Formuleringar i appen") och punkt 10.

## Kräver granskning av kryptoexpert

1. **Brevlåde-ID:n** (punkt 3): att behålla en statisk X25519-nyckel för
   adressering bredvid Olm, och om kontrollkoden ska omfatta
   adresseringsnycklarna.
2. **Kontrollkoden på Olm-nycklarna** (punkt 1): dagens funktion med Olms
   identitetsnycklar som indata. Bekräfta att det räcker.
3. **Utfyllnad utanför Olm** (punkt 4, alternativ C): rekommenderas inte,
   och är bara aktuell tillsammans med ett yttre lager.
4. **Vad storleken visar** (punkt 4): det första meddelandet och kedjeindex
   syns på storleken. Är det godtagbart?
5. **Huvudet är inte bundet till innehållet** (punkt 5): behövs en kontroll
   av brevlåde-ID:t inuti det krypterade?
6. **Olm-version** (punkt 5): version 1 med 8 byte MAC eller version 2 med
   32 byte.
7. **Krypteringen av historiken** (punkt 7): `Aes256Gcm` med en nyckel per
   konversation, och vad som ska vara associerad data.
8. **Pickles och återställning** (punkt 6): att ordningen hindrar att ett
   gammalt läge läses in, och hur pickle-nyckeln hanteras.
9. **Ett yttre AEAD-lager med en hemlighet från QR-koden** (öppen fråga i
   0003): fortfarande öppen.
