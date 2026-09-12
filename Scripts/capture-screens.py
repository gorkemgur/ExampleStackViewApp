#!/usr/bin/env python3
"""Walk the app on a booted simulator and photograph every screen.

Screenshots are the one thing a test suite cannot give you: XCUITest proves the
elements are there, but only a picture shows whether the result is worth looking at.
Every step is tolerant — a screen that cannot be reached is reported and skipped, so
a partial walk still yields the screens it did reach.
"""
import json
import os
import subprocess
import sys
import time

UDID = sys.argv[1]
OUT_DIR = sys.argv[2]
BUNDLE_ID = "com.gorkemgur.dupespace"


def run(args, timeout=120):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def describe():
    """The accessibility tree, once idb is willing to produce one."""
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
    """Locate an element by identifier, then by exact label, then by label prefix.

    `types` restricts the search to element kinds. Without it the prefix pass happily matches
    body copy: a sentence mentioning "History" is not the History tab, and tapping it does
    nothing while the walk waits for a screen that never arrives.
    """
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


def png_size(path):
    """Pixel dimensions straight out of a PNG header."""
    with open(path, "rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[12:16] != b"IHDR":
        return None
    return (
        int.from_bytes(header[16:20], "big"),
        int.from_bytes(header[20:24], "big"),
    )


def screen_size(tree):
    """The visible screen in points.

    Width comes from the accessibility tree, which reports it honestly. Height does not: the
    tallest element extends past the bottom of the screen when a list is scrollable, so it is
    derived from a screenshot's pixel height and the scale the width implies.
    """
    width = 0
    for element in tree:
        frame = element.get("frame") or {}
        width = max(width, frame.get("x", 0) + frame.get("width", 0))
    if width <= 0:
        return None

    probe = os.path.join(OUT_DIR, "_probe.png")
    run(["xcrun", "simctl", "io", UDID, "screenshot", probe])
    size = png_size(probe) if os.path.exists(probe) else None
    if os.path.exists(probe):
        os.remove(probe)
    if size is None:
        return None

    pixel_width, pixel_height = size
    scale = pixel_width / width
    if scale <= 0:
        return None
    return width, pixel_height / scale


def tap_point(x, y, settle=2.0):
    run(["idb", "ui", "tap", "--udid", UDID, str(int(x)), str(int(y))])
    time.sleep(settle)


def swipe_up():
    run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "280"])
    time.sleep(1.0)


def shot(name):
    path = os.path.join(OUT_DIR, name)
    run(["xcrun", "simctl", "io", UDID, "screenshot", path])
    ok = os.path.exists(path) and os.path.getsize(path) > 0
    print(f"{'captured' if ok else 'MISSED  '} {name}")
    return ok


def wait_for(identifier, timeout=150):
    deadline = time.time() + timeout
    while time.time() < deadline:
        element = find(describe(), identifier)
        if element is not None:
            return element
        time.sleep(3)
    print(f"never appeared: {identifier}")
    return None


def scroll_to(identifier, attempts=8):
    """Find an element, scrolling down until it comes into view."""
    for _ in range(attempts):
        element = find(describe(), identifier)
        if element is not None:
            return element
        swipe_up()
    print(f"not reachable by scrolling: {identifier}")
    return None


