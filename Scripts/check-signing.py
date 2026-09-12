#!/usr/bin/env python3
"""Refuse a `project.yml` that switches code signing off for a shippable target.

Every destination in the workflow is a simulator, and a simulator installs an unsigned `.app`
without complaint. A phone does not. So `CODE_SIGNING_ALLOWED: NO` sat in the app's and the
widget's Debug configuration for weeks: harmless for everything CI does, and fatal for the one
thing it never does, which is press Run with a device plugged in.

CI cannot prove device signing works — that needs a team and a certificate the runner has
none of. What it can prove is that nobody has switched signing off again, and that is the
whole of the regression.

The test bundles are a different case and stay exempt: they are never installed on anything
but a simulator, and they are not shipped.
"""
import re
import sys

SHIPPABLE = {"DupeSpace", "DupeSpaceWidgets"}
OFFENDING = re.compile(r"CODE_SIGNING_(?:ALLOWED|REQUIRED)\s*:\s*NO\b")
TOP_LEVEL_KEY = re.compile(r"^  ([A-Za-z_][\w-]*):\s*$")


def main(path: str = "project.yml") -> int:
    target = None
    found = []
    for number, line in enumerate(open(path).read().splitlines(), 1):
        key = TOP_LEVEL_KEY.match(line)
        if key:
            target = key.group(1)
        elif OFFENDING.search(line) and target in SHIPPABLE:
            found.append((number, target, line.strip()))

    if found:
        for number, target, text in found:
            print(f"::error file={path},line={number}::{target} disables signing: {text}")
        print(
            "A simulator does not care and a phone does. Signing must stay on for both "
            "shippable targets in every configuration — see docs/RUN-ON-YOUR-PHONE.md."
        )
        return 1

    print(f"signing is left on for {', '.join(sorted(SHIPPABLE))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
