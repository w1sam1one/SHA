# Frågor till kryptoexperten

Numren följer listan "Kräver granskning av kryptoexpert" sist i 0004.

1. **Brevlåde-ID** (§3 (A)): räcker en statisk X25519-nyckel bredvid Olm,
   eller ska kontrollkoden omfatta adresseringsnycklarna?
2. **Kontrollkoden** (§1): räcker 20 siffror ur SHA-256 av de två
   Olm-identitetsnycklarna?
3. **Utfyllnad utanför Olm** (§4 C): byggs inte. Behövs den med ett yttre
   lager?
4. **Storleken** (§4): är det godtagbart att typ 0 och kedjeindex syns?
5. **Huvudet** (§5): behövs brevlåde-ID:t inuti det krypterade, med en
   kontroll efter avkrypteringen?
6. **Olm-version** (§5): version 1 (8 byte MAC) eller version 2 (32 byte)?
7. **Historiken** (§7, F3): byggd med (B) i 0010, egna valvposter med
   slumpade namn och valvets nyckel, inte en nyckel per konversation.
   Räcker det, och vad får appen lova om raderad historik?
8. **Pickles och återställning** (§6):
   - Hindrar ordningen i `sha_olm_service.dart` att ett gammalt läge läses
     in, och att en meddelandenyckel används två gånger?
   - Är det rätt att prova typ 0 mot sparade sessioner före
     `createInboundSession`?
   - Är pickle-nyckeln (32 byte från den blandade slumpkällan, i en egen
     valvpost) rätt hanterad?
9. **Ett yttre lager** med en hemlighet från QR-koden (0003): behövs det?

## Från de oberoende granskningarna i fas 1

10. **`seen` är gemensam för alla kontakter.** Ett paket som först hanteras
    under fel kontakt blir senare en dubblett. Ska hashen nycklas per
    kontakt?
11. **Hashar rensas efter väggklockan** (72 timmar). Ett hopp i klockan kan
    ge fel felrad. Räcker det, eller behövs en monoton klocka?
12. **Raderna "kunde inte läsas", "saknas" och "kom fram för sent"** kan
    visas av vem som helst som kan brevlådans ID (0004 §10, 0008 (i)). Är
    råden i dem, till exempel "träffas och skanna igen", rätt då?
13. **En översvämmad brevlåda** (1 000 paket) ger en valvskrivning per nytt
    paket. Behövs en gräns?
14. **Raderingen av gamla sessioner** (F2, 0009 (iv) med 24 h marginal):
    håller argumentet för att inget meddelande går förlorat, och är
    luckorna godtagbara (se `ogranskat.md`)?