def relaunch_with_fixtures():
    """Restart the app against the deterministic fixtures.

    Without the flag the app runs for real: no photo permission on a fresh simulator,
    so every screen past the permission wall is unreachable and the walk photographs
    an empty library instead of the product.
    """
    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(1)
    result = run(["xcrun", "simctl", "launch", UDID, BUNDLE_ID, "-ui-testing"])
    print("relaunch:", result.stdout.strip() or result.stderr.strip())
    time.sleep(4)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    captured = 0

    relaunch_with_fixtures()

    if wait_for("storage.headline") is None:
        print("the app never reached its root screen")
        return 1
    captured += shot("01-overview.png")
    captured += capture_live_surfaces()

    entry = scroll_to("root.scan")
    if entry is None:
        return 0 if captured else 1
    tap(entry)

    start = wait_for("scan.start", timeout=60)
    if start is None:
        return 0
    captured += shot("02-scan.png")
    tap(start)

    if wait_for("scan.total", timeout=180) is not None:
        captured += shot("03-results.png")

    review = scroll_to("scan.review")
    if review is None:
        return report(captured)

    tap(review)
    if wait_for("review.total", timeout=90) is None:
        return report(captured)
    captured += shot("04-review.png")

    delete = find(describe(), "review.delete")
    if delete is None:
        return report(captured)

    tap(delete, settle=3.0)
    if wait_for("confirm.total", timeout=60) is not None:
        captured += shot("05-confirm.png")

        # Deleting here only touches the stub library, and it is the only way to photograph
        # what the app does afterwards.
        confirm = find(describe(), "confirm.delete")
        if confirm is not None:
            tap(confirm, settle=4.0)
            if wait_for("review.result", timeout=60) is not None:
                captured += shot("06-deleted.png")
                captured += capture_history()

    return report(captured)


EXPECTED = [
    "01-overview.png", "01b-live-surfaces.png", "02-scan.png", "03-results.png",
    "04-review.png", "05-confirm.png", "06-deleted.png", "07-history.png", "08-receipt.png",
]


def report(captured):
    """Say what came out, and name what did not.

    A partial walk used to be invisible: the screens it reached were committed over the old
    ones, the screens it did not were left behind, and the page ended up showing two different
    designs of the same app beside each other. Saying so is what makes that impossible to miss.
    """
    missing = [name for name in EXPECTED if not os.path.exists(os.path.join(OUT_DIR, name))]
    print(f"captured {captured} screens")
    if missing:
        print("MISSING " + " ".join(missing))
        return 2
    print("every expected screen was captured")
    return 0


def capture_live_surfaces():
    """The Lock Screen and Dynamic Island presentations.

    No simulator will show a Live Activity, so the app renders the same views on a screen of
    its own under `-ui-testing`. This is the only picture anyone gets of them.
    """
    entry = find(describe(), "root.livesurfaces")
    if entry is None:
        print("no live-surfaces entry on the overview")
        return 0

    tap(entry, settle=2.0)
    if wait_for("livepreview.close", timeout=30) is None:
        return 0

    captured = shot("01b-live-surfaces.png")

    close = find(describe(), "livepreview.close")
    if close is not None:
        tap(close, settle=1.5)
    return captured


def pop_to_overview(limit=4):
    """Walk back up the navigation stack until the overview's History control is in reach.

    History used to be a tab, reachable from anywhere; it is now a destination off the
    overview, so the walk has to come back for it the way a person would.
    """
    for _ in range(limit):
        tree = describe()
        if find(tree, "history.open") is not None:
            return True
        # Exact labels only. `find` falls back to a prefix match, and "Review" would happily
        # match the "Review and choose" button on the results screen — walking deeper into the
        # stack rather than back out of it.
        back = next(
            (
                element
                for element in tree
                if element.get("type") == "Button"
                and element.get("AXLabel") in ("Find duplicates", "Review", "DupeSpace", "Back")
            ),
            None,
        )
        if back is None:
            return False
        tap(back, settle=1.5)
    return find(describe(), "history.open") is not None


def capture_history():
    """The receipt, which only exists once something has actually been deleted."""
    if not pop_to_overview():
        print("could not get back to the overview to open History")
        return 0

    entry = find(describe(), "history.open")
    if entry is None:
        print("no History control on the overview")
        return 0
    tap(entry, settle=2.5)

    if wait_for("history.total", timeout=40) is None:
        return 0

    captured = shot("07-history.png")

    receipt = find(describe(), "history.deletion.headline")
    if receipt is not None:
        tap(receipt, settle=2.0)
        captured += shot("08-receipt.png")

    return captured


if __name__ == "__main__":
    raise SystemExit(main())
