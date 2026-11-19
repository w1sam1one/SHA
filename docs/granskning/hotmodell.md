# Hotmodell

## Vad SHA lovar

- **Innehållet** i ett meddelande kan bara läsas av de två personerna.
- **En kontakt är verifierad i person** (0001, D1): två personer har mötts,
  skannat varandras QR-koder och jämfört en kontrollkod.
- **Servern** (relayn) ser så lite som möjligt och sparar ingen IP-adress
  på disk eller i loggar (0002).
- Säkerhet och anonymitet går före bekvämlighet (`CLAUDE.md`, "Målet").

Appen lovar **inte** anonymitet mot servern eller nätet: "anonym" får inte
användas (0002, "Formuleringar i appen").

## Tillgångar

| Tillgång | Var | Skydd |
| --- | --- | --- |
| Olm-kontot och sessionerna (pickles) | Valvposten `olm.state.v1` | Pickles krypterade av vodozemac med pickle-nyckeln; posten krypterad med AES-GCM av en nyckel i Android Keystore |
| Pickle-nyckeln (32 byte) | Valvposten `olm.pickle-key.v1` | Keystore-nyckeln |
| X25519-nyckeln för brevlådor | Valvposten för identiteten | Keystore-nyckeln |
| Meddelanden som inte har skickats eller visats | Utkorg och inkorg i `olm.state.v1` | Som ovan; bara tills de har skickats eller visats (0005 (i)) |
| Skickade och visade meddelanden (historiken) | Egna valvposter `h.<16 slumpade hex>`, en eller flera per kontakt, listade i `olm.state.v1`, den tid användaren valt (0010 (B)) | Samma Keystore-nyckel; en raderad post kan finnas kvar på flashminnet och läsas tills `resetIdentity()` eller avinstallation. Filernas tider visar ungefär när man skrivit med varje kontakt, utan att visa vem |
| Kontakter: namn, när ni möttes, nycklar | `olm.state.v1` | Som ovan |
| Inställningar: serverns adress, intervallet | `olm.state.v1` | Som ovan |

## Angripare

| Angripare | Kan | Kan inte (om koden stämmer) |
| --- | --- | --- |
| **Den som driver servern** | Se brevlåde-ID, paketets storlek (hinken, typ 0, kedjeindex; 0004 §4), när det kom och IP-adressen; tappa, fördröja, kopiera eller flytta paket; lämna egna paket i en känd brevlåda | Läsa innehållet; se vem som pratar med vem utöver IP och tid; få appen att visa ett ändrat paket (Olm-MAC) |
| **Nätet mellan telefon och server** | Se att telefonen pratar med servern, och storlek och tid | Läsa eller ändra något: TLS med systemets CA:er |
| **Den som känner en brevlådes ID** (0002, fråga c och i) | Lämna skräp eller kopior där; hämta de krypterade paketen; fylla brevlådan, så att riktiga paket får 507 i upp till 48 timmar | Läsa paketen; få skräpet visat som ett meddelande. Raderna "kunde inte läsas", "saknas" och "kom fram för sent" kan dock visas (0008 (i)) |
| **En kontakt** | Läsa det du skickar till den; skicka meddelanden med påhittade ID eller tider | Läsa dina andra konversationer |
| **Den som har telefonen i handen, upplåst** | Läsa det som visas | – |
| **Den som har telefonen, låst** | – | Läsa valvet (Keystore-nyckeln kräver upplåst telefon på Android 9+) |
| **En annan app på telefonen** | – | Läsa appens filer (privat katalog, ingen backup, `FLAG_SECURE`) |
| **Leverantörskedjan** | Ett ändrat paket på pub.dev, crates.io eller i en action | – (se `flutter-och-bygget.md`) |

## Utanför modellen i den här fasen

- En telefon med root, eller med skadlig kod som läser minnet.
- Trafikanalys över tid, och att flera brevlådor från samma IP kan kopplas
  ihop (0002, fråga a; 0004 §9).
- Att leverantören av servern loggar (0002, fråga b).
- Säkerhetskopior.
- Ett yttre lager med en hemlighet från QR-koden (0003, öppen fråga).
