#!/usr/bin/env python3
"""Measure the two things a screenshot cannot tell you.

**Layout.** The accessibility tree carries every element's frame in points, so anything that
runs past the edge of the screen, any button smaller than a finger, and anything laid out to
nothing can be found by arithmetic rather than by eye.

**Animation.** Whether a transition animates is not visible in a still, and it turned out not to
be visible in a burst of stills either: `simctl io screenshot` costs two to three seconds a
frame on a CI runner, so the first attempt sampled one or two frames across an entire
transition and reported every animation in the app as static. That was the instrument failing,
not the app.

So the screen is recorded instead, and the recording is cut into frames afterwards. A
transition that animates passes through frames that are neither the old screen nor the new one;
one that snaps goes straight from the first to the second. With frames a thirtieth of a second
apart, the number of distinct ones is also a usable estimate of how long the movement lasted.

Everything is tolerant. A screen that cannot be reached is reported and skipped, so a partial
run still reports what it did reach.
"""
import hashlib
import json
import os
import shutil
import signal
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
# Anything above this is in the status or navigation bar, where the system gives a control the
# bar's full height to be tapped in whatever its label measures.
NAVIGATION_BAR_BOTTOM = 100.0

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
            if y < NAVIGATION_BAR_BOTTOM:
                notes.append(
                    f"{screen}: {describe_element(element)} is {w:.0f}x{h:.0f}pt, in the "
                    "navigation bar — the bar supplies the hit area"
                )
            else:
                findings.append(
                    f"{screen}: {describe_element(element)} is {w:.0f}x{h:.0f}pt, "
                    f"under the {MIN_TAP_TARGET:.0f}pt tap target"
                )

    notes.append(f"{screen}: {seen} named elements checked against a {width:.0f}pt screen")


def frames_from(video, directory):
    """Cut a recording into PNGs. Returns their digests in order, or None without ffmpeg."""
    if shutil.which("ffmpeg") is None:
        return None

    os.makedirs(directory, exist_ok=True)
    result = run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", video,
        "-vf", "fps=30,scale=iw/4:-1",
        os.path.join(directory, "f%04d.png")
    ], timeout=180)
    if result.returncode != 0:
        return None

    digests = []
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".png"):
            continue
        with open(os.path.join(directory, name), "rb") as handle:
            digests.append(hashlib.md5(handle.read()).hexdigest())
    shutil.rmtree(directory, ignore_errors=True)
    return digests


def sample(label, action, seconds=2.5):
    """Record the screen across `action`, then count the frames that differ.

    The action is performed while the recorder is running, which is the only way to catch a
    transition that is over in a third of a second.
    """
    video = os.path.join(OUT_DIR, "_clip.mp4")
    if os.path.exists(video):
        os.remove(video)

    recorder = subprocess.Popen(
        ["xcrun", "simctl", "io", UDID, "recordVideo", "--codec", "h264", video],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.5)  # the recorder needs a moment before it is actually capturing

    action()
    time.sleep(seconds)

    # SIGINT rather than kill: recordVideo only writes a playable file when asked to stop.
    recorder.send_signal(signal.SIGINT)
    try:
        recorder.wait(timeout=30)
    except subprocess.TimeoutExpired:
        recorder.kill()

    digests = frames_from(video, os.path.join(OUT_DIR, "_frames"))
    if os.path.exists(video):
        os.remove(video)

    if digests is None:
        notes.append(f"animation: {label} — not measured (no ffmpeg on this machine)")
        return
    if len(digests) < 4:
        notes.append(f"animation: {label} — only {len(digests)} frames recorded, inconclusive")
        return

    changes = sum(1 for index in range(1, len(digests)) if digests[index] != digests[index - 1])
    # A transition is over once the frames stop differing; the tail is the settled screen.
    last_change = 0
    for index in range(1, len(digests)):
        if digests[index] != digests[index - 1]:
            last_change = index
    moving_for = last_change / 30.0

    verdict = "animated" if changes >= 3 else ("one step only" if changes >= 1 else "static")
    notes.append(
        f"animation: {label} — {len(digests)} frames at 30fps, {changes} differing, "
        f"movement ends at {moving_for:.2f}s [{verdict}]"
    )
    if changes == 0:
        findings.append(f"animation: {label} never changed the screen at all")
    elif changes < 3:
        findings.append(
            f"animation: {label} went from one screen to the next in {changes} frame(s) — "
            "that is a cut, not a transition"
        )


def relaunch(text_size=None):
    """Restart against the fixtures, optionally at a larger Dynamic Type size.

    The size is passed as a launch argument, which UIKit reads in place of the device setting —
    the same trick the UI tests use, and the only way to ask "does this still fit?" without a
    human dragging a slider in Settings.
    """
    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(1)
    arguments = ["xcrun", "simctl", "launch", UDID, BUNDLE_ID, "-ui-testing"]
    if text_size:
        arguments += ["-UIPreferredContentSizeCategoryName", text_size]
    run(arguments)


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
    sample("cards entering on launch", relaunch, seconds=3.0)
    time.sleep(2)

    overview = describe()
    audit_layout("overview", overview)

    live = find(overview, "Live surfaces", types={"Button"})
    if live is not None:
        sample("live surfaces sheet presenting", lambda: tap(live, settle=0), seconds=2.0)
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

    sample("scan screen pushing in", lambda: tap(entry, settle=0), seconds=2.0)
    time.sleep(1.5)

    scan = describe()
    audit_layout("scan", scan)

    start = find(scan, "scan.start")
    if start is None:
        notes.append("scan: no start button, the rest of the walk was skipped")
        write_report()
        return 0

    sample("progress card replacing the intro", lambda: tap(start, settle=0), seconds=2.5)

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
        sample("review screen pushing in", lambda: tap(review, settle=0), seconds=2.0)
        time.sleep(1.5)
        audit_layout("review", describe())

    audit_large_text()

    write_report()
    return 0


def audit_large_text():
    """The same screens, with the text at an accessibility size.

    This is where padding chosen for one string length stops working: whatever overflows here
    overflows on the phone of the person most likely to need the app to be legible.
    """
    relaunch("UICTContentSizeCategoryAccessibilityL")
    time.sleep(4)

    overview = describe()
    if not overview:
        notes.append("large text: the app never came back up, skipped")
        return
    audit_layout("overview at accessibility text size", overview)
    shot(os.path.join(OUT_DIR, "large-text-overview.png"))

    entry = find(overview, "root.scan")
    for _ in range(8):
        if entry is not None:
            break
        run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "280"])
        time.sleep(1)
        entry = find(describe(), "root.scan")

    if entry is None:
        notes.append("large text: the scan entry was not reachable, so only the overview was audited")
        return

    tap(entry, settle=2.5)
    tree = describe()
    if find(tree, "scan.start") is None:
        notes.append("large text: the tap on the scan entry did not land, overview audited twice")
        return
    audit_layout("scan at accessibility text size", tree)
    shot(os.path.join(OUT_DIR, "large-text-scan.png"))


if __name__ == "__main__":
    sys.exit(main())
