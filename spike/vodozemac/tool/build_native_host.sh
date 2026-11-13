#!/usr/bin/env bash
# Builds the Rust library inside flutter_vodozemac for this computer (Linux),
# so `flutter test` can load it. Android builds compile it themselves via the
# plugin's cargokit; this is only for host tests.
#
# Uses the plugin's own Cargo.lock (--locked), so the exact crate versions the
# plugin was published with are built. Output: build/native/.
set -euo pipefail
cd "$(dirname "$0")/.."

plugin_dir="$(python3 -I -c '
import json, pathlib
cfg = json.load(open(".dart_tool/package_config.json"))
uri = next(p["rootUri"] for p in cfg["packages"] if p["name"] == "flutter_vodozemac")
print(pathlib.Path(uri.removeprefix("file://")).resolve())
')"

cargo build --release --locked \
  --manifest-path "$plugin_dir/rust/Cargo.toml" \
  --target-dir "$PWD/build/rust"

mkdir -p build/native
cp build/rust/release/libvodozemac_bindings_dart.so build/native/
echo "built build/native/libvodozemac_bindings_dart.so"
