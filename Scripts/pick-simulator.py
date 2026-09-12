#!/usr/bin/env python3
"""Print the UDID of the best available iPhone simulator.

Pinning a device name in the workflow breaks every time GitHub rotates its runner images, so
the destination is resolved from what the runner actually has. But "newest" was being decided
by sorting the name as text, and text says "iPhone SE (3rd generation)" is newer than "iPhone
16 Pro" because S sorts after 1. Every screenshot in this repository was therefore taken on a
4.7-inch device with square corners and a home button, which is not what anyone holds and not
what a modern device frame fits around.

So the ranking is explicit: the newest runtime, then the highest model number, then the larger
variant, and an SE only if there is nothing else on the machine.
"""
import json
import re
import subprocess
import sys

# Larger and more modern first. A screenshot of a Pro Max is the most useful one to have,
# because every smaller layout can be inferred from it and the reverse is not true.
VARIANT_RANK = {
    "pro max": 5,
    "plus": 4,
    "pro": 3,
    "": 2,
    "mini": 1,
}


def rank(name: str) -> tuple:
    """Sortable quality of a device name. Higher is better."""
    if "SE" in name:
        # Last resort: no notch, no island, and an aspect ratio nothing else shares.
        return (0, 0, 0)

    model = re.search(r"iPhone\s+(\d+)", name)
    number = int(model.group(1)) if model else 0

    lowered = name.lower()
    variant = ""
    for candidate in ("pro max", "plus", "pro", "mini"):
        if candidate in lowered:
            variant = candidate
            break

    return (1, number, VARIANT_RANK.get(variant, 2))


def main() -> int:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    runtimes = json.loads(raw)["devices"]

    best = None
    for runtime, devices in runtimes.items():
        if "iOS" not in runtime:
            continue
        match = re.search(r"iOS[-.](\d+)[-.](\d+)", runtime)
        version = (int(match.group(1)), int(match.group(2))) if match else (0, 0)

        for device in devices:
            if not device.get("isAvailable"):
                continue
            name = device["name"]
            if not name.startswith("iPhone"):
                continue

            key = (version, rank(name), name)
            if best is None or key > best[0]:
                best = (key, device["udid"], name, runtime)

    if best is None:
        print("no available iPhone simulator on this runner", file=sys.stderr)
        return 1

    _, udid, name, runtime = best
    print(f"selected {name} ({runtime}) {udid}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
