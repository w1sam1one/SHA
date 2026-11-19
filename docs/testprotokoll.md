# Testprotokoll: två riktiga telefoner (F6)

För grinden G3 och fas 2, "Klart när" punkt 2. Ägaren fyller i kolumnen
**Resultat** (OK, Fel, eller vad som hände). Skriv telefonmodell och
Android-version överst. Fynden blir F8.

- Telefon A: ______________________ Android: ____
- Telefon B: ______________________ Android: ____
- Server: `https://` ______________________ (G2, `docs/prototyp.md`)
- APK: commit ______ (debug, 0007)
- Datum: __________

Förberedelser: `docs/prototyp.md`, steg 1–3. **Steg 7 raderar appens valv
på telefonen; gör det sist.**

## 1. Första start

| # | Gör | Förväntat | Resultat |
| --- | --- | --- | --- |
| 1.1 | Öppna SHA på A | "Din identitet är skapad" visas, med en identitet | |
| 1.2 | Tryck **Fortsätt** | Kontakter visas, utan kontakter | |
| 1.3 | Titta överst | Ingen varning om skärmlås eller säkerhetshårdvara (finns det en: skriv vilken) | |
| 1.4 | Ta en skärmdump | Det går inte (`FLAG_SECURE`) | |
| 1.5 | Gör samma sak på B | Som ovan | |

## 2. Servern

| # | Gör | Förväntat | Resultat |
| --- | --- | --- | --- |
| 2.1 | **Inställningar** innan adressen är satt | Fältet "Serverns adress" är tomt. (Texten "Ingen server är inställd än …" i en chatt provas på B i 3.8.) | |
| 2.2 | **Inställningar** › skriv `http://` + din domän › **Spara adressen** | Ett fel: adressen måste börja med `https://` | |
| 2.3 | Skriv din domän utan `https://` › **Spara adressen** | "Adressen är sparad." och `https://` läggs till | |
| 2.4 | Välj **Varje minut** | Valet sitter kvar när fliken öppnas igen | |
| 2.5 | Vänta med B. B sparar sin adress först i 3.9 | – | |

## 3. Mötet

| # | Gör | Förväntat | Resultat |
| --- | --- | --- | --- |
| 3.1 | B: **Skanna**. A: **Min QR**. Skanna A:s kod | B visar en kontrollkod på 20 siffror. Skriv upp den | |
| 3.2 | B: skriv "A" som namn › **Ja, lägg till** | A finns bland B:s kontakter | |
| 3.3 | A: **Skanna**. B: **Min QR**. Skanna B:s kod | A visar **samma** 20 siffror som i 3.1 | |
| 3.4 | A: skriv "B" › **Ja, lägg till** | B finns bland A:s kontakter | |
| 3.5 | Öppna **Min QR** två gånger och jämför koderna | Koden är ny varje gång (en ny engångsnyckel) | |
| 3.6 | Debug-bygget: **Min QR** › kopiera koden, sedan **Skanna** › **Ange kod manuellt** på samma telefon (en telefon kan inte skanna sin egen skärm) | "Det där är din egen kod." | |
| 3.7 | Tycker du att texten "Kontrollera att …s telefon visar exakt samma 20 siffror" går att följa? | Båda telefonerna kan inte visa koden samtidigt (granskningen av P8). Skriv vad du tycker | |
| 3.8 | B (som inte har någon adress än): öppna kontakten A | "Ingen server är inställd än …" visas | |
| 3.9 | B: gör 2.3–2.4 och öppna kontakten A igen | Texten är borta | |

Använd inte "kopiera koden" och "Ange kod manuellt" för kontakterna i det
riktiga testet: en kontakt som läggs till så är inte verifierad i person.

## 4. Meddelanden

