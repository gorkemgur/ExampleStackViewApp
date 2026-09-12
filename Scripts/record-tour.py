#!/usr/bin/env python3
"""Two tours of the app, recorded end to end.

`record-deletion.py` films one instrument. This films the product: the whole path somebody
walks, twice, against the two libraries that matter.

  found  — the fixture with duplicates in it. Overview, scan, what it found, the review ladder,
           a plan, the confirmation and the deletion.
  clean  — the same library with nothing in it that matches anything. The scan does all of its
           real work and honestly finds nothing, which is the state this app is least often
           looked at in and the one a new user is most likely to be in.

Both are capped: a tour that runs long is a tour nobody watches to the end, and a GIF that runs
long is a GIF nobody loads.

  python3 Scripts/record-tour.py <udid> <out dir> [seconds]
"""
import json
import os
import signal
import subprocess
import sys
import time

UDID = sys.argv[1]
OUT_DIR = sys.argv[2]
BUDGET = float(sys.argv[3]) if len(sys.argv) > 3 else 19.0
BUNDLE_ID = "com.gorkemgur.dupespace"


def run(args, timeout=180):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def describe():
    for _ in range(20):
        result = run(["idb", "ui", "describe-all", "--udid", UDID])
        if result.returncode == 0 and result.stdout.strip():
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                pass
        time.sleep(2)
    return []


def find(tree, identifier):
    for element in tree:
        if element.get("AXUniqueId") == identifier:
            return element
    for element in tree:
        if element.get("AXLabel") == identifier:
            return element
    return None


def screen_height(tree):
    """The visible screen in points — see `capture-screens.py` for why the tree cannot say."""
    width = max((e.get("frame") or {}).get("x", 0) + (e.get("frame") or {}).get("width", 0) for e in tree) if tree else 0
    if width <= 0:
        return None
    probe = os.path.join(OUT_DIR, "_probe.png")
    run(["xcrun", "simctl", "io", UDID, "screenshot", probe])
    if not os.path.exists(probe):
        return None
    with open(probe, "rb") as handle:
        header = handle.read(24)
    os.remove(probe)
    if len(header) < 24 or header[12:16] != b"IHDR":
        return None
    pixel_width = int.from_bytes(header[16:20], "big")
    pixel_height = int.from_bytes(header[20:24], "big")
    scale = pixel_width / width
    return pixel_height / scale if scale > 0 else None


def on_glass(element, height):
    if height is None:
        return True
    frame = element.get("frame") or {}
    middle = frame.get("y", 0) + frame.get("height", 0) / 2
    return 100 <= middle <= height - 40


def tap(element, settle=1.2):
    frame = element.get("frame") or {}
    x = int(frame.get("x", 0) + frame.get("width", 0) / 2)
    y = int(frame.get("y", 0) + frame.get("height", 0) / 2)
    run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
    time.sleep(settle)


def swipe(from_y, to_y, settle=0.8):
    run(["idb", "ui", "swipe", "--udid", UDID, "200", str(from_y), "200", str(to_y)])
    time.sleep(settle)


def wait_for(identifier, timeout=90):
    deadline = time.time() + timeout
    while time.time() < deadline:
        element = find(describe(), identifier)
        if element is not None:
            return element
        time.sleep(2)
    print(f"  never appeared: {identifier}")
    return None


def reach(identifier, attempts=8):
    for _ in range(attempts):
        tree = describe()
        element = find(tree, identifier)
        if element is not None and on_glass(element, screen_height(tree)):
            return element
        swipe(620, 280)
    print(f"  not reachable: {identifier}")
    return None


def launch(clean):
    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(1)
    arguments = ["xcrun", "simctl", "launch", UDID, BUNDLE_ID, "-ui-testing"]
    if clean:
        arguments.append("-clean-library")
    run(arguments)
    time.sleep(4)


class Recorder:
    """Rolling for the whole tour, and stopped the moment the budget is spent."""

    def __init__(self, path):
        self.path = path
        self.process = subprocess.Popen(
            ["xcrun", "simctl", "io", UDID, "recordVideo", "--codec", "h264", "--force", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(1.5)
        self.started = time.time()

    @property
    def left(self):
        return BUDGET - (time.time() - self.started)

    def stop(self):
        # SIGINT rather than kill: recordVideo only writes a playable file when asked to stop.
        self.process.send_signal(signal.SIGINT)
        try:
            self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.process.kill()
        ok = os.path.exists(self.path) and os.path.getsize(self.path) > 0
        print(f"  {'recorded' if ok else 'MISSED  '} {self.path}")
        return ok


def hold(recorder, seconds):
    """Let the screen be looked at, but never past the budget."""
    time.sleep(max(0.0, min(seconds, recorder.left)))


def tour_found(recorder):
    """The path with something to find."""
    hold(recorder, 2.0)
    swipe(620, 300)
    hold(recorder, 1.2)
    swipe(300, 620)

    entry = reach("root.scan")
    if entry is None:
        return
    tap(entry, settle=1.4)

    start = wait_for("scan.start", timeout=40)
    if start is None:
        return
    hold(recorder, 1.6)          # the plan: what is about to be opened
    tap(start, settle=0.4)

    if wait_for("scan.total", timeout=90) is None:
        return
    hold(recorder, 1.8)

    review = reach("scan.review")
    if review is None:
        return
    tap(review, settle=1.4)

    if wait_for("review.total", timeout=60) is None:
        return
    hold(recorder, 1.6)
    swipe(700, 380)              # down the ladder
    hold(recorder, 1.4)
    swipe(380, 700)

    delete = find(describe(), "review.delete")
    if delete is None:
        return
    tap(delete, settle=2.0)

    confirm = wait_for("confirm.delete", timeout=40)
    if confirm is None:
        return
    hold(recorder, 1.4)
    tap(confirm, settle=0.0)

    if wait_for("review.freed", timeout=45) is None:
        print("  the outcome never arrived")
    hold(recorder, 2.2)


def tour_clean(recorder):
    """The same path with nothing to find."""
    hold(recorder, 2.2)
    swipe(620, 300)
    hold(recorder, 1.6)
    swipe(300, 620)

    entry = reach("root.scan")
    if entry is None:
        return
    tap(entry, settle=1.4)

    start = wait_for("scan.start", timeout=40)
    if start is None:
        return
    hold(recorder, 2.0)
    tap(start, settle=0.4)

    if wait_for("scan.total", timeout=90) is None:
        return
    # The whole point of this tour: the screen that says it looked and found nothing.
    hold(recorder, 3.5)
    swipe(620, 360)
    hold(recorder, recorder.left)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    failures = 0

    for name, clean, walk in (("found", False, tour_found), ("clean", True, tour_clean)):
        print(f"{name}:")
        launch(clean)
        if wait_for("storage.headline", timeout=60) is None:
            failures += 1
            continue
        recorder = Recorder(os.path.join(OUT_DIR, f"{name}.mov"))
        try:
            walk(recorder)
        finally:
            if not recorder.stop():
                failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
