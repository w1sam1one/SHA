# Färdplan: intern prototyp

Den här filen styr vad Claude bygger härnäst, enligt [`CLAUDE.md`](../CLAUDE.md).
Paketen görs i ordning. En grind betyder att ägaren måste göra något innan
arbetet fortsätter.

## Klart när

Prototypen är klar när allt detta gäller:

1. Två appinstanser som har skannat varandras QR-koder kan skicka och ta
   emot krypterade meddelanden via relayn.
2. Identitet, kontakter och Olm-sessioner finns kvar efter att appen har
   startats om.
3. Testplanen i 0004 §11 är grön i CI, även på Android-emulatorn. Körning på
   en riktig telefon ingår inte här, se G3.
4. CI bygger en debug-APK som ägaren kan ladda ner och installera.
5. `docs/prototyp.md` beskriver hur ägaren sätter upp relayn och provar med
   två telefoner.

## Paket

- [x] **P0 – Styrning.** `CLAUDE.md` och den här filen.
- [ ] **P1 – 0004 godkänd.** Merga PR #8. Skriv in ägarens beslut i 0004:
  status, merge-reglerna i §12 enligt `CLAUDE.md`, och listan över
  OGRANSKAT-punkter under "Före första utdelning" nedan.
- [ ] **P2 – Olm i bygget.** `flutter_vodozemac` med exakt samma version som
  spiken i appens `pubspec.yaml`. Rust i CI. Ett Android-emulatorjobb för
  appen, som `spike-android.yml`. Ingen funktion i appen ändras.
- [ ] **P3 – Olm bakom `CryptoService`.** Konto, sessioner och pickles, med
  pickle-nyckeln i `KeyVault` (0003 R6, 0004 §6). Ordningen vid krascher
  enligt §6. `resetIdentity()` raderar allt. Spikens R1–R7 som tester mot
  appens klasser.
- [ ] **P4 – Mötet och kontakten.** QR-koden `shaid:2` och kontrollkoden
  (§1). Adresseringsnyckel och brevlåde-ID enligt §3 (A), OGRANSKAT.
  Sessionsregeln (§2). Engångsnycklar (§8). Kontakter sparas krypterade via
  valvet.
- [ ] **P5 – Paketformat version 3.** Format och utfyllnad (§4, §5). Relayns
  största paketstorlek i `relay/limits.go` och dess tester.
- [ ] **P6 – Transport.** En relay-klient utan nytt beroende (`dart:io`).
  Hämtning enligt §9 (b). Intervallet 1, 5, 15 eller 60 minuter i
  inställningarna. Felfall och texter (§10, 0002). `INTERNET` i
  release-manifestet, med motivering i README. Relayns adress går att ställa
  in.
- [ ] **P7 – Hela kedjan i CI.** Två klienter mot en riktig relay: svaren
  204, 507 och 429, dubbletter, krascher och mutationer (§11).
- [ ] **P8 – Leverans till ägaren.** Debug-APK som CI-artefakt och
  `docs/prototyp.md`.

## Grindar (bara ägaren)

- **G1 – Aktivera.** Merga PR:en med `CLAUDE.md`. Innan dess gör den
  schemalagda körningen ingenting.
- **G2 – Relayn på riktigt.** Efter P8: hyr en VPS i EU och sätt upp relayn
  enligt `relay/README.md`. Claude kan hjälpa till steg för steg.
- **G3 – Två riktiga telefoner.** Prova prototypen. Kör även spiken på en
  arm64-telefon (villkor 1 i 0003).

## Före första utdelning

Inget av detta behövs för prototypen, men allt behövs innan appen ges till
någon annan än ägaren (0003, 0004 §13):

- En kryptoexpert har granskat alla OGRANSKAT-punkter och listan sist i
  0004.
- Flutter/Dart-lagret och bygget är granskade.
- Planen för säkerhetsuppdateringar (0004 §12) är godkänd, och Dependabot
  alerts och security updates är påslagna.
- `LICENSE` är bytt till AGPL-3.0.
- Spiken och appen är körda på en riktig arm64-telefon.

## Efter prototypen (inte nu)

- Historik i appen (0004 §7).
- Internt test på Google Play.
- Tor eller liknande, flera relays.

## Logg

Nyast först. En rad per paket eller körning som ändrar något.

- 2026-11-14 – P0: regler och färdplan skrivna. Väntar på G1.
