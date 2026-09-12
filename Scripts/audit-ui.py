#!/usr/bin/env python3
"""Measure the two things a screenshot cannot tell you.

**Layout.** The accessibility tree carries every element's frame in points, so anything that
runs past the edge of the screen, any button smaller than a finger, and anything laid out to
nothing can be found by arithmetic rather than by eye.

**Animation.** Whether a transition animates is not visible in a still. Screenshots taken in a
burst are: a transition that animates passes through frames that are neither the old screen nor
the new one, and one that snaps goes straight from the first to the second. The sampler runs as
fast as `simctl` will produce a frame — a few per second — so a short animation may show only
one or two intermediate frames. That is enough to tell moving from snapping; it is not enough
to measure a duration, and this script does not claim to.

Everything is tolerant. A screen that cannot be reached is reported and skipped, so a partial
run still reports what it did reach.
"""
import hashlib
import json
import os
import subprocess
import sys
import time

UDID = sys.argv[1]
OUT_DIR = sys.argv[2]
BUNDLE_ID = "com.gorkemgur.dupespace"

# Apple's own minimum for anything a finger has to hit.
MIN_TAP_TARGET = 44.0
# The tree reports fractional frames; a point of slack keeps rounding out of the findings.
EDGE_SLACK = 1.0

findings = []
notes = []


def run(args, timeout=120):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def describe():
    for _ in range(20):
        result = run(["idb", "ui", "describe-all", "--udid", UDID])
        if result.returncode == 0 and result.stdout.strip():
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                pass
        time.sleep(3)
    return []


def find(tree, identifier, types=None):
    def allowed(element):
        return types is None or element.get("type") in types

    for element in tree:
        if allowed(element) and element.get("AXUniqueId") == identifier:
            return element
    for element in tree:
        if allowed(element) and element.get("AXLabel") == identifier:
            return element

    needle = identifier.lower()
    for element in tree:
        label = element.get("AXLabel")
        if allowed(element) and isinstance(label, str) and label.lower().startswith(needle):
            return element
    return None


def center(element):
    frame = element.get("frame") or {}
    return (
        int(frame.get("x", 0) + frame.get("width", 0) / 2),
        int(frame.get("y", 0) + frame.get("height", 0) / 2),
    )


def tap(element, settle=2.0):
    x, y = center(element)
    run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
    time.sleep(settle)


def shot(path):
    run(["xcrun", "simctl", "io", UDID, "screenshot", path])
    return os.path.exists(path) and os.path.getsize(path) > 0


def frame_hash():
    """One frame of the display, as a digest. Identical frames hash identically."""
    path = os.path.join(OUT_DIR, "_frame.png")
    if not shot(path):
        return None
    with open(path, "rb") as handle:
        digest = hashlib.md5(handle.read()).hexdigest()
    os.remove(path)
    return digest


def screen_width(tree):
    width = 0
    for element in tree:
        frame = element.get("frame") or {}
        width = max(width, frame.get("x", 0) + frame.get("width", 0))
    return width


def describe_element(element):
    label = element.get("AXLabel") or element.get("AXUniqueId") or "(unlabelled)"
    if len(label) > 48:
        label = label[:45] + "…"
    return f"{element.get('type', '?')} \"{label}\""


def audit_layout(screen, tree):
    """Frames, against the screen they have to fit inside."""
    width = screen_width(tree)
    if width <= 0:
        notes.append(f"{screen}: no usable accessibility tree, layout not audited")
        return

    seen = 0
    for element in tree:
        frame = element.get("frame") or {}
        x, y = frame.get("x", 0), frame.get("y", 0)
        w, h = frame.get("width", 0), frame.get("height", 0)
        kind = element.get("type")
        label = element.get("AXLabel")

        # Elements with no label and no identifier are containers the app never named; their
        # frames are the system's business, not the app's.
        if not label and not element.get("AXUniqueId"):
            continue
        seen += 1

        if w <= 0 or h <= 0:
            findings.append(f"{screen}: {describe_element(element)} lays out to nothing ({w}x{h})")
            continue

        if x < -EDGE_SLACK:
            findings.append(
                f"{screen}: {describe_element(element)} starts {abs(x):.0f}pt off the left edge"
            )
        if x + w > width + EDGE_SLACK:
            findings.append(
                f"{screen}: {describe_element(element)} runs {x + w - width:.0f}pt "
                f"past the right edge ({width:.0f}pt)"
            )

        if kind == "Button" and (w < MIN_TAP_TARGET or h < MIN_TAP_TARGET):
            findings.append(
                f"{screen}: {describe_element(element)} is {w:.0f}x{h:.0f}pt, "
                f"under the {MIN_TAP_TARGET:.0f}pt tap target"
            )

    notes.append(f"{screen}: {seen} named elements checked against a {width:.0f}pt screen")


