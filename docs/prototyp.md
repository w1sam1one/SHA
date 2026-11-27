# Prova prototypen

Det här är fas 1 i [`docs/ROADMAP.md`](ROADMAP.md): en **intern prototyp**
som bara ägaren provar. Kryptot är inte granskat av en kryptoexpert än
(`OGRANSKAT` i koden). Ge inte appen eller APK:n till någon annan
(`CLAUDE.md`, "Aldrig").

Du behöver:
- en server i EU med en egen domän (grinden G2);
- två Android-telefoner med Android 9 (API 28) eller senare (grinden G3).
  Appen kräver det sedan 0014: nyckeln fungerar bara när telefonen är
  upplåst;
- APK:n, som du bygger själv (steg 2).

## 1. Sätt upp servern (G2)

Allt står i [`relay/README.md`](../relay/README.md). Kort:

1. Hyr en liten VPS i EU. Relayn håller paketen i minnet, högst 512 MiB
   som standard, och behöver mer RAM än så (`relay/README.md`). Med 1 GB
   RAM: starta relayn med `-max-total-mib 256`.
2. Peka en domän till serverns IP-adress. Byt ut `relay.example.se` i
   nginx-exemplet och `server.example.se` här mot din domän.
3. Gör servern säker, bygg relayn och kör den som en tjänst på
   `127.0.0.1:8080` med `-trusted-proxies 127.0.0.1`, enligt
   [`relay/DRIFT.md`](../relay/DRIFT.md), avsnitt 1 och 2.
4. Lägg nginx med TLS framför enligt `relay/DRIFT.md`, avsnitt 3, i den
   ordning som står där: nginx-exemplet i `relay/README.md` pekar på
   certifikatfiler som inte finns förrän det första certifikatet är hämtat.
   Certifikatet måste komma från en publik CA, till exempel Let's Encrypt
   med certbot: appen litar bara på telefonens egna CA:er, så ett
   självsignerat certifikat fungerar inte.
5. Kontrollera att varken nginx eller brandväggen loggar IP-adresser
   (`relay/README.md`, "Vad servern ser, sparar och inte ser").
   Leverantören kan ändå se och logga trafiken (0002, fråga b).
6. Prova från din dator:
   ```sh
   curl https://server.example.se/healthz   # ok
   ```

Claude kan hjälpa dig steg för steg, men hyr inte servern och hanterar
inga lösenord åt dig.

## 2. Bygg APK:n

