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
expect "$app" assets/licenses/android.txt
expect "$flutter_only" assets/licenses/zxing.txt
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
expect "$flutter_only" docs/butikstexter.md
expect "$flutter_only" CHANGELOG.md
expect "$flutter_only" test_driver/screenshots.dart
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

# check-manifest.py: only CAMERA, INTERNET and USE_BIOMETRIC, and no required
# feature.
manifest() {
  printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="se.sha.sha">' \
    '<uses-permission android:name="android.permission.CAMERA"/>' \
    '<uses-permission android:name="android.permission.INTERNET"/>' \
    '<uses-permission android:name="android.permission.USE_BIOMETRIC"/>' \
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
printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="se.sha.sha">' \
  '<uses-permission android:name="android.permission.CAMERA"/>' \
  '<uses-permission android:name="android.permission.INTERNET"/>' '</manifest>' > "$tmp/manifest.xml"
if python3 -I "$here/check-manifest.py" "$tmp/manifest.xml" > /dev/null; then
  echo "FAIL check-manifest: a missing USE_BIOMETRIC (the app lock) must fail"
  failed=1
fi
# Without a package attribute, the application id comes from the argument.
printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' \
  '<uses-permission android:name="android.permission.CAMERA"/>' \
  '<uses-permission android:name="android.permission.INTERNET"/>' \
  '<uses-permission android:name="android.permission.USE_BIOMETRIC"/>' \
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

# android-licenses.py: Gradle's list against the license page (F5, 0012).
cache="$tmp/gradle-cache"
pom() { # group artifact version body
  mkdir -p "$cache/$1/$2/$3/abc"
  printf '%s\n' "$4" > "$cache/$1/$2/$3/abc/$2-$3.pom"
}
pom androidx.core core 1.13.1 '<project xmlns="http://maven.apache.org/POM/4.0.0"><licenses><license><name>The Apache Software License, Version 2.0</name></license></licenses></project>'
pom com.google.guava guava-parent 33.4.0-android '<project><licenses><license><name>Apache License, Version 2.0</name></license></licenses></project>'
pom com.google.guava guava 33.4.0-android '<project xmlns="http://maven.apache.org/POM/4.0.0"><parent><groupId>com.google.guava</groupId><artifactId>guava-parent</artifactId><version>33.4.0-android</version></parent></project>'
pom io.flutter flutter_embedding_release 1.0.0-abc '<project></project>'
cat > "$tmp/deps.txt" <<'DEPS'
releaseRuntimeClasspath - Runtime classpath of '/release'.
+--- project :camera_android_camerax
|    +--- androidx.core:core:1.12.0 -> 1.13.1
|    \--- com.google.guava:guava:{strictly 33.4.0-android} -> 33.4.0-android (*)
+--- io.flutter:flutter_embedding_release:1.0.0-abc
+--- androidx.core:core:1.13.1 (c)
\--- androidx.lifecycle:lifecycle-common:2.8.0 (c)
DEPS
expected='androidx.core:core 1.13.1: The Apache Software License, Version 2.0
com.google.guava:guava 33.4.0-android: Apache License, Version 2.0
io.flutter:flutter_embedding_release 1.0.0-abc: BSD-3-Clause (Flutter)'
got="$(python3 -I "$here/android-licenses.py" "$tmp/deps.txt" "$cache" --print)"
if [ "$got" != "$expected" ]; then
  echo "FAIL android-licenses: the list from Gradle's tree"
  printf '%s\n' "$got"
  failed=1
fi
apache='TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION'
printf 'Rubrik\n\n%s\n\n----\n%s\n' "$expected" "$apache" > "$tmp/android.txt"
if ! python3 -I "$here/android-licenses.py" "$tmp/deps.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: a matching list must pass"
  failed=1
fi
# Without the Apache-2.0 text after the line ---- it fails.
printf 'Rubrik\n\n%s\n\n----\nApache License\n' "$expected" > "$tmp/android.txt"
if python3 -I "$here/android-licenses.py" "$tmp/deps.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: a page without the Apache-2.0 text must fail"
  failed=1
fi
# A library missing from the page fails.
printf 'Rubrik\n\n%s\n\n----\n%s\n' "$(printf '%s\n' "$expected" | sed '2d')" "$apache" > "$tmp/android.txt"
if python3 -I "$here/android-licenses.py" "$tmp/deps.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: a library missing from the page must fail"
  failed=1
fi
# A library under BSD or MIT needs its own text, with its copyright line,
# after the line ----: the POM names the license but has no text.
pom org.example bsdlib 1.0 '<project><licenses><license><name>Apache License, Version 2.0</name></license><license><name>BSD-3-Clause</name></license></licenses></project>'
cp "$tmp/deps.txt" "$tmp/deps3.txt"
printf '%s\n' '\--- org.example:bsdlib:1.0' >> "$tmp/deps3.txt"
list3="$(python3 -I "$here/android-licenses.py" "$tmp/deps3.txt" "$cache" --print)"
printf 'Rubrik\n\n%s\n\n----\n%s\n' "$list3" "$apache" > "$tmp/android.txt"
if python3 -I "$here/android-licenses.py" "$tmp/deps3.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: a BSD library without its text must fail"
  failed=1
fi
printf 'Rubrik\n\n%s\n\n----\n%s\n\norg.example:bsdlib innehåller kod under BSD-3-Clause:\nCopyright\n' "$list3" "$apache" > "$tmp/android.txt"
if ! python3 -I "$here/android-licenses.py" "$tmp/deps3.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: a BSD library with its text must pass"
  failed=1
fi
# A license that is not known to combine with AGPL-3.0 fails.
pom org.example lib 1.0 '<project><licenses><license><name>Some Proprietary License</name></license></licenses></project>'
printf '%s\n' '\--- org.example:lib:1.0' >> "$tmp/deps.txt"
printf 'Rubrik\n\n%s\n\n----\n%s\n' "$(python3 -I "$here/android-licenses.py" "$tmp/deps.txt" "$cache" --print 2>/dev/null)" "$apache" > "$tmp/android.txt"
if python3 -I "$here/android-licenses.py" "$tmp/deps.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: an unknown license must fail"
  failed=1
fi
# A library whose POM names no license fails.
pom org.example nolicense 2.0 '<project></project>'
printf '%s\n' '\--- org.example:nolicense:2.0' > "$tmp/deps2.txt"
printf 'Rubrik\n\n%s\n\n----\n' "$(python3 -I "$here/android-licenses.py" "$tmp/deps2.txt" "$cache" --print 2>/dev/null)" > "$tmp/android.txt"
if python3 -I "$here/android-licenses.py" "$tmp/deps2.txt" "$cache" --check "$tmp/android.txt" > /dev/null; then
  echo "FAIL android-licenses: a library without a license must fail"
  failed=1
fi
# The page for the tree in $1, made from --print, with the Apache-2.0 text.
page() {
  printf 'Rubrik\n\n%s\n\n----\n%s\n' \
    "$(python3 -I "$here/android-licenses.py" "$1" "$cache" --print 2>/dev/null)" \
    "$apache" > "$tmp/android.txt"
}
licenses_pass() { # tree, what
  page "$1"
  if ! python3 -I "$here/android-licenses.py" "$1" "$cache" --check "$tmp/android.txt" > /dev/null; then
    echo "FAIL android-licenses: $2 must pass"
    failed=1
  fi
}
licenses_fail() { # tree, what, [the error it must give]
  page "$1"
  if out="$(python3 -I "$here/android-licenses.py" "$1" "$cache" --check "$tmp/android.txt")"; then
    echo "FAIL android-licenses: $2 must fail"
    failed=1
  elif [ -n "${3:-}" ] && ! printf '%s\n' "$out" | grep -qF -- "$3"; then
    echo "FAIL android-licenses: $2 must fail with: $3"
    printf '%s\n' "$out"
    failed=1
  fi
}
apache_pom='<project><licenses><license><name>Apache-2.0</name></license></licenses></project>'
# A version range or a rich version with the version Gradle resolved is read
# (review of #48: such lines dropped out of the list).
pom com.google.android.gms play-services-basement 18.1.0 "$apache_pom"
pom org.foo rich 1.1 "$apache_pom"
pom org.foo ranged 1.5 "$apache_pom"
cat > "$tmp/deps4.txt" <<'DEPS'
releaseRuntimeClasspath - Runtime classpath of '/release'.
+--- com.google.android.gms:play-services-basement:[18.1.0] -> 18.1.0
+--- org.foo:rich:{require 1.0; reject 1.0.1} -> 1.1
\--- org.foo:ranged:{strictly [1.0,2.0)} -> 1.5 (*)
DEPS
got="$(python3 -I "$here/android-licenses.py" "$tmp/deps4.txt" "$cache" --print)"
if [ "$got" != 'com.google.android.gms:play-services-basement 18.1.0: Apache-2.0
org.foo:ranged 1.5: Apache-2.0
org.foo:rich 1.1: Apache-2.0' ]; then
  echo "FAIL android-licenses: ranges and rich versions with a resolved version"
  printf '%s\n' "$got"
  failed=1
fi
licenses_pass "$tmp/deps4.txt" "ranges and rich versions with a resolved version"
# A line without an exact version fails, instead of dropping out.
for line in 'org.foo:ranged:[1.0,2.0)' 'org.foo:nover FAILED' 'org.foo:dyn:1.+' \
  'org.foo:rich:{prefer 2.0}' 'org.foo:gone:1.0 (n)' 'org.foo:odd:1.0 -> [1.0,2.0)' \
  'org.foo:lat:latest.release' 'project :x -> org.foo:bar:3.0'; do
  printf 'releaseRuntimeClasspath\n+--- androidx.core:core:1.13.1\n\\--- %s\n' "$line" > "$tmp/deps5.txt"
  licenses_fail "$tmp/deps5.txt" "a tree line without an exact version ($line)" \
    "no exact version in Gradle's tree: $line"
done
# Two versions of one library fail.
printf 'releaseRuntimeClasspath\n+--- org.foo:rich:1.1\n\\--- org.foo:rich:1.0\n' > "$tmp/deps5.txt"
pom org.foo rich 1.0 "$apache_pom"
licenses_fail "$tmp/deps5.txt" "two versions of one library" "two versions of org.foo:rich"
# Only license names on the list pass: words in a name are not enough.
for name in 'Apache License 2.0 with Commons Clause' 'Apache Software License 1.1' \
  'BSD-4-Clause' 'Limited Use License' 'GPL-2.0-only AND BSD-3-Clause'; do
  pom org.foo odd 1.0 "<project><licenses><license><name>$name</name></license></licenses></project>"
  printf 'releaseRuntimeClasspath\n\\--- org.foo:odd:1.0\n' > "$tmp/deps5.txt"
  licenses_fail "$tmp/deps5.txt" "the license name '$name'" "license to check: org.foo:odd 1.0: $name"
done
# A module in NO_CODE whose POM is only a POM is left out. Any other POM
# with packaging "pom" stops the check, and so does a NO_CODE module that is
# no longer only a POM (second review of #48).
pom org.jetbrains.kotlin kotlin-bom 1.8.0 '<project><packaging>pom</packaging><licenses><license><name>Apache-2.0</name></license></licenses></project>'
pom org.jetbrains.kotlinx atomicfu 0.29.0 '<project><licenses><license><name>Apache-2.0</name></license></licenses></project>'
pom org.foo some-bom 1.0 '<project><packaging>pom</packaging><licenses><license><name>Apache-2.0</name></license></licenses></project>'
printf 'releaseRuntimeClasspath\n+--- org.jetbrains.kotlin:kotlin-bom:1.8.0\n\\--- androidx.core:core:1.13.1\n' > "$tmp/deps5.txt"
got="$(python3 -I "$here/android-licenses.py" "$tmp/deps5.txt" "$cache" --print)"
if [ "$got" != 'androidx.core:core 1.13.1: The Apache Software License, Version 2.0' ]; then
  echo "FAIL android-licenses: a module in NO_CODE is left out"
  printf '%s\n' "$got"
  failed=1
fi
licenses_pass "$tmp/deps5.txt" "a module in NO_CODE"
printf 'releaseRuntimeClasspath\n\\--- org.foo:some-bom:1.0\n' > "$tmp/deps5.txt"
licenses_fail "$tmp/deps5.txt" "a POM with packaging pom outside NO_CODE" \
  "only a POM: org.foo:some-bom 1.0"
printf 'releaseRuntimeClasspath\n\\--- org.jetbrains.kotlinx:atomicfu:0.29.0\n' > "$tmp/deps5.txt"
licenses_fail "$tmp/deps5.txt" "a module in NO_CODE that is not only a POM" \
  "org.jetbrains.kotlinx:atomicfu 0.29.0 is in NO_CODE"
# A license without a name stops the check; the parent's is not used.
pom org.foo unnamed 1.0 '<project><parent><groupId>com.google.guava</groupId><artifactId>guava-parent</artifactId><version>33.4.0-android</version></parent><licenses><license><url>https://www.gnu.org/licenses/gpl-3.0.txt</url></license></licenses></project>'
printf 'releaseRuntimeClasspath\n\\--- org.foo:unnamed:1.0\n' > "$tmp/deps5.txt"
licenses_fail "$tmp/deps5.txt" "a license without a name" \
  "license to check: org.foo:unnamed 1.0: (no name)"
# A module Gradle replaced by another is listed as the other.
pom org.bar new 2.0 "$apache_pom"
printf 'releaseRuntimeClasspath\n\\--- org.foo:old:1.0 -> org.bar:new:2.0\n' > "$tmp/deps5.txt"
got="$(python3 -I "$here/android-licenses.py" "$tmp/deps5.txt" "$cache" --print)"
if [ "$got" != 'org.bar:new 2.0: Apache-2.0' ]; then
  echo "FAIL android-licenses: a module replaced by another is listed as the other"
  printf '%s\n' "$got"
  failed=1
fi
# A range with a space and a resolved version is read.
printf 'releaseRuntimeClasspath\n\\--- org.foo:ranged:[1.0, 2.0) -> 1.5\n' > "$tmp/deps5.txt"
got="$(python3 -I "$here/android-licenses.py" "$tmp/deps5.txt" "$cache" --print)"
if [ "$got" != 'org.foo:ranged 1.5: Apache-2.0' ]; then
  echo "FAIL android-licenses: a range with a space"
  printf '%s\n' "$got"
  failed=1
fi
# A <license> outside <licenses> (in a plugin's configuration) is not read.
pom org.foo plugin-license 1.0 '<project><build><plugins><plugin><configuration><license><name>Apache-2.0</name></license></configuration></plugin></plugins></build></project>'
printf 'releaseRuntimeClasspath\n\\--- org.foo:plugin-license:1.0\n' > "$tmp/deps5.txt"
licenses_fail "$tmp/deps5.txt" "a license only in a plugin's configuration" \
  "no license found in the POM: org.foo:plugin-license 1.0"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "CI script tests passed"
