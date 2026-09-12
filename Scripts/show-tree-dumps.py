#!/usr/bin/env python3
"""Print every accessibility-tree dump the walk left behind.

The walk writes one of these wherever it looks for a control and does not find it. They were
going into the artifacts and into the middle of a three-thousand-line log, which is the same
as not writing them: the part of a CI log anyone reads is the bottom.
"""
import glob
import json
import os
import sys


def main() -> int:
    directory = sys.argv[1] if len(sys.argv) > 1 else "artifacts/screens"
    dumps = sorted(glob.glob(os.path.join(directory, "tree-*.json")))
    if not dumps:
        print("no tree dumps — every lookup the walk made was satisfied")
        return 0

    for dump in dumps:
        print(f"::group::{os.path.basename(dump)}")
        try:
            with open(dump) as handle:
                tree = json.load(handle)
        except (OSError, json.JSONDecodeError) as error:
            print(f"unreadable: {error}")
            print("::endgroup::")
            continue

        print(f"{len(tree)} elements")
        for element in tree:
            identifier = element.get("AXUniqueId")
            label = element.get("AXLabel")
            if not identifier and not label:
                continue
            frame = element.get("frame") or {}
            print(
                f"  {element.get('type')}: id={identifier!r} label={label!r} "
                f"at ({frame.get('x')},{frame.get('y')}) {frame.get('width')}x{frame.get('height')}"
            )
        print("::endgroup::")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