Du bygger APK:n själv på din dator (0007 (b)). CI laddar inte upp någon
APK. CI bygger en test-APK för emulatorn (x86_64), och samma debug-APK som
du bygger i steg 3, men bara för arm64 (jobbet "Debug APK for real phones
(arm64)" i `.github/workflows/ci.yml`). Jobbet kontrollerar att Flutter,
Olm och alla andra inbyggda bibliotek finns med för arm64.

**Ej provat:** ingen har följt stegen nedan än, och appen har aldrig körts
på en riktig telefon. Bygget för 32-bitars arm, som `flutter build apk
--debug` också gör, provas inte i CI. Skriv ner det som inte stämmer, så
rättar jag texten.

1. Installera:
   - Flutter **3.47.7**, samma som i CI (`.github/workflows/ci.yml`);
   - JDK 17 (`android/app/build.gradle.kts`);
   - Android SDK, till exempel via Android Studio, med **Android SDK
     Command-line Tools** och **NDK 28.2.13676358**. Den versionen krävs:
     Flutter 3.47.7 väljer den (`ndkVersion = flutter.ndkVersion`);
   - Rust via `rustup`, med `rustup toolchain install stable`. Pluginet
     lägger själv till Android-målen när det bygger (README, "Kom igång").

   Godkänn Androids licenser och kontrollera installationen:
   ```sh
   flutter doctor --android-licenses
   flutter doctor
   ```
2. Hämta koden och paketen, exakt enligt låsfilen:
   ```sh
   git clone https://github.com/w1sam1one/SHA.git
   cd SHA
   ```
   ```sh
   flutter pub get --enforce-lockfile
   ```
3. Bygg:
   ```sh
   flutter build apk --debug
   ```
   APK:n hamnar i `build/app/outputs/flutter-apk/app-debug.apk`. Första
   bygget tar en stund, eftersom Olm-biblioteket byggs från källkod.

   Vill du bygga exakt det som CI provar, och lite snabbare:
   ```sh
   flutter build apk --debug --target-platform android-arm64
   ```
   Den APK:n fungerar bara på telefoner med 64-bitars arm (arm64).

Bygg bara debug, och ge inte APK:n till någon annan: ingen utdelning före
kryptoexpertens granskning (`CLAUDE.md`, "Ägarens beslut" 1). Ett
release-bygge blir dessutom osignerat utan `key.properties`
(`android/app/build.gradle.kts`).

Det är en **debug-APK**. Den har två hjälpmedel för att prova utan kamera:
kopiera koden på **Min QR** och **Ange kod manuellt** på skannerskärmen. En
kontakt som läggs till på det sättet är inte verifierad i person.

## 3. Installera på båda telefonerna

1. Skicka APK:n till telefonen, till exempel med en kabel, eller kör
   `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
2. Öppna filen i appen **Filer** och tillåt installation från den när
   Android frågar.
3. Öppna SHA. Appen skapar din identitet första gången.

**En ny APK:** bygg den på samma dator. Den signeras då med samma
debugnyckel (`~/.android/debug.keystore`), och appen kan uppdateras utan att
identiteten och kontakterna försvinner. Byggs den på en annan dator måste
appen avinstalleras först, och då måste ni skanna varandra igen.

**Byte av app-id (0014, 2026-11-25):** appen heter nu
`io.github.w1sam1one.sha` för telefonen, i stället för `se.sha.sha`. En APK
som byggts efter bytet installeras som en ny app bredvid den gamla. Den
gamla, med sin identitet och sina kontakter, finns kvar tills du tar bort
den. I den nya måste ni träffas och skanna varandra igen.

## 4. Prova

1. **Servern:** gå till **Inställningar** på båda telefonerna, skriv
   serverns adress, till exempel `https://server.example.se`, och tryck
   **Spara adressen**. Välj sedan hur ofta appen ska hämta. Välj **Varje
   minut** för att prova (standard är var 5:e minut).
2. **Mötet:** kontrollkoden visas bara på telefonen som skannar.
   - Telefon B skannar A:s **Min QR**. Skriv upp de 20 siffrorna, skriv ett
     namn och tryck **Ja, lägg till**.
   - Telefon A skannar B:s **Min QR**. Kontrollera att A visar samma 20
     siffror som du skrev upp, skriv ett namn och tryck **Ja, lägg till**.
   - Texten i appen säger "Kontrollera att …s telefon visar exakt samma 20
     siffror", men båda telefonerna kan inte visa koden samtidigt. Det tas
     vidare i F6.
3. **Meddelanden:** öppna kontakten och skriv. Appen skickar direkt och
   hämtar vid en slumpad tid inom intervallet, bara när appen är öppen.
4. **Omstart:** stäng appen helt och öppna den igen. Identiteten och
   kontakterna ska finnas kvar, och ni ska kunna skriva vidare utan att
   skanna igen (fas 1, "Klart när" punkt 2). Meddelanden som har skickats
   eller visats finns kvar i 30 dagar, eller den tid du väljer under
   Inställningar (0010 (B)).

## Vad du kan se

- "Ingen server är inställd än …": skriv in serverns adress (steg 1).
- "Inte skickat än" på ett meddelande: servern har inte tagit emot det.
  Appen försöker igen vid nästa runda.
- "Servern är upptagen …" eller "Meddelandet väntar …": servern svarade 429
  eller 507 (0004 §10).
- "Ett meddelande från … kunde inte läsas": se 0004 §10. Händer det igen,
  träffas och skanna varandras QR-koder på nytt.
- "Ett äldre meddelande från … kom fram för sent" och "Några meddelanden
  från … saknas": se 0004 §10.

## Det här är inte klart

- Kryptot är inte granskat (fas 2, G6).
- Ingen säkerhetskopia. App-låset döljer bara skärmen (steg 1 i 0011).
- Appen hämtar inte i bakgrunden och skickar inga notiser (0002).
- Körningen på en riktig arm64-telefon är inte gjord (G3).

Skriv gärna vad som hände, så tar Claude det vidare i färdplanen.
