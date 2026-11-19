# SHA relay v1

En liten server som tar emot krypterade paket och lämnar ut dem igen.
Den gör bara två saker: **lämna** ett paket i en brevlåda och **hämta**
brevlådans paket. Beslutet bakom den finns i
[docs/decisions/0002-transport-v1.md](../docs/decisions/0002-transport-v1.md).

> **Inte driftsatt.** Ingen server är hyrd och inget är publicerat (G2 i
> [`docs/ROADMAP.md`](../docs/ROADMAP.md)). Appen skickar och hämtar via
> relayn sedan P6; hur ägaren sätter upp den står i
> [`docs/prototyp.md`](../docs/prototyp.md).

- Bara Gos standardbibliotek, inga andra beroenden.
- Paket ligger bara i RAM. Relayn skriver inga filer; loggraderna (utan
  identifierare) går till stderr och hamnar där driften skickar den.
- Servern dekrypterar ingenting och läser inte paketen, bara deras längd.

## Köra lokalt

Kräver Go 1.26 eller senare (`go.mod`). CI kör Go 1.27.4.

```sh
cd relay
go run .                       # lyssnar på 127.0.0.1:8080
go vet ./... && go test -race ./...
```

Prova med curl:

```sh
ID=00112233445566778899aabbccddeeff
head -c 322 /dev/urandom > paket.bin
curl -i --data-binary @paket.bin http://127.0.0.1:8080/v1/mailbox/$ID   # 204
curl -s http://127.0.0.1:8080/v1/mailbox/$ID | wc -c                    # 326 (4 + 322)
curl http://127.0.0.1:8080/healthz                                      # ok
```

Flaggor (`go run . -h`):

| Flagga | Standard | Betyder |
| --- | --- | --- |
| `-addr` | `127.0.0.1:8080` | Adress att lyssna på. Låt den vara lokal och lägg en TLS-proxy framför. |
| `-trusted-proxies` | tomt | Proxyadresser (IP eller CIDR, kommaseparerade) vars `X-Forwarded-For` används. Tomt = aldrig. |
| `-rate-limit` | `120` | Anrop per klient och minut. |
| `-max-packets-per-mailbox` | `1000` | Paket per brevlåda. |
| `-max-mailbox-mib` | `8` | MiB per brevlåda. |
| `-max-total-mib` | `512` | MiB för alla paket tillsammans. |

## API

| Anrop | Svar |
| --- | --- |
| `POST /v1/mailbox/{id}` med paketet som råa byte i kroppen | `204` sparat · `400` fel ID eller tom kropp · `413` för stort · `429` spamgräns · `507` fullt |
| `GET /v1/mailbox/{id}` | `200` med alla paket, äldst först · `400` fel ID · `429` spamgräns |
| `GET /healthz` | `200` och `ok` |

Allt annat ger `404`, eller `405` för fel metod på en känd sökväg, även
`HEAD`.

- **`{id}`** är brevlåde-ID:t som hex: exakt 32 tecken (16 byte, se
  `lib/crypto/src/olm_wire_format.dart`). Stora och små bokstäver betyder samma
  brevlåda.
- **Svarsformat för `GET`** (`application/octet-stream`): för varje paket
  4 byte längd (big-endian), sedan paketets byte. Inga paket ger en tom kropp.
- **Okänd och tom brevlåda ger samma svar:** `200`, samma huvuden och tom
  kropp, så att ingen kan se om ett ID har använts.
- **Hämtning raderar inget.** Paketen ligger kvar tills de går ut, så appen
  måste själv känna igen dubbletter. Det gör den redan: `MessageStore.add`
  tar bara emot samma meddelande-ID en gång.
- **Alla svar** har `Cache-Control: no-store`.

## Gränser och varför

