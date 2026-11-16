# Prova prototypen

Det här är fas 1 i [`docs/ROADMAP.md`](ROADMAP.md): en **intern prototyp**
som bara ägaren provar. Kryptot är inte granskat av en kryptoexpert än
(`OGRANSKAT` i koden). Ge inte appen eller APK:n till någon annan
(`CLAUDE.md`, "Aldrig").

Du behöver:
- en server i EU med en egen domän (grinden G2);
- två Android-telefoner, Android 7 (API 24) eller senare (grinden G3);
- APK:n (steg 2).

## 1. Sätt upp servern (G2)

Allt står i [`relay/README.md`](../relay/README.md). Kort:

1. Hyr en liten VPS i EU. 1 GB RAM räcker: relayn håller paketen i minnet,
   högst 512 MiB som standard.
2. Peka en domän (till exempel `server.example.se`) till serverns IP-adress.
3. Installera Go (se `relay/go.mod`) och bygg relayn:
   ```sh
   cd relay && go build -trimpath -o relay .
   ```
4. Kör relayn som en tjänst som lyssnar på `127.0.0.1:8080`. Lägg nginx med
   TLS framför, enligt exemplet i `relay/README.md` ("Exempel: nginx med TLS
   och utan åtkomstlogg"), och starta relayn med
   `-trusted-proxies 127.0.0.1`.
5. Kontrollera att varken nginx, brandväggen eller leverantören loggar
   IP-adresser (`relay/README.md`, "Vad servern ser, sparar och inte ser").
6. Prova från din dator:
   ```sh
   curl https://server.example.se/healthz   # ok
   ```

Claude kan hjälpa dig steg för steg, men hyr inte servern och hanterar
inga lösenord åt dig.

## 2. Hämta APK:n

Det här beror på beslutet i
[0007](decisions/0007-debug-apk-som-ci-artefakt.md):
- **(a)**: öppna den senaste körningen av CI på `main` under Actions och
  ladda ner artefakten.
- **(b)**: bygg själv med `flutter build apk --debug`. Det kräver Flutter,
  Android SDK, NDK och Rust (se README, "Kom igång").

Det är en **debug-APK**. Den har två hjälpmedel för att prova utan kamera:
kopiera koden på **Min QR** och **Ange kod manuellt** på skannerskärmen. En
kontakt som läggs till så har inte mötts på riktigt.

## 3. Installera på båda telefonerna

1. Skicka APK:n till telefonen, till exempel med en kabel.
2. Tillåt installation från den appen när Android frågar.
3. Öppna SHA. Appen skapar din identitet första gången.

## 4. Prova

1. **Servern:** gå till **Inställningar** på båda telefonerna och skriv
   serverns adress, till exempel `https://server.example.se`. Välj hur ofta
   appen ska hämta: 1, 5, 15 eller 60 minuter. Välj 1 minut för att prova.
2. **Mötet:** öppna **Min QR** på den ena telefonen och **Skanna** på den
   andra. Jämför kontrollkoden, skriv ett namn och spara. Gör sedan samma sak
   åt andra hållet.
3. **Meddelanden:** öppna kontakten och skriv. Appen skickar direkt och
   hämtar vid en slumpad tid inom intervallet, bara när appen är öppen.
4. **Omstart:** stäng appen helt och öppna den igen. Kontakterna och
   sessionerna ska finnas kvar (fas 1, "Klart när" punkt 2). Meddelanden
   som har visats sparas inte (0005 (i)).

## Vad du kan se

- "Inte skickat än" på ett meddelande: servern har inte tagit emot det.
  Appen försöker igen vid nästa runda.
- "Servern är upptagen …" eller "Meddelandet väntar …": servern svarade 429
  eller 507 (0004 §10).
- "Ett meddelande från … kunde inte läsas": se 0004 §10. Händer det igen,
  träffas och skanna varandras QR-koder på nytt.

## Det här är inte klart

- Kryptot är inte granskat (fas 2, G6).
- Ingen historik, ingen säkerhetskopia, inget app-lås.
- Appen hämtar inte i bakgrunden och skickar inga notiser (0002).
- Körningen på en riktig arm64-telefon är inte gjord (G3).

Skriv gärna vad som hände, så tar Claude det vidare i färdplanen.
