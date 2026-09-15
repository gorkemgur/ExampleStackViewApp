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

# Kept in step with `OnboardingPage.all`, which `OnboardingTests` pins at four.
ONBOARDING_PAGES = [1, 2, 3, 4]

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


def screen_width(tree):
    width = 0
    for element in tree:
        frame = element.get("frame") or {}
        width = max(width, frame.get("x", 0) + frame.get("width", 0))
    return width


def screen_height(tree):
    """The visible screen in points.

    The tree cannot say: the tallest element of a scroll view extends well past the bottom of
    the glass. So it comes from a screenshot's pixel height and the scale the honest width
    implies.
    """
    width = screen_width(tree)
    if width <= 0:
        return None
    probe = os.path.join(OUT_DIR, "_probe.png")
    if not shot(probe):
        return None
    try:
        with open(probe, "rb") as handle:
            header = handle.read(24)
    except OSError:
        return None
    finally:
        os.remove(probe)
    if len(header) < 24 or header[12:16] != b"IHDR":
        return None
    pixel_width = int.from_bytes(header[16:20], "big")
    pixel_height = int.from_bytes(header[20:24], "big")
    scale = pixel_width / width
    return pixel_height / scale if scale > 0 else None


def is_on_glass(element, height):
    """Is this element's centre actually on the screen, rather than merely in the tree?

    idb reports the elements a scroll view has scrolled past the bottom of the glass with the
    frame they *would* have, `find` hands one of those back quite happily, and `tap` then taps
    a coordinate the screen does not have — which the simulator discards in silence. That is
    why this report said the live surfaces sheet "never changed the screen at all": it was not
    a missing animation, it was a tap a thousand points below the glass.
    """
    if height is None:
        return True
    frame = element.get("frame") or {}
    middle = frame.get("y", 0) + frame.get("height", 0) / 2
    return 100 <= middle <= height - 40


def swipe(from_y, to_y):
    run(["idb", "ui", "swipe", "--udid", UDID, "200", str(from_y), "200", str(to_y)])
    time.sleep(1.0)


def content_offset(tree):
    """How far the screen has been scrolled, read off the tree.

    The topmost named element's y is as good a ruler as any: nothing else moves it.
    """
    tops = [
        (element.get("frame") or {}).get("y")
        for element in tree
        if element.get("AXLabel") or element.get("AXUniqueId")
    ]
    tops = [y for y in tops if isinstance(y, (int, float))]
    return min(tops) if tops else None


def scroll_to(identifier, attempts=30, stalls_allowed=2):
    """Find an element and bring it onto the glass, so that tapping it means something.

    Scrolls until the content stops moving rather than a fixed number of times: a counted
    swipe is a bet on the length of the screen, and screens get longer. See the same
    function in `Scripts/capture-screens.py`, where that bet came due.
    """
    previous = None
    stalled = 0
    for _ in range(attempts):
        tree = describe()
        element = find(tree, identifier)
        if element is not None and is_on_glass(element, screen_height(tree)):
            return element

        offset = content_offset(tree)
        if previous is not None and offset is not None and abs(offset - previous) < 1:
            stalled += 1
            if stalled >= stalls_allowed:
                return None
        else:
            stalled = 0
        previous = offset
        swipe(620, 280)

    return None


def scroll_to_top(swipes=10):
    for _ in range(swipes):
        swipe(280, 620)


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

        # The same point of slack the edge checks already take, and for the same reason. A
        # control given `minHeight: 44` came back as 43.7 on a 3x screen and the report said
        # "44x44pt, under the 44pt tap target" — a finding that reads as a bug in the report,
        # because it is one. Printed to a decimal now, so a real violation still reads as 32.0
        # rather than as another rounding.
        if kind == "Button" and (
            w < MIN_TAP_TARGET - EDGE_SLACK or h < MIN_TAP_TARGET - EDGE_SLACK
        ):
            if y < NAVIGATION_BAR_BOTTOM:
                notes.append(
                    f"{screen}: {describe_element(element)} is {w:.1f}x{h:.1f}pt, in the "
                    "navigation bar — the bar supplies the hit area"
                )
            else:
                findings.append(
                    f"{screen}: {describe_element(element)} is {w:.1f}x{h:.1f}pt, "
                    f"under the {MIN_TAP_TARGET:.0f}pt tap target"
                )

    notes.append(f"{screen}: {seen} named elements checked against a {width:.0f}pt screen")


def frames_from(video):
    """Read a recording as one brightness grid per frame, in order.

    AVFoundation rather than ffmpeg: the runner has no ffmpeg, and every machine that can build
    this app already has the framework that reads video frames. Returns None when it cannot be
    read, which is reported as "not measured" rather than as "nothing moved".
    """
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frame-digests.swift")
    if not (os.path.exists(script) and shutil.which("swift") is not None):
        return None

    result = run(["swift", script, video], timeout=300)
    if result.returncode != 0 or not result.stdout.strip():
        print("frame-digests failed:", (result.stderr or "").strip()[:400])
        return None

    frames = []
    for line in result.stdout.strip().splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        cells = parts[1]
        frames.append([int(cells[i:i + 2], 16) for i in range(0, len(cells), 2)])
    return frames or None


def difference(before, after):
    """Mean absolute difference between two frames, in brightness levels out of 255."""
    if not before or len(before) != len(after):
        return 0.0
    return sum(abs(a - b) for a, b in zip(before, after)) / len(before)


# H.264 decodes a still screen slightly differently from frame to frame. Averaged over a
# sixteenth of the screen that noise lands well under one brightness level, while anything the
# eye would call movement is far above it. Without this floor every recording of a static
# screen reads as an animation.
NOISE_FLOOR = 1.5