| Gräns | Värde | Varför |
| --- | --- | --- |
| Brevlåde-ID | 32 hextecken | `PacketV3.mailboxIdLength = 16` byte. |
| Största paket | 65 712 byte | Paketformat 3 (0004 §5): huvud 1 + 16 + 1 och det största Olm-meddelandet, 65 694 byte (hinken 65 536, typ 0 och ett kedjeindex på upp till 3 byte). Storleken beror på hinken, Olm-typen och kedjeindex (0004 §4), men relayn kontrollerar bara största längd. Härledningen står i `limits.go`. |
| Tom kropp | avvisas | Ett paket är aldrig tomt. |
| Livslängd | 48 timmar | Appen hämtar dagens och gårdagens brevlåda (`inboxMailboxes`). Paketen raderas automatiskt; städningen körs var 30:e sekund, och utgångna paket lämnas aldrig ut. |
| Paket per brevlåda | 1 000 | En brevlåda är en riktning i en konversation under ett dygn. |
| Byte per brevlåda | 8 MiB | Begränsar storleken på ett `GET`-svar. |
| Totalt minne | 512 MiB | Paketens byte plus en uppskattad kostnad per paket och brevlåda. Taket gäller lagrade paket. Förfrågningar som pågår, spamgränsens tabell och Go-runtimens eget minne kommer utöver; räkna med mer RAM än taket. |
| När ett tak nås | `507`, det nya paketet avvisas | De sparade paketen behålls. Att i stället kasta de äldsta skulle tyst tappa meddelanden; ett avvisat paket kan avsändaren försöka skicka igen. Nackdel: den som kan ett brevlåde-ID kan fylla brevlådan (0002, fråga c). |
| Spamgräns | 120 anrop per minut och klient | Räknas per IPv4-adress och per IPv6-/64 (ett nät får oftast hela /64). `429` med `Retry-After`. Gäller `POST` och `GET` på brevlådor (inte `/healthz`) och kontrolleras innan något annat läses. |
| HTTP | huvuden 5 s, läsning 30 s, skrivning 2 min, inaktiv 60 s, huvuden högst 8 KiB | Mot långsamma eller hängande anslutningar. Skrivtiden räcker för ett fullt `GET`-svar på 8 MiB om klienten tar emot minst cirka 0,6 Mbit/s. |

### Spamgränsen och IP-adresser

- IP-adressen finns bara i RAM, som nyckel i spamgränsen.
- Varje klients räkneverk gäller en minut. Det raderas vid nästa städning
  efter att minuten har gått, alltså **högst 90 sekunder** efter klientens
  första anrop i fönstret. Ett anrop efter minuten startar ett nytt fönster
  under samma adress, så en adress som anropar minst en gång i minuten finns
  kvar hela tiden, även när anropen kommer från olika telefoner bakom samma
  adress. Adressen är borta senast 90 sekunder efter det sista anropet från
  den.
- Go frigör minnet vid skräpsamling men skriver inte över det.
- Många användare bakom samma VPN-utgång eller operatörs-NAT delar en gräns
  (0002, fråga e).
- Tabellen växer med antalet olika klienter per minut (ungefär 100 byte per
  klient, uppskattat). Den som förfogar över många IPv6-nät kan därför få
  den att växa. Antalet samtidiga anslutningar har inget eget tak i v1.

## IP-adressen bakom en omvänd proxy

Utan `-trusted-proxies` använder relayn TCP-motpartens adress och bryr sig
inte om `X-Forwarded-For`. Bakom en proxy är motparten proxyn själv, så alla
klienter skulle dela en gräns.

Med `-trusted-proxies 127.0.0.1` gäller:
- Kommer anropet från en betrodd proxy läser relayn `X-Forwarded-For` från
  höger till vänster och tar första adressen som inte är en betrodd proxy.
- Allt till vänster om det din egen proxy lade till har klienten själv
  kunnat skriva, och används aldrig.

**Risk:** om relayn går att nå utan att gå via proxyn, eller om en betrodd
adress kan användas av någon annan, kan vem som helst skicka ett falskt
`X-Forwarded-For`. Då kan de välja vilken klient de räknas som: de slipper
sin egen gräns, eller fyller någon annans. Därför:
- Lyssna bara på `127.0.0.1` (standard) eller ett privat nät som bara proxyn
  når.
- Låt proxyn **skriva över** `X-Forwarded-For` med klientens adress, inte
  lägga till. Se nginx-exemplet.
- Ange så smala adresser som möjligt i `-trusted-proxies`.

## Vad servern ser, sparar och inte ser

| | |
| --- | --- |
| **Ser** | Avsändarens och hämtarens IP-adress (eller proxyns), brevlåde-ID, paketets storlek, tidpunkt. |
| **Sparar i RAM** | Paketets byte och när det går ut, per brevlåde-ID, i högst 48 timmar. Klientens adress i spamgränsen medan den anropar, och högst 90 sekunder efter dess sista anrop. Räknare utan identifierare. |
| **Sparar aldrig** | IP-adresser på disk eller i loggar. Brevlåde-ID:n eller paket i loggar. Paket på disk. |
| **Ser inte** | Innehållet: paketen är krypterade, och relayn har inga nycklar. Vem som pratar med vem: paketet innehåller inga identiteter, bara ett brevlåde-ID som byts varje dygn. |

Vad servern ändå kan lära sig, och vad leverantören och proxyn ser, står i
0002 under "Öppna frågor". **Servern ser IP-adressen.** Den sparar den bara
inte.

