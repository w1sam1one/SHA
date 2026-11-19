# Underlag till Data safety (F10)

Vad SHA:s egen kod gör med data, med fil som källa. Det ersätter punkt 6 i
[`docs/release.md`](release.md), som beskrev läget före P6.

**Du måste själv kontrollera varje svar mot Googles definitioner innan du
skickar in** (F9). Listan säger vad koden gör, inte hur Googles formulär ska
tolkas, och den täcker inte vad Googles bibliotek (CameraX och media3) gör.
Allt nedan är läst i koden, inte provat på en telefon (G3).

## Vad som lämnar telefonen

| Data | Vart | Hur | Källa |
| --- | --- | --- | --- |
| Krypterade meddelanden (paket) | Den server som användaren skriver in under Inställningar | `https`, bara medan appen är öppen; innehållet är krypterat med Olm från telefon till telefon, och servern kan inte läsa det | `lib/features/transport/relay_client.dart`, `lib/features/transport/transport.dart`, `lib/crypto/src/sha_olm_service.dart` |
| Brevlåde-ID (16 byte, byts varje dygn) | Samma server, i adressen | En pseudonym per kontakt, riktning och dygn | `lib/features/chat/messaging_service.dart`, `lib/crypto/src/sha_crypto_service.dart` |
| IP-adress | Servern ser den, som vid all trafik | Relayns kod sparar den inte på disk eller i loggar. För spamgränsen finns den i RAM i högst 90 sekunder | `relay/README.md`, `relay/ratelimit.go`, 0002 |

Inget annat skickas av appens egen kod: inga konton, ingen analys, inga
kraschrapporter, inga annonser och ingen push. Det enda stället i `lib/`
som använder nätet är `lib/features/transport/relay_client.dart`
(`HttpClient`), och `pubspec.yaml` har inga paket för analys eller push.
Det är läst, inte testat: inget test hindrar att nätet används någon
annanstans.

ML Kit är borttaget (0012 (C1)). QR-koden läses i appen av `zxing2`, i ren
Dart (`lib/features/qr/qr_decoder.dart`). Om CameraX (via `camera`), eller
media3 som följer med det, skickar något till Google: **ej verifierat**.

## Vad som sparas på telefonen

Allt ligger krypterat i appens privata `noBackupFilesDir`, med en nyckel i
Android Keystore (`android/app/src/main/kotlin/se/sha/sha/keystore/KeystoreVault.kt`).
Backup och enhetsöverföring är avstängda (`allowBackup="false"`,
`android/app/src/main/res/xml/data_extraction_rules.xml`).

| Data | Hur länge | Källa |
| --- | --- | --- |
| Identitetens nyckelpar och Olm-kontot | Tills appen avinstalleras eller återställs (se nedan) | `lib/crypto/src/sha_crypto_service.dart`, `lib/crypto/src/sha_olm_service.dart` |
| Olm-sessioner per kontakt | Tills en nyare session har tagit över enligt (iv) i 0009, eller som ovan | `lib/crypto/src/sha_olm_service.dart` (`_removeOld`) |
| Engångsnycklar som har visats i en QR-kod men inte använts | 30 dagar | `lib/crypto/src/sha_olm_service.dart` (`keepUnusedOneTimeKeys`) |
| Räknare för paket som inte gick att läsa | Tills appen har visat dem | `lib/crypto/src/sha_olm_service.dart` (`clearFailureCounts`) |
| Kontakter: namnet användaren skriver, när ni möttes, kontaktens offentliga nycklar | Som ovan | `lib/crypto/src/sha_olm_service.dart` |
| Meddelanden | Bara tills de har skickats eller visats; sedan bara i minnet tills appen stängs | 0005 (i), `lib/features/chat/message_store.dart` |
| Serverns adress och hur ofta appen hämtar | Som identiteten | `lib/features/transport/transport_settings.dart` |
| Hashar av hämtade paket (för att känna igen dubbletter) | Minst 72 timmar; de rensas vid nästa skrivning efter det | `lib/crypto/src/sha_olm_service.dart` (`keepHashes`) |

`resetIdentity()` raderar allt, valvets nyckel först
(`lib/crypto/src/crypto_service.dart`). Appen erbjuder det bara när nyckeln
inte går att läsa ("Radera och skapa ny identitet?",
`lib/features/onboarding/identity_recovery_screen.dart`). Annars raderar en
avinstallation allt.

## Behörigheter

- `CAMERA`: bara för att skanna QR-koder, och bara medan skannern är öppen
  och appen syns (`lib/features/qr/qr_camera.dart`). Bilderna läses i
  minnet och sparas eller skickas inte. Inget ljud spelas in
  (`enableAudio: false`).
- `INTERNET`: i appens egen kod bara för servern
  (`android/app/src/main/AndroidManifest.xml`). Behörigheten gäller hela
  appen, även biblioteken (se CameraX och media3 ovan).
- Det som biblioteken lägger till (`RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE`,
  `READ_EXTERNAL_STORAGE` och `ACCESS_NETWORK_STATE`) tas bort ur
  manifestet. CI kontrollerar att release-manifestet bara begär `CAMERA`,
  `INTERNET` och androidx.core:s interna
  `se.sha.sha.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
  (`.github/scripts/check-manifest.py`, `docs/release.md`, punkt 0).

## Annat

- **Ingen loggning** i appkoden (`test/security/no_logging_test.dart`).
- **Urklipp:** appens egna kopieringsknappar finns bara i debugbyggen
  (`kDebugMode` i `lib/features/onboarding/identity_screen.dart` och
  `lib/features/qr/my_qr_screen.dart`). Vanliga textfält har systemets
  kopiera och klistra in.
- **Skärmdumpar** är avstängda (`FLAG_SECURE`,
  `android/app/src/main/kotlin/se/sha/sha/MainActivity.kt`).

## Förslag till svar (ej kontrollerade mot Googles definitioner)

- **Samlar appen in data?** Meddelandena går via en server men är krypterade
  från telefon till telefon. Google undantar data som är krypterad så att
  bara avsändare och mottagare kan läsa den; **kontrollera** att det gäller
  här (F9). Kontrollera också IP-adressen och brevlåde-ID:n, som når
  servern okrypterade, och om spamgränsens 90 sekunder räknas som tillfällig
  behandling.
- **Delas data med tredje part?** Inte av appens egen kod. CameraX: se ovan.
- **Krypteras data under överföring?** Ja: `https`, och innehållet med Olm.
- **Kan användaren be att data raderas?** Allt på telefonen raderas när
  appen avinstalleras; det finns ingen egen knapp för det i vanlig
  användning. På servern finns paket i högst 48 timmar (`relay/limits.go`,
  `packetTTL`). Om Play kräver en raderingsfunktion i appen: kontrollera i
  F9.
