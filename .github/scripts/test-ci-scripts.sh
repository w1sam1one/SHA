#!/usr/bin/env bash
# Tests for changed-jobs.sh and check-docs.py (ci.yml, job "changes").
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
failed=0

# expect "<flags>" path...: the flags changed-jobs.sh must print for the paths.
expect() {
  local want="$1"
  shift
  local got
  got="$(printf '%s\n' "$@" | "$here/changed-jobs.sh" | tr '\n' ' ')"
  if [ "$got" != "$want " ]; then
    echo "FAIL changed-jobs: $* -> $got(want $want)"
    failed=1
  fi
}

none="flutter=false android=false spike=false relay=false docs_only=true"
all="flutter=true android=true spike=true relay=true docs_only=false"
app="flutter=true android=true spike=false relay=false docs_only=false"
flutter_only="flutter=true android=false spike=false relay=false docs_only=false"

expect "$none" docs/ROADMAP.md README.md CLAUDE.md relay/DRIFT.md spike/vodozemac/README.md "docs/ändring.md"
expect "$app" lib/main.dart
expect "$app" test/crypto/olm_service_cases.dart
expect "$app" integration_test/vault_test.dart
expect "$app" android/app/src/main/AndroidManifest.xml
expect "$app" pubspec.yaml
expect "$app" docs/ROADMAP.md pubspec.lock
expect "$flutter_only" assets/licenses/rust.txt
expect "$flutter_only" tool/build_relay.sh
expect "$flutter_only" analysis_options.yaml
expect "$flutter_only" .github/workflows/spike-android.yml
expect "flutter=true android=false spike=true relay=false docs_only=false" spike/vodozemac/pubspec.lock
expect "flutter=true android=false spike=false relay=true docs_only=false" relay/store.go
expect "flutter=true android=true spike=true relay=false docs_only=false" rust/src/lib.rs
expect "flutter=true android=true spike=true relay=false docs_only=false" spike/x/Cargo.lock
expect "flutter=true android=true spike=true relay=false docs_only=false" rust/Cargo.toml
expect "flutter=true android=true spike=true relay=false docs_only=false" rust-toolchain.toml
expect "$flutter_only" LICENSE
expect "$app" "lib/säkerhet.dart"
expect "$all" .github/workflows/ci.yml
expect "$all" .github/scripts/resource-monitor.sh
if [ "$(printf '' | "$here/changed-jobs.sh" | tr '\n' ' ')" != "$all " ]; then
  echo "FAIL changed-jobs: an empty list must run everything"
  failed=1
fi

# check-docs.py: broken relative links fail; working ones, web links, anchors
# and links in code do not.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/root"
mkdir -p "$root/docs"
touch "$root/README.md"
# Exists, but outside the checkout that check-docs.py runs in.
touch "$tmp/outside.md"
# The backticks are Markdown, not shell.
# shellcheck disable=SC2016
printf '%s\n' '[a](../README.md) [b](https://example.se) [c](#x) [d](../README.md#y)' \
  '`[e](missing.md)`' '```' '[f](missing.md)' '```' > "$root/docs/good.md"
printf '%s\n' '[a](missing.md)' > "$root/docs/bad.md"
printf '%s\n' '[a](../../outside.md)' > "$root/docs/outside.md"
touch "$root/docs/with space.md"
printf '%s\n' '[a](with%20space.md)' > "$root/docs/space.md"
if ! (cd "$root" && python3 -I "$here/check-docs.py" docs/good.md > /dev/null); then
  echo "FAIL check-docs: docs/good.md has no broken links"
  failed=1
fi
if (cd "$root" && python3 -I "$here/check-docs.py" docs/bad.md > /dev/null); then
  echo "FAIL check-docs: docs/bad.md has a broken link"
  failed=1
fi
if (cd "$root" && python3 -I "$here/check-docs.py" docs/outside.md > /dev/null); then
  echo "FAIL check-docs: docs/outside.md links outside the repository"
  failed=1
fi
if ! (cd "$root" && python3 -I "$here/check-docs.py" docs/space.md > /dev/null); then
  echo "FAIL check-docs: docs/space.md links to a file that exists"
  failed=1
fi

# changed-files.sh: a moved file is listed under both paths, and å, ä, ö
# are not escaped.
repo="$tmp/repo"
mkdir -p "$repo/integration_test"
git -C "$repo" init -q
echo a > "$repo/integration_test/t.dart"
git -C "$repo" add -A
git -C "$repo" -c user.name=ci -c user.email=ci@example.invalid commit -q -m a
mkdir -p "$repo/docs" "$repo/lib"
git -C "$repo" mv integration_test/t.dart docs/t.dart
echo b > "$repo/lib/säkerhet.dart"
git -C "$repo" add -A
git -C "$repo" -c user.name=ci -c user.email=ci@example.invalid commit -q -m b
got="$(cd "$repo" && "$here/changed-files.sh" HEAD^ | sort | tr '\n' ' ')"
if [ "$got" != "docs/t.dart integration_test/t.dart lib/säkerhet.dart " ]; then
  echo "FAIL changed-files: got '$got'"
  failed=1
fi
if (cd "$repo" && "$here/changed-files.sh" 0000000000000000000000000000000000000000 > /dev/null 2>&1); then
  echo "FAIL changed-files: an unknown base must fail"
  failed=1
fi

# check-manifest.py: only CAMERA and INTERNET, and no required feature.
manifest() {
  printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="se.sha.sha">' \
    '<uses-permission android:name="android.permission.CAMERA"/>' \
    '<uses-permission android:name="android.permission.INTERNET"/>' \
    '<uses-permission android:name="se.sha.sha.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/>' \
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>' \
    "$@" '</manifest>'
}
check_manifest() { # expect_ok extra-xml...
  local want="$1"
  shift
  manifest "$@" > "$tmp/manifest.xml"
  if python3 -I "$here/check-manifest.py" "$tmp/manifest.xml" > /dev/null; then
    got=ok
  else
    got=bad
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL check-manifest: $* -> $got (want $want)"
    failed=1
  fi
}
check_manifest ok
check_manifest bad '<uses-permission android:name="android.permission.RECORD_AUDIO"/>'
check_manifest bad '<uses-permission-sdk-23 android:name="android.permission.READ_CONTACTS"/>'
check_manifest bad '<uses-feature android:name="android.hardware.camera.any"/>'
check_manifest bad '<uses-feature android:name="android.hardware.camera.any" android:required="true"/>'
check_manifest ok '<uses-feature android:name="android.hardware.camera.any" android:required="false"/>'
printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="se.sha.sha">' \
  '<uses-permission android:name="android.permission.INTERNET"/>' '</manifest>' > "$tmp/manifest.xml"
if python3 -I "$here/check-manifest.py" "$tmp/manifest.xml" > /dev/null; then
  echo "FAIL check-manifest: a missing CAMERA must fail"
  failed=1
fi
# Without a package attribute, the application id comes from the argument.
printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' \
  '<uses-permission android:name="android.permission.CAMERA"/>' \
  '<uses-permission android:name="android.permission.INTERNET"/>' \
  '<uses-permission android:name="se.sha.sha.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/>' \
  '</manifest>' > "$tmp/manifest.xml"
if ! python3 -I "$here/check-manifest.py" "$tmp/manifest.xml" se.sha.sha > /dev/null; then
  echo "FAIL check-manifest: the application id argument must be used"
  failed=1
fi
if python3 -I "$here/check-manifest.py" "$tmp/manifest.xml" > /dev/null; then
  echo "FAIL check-manifest: another app's permission must fail"
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "CI script tests passed"
