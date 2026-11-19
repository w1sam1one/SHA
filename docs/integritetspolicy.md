# Integritetspolicy – utkast (F10)

**Utkast.** Granskas av ägaren innan det publiceras (G10). Det beskriver bara
det koden gör i dag; källorna står i [`docs/data-safety.md`](data-safety.md).
Ord som "anonym" och "inga loggar" används inte (0002, "Formuleringar i
appen").

Innan det publiceras:

- Vad Googles kamerabibliotek (CameraX, och media3 som följer med det) gör
  med bilden och nätet är inte kontrollerat. Texten om kameran nedan gäller
  appens egen kod.
- Delarna som en integritetspolicy brukar ha enligt GDPR saknas: vem som
  är personuppgiftsansvarig, den rättsliga grunden, hur länge IP-adressen
  finns, användarens rättigheter och rätten att klaga hos IMY. De tas fram i
  F9 och G10.
- Meningarna om servern gäller SHA:s eget serverprogram (`relay/`). Driver
  ägaren en server för appen ska dess adress stå här.

## Svenska

**Vem:** SHA utvecklas av Wisam Husein. Kontakt: ______ (fylls i av
ägaren).

**Inga konton.** SHA har inga konton, inget telefonnummer och ingen e-post.
Din identitet skapas på din telefon.

**Dina meddelanden** krypteras på din telefon och kan bara läsas av den du
skriver till. De skickas via en server som du själv anger under
Inställningar. Servern kan inte läsa dem. SHA:s serverprogram tar bara emot
och lämnar ut krypterade paket, och raderar ett paket efter högst 48 timmar.
En server med ett annat program kan spara mer.

**Vad servern ser:** ett brevlåde-ID som byts varje dygn, paketets storlek,
när det kom, när du hämtar och din IP-adress. Brevlådor som hämtas från
samma IP-adress vid ungefär samma tid kan kopplas ihop. SHA:s serverprogram
sparar inte din IP-adress på disk eller i loggar; för spamgränsen finns den
i serverns minne så länge det kommer anrop från den, även från andra på
samma nät, och tas bort senast 90 sekunder efter det senaste. Den som
driver servern och leverantören av den kan ändå se och spara trafiken.

**På din telefon** sparas din identitet, dina kontakter (namnet du skriver,
när ni träffades och kontaktens nycklar), inställningarna, meddelanden som
inte har skickats eller visats än, och uppgifter som appen behöver för
krypteringen. Allt är krypterat med en nyckel som telefonen skyddar, och
inget säkerhetskopieras. Hur väl nyckeln skyddas beror på telefonen; appen
visar det under Teknisk information. Meddelanden som har skickats eller
visats sparas så länge du väljer under Inställningar (30 dagar om du inte
väljer något annat) och tas sedan bort ur appen. Väljer du "Spara inte"
sparas de inte.

**Kameran** används bara för att skanna QR-koder, och bara medan skannern
är öppen. Appen läser bilden och sparar den inte. Inget ljud spelas in.

**Ingen analys, inga annonser och inga kraschrapporter** i appens egen kod.
QR-koden läses av appen själv och skickas inte vidare.

**Radera allt:** avinstallera appen, så raderas allt den har sparat på
telefonen. Hos SHA:s serverprogram raderas paketen efter högst 48 timmar.

## English

**Who:** SHA is developed by Wisam Husein. Contact: ______ (to be filled in
by the owner).

**No accounts.** SHA has no accounts, no phone number and no e-mail. Your
identity is created on your phone.

**Your messages** are encrypted on your phone and can only be read by the
person you write to. They go through a server that you enter yourself under
Settings. The server cannot read them. SHA's server program only receives
and hands out encrypted packets, and deletes a packet after at most 48
hours. A server running another program may keep more.

**What the server sees:** a mailbox ID that changes every day, the packet's
size, when it arrived, when you fetch, and your IP address. Mailboxes
fetched from the same IP address at about the same time can be linked.
SHA's server program does not store your IP address on disk or in logs; for
the spam limit it is kept in the server's memory while requests come from
it, also from others on the same network, and removed at most 90 seconds
after the last one. Whoever runs the server, and its provider, can still
see and save the traffic.

**On your phone** the app keeps your identity, your contacts (the name you
type, when you met and the contact's keys), the settings, messages not yet
sent or shown, and what the app needs for the encryption. All of it is
encrypted with a key the phone protects, and none of it is backed up. How
well the key is protected depends on the phone; the app shows it under
Technical information. Messages that have been sent or shown are kept for
as long as you choose under Settings (30 days unless you choose otherwise)
and are then removed from the app. If you choose "Spara inte" (do not
keep), they are not saved.

**The camera** is used only to scan QR codes, and only while the scanner is
open. The app reads the picture and does not save it. No sound is recorded.

**No analytics, no ads and no crash reports** in the app's own code. The QR
code is read by the app itself and is not sent anywhere.

**Delete everything:** uninstall the app, and everything it has stored on
the phone is deleted. On SHA's server program, packets are deleted after at
most 48 hours.
