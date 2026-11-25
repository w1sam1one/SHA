# Vad som är testat

Alla tester körs i CI på varje PR (`.github/workflows/ci.yml`):

- **`flutter`-jobbet:** `flutter analyze` och `flutter test`. Olm-biblioteket
  byggs för datorn med `tool/build_native_host.sh` och relayn med
  `tool/build_relay.sh`.
- **`app-android`-jobbet:** testerna i `integration_test/` på en emulator
  (API 35, x86_64).
- **`relay`-jobbet:** `go vet` och `go test -race`.
- **`spike-vodozemac`-jobbet:** spikens egna tester (0003).

## Per område

| Område | Tester | Var | Körs |
| --- | --- | --- | --- |
| R1–R7 från spiken, krascher enligt §6, sessionsnummer, `resetIdentity()` | 26 | `test/crypto/olm_service_cases.dart` | Datorn och emulatorn (R8) |
| Kontakter, sessionsregeln 0006, engångsnycklar §8 | 15 | `test/crypto/olm_contacts_test.dart` | Datorn |
| Radering av gamla sessioner, 0009 (iv): varje villkor, motexemplet, utkorgen, omstart, tillstånd från före F2 | 16 | `test/crypto/olm_session_removal_test.dart` | Datorn |
| Historiken, 0010 (B): egna poster med slumpade namn, krasch vid varje skrivning, full post och dubbletter vid gränsen, rensning, skadad eller oläsbar post, återställning | 14 | `test/crypto/olm_history_test.dart` | Datorn |
| Storlekstabellen §4 med riktiga Olm-meddelanden, kedjeindex 127/128/16 384 | 6 | `test/crypto/olm_sizes_test.dart` | Datorn |
| Utfyllnaden (A) | 8 | `test/crypto/olm_padding_test.dart` | Datorn |
| Paketformat 3 | 6 | `test/crypto/olm_wire_format_test.dart` | Datorn |
| Inställningar och felräknare i valvposten | 5 | `test/crypto/olm_settings_test.dart` | Datorn |
| Valvet: skriva, läsa, stora poster, återställning, misslyckad skrivning, avbruten återställning, byte som kan nollas | 7 | `integration_test/vault_test.dart` | Emulatorn |
| Valvets felkoder | 6 | `test/crypto/android_keystore_vault_test.dart` | Datorn |
| Mätningen i 0005 och med 50 sessioner | 2 | `integration_test/olm_service_test.dart` | Emulatorn |
| QR-koden `shaid:2` | 4 | `test/features/contact_code_test.dart` | Datorn |
| Skannern (0012 (C1)): koden som "Min QR" ritar, 100 slumpade koder, koderna som `zxing2` bara läser vridna eller kastar fel på, utfyllda rader, en bild i taget | 12 | `test/features/qr_decoder_test.dart` | Datorn |
| Kameran: start, bakgrund och tillbaka, även mitt i en start, att lämna skärmen, nekad behörighet, ficklampan | 5 | `test/widget/qr_camera_test.dart` | Datorn (en låtsaskamera) |
| Release-manifestet: bara `CAMERA`, `INTERNET` och `USE_BIOMETRIC`, ingen krävd hårdvara | – | `.github/scripts/check-manifest.py` | CI (emulatorjobbet) |
| `FLAG_SECURE` i alla byggtyper, i källkoden: `onCreate` är exakt `super.onCreate` och flaggan, `setFlags` anropas bara där, inget annat ändrar fönstrets flaggor, och det finns ingen annan aktivitet i koden eller i någon byggtyps manifest (F11) | 2 | `test/security/flag_secure_test.dart` | Datorn |
| Skärmbilderna till butiken (F11): den riktiga appen, fem skärmar, rätt skärm i varje bild och inte låset, ingen bild svart eller tom, och inga bilder på en enhet där SHA redan har en identitet. Att `FLAG_SECURE` är satt följer av källkoden (raden ovan) och är inte kontrollerat medan testet kör | 1 | `integration_test/screenshots_test.dart` | Emulatorn |
| Ändringsloggen (F12): den översta versionen är den i `pubspec.yaml`, versionCode minskar nedåt i filen, bara den översta är "inte släppt", och texten följer 0002 | 2 | `test/release/changelog_test.dart` | Datorn |
| Butikstexterna (F11): förbjudna ord enligt 0002 på svenska och engelska, längderna, och inget löfte om öppen källkod förrän `LICENSE` är AGPL-3.0 | 3 | `test/security/store_texts_test.dart` | Datorn |
| Android-biblioteken på licenssidan (0012): listan i `assets/licenses/android.txt` jämförs med Gradles lista för release-bygget, varje rad i Gradles träd måste ha en exakt version, licensnamnet ur bibliotekets POM måste stå på en kort lista, och ett bibliotek under BSD eller MIT måste ha sin text på sidan | – | `.github/scripts/android-licenses.py`, provat med `test-ci-scripts.sh` | CI (emulatorjobbet) |
| JSON-texten v3 | 6 | `test/features/message_payload_test.dart` | Datorn |
| Relay-klienten mot en server på datorn | 11 | `test/features/relay_client_test.dart` | Datorn |
| Transporten med två appar och en låtsasserver: 204, 507, 429, dubbletter, krascher, rundor, kontaktens tid till 0009, historiken efter en omstart, "Spara inte", kallstart, kortare tid och en oläsbar post | 26 | `test/features/transport_test.dart` | Datorn |
| Rundorna i §9 (b) och spamgränsen | 4 | `test/features/fetch_plan_test.dart` | Datorn |
| Hela kedjan mot den riktiga relayn | 5 | `test/chain/relay_chain_test.dart` | Datorn |
| Texterna i §10 | 5 | `test/features/notice_texts_test.dart` | Datorn |
| Inga loggar, inga felobjekt i texter, inget som liknar nycklar | 5 | `test/security/no_logging_test.dart` | Datorn |
| Inga kryptoord i texter, inga löften som inte håller (0002, "Formuleringar i appen"), låsta Olm-versioner | 4 | `test/security/` | Datorn |
| Skärmar: chatten, QR-fliken, livscykeln, återställning, licenssidan (F5), vad servern ser och VPN-meningen (F5), valet av historik (F3), kontrast | 23 | `test/widget/`, `test/ui/` | Datorn |
| App-låset (F4): låst vid start, avbrutet, 5 minuter i bakgrunden mätt med telefonens tid sedan start, telefonens egen fråga, en långsam PIN-skärm, inget skärmlås, fel håller det låst, en öppen sida bakom låset, hemskärmen bakom låset, en notis, skärmen täckt vid återkomst, åter i bakgrunden under kontrollen, kanalen till Android | 20 | `test/widget/app_lock_test.dart` | Datorn (en låtsastelefon) |
| Relayn: gränser, loggar utan IP, spamgräns | – | `relay/*_test.go` | Datorn |
| Slumptal för långlivade nycklar (`entropy.dart`) | 3 | `test/crypto/entropy_test.dart` | Datorn |
| X25519, HKDF och brevlåde-ID (används för §3 (A)), och det gamla formatet 2 | 19 | `test/crypto/crypto_service_test.dart` | Datorn |
| AES-256-GCM och utfyllnaden i format 2 | 9 | `test/crypto/aes_gcm_test.dart`, `test/crypto/padding_test.dart` | Datorn |
| Serverns adress, intervallet och historikens längd | 5 | `test/features/transport_settings_test.dart` | Datorn |
| "Verifierad i person" | 3 | `test/security/trust_display_test.dart` | Datorn |
| Olm i appbygget: biblioteket laddas och en session går åt båda hållen | 2 | `integration_test/olm_build_test.dart` | Emulatorn |