## Loggning

Relayn skriver bara till stderr:
- en rad vid start (port, inte adress, och gränserna);
- fel med fasta texter, utan identifierare;
- räknare var 15:e minut och vid avstängning (t.ex. `stored=`,
  `rejected_rate=`, antal brevlådor och byte).

Inga IP-adresser, brevlåde-ID:n eller paket skrivs ut:
- **net/http:s egen fellogg** kan innehålla klientens adress, t.ex. `http:
  panic serving <adress>`. Den är ersatt med en fast text.
- **Panik i en hanterare** fångas utan att värdet loggas.
- **Fel från `net.Listen`** innehåller lyssningsadressen och ersätts också.

Testet `TestLogsHoldNoAddressesOrMailboxIDs` kör hela programmet. Det
gör anrop av alla slag, får net/http att logga ett fel som nämner klienten,
och kontrollerar att varken adresser eller brevlåde-ID:t finns i loggen.

## Exempel: nginx med TLS och utan åtkomstlogg

**Exempel, inte driftsatt.** Byt `relay.example.se` och certifikatsökvägarna.
Starta relayn med `-trusted-proxies 127.0.0.1`.

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name relay.example.se;

    ssl_certificate     /etc/letsencrypt/live/relay.example.se/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/relay.example.se/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Ingen åtkomstlogg: varje rad skulle innehålla IP-adress och brevlåde-ID.
    access_log off;
    # nginx fellogg tar med "client: <IP>" även på nivån crit. /dev/null
    # stänger av den helt; skriv en fil i stället om du behöver felsöka.
    error_log /dev/null crit;

    # Största paket, se relay/limits.go. Bufferten lika stor, så att nginx
    # håller kroppen i minnet i stället för att skriva den till en temporär fil.
    client_max_body_size    65712;
    client_body_buffer_size 65712;
    # Skriv inte heller svar till temporära filer på disk.
    proxy_max_temp_file_size 0;

    location /v1/mailbox/ {
        proxy_pass http://127.0.0.1:8080;
        # Skriv över, lägg inte till: klientens egen rubrik ska inte följa med.
        proxy_set_header X-Forwarded-For $remote_addr;
    }
    location = /healthz {
        proxy_pass http://127.0.0.1:8080;
    }
    location / {
        return 404;
    }
}
```

Även med avstängda loggar ser serverleverantören och proxyn trafiken (0002,
fråga b). Kontrollera också att inget annat på servern loggar
anslutningar: brandvägg, lastbalanserare, leverantörens nätloggar.

### Vad som är provat lokalt

Exemplet ovan provades 2026-11-13 med nginx 1.24 och ett självsignerat
certifikat på samma maskin, då med gränsen 65 581 byte (paketformat 2).
Ändringarna var lokala portar och sökvägar, och fellogg till en fil på nivå
`crit` för att kunna läsa den. Resultat:
- TLS, `POST`, `GET` (även 2 × 65 581 byte), `/healthz` och `404` för okänd
  sökväg fungerade.
- `413` för 65 582 byte stoppades redan i nginx.
- Spamgränsen räknades per klientadress via `X-Forwarded-For`. Ett falskt
  `X-Forwarded-For` från klienten skrevs över och hjälpte inte.
- Båda nginx-loggarna var tomma (0 byte). Relayns logg innehöll varken
  adresser eller brevlåde-ID.
- **Kroppen hålls i minnet:** utan `client_body_buffer_size` lika stor som
  gränsen försökte nginx skriva paketet till en temporär fil på disk. Det
  syntes i felloggen, och raden innehöll klientens adress trots nivån
  `crit`.
- **`proxy_max_temp_file_size 0` är ej verifierat:** testet kunde inte visa
  någon skillnad med eller utan inställningen. Den är kvar enligt nginx
  dokumentation.

**Den nya gränsen 65 712 byte** (paketformat 3) provades 2026-11-16 på samma
sätt, med nginx 1.24 och exemplet ovan. Spamgränsen provades inte om.
- Två `POST` med 65 712 byte gav `204`. `GET` gav 131 432 byte
  (2 × (4 + 65 712)), lika med de två paketen.
- `413` för 65 713 byte stoppades redan i nginx: relayn såg inte anropet.
- `/healthz` och `404` fungerade.
- Båda nginx-loggarna var tomma (0 byte), och nginx skrev inga temporära
  filer.

**Inte provat:**
- en riktig server, ett riktigt certifikat och IPv6 utifrån;
- belastning och många samtidiga klienter i drift;
- leverantörens och operativsystemets loggar;
- andra proxyer än nginx.
