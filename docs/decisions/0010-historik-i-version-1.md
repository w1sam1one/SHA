# 0010 – Historik i version 1 (F3)

Status: **Proposed – owner decides.** Skrivet 2026-11-17.

Underlag för F3 i [`docs/ROADMAP.md`](../ROADMAP.md) (0004 §7, 0005 (C) och
(ii)). I prototypen sparas ett meddelande bara tills det har skickats eller
visats (0005 (i)); efter en omstart är chatten tom.

## Varför ett beslut behövs

- Historik på disk betyder att den som får telefonen upplåst, eller ett fel
  i valvet, når fler meddelanden. Ingen historik betyder att chatten är tom
  efter varje omstart.
- Valet ändrar vad användaren får se och vad appen lovar.

## Fakta

- Valvet krypterar varje post med AES-256-GCM och en Keystore-nyckel, med
  postens namn som associerad data (`KeystoreVault.kt`). Ingen ny
  kryptografi behövs för att spara fler poster.
- Hela Olm-tillståndet är en post på cirka 850 KiB i mätningen; en skrivning
  tog högst 49 ms (0005, gränsen 300 ms). Historik i samma post skulle växa
  utan gräns.
- Det finns inget `sqlite3` eller `path_provider` i lockfilen (0005).

## Alternativ

- **(A) Ingen historik**, som i prototypen.
  - Minst att skydda och minst kod.
  - Men chatten är tom efter en omstart.
- **(B) Historik i egna valvposter**, en per kontakt och månad
  (`history.<kontakt>.<år-månad>`), med en gräns för hur länge den sparas.
  - Ingen ny kryptografi och inget nytt beroende: valvet finns redan.
  - Varje post är liten, så skrivningen håller sig under 300 ms.
  - Raderas av `resetIdentity()` (valvet tas bort helt) och när tiden har
    gått ut.
  - Men det är ny kod för att läsa och skriva posterna, och historiken finns
    på disk.
- **(C) SQLite** (`sqlite3` eller `sqflite`), med kryptering per rad eller
  SQLCipher (0005 (C)).
  - Bra för stora mängder och sökning.
  - Men det är ett nytt beroende och ny användning av kryptering. **Kräver
    granskning av kryptoexpert.**

## Rekommendation: (B), med en gräns som användaren väljer

Förslag på gräns: 30 dagar som standard, och valen "Spara inte", "7 dagar",
"30 dagar" och "1 år" under Inställningar. Texten i appen ska säga att
historiken finns krypterad på telefonen och att den raderas efter den
valda tiden.

## Ägaren beslutar

- [ ] (A), (B) eller (C).
- [ ] Med (B): standard och val för hur länge (förslag ovan).
