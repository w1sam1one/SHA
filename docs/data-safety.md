# Underlag till Data safety (F10)

Vad SHA:s egen kod gör med data, med fil som källa. Det ersätter punkt 6 i
[`docs/release.md`](release.md), som beskrev läget före P6.

**Du måste själv kontrollera varje svar mot Googles definitioner innan du
skickar in** (F9). Listan säger vad koden gör, inte hur Googles formulär ska
tolkas, och den täcker inte vad Googles bibliotek (ML Kit, CameraX) gör.

## Vad som lämnar telefonen

| Data | Vart | Hur | Källa |
| --- | --- | --- | --- |
| Krypterade meddelanden (paket) | Den server som användaren skriver in under Inställningar | `https`, bara medan appen är öppen; innehållet är krypterat med Olm från telefon till telefon, och servern kan inte läsa det | `lib/features/transport/relay_client.dart`, `lib/features/transport/transport.dart`, `lib/crypto/src/sha_olm_service.dart` |
| Brevlåde-ID (16 byte, byts varje dygn) | Samma server, i adressen | En pseudonym per kontakt, riktning och dygn | `lib/features/chat/messaging_service.dart`, `lib/crypto/src/sha_crypto_service.dart` |
| IP-adress | Servern ser den, som vid all trafik | Relayns kod sparar den inte på disk eller i loggar | `relay/README.md`, 0002 |

Inget annat skickas av appens egen kod: inga konton, ingen analys, inga
kraschrapporter, inga annonser och ingen push (`pubspec.yaml`,
`test/security/no_logging_test.dart`).

Om ML Kit eller CameraX (via `mobile_scanner`) skickar något till Google:
**ej verifierat**. Kontrollera Googles dokumentation för ML Kit.

## Vad som sparas på telefonen

Allt ligger krypterat i appens privata `noBackupFilesDir`, med en nyckel i
Android Keystore (`android/app/src/main/kotlin/se/sha/sha/keystore/KeystoreVault.kt`).
Backup och enhetsöverföring är avstängda (`allowBackup="false"`,
`res/xml/data_extraction_rules.xml`).

| Data | Hur länge | Källa |
| --- | --- | --- |
| Identitetens nyckelpar och Olm-kontot | Tills användaren återställer appen | `lib/crypto/src/sha_crypto_service.dart`, `lib/crypto/src/sha_olm_service.dart` |
| Kontakter: namnet användaren skriver, när ni möttes, kontaktens offentliga nycklar | Som ovan | `lib/crypto/src/sha_olm_service.dart` |
| Meddelanden | Bara tills de har skickats eller visats; sedan bara i minnet tills appen stängs | 0005 (i), `lib/features/chat/message_store.dart` |
| Serverns adress och hur ofta appen hämtar | Som identiteten | `lib/features/transport/transport_settings.dart` |
| Hashar av hämtade paket (för att känna igen dubbletter) | 72 timmar | `lib/crypto/src/sha_olm_service.dart` (`keepHashes`) |

`resetIdentity()` raderar allt, valvets nyckel först
(`lib/crypto/src/crypto_service.dart`). Appen erbjuder det bara när nyckeln
inte går att läsa ("Radera och skapa ny identitet?",
`lib/features/onboarding/identity_recovery_screen.dart`). Annars raderar en
avinstallation allt.

## Behörigheter

- `CAMERA`: bara för att skanna QR-koder. Appens kod ber inte om bilderna
  och sparar inga (`lib/features/qr/scan_screen.dart`).
- `INTERNET`: bara för servern (`android/app/src/main/AndroidManifest.xml`).
- Vad biblioteken lägger till i det färdiga manifestet: **ej verifierat**
  (`docs/release.md`, punkt 0).

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
  här (F9).
- **Delas data med tredje part?** Inte av appens egen kod. ML Kit: se ovan.
- **Krypteras data under överföring?** Ja: `https`, och innehållet med Olm.
- **Kan användaren be att data raderas?** Allt på telefonen raderas när
  appen avinstalleras; det finns ingen egen knapp för det i vanlig
  användning. På servern finns paket i högst 48 timmar (`relay/limits.go`,
  `packetTTL`). Om Play kräver en raderingsfunktion i appen: kontrollera i
  F9.
