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
A BOM (a POM with packaging "pom" and no .jar or .aar) has no code in the
APK and is left out.

Every line of Gradle's tree must give a library with an exact version: a
line that does not (a version range without a resolved version, FAILED, a
module replaced by something else) fails the check, so that no library
drops out of the list without notice (review of #48).

--check compares the list in ASSET (its lines before the line "----") with
what Gradle resolved, and fails if they differ, or if a license is missing
or is not on the short list below of license names that combine with
AGPL-3.0. On a difference it prints the list as it should be. --print only
prints it.

After the line "----" ASSET has the license texts: the Apache-2.0 text, and
for each library under another license (BSD or MIT, whose copyright line
must go with the app) a paragraph that starts with the library's
group:artifact and a space, followed by its text. --check fails if one is
missing. Only a person can add one: the POM names the license, but does not
hold its text.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

SEPARATOR = "----"

# One dependency line of Gradle's tree, after its indentation.
TREE = re.compile(r"^[\s|]*[+\\]--- (.*?)\s*$")
# A module in it: "group:artifact[:asked][ -> resolved]". The asked version
# can be "{strictly 1.0}" or a range; the resolved one is a version, or
# "group:artifact:version" when Gradle replaced the module.
MODULE = re.compile(
    r"^([\w.\-]+):([\w.\-]+)(?::(\{[^}]*\}|[^\s{]+))?(?: -> (\S+))?$"
)
STRICTLY = re.compile(r"^\{strictly ([^\s{}]+)\}$")
# An exact version: no range, no "1.+", no "latest.release".
EXACT = re.compile(r"^\w[\w.\-+]*$")
# One line of the list on the license page.
LISTED = re.compile(r"^[\w.\-]+:[\w.\-]+ \S+: ")

# License names, exactly as the POMs write them, that combine with AGPL-3.0.
# Any other name stops the check for a person to decide: words in a name are
# not enough ("Apache 2.0 with Commons Clause", "BSD-4-Clause"; review of
# #48).
APACHE = {
    "Apache 2.0",
    "Apache-2.0",
    "Apache License 2.0",
    "Apache License, Version 2.0",
    "The Apache License, Version 2.0",
    "The Apache Software License, Version 2.0",
}
# These also need their own text on the page, with the copyright line.
OWN_TEXT = {
    "BSD-2-Clause",
    "BSD-3-Clause",
    "MIT",
    "MIT License",
    "The MIT License",
}
# A line of the Apache-2.0 text, which must be after the line "----".
APACHE_TEXT = "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"

# Groups whose POMs name no license, with where the license is stated.
KNOWN = {
    # The Flutter engine and embedding: Flutter's own LICENSE, BSD-3-Clause.
    # The engine's third-party notices are on the license page through
    # Flutter's own LicenseRegistry.
    "io.flutter": "BSD-3-Clause (Flutter)",
}


def exact(asked, resolved):
    """The version Gradle resolved, or None if the line has none."""
    if resolved:
        return resolved if EXACT.match(resolved) else None
    if asked is None:
        return None
    strictly = STRICTLY.match(asked)
    version = strictly.group(1) if strictly else asked
    if version.endswith("+") or version.startswith("latest."):
        return None
    return version if EXACT.match(version) else None


def modules(dependencies):
    """The resolved group:artifact -> version in Gradle's dependency tree,
    and the lines that do not give one."""
    found, problems = {}, []
    for raw in dependencies.splitlines():
        line = TREE.match(raw)
        if not line:
            continue  # the heading, the legend and empty lines
        body = line.group(1)
        if body.startswith("project "):
            continue  # a module of the build itself: a Flutter plugin
        if body.endswith(" (c)"):
            continue  # a constraint, not a dependency
        if body.endswith(" (*)"):
            body = body[: -len(" (*)")]
        m = MODULE.match(body)
        version = None
        if m:
            group, artifact, asked, resolved = m.groups()
            if resolved and resolved.count(":") == 2:
                group, artifact, resolved = resolved.split(":")
            version = exact(asked, resolved)
        if version is None:
            problems.append(f"no exact version in Gradle's tree: {body}")
            continue
        key = f"{group}:{artifact}"
        if found.get(key, version) != version:
            problems.append(f"two versions of {key}: {found[key]} and {version}")
        found[key] = version
    return found, problems


def pom(cache, group, artifact, version):
    """The POM's root element without namespaces, or None."""
    folder = pathlib.Path(cache) / group / artifact / version
    for path in sorted(folder.glob(f"*/{artifact}-{version}.pom")):
        root = ET.parse(path).getroot()
        for e in root.iter():
            e.tag = e.tag.split("}")[-1]
        return root
    return None


def bom(cache, group, artifact, version):
    """Whether the module is only a POM: packaging "pom", and no code."""
    root = pom(cache, group, artifact, version)
    if root is None or (root.findtext("packaging") or "").strip() != "pom":
        return False
    folder = pathlib.Path(cache) / group / artifact / version
    return not any(folder.glob("*/*.jar")) and not any(folder.glob("*/*.aar"))


def licenses(cache, group, artifact, version, depth=0):
    """License names from the POM's <licenses>, or from its parents."""
    root = pom(cache, group, artifact, version)
    if root is None or depth > 8:
        return []
    names = [
        " ".join((lic.findtext("name") or "").split())
        for lic in root.findall("./licenses/license")
    ]
    names = [n for n in names if n]
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


def listing(dependencies, cache):
    """The lines for the license page, the problems found, and the libraries
    whose license text the page must have: {group:artifact: license}, with
    "Apache-2.0" for all those under Apache-2.0."""
    found, problems = modules(dependencies)
    lines, texts = [], {}
    for key, version in sorted(found.items()):
        group, artifact = key.split(":", 1)
        if bom(cache, group, artifact, version):
            continue
        names = licenses(cache, group, artifact, version)
        if not names and group in KNOWN:
            lines.append(f"{key} {version}: {KNOWN[group]}")
            continue  # Flutter's own page has the text
        if not names:
            problems.append(f"no license found in the POM: {key} {version}")
            names = ["?"]
        for name in names:
            if name in APACHE:
                texts["Apache-2.0"] = "Apache-2.0"
            elif name in OWN_TEXT:
                texts[key] = name
            elif name != "?":
                problems.append(f"license to check: {key} {version}: {name}")
        lines.append(f"{key} {version}: {', '.join(names)}")
    if not lines:
        problems.append("Gradle's list has no libraries")
    return lines, problems, texts


def main(argv):
    if len(argv) < 4 or argv[3] not in ("--check", "--print"):
        print(__doc__, file=sys.stderr)
        return 2
    lines, problems, texts = listing(pathlib.Path(argv[1]).read_text(), argv[2])
    if argv[3] == "--print":
        print("\n".join(lines))
        for p in problems:
            print(f"problem: {p}", file=sys.stderr)
        return 0
    if len(argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    head, _, tail = pathlib.Path(argv[4]).read_text().partition(
        f"\n{SEPARATOR}\n"
    )
    listed = [l for l in head.splitlines() if LISTED.match(l)]
    for key, name in texts.items():
        if key == "Apache-2.0":
            if APACHE_TEXT not in tail:
                problems.append(
                    f"{argv[4]} has no Apache-2.0 text after the line {SEPARATOR}"
                )
        elif not any(l.startswith(f"{key} ") for l in tail.splitlines()):
            problems.append(
                f"{key} is under {name}: its text, with its copyright line, "
                f"must be after the line {SEPARATOR}, in a paragraph that "
                f"starts with '{key} '"
            )
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