# A navigation push lasts roughly a third of a second. Below this many frames a second the
# recording holds one or two samples of it, which is not enough to tell a transition from a
# cut — and a report that cannot tell should say so rather than pick one.
RESOLVABLE_FPS = 15.0


def sample(label, action, seconds=2.5):
    """Record the screen across `action`, then measure how much of it moved.

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

    frames = frames_from(video)
    if os.path.exists(video):
        os.remove(video)

    if frames is None:
        notes.append(f"animation: {label} — not measured (no frame reader on this machine)")
        return
    if len(frames) < 4:
        notes.append(f"animation: {label} — only {len(frames)} frames recorded, inconclusive")
        return

    # Frames per second, measured from the clip rather than assumed: the recorder gives what
    # the simulator can produce, which on a loaded runner is not 30.
    fps = len(frames) / max(seconds + 1.5, 0.001)

    deltas = [difference(frames[i - 1], frames[i]) for i in range(1, len(frames))]
    moving = [delta > NOISE_FLOOR for delta in deltas]
    changes = sum(moving)
    peak = max(deltas) if deltas else 0.0

    # A transition is over once the frames stop moving; the tail is the settled screen.
    last_change = 0
    for index, is_moving in enumerate(moving, start=1):
        if is_moving:
            last_change = index
    moving_for = last_change / max(fps, 1.0)

    verdict = "animated" if changes >= 3 else ("one step only" if changes >= 1 else "static")
    notes.append(
        f"animation: {label} — {len(frames)} frames at ~{fps:.0f}fps, {changes} moving "
        f"(peak {peak:.1f} levels), last movement at {moving_for:.2f}s [{verdict}]"
    )
    if changes == 0:
        findings.append(f"animation: {label} never changed the screen at all")
    elif changes < 3 and fps < RESOLVABLE_FPS:
        # Not a finding, because the clip could not have shown one either way. A push lasts
        # about a third of a second; below fifteen frames a second that is one or two samples,
        # so "one step only" is a statement about the recorder on a loaded runner and not about
        # the app. Saying "cut" here would be the report inventing a defect.
        notes.append(
            f"animation: {label} — at ~{fps:.0f}fps the clip cannot resolve a transition, "
            "so the step count says nothing"
        )
    elif changes < 3:
        findings.append(
            f"animation: {label} went from one screen to the next in {changes} frame(s) — "
            "that is a cut, not a transition"
        )


def relaunch(text_size=None, extra=None):
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
    if extra:
        arguments += extra
    run(arguments)


def write_report():
    lines = ["# UI audit", ""]
    lines.append("Layout is measured from the accessibility tree; animation from a screen")
    lines.append("recording taken across each transition and read frame by frame. See")
    lines.append("`Scripts/audit-ui.py` for what each number can and cannot say.")
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

    # Scrolled to rather than looked for in place: the entry is the last thing on the overview.
    live = scroll_to("root.livesurfaces")
    if live is not None:
        sample("live surfaces sheet presenting", lambda: tap(live, settle=0), seconds=2.0)
        time.sleep(1.5)
        sheet = describe()
        audit_layout("live surfaces", sheet)
        close = find(sheet, "livepreview.close")
        if close is not None:
            tap(close, settle=1.5)
    else:
        notes.append("live surfaces: no entry point found, skipped")

    # Everything after this looks for its control by scrolling *down*, and the overview is now
    # at the bottom.
    scroll_to_top()

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
    audit_onboarding()

    write_report()
    return 0


def audit_onboarding():
    """The first screen anybody sees, which `-ui-testing` otherwise hides.

    Suppressing onboarding under test is not optional — every UI test and this walk launch into
    what looks like a fresh install and would stop on its first page. `-onboarding` asks for it
    back, passed alongside `-ui-testing` rather than instead of it. Without this step it would
    be the one screen in the app that ships unmeasured.

    Last in the walk on purpose: it restarts the app into a modal cover, which is not a state
    anything after it could be audited from.
    """
    relaunch(extra=["-onboarding"])
    time.sleep(2.5)

    for page in range(len(ONBOARDING_PAGES)):
        tree = describe()
        if find(tree, "onboarding.title") is None:
            notes.append(
                f"onboarding: page {page + 1} was never reached — the screen did not present, "
                "or -onboarding is not wired to the gate"
            )
            return
        audit_layout(f"onboarding page {page + 1}", tree)
        shot(os.path.join(OUT_DIR, f"onboarding-{page + 1}.png"))

        key = find(tree, "onboarding.primary")
        if key is None:
            notes.append(f"onboarding: page {page + 1} has no primary control")
            return
        # Not past the last page: its key raises the photo permission alert, which no simulator
        # walk can answer and which would leave every screenshot after it behind a system sheet.
        if page == len(ONBOARDING_PAGES) - 1:
            break
        sample(f"onboarding page {page + 1} to {page + 2}", lambda: tap(key, settle=0), seconds=2.0)

    relaunch()


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

    tap(entry, settle=3.0)
    tree = describe()
    for _ in range(4):
        if find(tree, "scan.start") is not None:
            break
        run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "280"])
        time.sleep(1)
        tree = describe()

    if find(tree, "scan.start") is None:
        notes.append("large text: the scan screen was never reached, only the overview audited")
        return
    audit_layout("scan at accessibility text size", tree)
    shot(os.path.join(OUT_DIR, "large-text-scan.png"))


if __name__ == "__main__":
    sys.exit(main())
