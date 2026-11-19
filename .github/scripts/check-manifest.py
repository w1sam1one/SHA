#!/usr/bin/env python3
"""Checks the merged release manifest (ci.yml, job "app-android").

Decisions 0012 (C1) and 0011 (B), and README: the app asks only for CAMERA,
INTERNET and USE_BIOMETRIC (the app lock), and no hardware feature is
required, so a phone without a camera can still install the app and show
its QR code. Libraries may add permissions and
features of their own (the camera plugin adds RECORD_AUDIO and
WRITE_EXTERNAL_STORAGE, the merger READ_EXTERNAL_STORAGE with it, and
media3 through CameraX's video use case ACCESS_NETWORK_STATE); the app's
manifest removes them, and this check fails if one gets through.

androidx.core adds the app's own DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION,
which no other app can hold; it is allowed.

Usage: check-manifest.py MANIFEST.xml [APPLICATION_ID]
The merged release manifest from Gradle. APPLICATION_ID defaults to the
manifest's package attribute.
"""
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
REQUIRED = {
    "android.permission.CAMERA",
    "android.permission.INTERNET",
    # The app lock (F4, 0011 (B)): the phone's own fingerprint, face or PIN.
    "android.permission.USE_BIOMETRIC",
}


def problems(manifest, application_id=None):
    root = ET.fromstring(manifest)
    package = application_id or root.get("package", "")
    allowed = REQUIRED | {f"{package}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"}
    found = set()
    for tag in ("uses-permission", "uses-permission-sdk-23"):
        for element in root.iter(tag):
            found.add(element.get(ANDROID + "name", ""))
    out = []
    for name in sorted(found - allowed):
        out.append(f"permission not allowed: {name}")
    for name in sorted(REQUIRED - found):
        out.append(f"permission missing: {name}")
    for element in root.iter("uses-feature"):
        if element.get(ANDROID + "required", "true") != "false":
            name = element.get(ANDROID + "name", "?")
            out.append(f"feature required: {name}")
    return out


def main(path, application_id=None):
    with open(path, encoding="utf-8") as f:
        found = problems(f.read(), application_id)
    for line in found:
        print(line)
    if not found:
        print(
            "manifest ok: only CAMERA, INTERNET and USE_BIOMETRIC, "
            "no required feature"
        )
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