| # | Gör | Förväntat | Resultat |
| --- | --- | --- | --- |
| 4.1 | A skriver "hej" till B | "Inte skickat än" försvinner inom några sekunder | |
| 4.2 | Vänta högst 2 minuter med B:s app öppen | "hej" visas hos B | |
| 4.3 | B svarar | Svaret visas hos A inom 2 minuter | |
| 4.4 | Skicka å, ä, ö och en emoji | Kommer fram oförändrat | |
| 4.5 | Skicka ett långt meddelande (flera stycken) | Kommer fram | |
| 4.6 | Lås B:s telefon i 5 minuter medan A skriver. Lås upp och öppna SHA | Meddelandet visas först när appen är öppen igen | |
| 4.7 | Slå av nätet på A och skriv | "Inte skickat än" står kvar. Slå på nätet: det skickas vid nästa runda | |

## 5. Omstart

| # | Gör | Förväntat | Resultat |
| --- | --- | --- | --- |
| 5.1 | Stäng SHA helt på A (svep bort den) och öppna igen | Identiteten och kontakten finns kvar, och chatten visar de meddelanden som har skickats och visats (historiken, 30 dagar som standard, 0010 (B)) | |
| 5.2 | Skriv till B | Det fungerar utan ny skanning | |
| 5.3 | Låt B skriva medan A:s app är stängd. Öppna A | Meddelandet visas | |
| 5.4 | Starta om telefonen A och öppna SHA | Som 5.1–5.2 | |
| 5.5 | Välj "Spara inte" under Inställningar på A, stäng SHA helt och öppna igen | Chatten är tom, utom meddelanden som inte har visats än | |

## 6. Tillgänglighet (TalkBack)

| # | Gör | Förväntat | Resultat |
| --- | --- | --- | --- |
| 6.1 | Slå på TalkBack. Gå igenom Kontakter, Min QR, Skanna, en chatt och Inställningar | Allt läses upp på svenska, och knapparna har namn | |
| 6.2 | I en chatt | "Verifierad i person" läses upp i rubriken | |
| 6.3 | Skicka ett meddelande med TalkBack | Det går | |

## 7. Farten i valvet (StrongBox)

Det här **raderar appens valv** på telefonen: identitet, kontakter och
sessioner. Gör det sist, och skanna igen efteråt om du vill fortsätta.

0. Skriv först upp vad appen visade om nyckelns skydd vid steg 1.1
   (StrongBox, TEE eller bara mjukvara): ______________________
1. Koppla telefonen till datorn med USB-felsökning på.
2. Kör från repot (kräver Flutter, Android SDK, NDK och Rust):
   ```sh
   flutter test integration_test/vault_test.dart integration_test/olm_service_test.dart -d <telefonens id>
   ```
3. Skriv in raderna som börjar med `VAULT`, `MEASURE-0005` och
   `MEASURE-P4`:

| Mätning | Värde | Gräns |
| --- | --- | --- |
| VAULT 512 KiB, skriv / läs | | – |
| VAULT 2048 KiB, skriv / läs | | – |
| MEASURE-0005, största skrivning | | 300 ms (0005) |
| MEASURE-P4, största skrivning | | 300 ms |
| Alla tester gröna? | | Ja |

Efteråt är appen borttagen från telefonen: `flutter test` avinstallerar
den när testerna är klara. Installera APK:n igen (`docs/prototyp.md`, steg
2 och 3), med `adb install -r build/app/outputs/flutter-apk/app-debug.apk`,
och stäng av USB-felsökningen.

Det här är också körningen på en riktig arm64-telefon i villkor 1 i 0003
(R8), för Olm-testerna i appen. Spiken körs enligt
`spike/vodozemac/README.md`.

## 8. Det som inte ska hända

Skriv om något av detta händer:
- appen kraschar eller fryser;
- ett meddelande visas två gånger, eller försvinner innan det har visats
  (att visade meddelanden är borta efter en omstart är förväntat);
- en text innehåller konstiga tecken, långa koder eller engelska feltexter;
- appen hämtar när den inte är öppen (syns som datatrafik i Android).

Ägarens sammanfattning: ________________________________________________
