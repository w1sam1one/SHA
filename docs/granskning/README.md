# Granskningspaket (F1)

Underlag för de två granskningarna före första utdelningen
([`docs/ROADMAP.md`](../ROADMAP.md), "Före första utdelning", G6):

1. **Kryptot**, av en kryptoexpert: alla `OGRANSKAT`-punkter och listan
   sist i [0004](../decisions/0004-olm-integration-design.md).
2. **Flutter/Dart-lagret och bygget** (0003, "Beslut", villkor 2).

Paketet beskriver koden som den är när fas 1 är klar (P3–P7). Radnummer
gäller den commit som PR:en för F1 mergas på; `git blame` visar om en rad
har flyttat sedan dess.

| Fil | Innehåll |
| --- | --- |
| [hotmodell.md](hotmodell.md) | Vad som skyddas, mot vem, och vad som inte skyddas |
| [ogranskat.md](ogranskat.md) | Varje `OGRANSKAT`-punkt med fil, rad, valet och vad som ska granskas |
| [testat.md](testat.md) | Vad som är testat, hur och var, och vad som inte är det |
| [fragor.md](fragor.md) | Öppna frågor till kryptoexperten |
| [flutter-och-bygget.md](flutter-och-bygget.md) | Underlaget för granskningen av Flutter/Dart-lagret och bygget |

**Så används paketet:** granskaren läser hotmodellen, sedan
`ogranskat.md` punkt för punkt mot koden, och svarar på `fragor.md`.
Fynden blir F8. Inget i paketet är en del av appen.

**Ärlighet:** "testat" betyder att ett test körs i CI eller kördes lokalt och
syns i en PR. "Läst" betyder att någon läste koden. "Ej verifierat" står där
inget av det gäller.
