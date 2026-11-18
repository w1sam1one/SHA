# Vad som är testat

Alla tester körs i CI på varje PR (`.github/workflows/ci.yml`):

- **`flutter`-jobbet:** `flutter analyze` och `flutter test`. Olm-biblioteket
  byggs för datorn med `tool/build_native_host.sh` och relayn med
  `tool/build_relay.sh`.
- **`app-android`-jobbet:** testerna i `integration_test/` på en emulator
  (API 35, x86_64).
- **`relay`-jobbet:** `go vet` och `go test -race`.
- **`spike`-jobbet:** spikens egna tester (0003).

## Per område

| Område | Tester | Var | Körs |
| --- | --- | --- | --- |
| R1–R7 från spiken, krascher enligt §6, sessionsnummer, `resetIdentity()` | 26 | `test/crypto/olm_service_cases.dart` | Datorn och emulatorn (R8) |
| Kontakter, sessionsregeln 0006, engångsnycklar §8 | 15 | `test/crypto/olm_contacts_test.dart` | Datorn |
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
| Release-manifestet: bara `CAMERA` och `INTERNET`, ingen krävd hårdvara | – | `.github/scripts/check-manifest.py` | CI (emulatorjobbet) |
| JSON-texten v3 | 6 | `test/features/message_payload_test.dart` | Datorn |
| Relay-klienten mot en server på datorn | 11 | `test/features/relay_client_test.dart` | Datorn |
| Transporten med två appar och en låtsasserver: 204, 507, 429, dubbletter, krascher, rundor | 20 | `test/features/transport_test.dart` | Datorn |
| Rundorna i §9 (b) och spamgränsen | 4 | `test/features/fetch_plan_test.dart` | Datorn |
| Hela kedjan mot den riktiga relayn | 5 | `test/chain/relay_chain_test.dart` | Datorn |
| Texterna i §10 | 5 | `test/features/notice_texts_test.dart` | Datorn |
| Inga loggar, inga felobjekt i texter, inget som liknar nycklar | 5 | `test/security/no_logging_test.dart` | Datorn |
| Inga kryptoord i texter, låsta Olm-versioner | 2 | `test/security/` | Datorn |
| Skärmar: chatten, QR-fliken, livscykeln, återställning, kontrast | 19 | `test/widget/`, `test/ui/` | Datorn |
| Relayn: gränser, loggar utan IP, spamgräns | – | `relay/*_test.go` | Datorn |

## Mutationer

Varje ny regel har minst en avsiktlig ändring som visade att ett test
faller (`CLAUDE.md`). De står i respektive PR:
[#20](https://github.com/w1sam1one/SHA/pull/20),
[#22](https://github.com/w1sam1one/SHA/pull/22),
[#23](https://github.com/w1sam1one/SHA/pull/23),
[#24](https://github.com/w1sam1one/SHA/pull/24),
[#25](https://github.com/w1sam1one/SHA/pull/25) och
[#26](https://github.com/w1sam1one/SHA/pull/26).

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
