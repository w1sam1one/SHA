#!/usr/bin/env python3
"""The Android libraries in the release app and their licenses (F5, 0012).

Decision 0012 (C1), "Testa": the license page shows every library in the
APK, with a license that can be combined with AGPL-3.0, and the list is
checked against Gradle's own list of dependencies in CI, without a new
plugin.

Usage:
  android-licenses.py DEPENDENCIES GRADLE_CACHE --check ASSET
  android-licenses.py DEPENDENCIES GRADLE_CACHE --print

DEPENDENCIES is the output of
  ./gradlew -q :app:dependencies --configuration releaseRuntimeClasspath
GRADLE_CACHE is ~/.gradle/caches/modules-2/files-2.1, where Gradle keeps the
POM files it resolved. Each library's license is read from its POM, or from
the POM of a parent. Modules of the build itself (`project :...`) are the
Flutter plugins, whose licenses Flutter collects from their Dart packages.

--check compares the list in ASSET (its lines before the line "----") with
what Gradle resolved, and fails if they differ, or if a license is missing
or is not one known to combine with AGPL-3.0. On a difference it prints the
list as it should be. --print only prints it.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

SEPARATOR = "----"

# One dependency in Gradle's tree: "group:artifact[:version][ -> resolved]".
DEPENDENCY = re.compile(
    r"^[\s|+\\\-]*([\w.\-]+):([\w.\-]+)(?::([\w.+\-]+))?(?: -> ([\w.+\-]+))?"
)
# One line of the list on the license page.
LISTED = re.compile(r"^[\w.\-]+:[\w.\-]+ \S+: ")

# Licenses known to combine with AGPL-3.0, by words in their names. Anything
# else stops the check for a human decision.
ALLOWED = (("apache", "2"), ("mit",), ("bsd",))

# Groups whose POMs name no license, with where the license is stated.
KNOWN = {
    # The Flutter engine and embedding: Flutter's own LICENSE, BSD-3-Clause.
    # The engine's third-party notices are on the license page through
    # Flutter's own LicenseRegistry.
    "io.flutter": "BSD-3-Clause (Flutter)",
}


def modules(dependencies):
    """The resolved group:artifact -> version in Gradle's dependency tree."""
    found = {}
    for raw in dependencies.splitlines():
        if "project :" in raw or raw.rstrip().endswith((" (n)", " (c)")):
            continue
        line = re.sub(r"\{strictly ([^}]+)\}", r"\1", raw)
        m = DEPENDENCY.match(line)
        if not m or not (m.group(3) or m.group(4)):
            continue
        group, artifact, asked, resolved = m.groups()
        found[f"{group}:{artifact}"] = resolved or asked
    return found


def pom(cache, group, artifact, version):
    """The POM's root element without namespaces, or None."""
    folder = pathlib.Path(cache) / group / artifact / version
    for path in sorted(folder.glob(f"*/{artifact}-{version}.pom")):
        root = ET.parse(path).getroot()
        for e in root.iter():
            e.tag = e.tag.split("}")[-1]
        return root
    return None


def licenses(cache, group, artifact, version, depth=0):
    """License names from the POM, or from its parents."""
    root = pom(cache, group, artifact, version)
    if root is None or depth > 8:
        return []
    names = [
        (lic.findtext("name") or "").strip()
        for lic in root.iter("license")
        if (lic.findtext("name") or "").strip()
    ]
    if names:
        return names
    parent = root.find("parent")
    if parent is None:
        return []
    return licenses(
        cache,
        (parent.findtext("groupId") or "").strip(),
        (parent.findtext("artifactId") or "").strip(),
        (parent.findtext("version") or "").strip(),
        depth + 1,
    )


def allowed(name):
    words = name.lower()
    return any(all(w in words for w in rule) for rule in ALLOWED)


def listing(dependencies, cache):
    """The lines for the license page, and the problems found."""
    lines, problems = [], []
    for key, version in sorted(modules(dependencies).items()):
        group, artifact = key.split(":", 1)
        names = licenses(cache, group, artifact, version)
        if not names and group in KNOWN:
            names = [KNOWN[group]]
        if not names:
            problems.append(f"no license found in the POM: {key} {version}")
            names = ["?"]
        for name in names:
            if name != "?" and not allowed(name):
                problems.append(f"license to check: {key} {version}: {name}")
        lines.append(f"{key} {version}: {', '.join(names)}")
    if not lines:
        problems.append("Gradle's list has no libraries")
    return lines, problems


def main(argv):
    if len(argv) < 4 or argv[3] not in ("--check", "--print"):
        print(__doc__, file=sys.stderr)
        return 2
    lines, problems = listing(pathlib.Path(argv[1]).read_text(), argv[2])
    if argv[3] == "--print":
        print("\n".join(lines))
        return 0
    if len(argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    head = pathlib.Path(argv[4]).read_text().split(f"\n{SEPARATOR}\n")[0]
    listed = [l for l in head.splitlines() if LISTED.match(l)]
    if listed != lines:
        problems.append(f"{argv[4]} does not match Gradle's list")
        print("The list should be (between the markers):")
        print("<<<")
        print("\n".join(lines))
        print(">>>")
    for p in problems:
        print(f"::error::{p}")
    if not problems:
        print(f"licenses ok: {len(lines)} Android libraries")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
