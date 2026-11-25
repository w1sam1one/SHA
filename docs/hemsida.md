# SHA – hemsidans text

Text till hemsidan (0014 (1a)), byggd på butikstexterna i
[`butikstexter.md`](butikstexter.md). Hemsidans adress är inte bestämd än
(G12). Texten publiceras först när appen delas ut, efter G6, G8 och allt
under "Före första utdelning" i [`ROADMAP.md`](ROADMAP.md).

---

## SHA

Krypterade meddelanden med personer du har träffat och skannat QR-kod med.
Det behövs inget telefonnummer och inget konto.

Vad appen gör, och vad servern ser, står i [butikstexten](butikstexter.md)
och i appens "Teknisk information".

## Ladda ner

- Den senaste versionen finns under releaser på GitHub:
  https://github.com/w1sam1one/SHA/releases
- Appen kräver Android 9 eller senare.
- Telefonen frågar om du vill tillåta installation från den app du laddar
  ner med, till exempel webbläsaren.
- Vill du få nya versioner automatiskt kan du följa releaserna med
  Obtainium (https://github.com/ImranR98/Obtainium).

## Kontrollera appen innan du installerar den

Varje APK är signerad med samma nyckel. Jämför signeringscertifikatets
fingeravtryck med det här, till exempel med `apksigner verify --print-certs
SHA-x.y.z.apk` på en dator. Stämmer det inte, installera inte appen.

Signeringscertifikatets SHA-256: inte skapat än (G9)

Fingeravtrycket står också i README och SECURITY.md i repot. APK-filens
egen SHA-256 står i releasen och här nedan för varje version.

Appen visar sitt eget fingeravtryck under "Teknisk information". En falsk
app kan visa vilket värde som helst, så det ersätter inte kontrollen före
installationen.

## Versioner

Ingen version är släppt än. För varje version står här versionen, datumet,
APK-filens SHA-256 och en länk till releasen, och ändringarna står i
[`CHANGELOG.md`](../CHANGELOG.md).

## Från 2027

Google kräver från 2027 att appar på vanliga Android-telefoner kommer från
en registrerad utvecklare. Annars måste du slå på ett "avancerat flöde" i
telefonen, med ett dygns väntan, eller installera med ADB. Hur SHA gör
bestäms före 2027 (0014).
