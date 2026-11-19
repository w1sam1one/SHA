# 0010 – Historik i version 1 (F3)

Status: **Beslutat av ägaren 2026-11-18: (B)**, historik i egna valvposter
med valvets nyckel, 30 dagar som standard. Byggt i F3 2026-11-19. Skrivet
2026-11-17.

Underlag för F3 i [`docs/ROADMAP.md`](../ROADMAP.md) (0004 §7, 0005 (C) och
(ii)). I prototypen sparas ett meddelande bara tills det har skickats eller
visats (0005 (i)); efter en omstart är chatten tom.

## Varför ett beslut behövs

- Historik på disk betyder att den som får telefonen upplåst, eller ett fel
  i valvet, når fler meddelanden. Ingen historik betyder att chatten är tom
  efter varje omstart.
- Valet ändrar vad användaren får se och vad appen lovar.

## Fakta

- Valvet krypterar varje post med AES-256-GCM och **en och samma**
  Keystore-nyckel, med postens namn som associerad data (`KeystoreVault.kt`).
- **0004 §7 (a)** rekommenderade en nyckel per konversation, just för att det
  som blir kvar på lagringen efter en radering inte ska gå att läsa. Med en
  gemensam nyckel kan en raderad post som finns kvar på flashminnet läsas så
  länge valvets nyckel finns, alltså fram till `resetIdentity()`. Punkt 7 i
  listan sist i 0004 (krypteringen av historiken) gäller fortfarande.
- Valvets postnamn får vara högst 64 tecken (`KeystoreVault.kt`), och de
  sparas i klartext som filnamn (`<namn>.bin`). Ett namn med kontaktens id
  (64 tecken) och månad skulle vara för långt, och avslöja aktivitet per
  kontakt och månad.
- Hela Olm-tillståndet är en post på cirka 850 KiB i mätningen; en skrivning
  tog högst 49 ms (0005, gränsen 300 ms). Historik i samma post skulle växa
  utan gräns.
- Att spara tillståndet och en historikpost är två skrivningar, inte en.
- Det finns inget `sqlite3` eller `path_provider` i lockfilen (0005).

## Alternativ

- **(A) Ingen historik**, som i prototypen.
  - Minst att skydda och minst kod.
  - Men chatten är tom efter en omstart.
- **(B) Historik i egna valvposter** med en gräns för hur länge den sparas.
  - Postnamnen är slumpade (till exempel `h.<16 slumpade hex>`) och listan
    över dem ligger i Olm-tillståndet, så att filnamnen inte visar vem.
    Filernas tider och storlekar visar ändå ungefär när något skrevs.
  - Inget nytt beroende och ingen ny primitiv: valvet finns redan.
  - Raderas av `resetIdentity()` och när tiden har gått ut.
  - **Men** alla poster delar valvets nyckel: en raderad post som finns kvar
    på lagringen kan läsas tills `resetIdentity()`. Texten i appen får därför
    inte lova mer än att historiken *tas bort ur appen* efter tiden.
  - Ordningen mellan tillståndet och historikposten måste bestämmas så att
    en krasch inte visar ett meddelande två gånger eller tappar det.
  - Hur snabb en skrivning är: **ej mätt**.
- **(B2) Som (B), men en egen Keystore-nyckel per post.** När tiden har gått
  ut raderas nyckeln, och då går posten inte att läsa även om filen finns
  kvar. Det är det 0004 §7 (a) ville uppnå.
  - Det bygger på att Keystore verkligen tar bort nyckeln. Nyckelns
    krypterade data kan finnas kvar på lagringen en tid, och appen ber inte
    om skydd mot att den återställs (rollback resistance). `reset()` bygger
    redan på samma antagande.
  - `reset()` och `resetIdentity()` måste då radera varje posts nyckel, inte
    bara valvets.
  - Inget nytt beroende, men en ändring i valvet (en nyckel per post).
    **Kräver granskning av kryptoexpert.**
- **(C) SQLite** (`sqlite3` eller `sqflite`), med kryptering per rad eller
  SQLCipher (0005 (C)).
  - Bra för stora mängder och sökning.
  - Men det är ett nytt beroende och ny användning av kryptering. **Kräver
    granskning av kryptoexpert.**

## Rekommendation: (B2), med en gräns som användaren väljer

(B2) håller det 0004 §7 (a) var till för. Den kräver granskning av
kryptoexpert, som punkt 7 i 0004 redan gör. (B) är enklare men lovar mindre.

Förslag på gräns: 30 dagar som standard, och valen "Spara inte", "7 dagar",
"30 dagar" och "1 år" under Inställningar. Texten i appen säger att
historiken finns krypterad på telefonen och tas bort efter den valda tiden.
Med (B2) kan den också säga att den då inte går att läsa, men först när
kryptoexperten har granskat antagandet om Keystore ovan.

## Ägaren beslutar

- [x] **(B)**, beslutat 2026-11-18, inte den rekommenderade (B2). Med (B)
  delar alla poster valvets nyckel, så texten i appen får bara lova att
  historiken *tas bort ur appen* efter tiden, inte att den blir oläslig (se
  (B) ovan). Den exakta texten läggs fram för ägaren.
- [x] Standard **30 dagar**. Valen är **Spara inte**, **7 dagar**, **30
  dagar** och **1 år**, under Inställningar. Beslutat 2026-11-18.
