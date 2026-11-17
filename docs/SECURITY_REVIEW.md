# Säkerhetsgranskning – SHA MVP

Prioritet: säkerhet och anonymitet. Förutsättning: krypterade paket skickas
till en pool av ”dumma” relä-servrar som vidarebefordrar dem till mottagaren.
Reläerna betraktas som **opålitliga och avlyssnande**: de kan spara, kopiera,
fördröja, ändra, spela upp igen och skicka tillbaka paket, och de ser
IP-adresser och tider.

## Fynd i första versionen och vad som gjorts

| # | Fynd | Allvar | Åtgärd |
|---|------|--------|--------|
| 1 | Privat nyckel låg i `flutter_secure_storage` (RSA-omslagen nyckel, data i SharedPreferences, `resetOnError`-logik i ett tredjepartsbibliotek). Ingen StrongBox, inget krav på upplåst telefon. | Hög | Egen Keystore-bindning i Kotlin: AES-256-GCM-nyckel skapad i Keystore, StrongBox först, `setUnlockedDeviceRequired`, filer i `noBackupFilesDir`, namn som AAD. Beroendet borttaget. |
| 2 | Identitetens privata nyckel låg kvar i minnet hela app-livet. | Medel | Packas upp bara vid nyckelavtal och nollställs direkt. Vid start läses bara den publika nyckeln. |
| 3 | Samma nyckel i båda riktningarna. Utan avsändarinfo i klartext (vilket reläer kräver för anonymitet) skulle ett reflekterat paket accepteras. | Hög | Separata nycklar per riktning (L2H/H2L). Test: reflekterat paket avvisas. |
| 4 | Metadata (avsändarens och mottagarens identitetshash, id, tid) var tänkt som AAD i klartext. Reläet skulle då se vem som pratar med vem. | Hög (anonymitet) | Paketet innehåller bara ett roterande brevlåde-id. Allt annat ligger i chiffertexten. |
| 5 | Meddelandelängd syntes exakt i chiffertexten. | Medel (anonymitet) | Utfyllnad till fem fasta storlekar. |
| 6 | Sexsiffrig kontrollkod (~20 bitar) gick att ”prova fram” med en utbytt QR-kod. | Medel | 20 siffror (~66 bitar). |
| 7 | En enda slumpkälla för identitetsnyckeln. | Låg | HKDF-blandning av Dart- och Android-CSPRNG med rimlighetskontroller. |
| 8 | Ogiltiga (low-order) nycklar upptäcktes först vid första meddelandet. | Låg | Kontrolleras direkt vid skanning, innan användaren bekräftar. |
| 9 | `PublicIdentity` gick att skapa med en hash som inte matchade nyckeln. | Låg | Hashen räknas alltid ut i konstruktorn. |
| 10 | Kopiering av identitet/QR-kod till urklipp (som andra appar och tangentbord kan läsa) och manuell inmatning av kod (som kringgår mötet IRL). | Medel (anonymitet) | Bara i debug-byggen. |
| 11 | Tangentbordet kunde lära sig av det som skrevs i chatt, namn och sök. | Medel (anonymitet) | `enableIMEPersonalizedLearning: false` (inkognitoläge för tangentbord). |
| 12 | Felmeddelanden från plattformen kunde innehålla detaljer. | Låg | Native-koden skickar bara fasta felkoder; Dart mappar dem till fasta texter. |
| 13 | Ingen policy för nätverkstrafik inför reläerna. | Låg | `network_security_config.xml`: ingen klartext, bara systemets CA:er. |
| 14 | Repriser av samma paket. | Låg | Meddelande-id i chiffertexten; dubbletter lagras inte. |

Behållet från första versionen: `FLAG_SECURE`, ingen backup, inga loggar,
inbäddade typsnitt. Release-bygget hade inga nätverksbehörigheter fram till
P6, som lägger till `INTERNET` för servern (se README, "Android-härdning").

## Vad en angripare kan och inte kan

| Angripare | Kan | Kan inte |
|-----------|-----|----------|
| Relä-server | Se brevlåde-id, paketstorlek (en av fem), tid, avsändarens/mottagarens IP | Läsa innehåll, se identiteter, ändra eller flytta paket utan att det upptäcks, reflektera paket |
| Annan app på telefonen | – | Läsa nyckelfilerna, använda Keystore-nyckeln, ta skärmdumpar, läsa urklipp med SHA-data (release) |
| Tjuv med låst telefon | – | Använda Keystore-nyckeln (kräver upplåst telefon) |
| Tjuv med upplåst telefon | Öppna appen | Exportera nyckeln från Keystore |
| Root/skadlig kod i OS | Läsa appens minne medan den körs | Exportera nyckeln från StrongBox/TEE |

## Rekommenderade nästa steg (i prioritetsordning)

1. **Forward secrecy**: använd granskad Double Ratchet (libsignal) i stället
   för statiska nycklar. Viktigast eftersom reläer kan spara trafik.
2. **Transport utan IP-läckor**: Tor (t.ex. via Arti) eller mixnät mot reläerna,
   fast pollningsintervall, täcktrafik (dummy-paket) och samma paketstorlek
   oavsett aktivitet.
3. **Ingen FCM/Google-push**: det läcker metadata. Använd pollning eller
   UnifiedPush.
4. **App-lås**: kräv biometri/PIN för Keystore-nyckeln
   (`setUserAuthenticationParameters`) och lås appen efter en stund i
   bakgrunden.
5. **Krypterad lokal lagring** när kontakter och meddelanden ska sparas
   permanent, med en separat Keystore-nyckel.
6. **Certifikat-pinning** mot reläerna i `network_security_config.xml`.
7. **Release-bygge** med `--obfuscate --split-debug-info` och eget
   signeringscertifikat (inte debug-nyckeln).
8. **Extern granskning** av `lib/crypto/` och Kotlin-koden innan lansering.
