# Spike: flutter_vodozemac (Olm) för SHA

Prototyp för beslut D3. Resultaten och slutsatserna står i
[docs/decisions/0003-protocol-library.md](../../docs/decisions/0003-protocol-library.md).

> Ingen del av appen. Inget här byggs in i SHA eller delas ut. Appens
> `pubspec.yaml` är orörd; spiken har sin egen med exakta versioner och egen
> lockfil.

- `flutter_vodozemac` **0.9.1**, `vodozemac` **0.9.1** och `flutter_rust_bridge`
  **2.13.0**. Alla är låsta exakt, och `flutter_vodozemac` och `vodozemac`
  har licensen **AGPL-3.0**.
- Ingen egen kryptografi. `lib/olm_spike.dart` sätter bara ihop
  bibliotekets publika API: QR-innehållet, regeln för vilken session som
  används och lagringen.
- `test/olm_spike_test.dart` innehåller kraven R1–R8 som tester. Varje fynd
  skrivs som en rad `SPIKE-REPORT`.

## Köra på datorn (Linux)

Kräver Flutter 3.47.7 och Rust 1.97.0. Pluginets Rust-del byggs först för
datorn; på Android bygger pluginet den själv.

```sh
cd spike/vodozemac
flutter pub get --enforce-lockfile
./tool/build_native_host.sh        # → build/native/libvodozemac_bindings_dart.so
flutter test
```

## Köra på Android (R8)

```sh
flutter test integration_test/olm_spike_test.dart -d <enhet>
```

CI kör samma sak på en emulator, i `.github/workflows/spike-android.yml`.
