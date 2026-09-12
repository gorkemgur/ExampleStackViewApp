#!/usr/bin/env python3
"""Record the deletion, which is the one part of this app a still cannot show.

`capture-screens.py` photographs states. The handover instrument is not a state — it is a
block crossing a gate while a held segment travels down it, and the only honest way to review
that is to watch it. `xcrun simctl io recordVideo` runs until it is interrupted, so this drives
the app to the confirmation sheet, starts the recorder, taps the key, waits for the outcome,
and stops.

The .mov is committed and turned into a GIF elsewhere: the macOS runners have no ffmpeg and
installing one to make a preview would cost more than the preview is worth.
"""
import json
import os
import signal
import subprocess
import sys
import time

UDID = sys.argv[1]
OUT_PATH = sys.argv[2]
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
        time.sleep(3)
    return []


def find(tree, identifier):
    for element in tree:
        if element.get("AXUniqueId") == identifier:
            return element
    for element in tree:
        if element.get("AXLabel") == identifier:
            return element
    return None


def tap(element, settle=1.5):
    frame = element.get("frame") or {}
    x = frame.get("x", 0) + frame.get("width", 0) / 2
    y = frame.get("y", 0) + frame.get("height", 0) / 2
    run(["idb", "ui", "tap", "--udid", UDID, str(int(x)), str(int(y))])
    time.sleep(settle)


def wait_for(identifier, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        element = find(describe(), identifier)
        if element is not None:
            return element
        time.sleep(2)
    print(f"never appeared: {identifier}")
    return None


def swipe_up():
    run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "280"])
    time.sleep(0.8)


def scroll_to(identifier, attempts=8):
    for _ in range(attempts):
        element = find(describe(), identifier)
        if element is not None:
            return element
        swipe_up()
    return None


def main():
    os.makedirs(os.path.dirname(OUT_PATH) or ".", exist_ok=True)

    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(1)
    run(["xcrun", "simctl", "launch", UDID, BUNDLE_ID, "-ui-testing"])
    time.sleep(4)

    if wait_for("storage.headline", timeout=60) is None:
        return 1

    entry = scroll_to("root.scan")
    if entry is None:
        return 1
    tap(entry)

    start = wait_for("scan.start", timeout=60)
    if start is None:
        return 1
    tap(start)

    if wait_for("scan.total", timeout=180) is None:
        return 1

    review = scroll_to("scan.review")
    if review is None:
        return 1
    tap(review)

    if wait_for("review.total", timeout=90) is None:
        return 1

    delete = find(describe(), "review.delete")
    if delete is None:
        return 1
    tap(delete, settle=3.0)

    confirm = wait_for("confirm.delete", timeout=60)
    if confirm is None:
        return 1

    # Rolling before the tap: the first beat — the red key being spent and the instrument
    # taking its place — is the one that most needs watching.
    recorder = subprocess.Popen(
        ["xcrun", "simctl", "io", UDID, "recordVideo", "--codec", "h264", "--force", OUT_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.5)

    tap(confirm, settle=0.0)

    # The whole of it: the held gate, the crossing, the dismissal, and the success slab
    # arriving on the review screen behind it.
    if wait_for("review.freed", timeout=60) is None:
        print("the outcome never arrived; recording what there was")
    time.sleep(2.0)

    recorder.send_signal(signal.SIGINT)
    try:
        recorder.wait(timeout=30)
    except subprocess.TimeoutExpired:
        recorder.kill()

    ok = os.path.exists(OUT_PATH) and os.path.getsize(OUT_PATH) > 0
    print(f"{'recorded' if ok else 'MISSED  '} {OUT_PATH}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