def sample(label, seconds=2.0, interval=0.0):
    """Hash every frame the display will give us for a while.

    `interval` is a floor, not a cadence: a screenshot takes as long as it takes.
    """
    started = time.time()
    frames = []
    while time.time() - started < seconds:
        digest = frame_hash()
        if digest is not None:
            frames.append((time.time() - started, digest))
        if interval:
            time.sleep(interval)

    if not frames:
        notes.append(f"animation: {label} produced no frames")
        return

    distinct = []
    for _, digest in frames:
        if not distinct or distinct[-1] != digest:
            distinct.append(digest)

    changes = len(distinct) - 1
    last_change = 0.0
    for index in range(1, len(frames)):
        if frames[index][1] != frames[index - 1][1]:
            last_change = frames[index][0]

    verdict = "moving" if changes >= 2 else ("one step only" if changes == 1 else "static")
    notes.append(
        f"animation: {label} — {len(frames)} frames sampled over {frames[-1][0]:.1f}s, "
        f"{changes} change(s), settled at {last_change:.1f}s [{verdict}]"
    )
    if changes == 0:
        findings.append(f"animation: {label} never changed the screen at all")


def relaunch():
    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(1)
    run(["xcrun", "simctl", "launch", UDID, BUNDLE_ID, "-ui-testing"])


def write_report():
    lines = ["# UI audit", ""]
    lines.append("Layout is measured from the accessibility tree; animation from a burst of")
    lines.append("screenshots. See `Scripts/audit-ui.py` for what each number can and cannot say.")
    lines.append("")

    lines.append(f"## Findings ({len(findings)})")
    lines.append("")
    if findings:
        lines.extend(f"- {item}" for item in findings)
    else:
        lines.append("- Nothing overflowed, nothing was untappable, nothing failed to move.")
    lines.append("")

    lines.append("## Measurements")
    lines.append("")
    lines.extend(f"- {note}" for note in notes)
    lines.append("")

    path = os.path.join(OUT_DIR, "ui-audit.md")
    with open(path, "w") as handle:
        handle.write("\n".join(lines))
    print("\n".join(lines))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # The entrance animation happens once, on the first paint after launch.
    relaunch()
    sample("cards entering on launch", seconds=2.5)
    time.sleep(2)

    overview = describe()
    audit_layout("overview", overview)

    live = find(overview, "Live surfaces", types={"Button"})
    if live is not None:
        x, y = center(live)
        run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
        sample("live surfaces sheet presenting", seconds=2.0)
        time.sleep(1.5)
        sheet = describe()
        audit_layout("live surfaces", sheet)
        close = find(sheet, "livepreview.close", types={"Button"})
        if close is not None:
            tap(close, settle=1.5)
    else:
        notes.append("live surfaces: no entry point found, skipped")

    entry = find(describe(), "root.scan")
    for _ in range(8):
        if entry is not None:
            break
        run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "280"])
        time.sleep(1)
        entry = find(describe(), "root.scan")

    if entry is None:
        notes.append("scan: never reached, the rest of the walk was skipped")
        write_report()
        return 0

    x, y = center(entry)
    run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
    sample("scan screen pushing in", seconds=2.0)
    time.sleep(1.5)

    scan = describe()
    audit_layout("scan", scan)

    start = find(scan, "scan.start")
    if start is None:
        notes.append("scan: no start button, the rest of the walk was skipped")
        write_report()
        return 0

    x, y = center(start)
    run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
    sample("progress card replacing the intro", seconds=2.5)

    # The scan itself is the longest wait in the app; sample the tail of it so the results
    # transition is caught rather than guessed at.
    deadline = time.time() + 180
    while time.time() < deadline and find(describe(), "scan.total") is None:
        time.sleep(2)

    results = describe()
    audit_layout("results", results)

    review = find(results, "scan.review")
    for _ in range(8):
        if review is not None:
            break
        run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "280"])
        time.sleep(1)
        review = find(describe(), "scan.review")

    if review is not None:
        x, y = center(review)
        run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
        sample("review screen pushing in", seconds=2.0)
        time.sleep(1.5)
        audit_layout("review", describe())

    write_report()
    return 0


if __name__ == "__main__":
    sys.exit(main())
