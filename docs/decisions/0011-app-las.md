# 0011 – App-lås med PIN eller biometri (F4)

Status: **Beslutat av ägaren 2026-11-18: (B).** Steg 1 i version 1, med 5
minuter i bakgrunden; byggt i F4 2026-11-19. Steg 2 först efter
telefontester och kryptoexpertens granskning (G6). Skrivet 2026-11-17.

Underlag för F4 i [`docs/ROADMAP.md`](../ROADMAP.md) (README, "Nästa
steg").

## Varför ett beslut behövs

Den som har telefonen upplåst i handen kan i dag öppna SHA och läsa det som
visas. Ett lås ändrar vad användaren får göra och vad appen lovar.

## Fakta

- Valvets Keystore-nyckel fungerar bara när telefonen är upplåst (Android
  9+, `KeystoreVault.kt`).
- Android har `BiometricPrompt` i själva plattformen
  (`android.hardware.biometrics`) från API 28. Telefonens PIN, mönster eller
  lösenord som alternativ finns från API 29 (`setDeviceCredentialAllowed`)
  och från API 30 med `setAllowedAuthenticators`. Det kräver inget nytt
  beroende, men behörigheten `USE_BIOMETRIC` i manifestet.
- **Appens minSdk är 24** (`android/app/build.gradle.kts`). På Android 7–8.1
  (API 24–27) finns inte `BiometricPrompt`. Där finns
  `KeyguardManager.createConfirmDeviceCredentialIntent` (telefonens PIN) och
  `FingerprintManager` (bara fingeravtryck, föråldrad). På Android 9 (API 28)
  finns `BiometricPrompt`, men utan telefonens PIN som alternativ.
  *Senare (granskningen av F4):* på Android 10 (API 29) kan `BiometricPrompt`
  avbrytas direkt eller inte visa PIN-skärmen på telefoner utan biometri
  (androidx.biometric går runt det). F4 använder därför `KeyguardManager` till
  och med Android 10, och `BiometricPrompt` först från Android 11.
- `androidx.biometric` vore ett nytt beroende.
- Inställningarna för en Keystore-nyckel bestäms när nyckeln skapas. Att
  kräva upplåsning för valvets nyckel betyder en ny nyckel och att varje post
  krypteras om, med ordningen vid krascher i 0004 §6.
- En nyckel som kräver upplåsning blir ogiltig när skärmlåset stängs av
  eller återställs. En nyckel som kräver fingeravtryck eller ansikte varje
  gång den används blir dessutom ogiltig när ett nytt fingeravtryck läggs
  till och när alla tas bort. Att byta en PIN mot en annan gör den inte
  ogiltig.
- En egen PIN för SHA som bara skyddar en skärm är svag; en PIN som skyddar
  en nyckel kräver att nyckeln tas fram ur PIN-koden, och det är ny
  nyckelhärledning, som `CLAUDE.md` inte tillåter ("Aldrig").

## Alternativ

- **(A) Inget lås.** Telefonens eget skärmlås är skyddet. Appen varnar redan
  om telefonen saknar skärmlås.
- **(B) Telefonens eget lås inuti appen** med plattformens `BiometricPrompt`:
  appen frågar efter fingeravtryck, ansikte eller telefonens PIN när den
  öppnas och efter en tid i bakgrunden.
  - På Android 7–9 (API 24–28): telefonens PIN via `KeyguardManager`,
    eftersom `BiometricPrompt` före API 29 inte kan erbjuda PIN. För att
    slippa `KeyguardManager` helt måste minSdk höjas till 29 (ett eget
    beslut för ägaren).
  - Valvets nyckel kan dessutom kräva att användaren har låst upp nyligen
    (`setUserAuthenticationParameters` från API 30,
    `setUserAuthenticationValidityDurationSeconds` före), så att låset inte
    bara är en skärm. Det kräver en ny nyckel (se Fakta), och appen måste
    fråga igen när tiden går ut medan den är öppen, eftersom varje sändning
    och mottagning skriver till valvet.
  - Inget nytt beroende och ingen ny kryptografi.
  - Men en nyckel som kräver upplåsning blir ogiltig när skärmlåset stängs
    av eller återställs. Då försvinner identiteten (som i dag med
    `keyInvalidated`). Det måste testas på riktiga telefoner (F6).
- **(C) En egen PIN för SHA.** Avråds: som skärm är den svag, och som skydd
  för en nyckel kräver den ny nyckelhärledning.

## Rekommendation: (B), först som en skärm, sedan bundet till nyckeln

Steg 1: låsskärmen med `BiometricPrompt` när appen öppnas och efter 5
minuter i bakgrunden. Steg 2, efter tester på riktiga telefoner: valvets
nyckel kräver upplåsning. Steg 2 påverkar säkerheten och **kräver granskning
av kryptoexpert**.

## Ägaren beslutar

- [x] **(B)**, beslutat 2026-11-18.
- [x] Steg 1 ingår i version 1: appen låses när den öppnas och efter **5
  minuter** i bakgrunden.
- [x] Steg 2 (valvets nyckel kräver upplåsning) kommer först efter
  telefontester och kryptoexpertens granskning (G6).

Steg 2 ändrar säkerheten. Enligt `CLAUDE.md` ("Vad Claude bestämmer
själv") lägger Claude därför fram ett eget beslutsunderlag innan steg 2
byggs. Det är Claudes regel, inte en del av ägarens beslut.
