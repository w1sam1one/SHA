#!/usr/bin/env bash
# Decides which jobs in ci.yml a change needs (job "changes").
#
# Reads the changed paths, one per line, on stdin. Prints flutter=, android=,
# spike=, relay= and docs_only= as true or false, for $GITHUB_OUTPUT.
#
# - Documentation only (*.md anywhere, docs/): none of the four jobs; the
#   quick check in "changes" is enough. LICENSE is not documentation here:
#   Flutter puts it in the app's license notices (NOTICES), so the Flutter
#   job builds and tests it.
# - Anything else runs "flutter": its tests also read files outside lib/ and
#   test/ (android/app/src/main/kotlin, spike/vodozemac/pubspec.yaml, relay/).
# - "android" (the emulator): lib/, test/ (integration_test/ imports from
#   it), integration_test/, android/, pubspec.yaml, pubspec.lock and Rust
#   files.
# - "spike": spike/ and Rust files.
# - "relay": relay/.
# - ci.yml and .github/scripts/: everything.
# An empty list (the diff could not be made) also runs everything.
set -euo pipefail

flutter=false android=false spike=false relay=false docs_only=true seen=false
while IFS= read -r f; do
  [ -n "$f" ] || continue
  seen=true
  case "$f" in
    *.md | docs/*) continue ;;
  esac
  docs_only=false
  flutter=true
  rust=false
  case "$f" in
    *.rs | Cargo.toml | */Cargo.toml | Cargo.lock | */Cargo.lock | rust-toolchain* | */rust-toolchain*) rust=true ;;
  esac
  case "$f" in
    .github/workflows/ci.yml | .github/scripts/*) android=true spike=true relay=true ;;
    lib/* | test/* | integration_test/* | android/* | pubspec.yaml | pubspec.lock) android=true ;;
    spike/*) spike=true ;;
    relay/*) relay=true ;;
  esac
  if [ "$rust" = true ]; then
    android=true spike=true
  fi
done

if [ "$seen" = false ]; then
  flutter=true android=true spike=true relay=true docs_only=false
fi

printf 'flutter=%s\nandroid=%s\nspike=%s\nrelay=%s\ndocs_only=%s\n' \
  "$flutter" "$android" "$spike" "$relay" "$docs_only"
