#!/usr/bin/env python3
"""Check that an APK has everything a phone with one ABI needs.

ci.yml, job "app-arm64": the debug APK built for real phones
(--target-platform android-arm64). A build can succeed and still leave out
a native library for that ABI; the app then installs but stops when the
library is loaded. This fails unless the APK has, for the ABI:

- Flutter's engine (libflutter.so) and the Olm library that cargokit builds
  from Rust (libflutter_vodozemac.so, flutter_vodozemac's cargokit libname);
- every other native library that the APK has for any ABI.

Usage: check-apk-abi.py <apk> <abi>, for example arm64-v8a.
"""

import sys
import zipfile

REQUIRED = ("libflutter.so", "libflutter_vodozemac.so")


def problems(names, abi):
    """The problems for the zip entry names of an APK."""
    by_abi = {}
    for name in names:
        parts = name.split("/")
        if len(parts) == 3 and parts[0] == "lib" and parts[2].endswith(".so"):
            by_abi.setdefault(parts[1], set()).add(parts[2])
    have = by_abi.get(abi, set())
    found = []
    if not have:
        found.append(f"no native libraries for {abi}")
    for lib in REQUIRED:
        if lib not in have:
            found.append(f"missing for {abi}: {lib}")
    for other, libs in sorted(by_abi.items()):
        for lib in sorted(libs - have - set(REQUIRED)):
            found.append(f"only for {other}, not for {abi}: {lib}")
    return found, sorted(have)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: check-apk-abi.py <apk> <abi>")
    apk, abi = sys.argv[1], sys.argv[2]
    try:
        with zipfile.ZipFile(apk) as z:
            names = z.namelist()
    except (OSError, zipfile.BadZipFile) as e:
        sys.exit(f"cannot read {apk}: {e}")
    found, have = problems(names, abi)
    for lib in have:
        print(f"lib/{abi}/{lib}")
    if found:
        for p in found:
            print(f"::error::{p}")
        sys.exit(1)
    print(f"{apk}: everything for {abi} is there")


if __name__ == "__main__":
    main()
