# Ändringslogg

Nyast först. Rubriken för varje version är raden `version:` i
`pubspec.yaml`: versionsnamnet, ett plustecken och versionCode, och sedan
"inte släppt" eller datumet då versionen släpptes. versionCode måste öka
för varje version som delas ut, annars installerar Android den inte som en
uppdatering. `test/release/changelog_test.dart` kontrollerar det, och att
texten följer 0002, "Formuleringar i appen". Texten under en version kan
användas i releasen.

## 1.0.0+1 – inte släppt

Den första versionen. Den delas inte ut till någon annan än ägaren förrän
en kryptoexpert har granskat kryptot (G6) och koden har licensen AGPL-3.0
(G8). Den delas ut som APK på hemsidan och i GitHub Releases (0014).

### Det här finns med

- Ni blir kontakter genom att skanna varandras QR-koder när ni träffas.
  Det behövs inget telefonnummer och inget konto.
- Meddelandena krypteras på telefonen och går via en server vars adress du
  anger. Servern kan inte läsa dem.
- Appen hämtar nya meddelanden bara när den är öppen: varje minut, var 5:e
  eller 15:e minut, eller varje timme.
- Historiken sparas i 30 dagar om du inte väljer något annat: Spara inte,
  7 dagar, 30 dagar eller 1 år.
- Har telefonen ett skärmlås, låses appen med det när den öppnas och när
  den har varit i bakgrunden i 5 minuter.
- QR-koden läses på telefonen, utan Googles ML Kit.
- Skärmdumpar är avstängda i appen.
- "Teknisk information" beskriver vad servern ser, och en licenssida visar
  alla bibliotek i appen och deras licenser.

### Det här finns inte med

- Notiser och hämtning i bakgrunden.
- Säkerhetskopia. Tappar du telefonen måste ni träffas och skanna
  varandras QR-koder igen.
- Grupper, iOS och flera servrar.
