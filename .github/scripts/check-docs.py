#!/usr/bin/env python3
"""The quick check for documentation (ci.yml, job "changes").

Every relative link in the given Markdown files must point to a file or
directory that exists in the checkout. Links to web pages, e-mail
addresses and anchors on the same page are not checked. Prints one line
per broken link and exits with 1 if there is any.

Usage: check-docs.py FILE.md ...
"""
import pathlib
import re
import sys

# [text](target) and [text](target "title"), not images' alt text rules.
LINK = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
FENCE = re.compile(r"^\s*(```|~~~)")


def links(text):
    in_fence = False
    for number, line in enumerate(text.splitlines(), start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        # Inline code may hold example links.
        line = re.sub(r"`[^`]*`", "", line)
        for match in LINK.finditer(line):
            yield number, match.group(1)


def main(paths):
    root = pathlib.Path.cwd().resolve()
    broken = 0
    for name in paths:
        path = pathlib.Path(name)
        if path.suffix.lower() != ".md" or not path.is_file():
            continue
        for number, target in links(path.read_text(encoding="utf-8")):
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
                continue
            file_part = target.split("#", 1)[0]
            if not file_part:
                continue
            resolved = (path.parent / file_part).resolve()
            if root not in resolved.parents and resolved != root:
                print(f"{name}:{number}: link outside the repository: {target}")
                broken += 1
            elif not resolved.exists():
                print(f"{name}:{number}: broken link: {target}")
                broken += 1
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
