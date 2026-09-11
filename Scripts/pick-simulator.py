#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator.

Pinning a device name in the workflow breaks every time GitHub rotates its runner images,
so the destination is resolved from what the runner actually has.
"""
import json
import re
import subprocess
import sys


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
            if not device["name"].startswith("iPhone"):
                continue
            key = (version, device["name"])
            if best is None or key > best[0]:
                best = (key, device["udid"], device["name"], runtime)

    if best is None:
        print("no available iPhone simulator on this runner", file=sys.stderr)
        return 1

    _, udid, name, runtime = best
    print(f"selected {name} ({runtime}) {udid}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