## Mutationer

Varje ny regel har minst en avsiktlig ändring som visade att ett test
faller (`CLAUDE.md`). De står i respektive PR:
[#20](https://github.com/w1sam1one/SHA/pull/20),
[#22](https://github.com/w1sam1one/SHA/pull/22),
[#23](https://github.com/w1sam1one/SHA/pull/23),
[#24](https://github.com/w1sam1one/SHA/pull/24),
[#25](https://github.com/w1sam1one/SHA/pull/25),
[#26](https://github.com/w1sam1one/SHA/pull/26) och
[#43](https://github.com/w1sam1one/SHA/pull/43), med rättningar i
[#44](https://github.com/w1sam1one/SHA/pull/44).

## Mätt

- **0005, på emulatorn:** tillståndet var 844–847 KiB, en skrivning till
  valvet tog högst 49 ms och kryptering med sparande högst 83 ms. Gränsen är
  300 ms.
- **50 sessioner för en kontakt:** högst 16 ms.
- **nginx 1.24 med relayn**, provat lokalt: 65 712 byte tas emot och 65 713
  stoppas (`relay/README.md`).

## Inte testat

- En riktig telefon (arm64): G3 och villkor 1 i 0003.
- Ett fsync som misslyckas, och ett strömavbrott mitt i en skrivning.
- StrongBox och farten på en riktig telefon (F6).
- Kedjeindex från 2 097 152 (4 byte).
- Hela storlekstabellen på Android; R7 kontrollerar tre rader där.
- TLS mot relayn i kedjetesterna (nginx provades för hand, P5).
- En fast testvektor för kontrollkoden (0004 §11.3).
- TalkBack (F6).
- Skannern med en riktig kamera: att kameran startar, stängs och läser en
  kod på en telefon, och hur fort (G3). Emulatorn i CI har ingen kamera.
