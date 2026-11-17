# Integritetspolicy – utkast (F10)

**Utkast.** Granskas av ägaren innan det publiceras (G10). Det beskriver bara
det koden gör i dag; källorna står i [`docs/data-safety.md`](data-safety.md).
Ord som "anonym" och "inga loggar" används inte (0002, "Formuleringar i
appen").

## Svenska

**Vem:** SHA utvecklas av Wisam Husein. Kontakt: ______ (fylls i av
ägaren).

**Inga konton.** SHA har inga konton, inget telefonnummer och ingen e-post.
Din identitet skapas på din telefon.

**Dina meddelanden** krypteras på din telefon och kan bara läsas av den du
skriver till. De skickas via en server som bara lämnar och hämtar krypterade
paket. Servern kan inte läsa dem. Ett paket raderas från servern efter
högst 48 timmar.

**Vad servern ser:** ett brevlåde-ID som byts varje dygn, paketets storlek,
när det kom och din IP-adress. Servern sparar inte din IP-adress. Den som
driver servern och leverantören av den kan ändå se trafiken.

**På din telefon** sparas din identitet, dina kontakter (namnet du skriver
och kontaktens nycklar), inställningarna och meddelanden som inte har
skickats eller visats än. Allt är krypterat med en nyckel i telefonens
säkra lagring, och inget säkerhetskopieras. Meddelanden som har visats
sparas inte.

**Kameran** används bara för att skanna QR-koder. Inga bilder sparas.

**Ingen analys, inga annonser och inga kraschrapporter** i appens egen kod.
Skannern använder Googles ML Kit; vad den skickar till Google beskrivs av
Google.

**Radera allt:** avinstallera appen, så raderas allt den har sparat på
telefonen. Det som finns på servern raderas efter högst 48 timmar.

## English

**Who:** SHA is developed by Wisam Husein. Contact: ______ (to be filled in
by the owner).

**No accounts.** SHA has no accounts, no phone number and no e-mail. Your
identity is created on your phone.

**Your messages** are encrypted on your phone and can only be read by the
person you write to. They go through a server that only stores and hands
out encrypted packets. The server cannot read them. A packet is deleted from
the server after at most 48 hours.

**What the server sees:** a mailbox ID that changes every day, the packet's
size, when it arrived and your IP address. The server does not store your
IP address. Whoever runs the server, and its provider, can still see the
traffic.

**On your phone** the app keeps your identity, your contacts (the name you
type and the contact's keys), the settings, and messages not yet sent or
shown. All of it is encrypted with a key in the phone's secure storage, and
none of it is backed up. Messages that have been shown are not kept.

**The camera** is used only to scan QR codes. No pictures are kept.

**No analytics, no ads and no crash reports** in the app's own code. The
scanner uses Google's ML Kit; what it sends to Google is described by
Google.

**Delete everything:** uninstall the app, and everything it has stored on
the phone is deleted. What is on the server is deleted after at most 48
hours.
