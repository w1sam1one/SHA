# 0011 – App-lås med PIN eller biometri (F4)

Status: **Proposed – owner decides.** Skrivet 2026-11-17.

Underlag för F4 i [`docs/ROADMAP.md`](../ROADMAP.md) (README, "Nästa
steg").

## Varför ett beslut behövs

Den som har telefonen upplåst i handen kan i dag öppna SHA och läsa det som
visas. Ett lås ändrar vad användaren får göra och vad appen lovar.

## Fakta

- Valvets Keystore-nyckel fungerar bara när telefonen är upplåst (Android
  9+, `KeystoreVault.kt`).
- Android har `BiometricPrompt` i själva plattformen
  (`android.hardware.biometrics`, API 28+), med telefonens PIN, mönster eller
  lösenord som alternativ från API 30. Det kräver inget nytt beroende.
- `androidx.biometric` vore ett nytt beroende.
- En egen PIN i appen kräver att en nyckel tas fram ur PIN-koden: det är ny
  nyckelhärledning, som `CLAUDE.md` inte tillåter ("Aldrig").

## Alternativ

- **(A) Inget lås.** Telefonens eget skärmlås är skyddet. Appen varnar redan
  om telefonen saknar skärmlås.
- **(B) Telefonens eget lås inuti appen** med plattformens `BiometricPrompt`:
  appen frågar efter fingeravtryck, ansikte eller telefonens PIN när den
  öppnas och efter en tid i bakgrunden.
  - Valvets nyckel kan dessutom kräva att användaren har låst upp nyligen
    (`setUserAuthenticationParameters`), så att låset inte bara är en skärm.
  - Inget nytt beroende och ingen ny kryptografi.
  - Men en nyckel som kräver upplåsning kan göras ogiltig av Android när
    användaren byter skärmlås. Då försvinner identiteten (som i dag med
    `keyInvalidated`). Det måste testas på riktiga telefoner (F6).
- **(C) En egen PIN för SHA.** Avråds: ny nyckelhärledning.

## Rekommendation: (B), först som en skärm, sedan bundet till nyckeln

Steg 1: låsskärmen med `BiometricPrompt` när appen öppnas och efter 5
minuter i bakgrunden. Steg 2, efter tester på riktiga telefoner: valvets
nyckel kräver upplåsning. Steg 2 påverkar säkerheten och **kräver granskning
av kryptoexpert**.

## Ägaren beslutar

- [ ] (A), (B) eller (C).
- [ ] Med (B): tiden i bakgrunden innan appen låses (förslag: 5 minuter), och
  om steg 2 ska ingå i version 1.
