# Granskning av Flutter/Dart-lagret och bygget

Underlag för villkor 2 i 0003 ("Beslut") och 0004 §13 punkt 2 och 10.

## Lagren

| Lager | Var | Regler |
| --- | --- | --- |
| Kryptomodulen | `lib/crypto/` | Appen når den bara via `CryptoService` (`lib/crypto/crypto.dart`). Modulen importerar inget UI eller appkod (`test/security/no_logging_test.dart`). |
| Valvet, inbyggt | `android/app/src/main/kotlin/se/sha/sha/keystore/` | AES-256-GCM med en Keystore-nyckel, StrongBox om den finns, bara upplåst telefon från Android 9 (`KeystoreVault.kt:215-225`). Fasta felkoder, inga loggar. |
| Transporten | `lib/features/transport/` | Bara `dart:io`; `https` (och `http` till telefonen själv utanför release); ingen komprimering, inga omdirigeringar, en anslutning per anrop. |
| UI | `lib/features/`, `lib/ui/` | Inga kryptoord utanför `technical_info_sheet.dart`; "servern", aldrig "relayn"; inga felobjekt i texter. |

## Beroenden

Från `pubspec.yaml`; exakta versioner står i `pubspec.lock`, som är
incheckad.

| Paket | Version | Varför |
| --- | --- | --- |
| `flutter_vodozemac`, `vodozemac` | 0.9.1 (exakt) | Olm (0003) |
| `flutter_rust_bridge` | 2.13.0 (exakt) | Bindningarna till Rust |
| `cryptography` | ^2.9.0 | AES-GCM, HKDF, SHA-256, X25519 |
| `flutter_riverpod` | ^3.4.3 | Tillstånd i appen |
| `qr_flutter` | ^4.1.0 | Visa QR-koden |
| `mobile_scanner` | ^7.4.2 | Skanna QR-koden (ML Kit och CameraX) |

`test/security/olm_versions_test.dart` kontrollerar att Olm-paketen är
låsta.

## Bygget

- **Flutter 3.47.7**, kontrollerad med SHA-256 i CI (`ci.yml`).
- **Rust i Android-bygget är inte låst:** pluginets cargokit kör
  `rustup run stable cargo build` utan `--locked` (`ci.yml:11-14` och
  `:171`). Värdbyggena (spiken och `tool/build_native_host.sh`) använder
  Rust 1.97.0 och `--locked`. 0004 §13 punkt 10: antingen låses det, eller
  så godtar ägaren det efter den här granskningen.
- **Actions är låsta till fulla SHA:er.** `permissions: contents: read`.
- **Dependabot** finns för versioner (`.github/dependabot.yml`). Alerts och
  security updates väntar på G7.
- **Debug och release:** debug-bygget har utvecklarhjälp (kopiera koden,
  ange koden för hand: `kDebugMode`) och går att felsöka. Hur appen delas
  ut till testare och på Google Play bestäms i fas 2 och 3.

## Android

- **Behörigheter** i appens eget manifest: `CAMERA` och `INTERNET`. Vad
  biblioteken lägger till i det färdiga manifestet är **ej verifierat**
  (`docs/release.md`, punkt 0).
- **Ingen backup** (`allowBackup="false"`, `data_extraction_rules.xml`), och
  valvet ligger i `noBackupFilesDir`.
- **`FLAG_SECURE`** (`MainActivity.kt:16-17`): inga skärmdumpar.
- **`network_security_config.xml`:** ingen klartext och bara systemets
  CA:er. `dart:io` läser inte den filen; transportens egna regler står i
  `lib/features/transport/relay_client.dart:77`.
- **Tangentbordet** ombeds att inte lära sig av det som skrivs.

## Att granska särskilt

1. Att inga nycklar, ingen klartext och inga nonces loggas, och att
   bibliotekens feltexter aldrig visas (`test/security/no_logging_test.dart`
   och `lib/core/errors.dart`).
2. Plattformskanalen: att varje fel blir en fast kod, och att byte från
   kanalen kopieras innan de nollas (`android_keystore_vault.dart`).
3. Att `dart:io` gör samma TLS-kontroll som Android: bara systemets
   rotcertifikat, ingen `badCertificateCallback`.
4. Riverpod 3: att ingen provider ändras under ett bygge, och att
   `ref.mounted` kontrolleras efter `await`.
5. Att Rust i Android-bygget inte är låst (se ovan).
6. Vad ML Kit och CameraX gör med kamerabilden, och om de använder nätet
   (`docs/release.md`, punkt 6: ej verifierat).
