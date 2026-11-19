# Butikstexter och skärmbilder (F11)

**Utkast. Ägaren godkänner texterna innan de används** (`CLAUDE.md`: det
användaren får se och lova är ägarens). Texterna gäller appen som den är
när den släpps, alltså efter grindarna G6, G8 och G9–G11 i
[`docs/ROADMAP.md`](ROADMAP.md).

## Reglerna

- Inget som appen inte gör, och inget av det som `docs/release.md`, punkt 7,
  räknar upp: att raderad historik inte går att läsa, att app-låset skyddar
  nyckeln eller meddelandena på lagringen, att appen hämtar i bakgrunden
  eller att den har forward secrecy.
- Orden i 0002, "Formuleringar i appen". `test/security/store_texts_test.dart`
  stoppar de förbjudna orden i texterna nedan, på svenska och engelska, och
  kontrollerar längderna.
- Längderna är de som Play Console brukar ha: namn högst 30 tecken, kort
  beskrivning högst 80 och fullständig beskrivning högst 4 000. **Ej
  kontrollerat** mot Googles egna sidor (F9, `docs/play-krav.md`).

## Kontrollera före släppet

- [ ] `LICENSE` är bytt till AGPL-3.0 (G8). Annars ska meningen om
  källkoden bort.
- [ ] Intervallen, historikens val och app-låsets 5 minuter stämmer med
  appen (`lib/features/transport/transport_settings.dart`,
  `lib/features/lock/app_lock.dart`).
- [ ] Att skärmdumpar är avstängda är provat på en riktig telefon
  (`docs/testprotokoll.md`, 1.4).
- [ ] Ägaren har godkänt texterna.

## Svenska

### Namn

```text
SHA
```

### Kort beskrivning

```text
Krypterade meddelanden med personer du har träffat och skannat QR-kod med.
```

### Fullständig beskrivning

```text
SHA är en app för krypterade meddelanden mellan personer som har träffats. Ni blir kontakter genom att skanna varandras QR-koder när ni ses. Det behövs inget telefonnummer och inget konto.

Så fungerar det
• Ni träffas och skannar varandras QR-koder. Då står kontakten som verifierad i person.
• Meddelandena krypteras på din telefon och kan bara läsas på era två telefoner. De går via en server som du ställer in, och som bara tar emot och lämnar ut krypterade paket.
• Appen hämtar nya meddelanden bara när den är öppen, så ofta du väljer: varje minut, var 5:e eller 15:e minut, eller varje timme. Det finns inga notiser.

Vad servern ser
Servern kan inte läsa dina meddelanden. Den ser din IP-adress, när du skickar och hämtar, och hur stora paketen är. SHA:s serverprogram sparar inte din IP-adress på disk eller i loggar, men den som driver servern kan ändå se och spara trafiken. Vi rekommenderar VPN om du inte vill att servern ska se din IP-adress.

Bra att veta
• Historiken sparas i 30 dagar om du inte väljer något annat: Spara inte, 7 dagar, 30 dagar eller 1 år.
• Appen låses med telefonens eget skärmlås när den öppnas och när den har varit i bakgrunden i 5 minuter. Låset döljer skärmen.
• Skärmdumpar är avstängda i appen.
• Det finns ingen säkerhetskopia. Tappar du telefonen måste ni träffas och skanna varandras QR-koder igen.
• Kameran används bara för att skanna QR-koder.
• Källkoden är öppen under AGPL-3.0.
```

## English

### Name

```text
SHA
```

### Short description

```text
Encrypted messages with people you have met and scanned a QR code with.
```

### Full description

```text
SHA is an app for encrypted messages between people who have met. You become contacts by scanning each other's QR codes when you meet. No phone number and no account are needed.

How it works
• You meet and scan each other's QR codes. The contact is then shown as verified in person.
• Messages are encrypted on your phone and can only be read on your two phones. They go through a server that you set, which only takes in and hands out encrypted packets.
• The app fetches new messages only while it is open, as often as you choose: every minute, every 5 or 15 minutes, or every hour. There are no notifications.

What the server sees
The server cannot read your messages. It sees your IP address, when you send and fetch, and how large the packets are. SHA's server program does not store your IP address on disk or in logs, but whoever runs the server can still see and save the traffic. We recommend a VPN if you do not want the server to see your IP address.

Good to know
• The history is kept for 30 days unless you choose otherwise: not at all, 7 days, 30 days or 1 year.
• The app is locked with the phone's own screen lock when it opens and after 5 minutes in the background. The lock hides the screen.
• Screenshots are turned off in the app.
• There is no backup. If you lose your phone, you need to meet and scan each other's QR codes again.
• The camera is used only to scan QR codes.
• The source code is open under AGPL-3.0.
• The app is in Swedish.
```

## Skärmbilder

Appen sätter `FLAG_SECURE` i alla byggtyper, så telefonens egna
skärmdumpar blir svarta. Det ändras inte för skärmbilderna
(`test/security/flag_secure_test.dart`). I stället tar ett test bilderna
genom Flutters egen ritning, i ett debug-bygge som aldrig är release-appen:

```sh
flutter drive --driver=test_driver/screenshots.dart \
  --target=integration_test/screenshots_test.dart -d <enhet>
```

- Bilderna hamnar i `build/screenshots/`: identiteten, chattarna, Min QR,
  kontakterna och inställningarna.
- Appen måste starta som för en ny användare, och testet skapar en ny
  identitet på enheten. Har SHA redan en identitet där, stannar testet före
  den första bilden, eftersom bilderna annars skulle visa den och dess
  kontakter. Testet raderar aldrig något. Kör det på en emulator, eller på
  en testtelefon där SHA inte är installerad, och avinstallera appen
  efteråt.
- CI kör samma test på emulatorn och kontrollerar att ingen bild är svart
  eller tom.
- **Inte med än:** en chatt med meddelanden. Den kräver en andra telefon
  eller en låtsasserver i testet.
- **Ej kontrollerat:** vilka storlekar och hur många bilder Play kräver
  (F9).
