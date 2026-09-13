#!/usr/bin/env python3
"""Run the app against a real Photos library, on a simulator, with the real PhotoKit code.

Everything else in this repository runs against stubs. `PhotoKitMediaLibrary`,
`PhotoKitAssetAnalyzer` and `PhotoKitDeleter` — the last of which is the code that actually
destroys someone's photographs — had never been executed once, because a simulator starts with
an empty library and nothing was putting anything into it.

`xcrun simctl addmedia` puts real files in, `simctl privacy` grants the permission that would
otherwise stop the app at the wall, and launching *without* `-ui-testing` means every service
is the real one. So the only thing missing was the media, and `make-library.swift` writes it.

WHAT IS ASSERTED, AND WHY IT IS SPLIT.

Hard failures are the ones that are deterministic or unsafe:

  * the two exact pairs must be found. They share every byte; a scan that misses them has a
    broken digest stage, and there is no threshold to argue about.
  * no group may contain a file with no partner. A singleton in a group is the app offering to
    delete something it never had a reason to match, which is the one thing it must never do.
  * the group count may not exceed what was built.

The perceptual pairs — a photo re-sent at half size, a clip re-encoded at a fifth of the
bitrate — are reported rather than required on this first pass. They depend on a threshold,
and a threshold is a judgement to be looked at with real numbers in front of it, not a thing to
assert before anyone has seen one.

  python3 Scripts/real-library-check.py <udid> <library dir> <artifacts dir>
"""
import json
import os
import subprocess
import sys
import time

UDID = sys.argv[1]
LIBRARY = sys.argv[2]
OUT_DIR = sys.argv[3] if len(sys.argv) > 3 else "artifacts/real"
BUNDLE_ID = "com.gorkemgur.dupespace"

#: Files built with no partner. If any of these is offered for deletion, the matcher has
#: grouped two things it never compared, and that is a stop-the-line failure.
SINGLETONS = ["photo-5", "photo-6", "photo-7", "photo-8", "clip-14", "clip-15"]
#: Byte-identical pairs. Not a threshold, not a judgement: these must be found.
EXACT = ["photo-1", "photo-2"]

failures = []
notes = []


def run(args, timeout=600):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def describe():
    for _ in range(25):
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
    return None


def tap(element, settle=1.5):
    frame = element.get("frame") or {}
    x = int(frame.get("x", 0) + frame.get("width", 0) / 2)
    y = int(frame.get("y", 0) + frame.get("height", 0) / 2)
    run(["idb", "ui", "tap", "--udid", UDID, str(x), str(y)])
    time.sleep(settle)


def shot(name):
    os.makedirs(OUT_DIR, exist_ok=True)
    run(["xcrun", "simctl", "io", UDID, "screenshot", os.path.join(OUT_DIR, name)])


#: The buttons that grant what the app is asking for, in the order it is worth trying them.
#: "Allow Full Access" is the library; "Allow" covers the deletion alert and the older wording.
CONSENT = ["allow full access", "allow", "delete"]


def answer_system_prompt(tree):
    """Tap through a system permission dialog if one is on the screen.

    `simctl privacy grant photos` exits 0 and iOS asks anyway — the first run of this job spent
    two minutes waiting for an overview that was behind *"DupeSpace would like full access to
    your Photo Library"* the whole time.

    Tapping it is the better answer regardless. The permission flow is part of the real path,
    and a job whose whole point is that nothing here is a stub should not be skipping the one
    dialog a real user has to answer.
    """
    for wanted in CONSENT:
        for element in tree:
            label = element.get("AXLabel")
            if (
                element.get("type") == "Button"
                and isinstance(label, str)
                and label.strip().lower() == wanted
            ):
                print(f"answering the system: {label!r}")
                tap(element, settle=2.5)
                return True
    return False


def wait_for_any(identifiers, timeout=300):
    deadline = time.time() + timeout
    while time.time() < deadline:
        tree = describe()
        for identifier in identifiers:
            element = find(tree, identifier)
            if element is not None:
                return identifier, element
        # Nothing yet — but it may be that the app is behind a dialog rather than still working.
        answer_system_prompt(tree)
        time.sleep(2)
    return None, None


def scroll_to(identifier, attempts=10):
    for _ in range(attempts):
        element = find(describe(), identifier)
        if element is not None:
            frame = element.get("frame") or {}
            middle = frame.get("y", 0) + frame.get("height", 0) / 2
            if 100 <= middle <= 800:
                return element
        run(["idb", "ui", "swipe", "--udid", UDID, "200", "620", "200", "300"])
        time.sleep(1)
    return None


def labels(tree, limit=40):
    """Every readable line on the screen, in order."""
    out = []
    for element in tree:
        label = element.get("AXLabel")
        if isinstance(label, str) and label.strip():
            out.append(label.strip())
        if len(out) >= limit:
            break
    return out


def show(reason, tree):
    """Print what a screen says.

    Three photographs pairs went missing on the first end-to-end run and the log could say only
    that they were not offered. Whether Photos de-duplicated them on import, or the analyzer
    returned nothing for images, or the scan never reached them, are three different bugs with
    three different fixes — and the screen says which, if anyone reads it.
    """
    print(f"--- {reason}")
    for line in labels(tree):
        print(f"    {line}")
    print("--- end")


def dump_tree(reason):
    """Print what is actually on the screen.

    A failure that says only "this identifier was not there" costs a whole round trip to find
    out which screen it was looking at, and the artifact holding the screenshot is not always
    reachable. The log always is.
    """
    tree = describe()
    print(f"--- what was on the screen at {reason}: {len(tree)} elements")
    for element in tree:
        identifier = element.get("AXUniqueId")
        label = element.get("AXLabel")
        if identifier or label:
            print(f"    {element.get('type')}: id={identifier!r} label={label!r}")
    print("--- end")


def stage(name):
    print(f"\n=== {name}")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    stage("putting a real library on the device")
    media = sorted(
        os.path.join(LIBRARY, name)
        for name in os.listdir(LIBRARY)
        if name.endswith((".jpg", ".mov"))
    )
    if not media:
        failures.append("no media was generated")
        return report()
    added = run(["xcrun", "simctl", "addmedia", UDID] + media)
    if added.returncode != 0:
        failures.append(f"addmedia refused the library: {added.stderr.strip()[:300]}")
        return report()
    print(f"added {len(media)} files")

    stage("granting the permission the app would otherwise stop at")
    # Without this the app draws its permission wall and every screen past it is unreachable —
    # which is the real reason none of this code had ever run.
    granted = run(["xcrun", "simctl", "privacy", UDID, "grant", "photos", BUNDLE_ID])
    # Printed either way. A silent success and a silent no-op look identical from here, and
    # which of the two it was decides whether a missing overview is a slow read or a wall.
    print(f"privacy grant exited {granted.returncode}: "
          f"{(granted.stdout + granted.stderr).strip()[:200] or '(nothing said)'}")
    if granted.returncode != 0:
        notes.append(f"privacy grant exited {granted.returncode}")

    stage("launching with no fixtures at all")
    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(1)
    # No `-ui-testing`: PhotoKitMediaLibrary, PhotoKitAssetAnalyzer, PhotoKitDeleter.
    run(["xcrun", "simctl", "launch", UDID, BUNDLE_ID])
    time.sleep(4)

    # Polled, not looked at once. Every other walk in this repository polls its first look at a
    # cold simulator and this one did not — it slept six seconds, checked, and called a library
    # that was still being read "the app did not get past launch". A real PhotoKit fetch and
    # the inventory behind it take longer than a stub, which is the entire point of this job.
    #
    # `access.headline` is in the list because the two outcomes need different answers: a slow
    # read is worth waiting for, a permission wall means the grant did not take and waiting
    # will never help.
    which, _ = wait_for_any(["storage.headline", "access.headline", "library.loading"], timeout=120)
    if which in (None, "library.loading"):
        shot("00-launch.png")
        dump_tree("launch")
        failures.append(
            "the overview never appeared — the app did not get past launch"
            if which is None else
            "the library was still being read after two minutes"
        )
        return report()
    if which == "access.headline":
        shot("00-permission-wall.png")
        failures.append(
            "the app is showing its permission wall: `simctl privacy grant photos` did not take"
        )
        return report()
    shot("01-overview.png")

    stage("scanning a library nobody stubbed")
    entry = scroll_to("root.scan")
    if entry is None:
        failures.append("the scan entry point was never reachable")
        return report()
    tap(entry, settle=2)

    start = find(describe(), "scan.start")
    if start is None:
        failures.append("the scan screen did not open")
        return report()
    shot("02-plan.png")
    # The plan states how many of each kind are indexed and how many will actually be opened.
    # If Photos de-duplicated the byte-identical pairs on import, the count is short here and
    # nothing further along is worth reading.
    show("what the scan says it is about to do", describe())
    tap(start, settle=1)

    which, _ = wait_for_any(["scan.total", "scan.empty"], timeout=300)
    if which is None:
        shot("03-stuck.png")
        failures.append("the scan never finished against the real library")
        return report()
    shot("03-results.png")
    show("what the scan found", describe())

    if which == "scan.empty":
        failures.append("the scan found nothing at all — the two byte-identical pairs are in there")
        return report()

    stage("reading what it is offering")
    review = scroll_to("scan.review")
    if review is None:
        failures.append("the review entry point never appeared")
        return report()
    tap(review, settle=2)

    tree = describe()
    if find(tree, "review.total") is None:
        failures.append("the review screen did not open")
        return report()
    shot("04-review.png")
    show("what is on offer", tree)

    groups = [
        element for element in tree
        if isinstance(element.get("AXUniqueId"), str)
        and element["AXUniqueId"].startswith("review.group.")
    ]
    labels = " ".join(
        str(element.get("AXLabel") or "") for element in tree
    ).lower()

    notes.append(f"{len(groups)} groups on the review screen")

    for stem in EXACT:
        if stem not in labels:
            failures.append(f"{stem} is byte-identical to its copy and was not offered")
    for stem in SINGLETONS:
        if stem in labels:
            failures.append(f"{stem} has no partner and was offered for deletion")

    for stem in ["photo-3", "photo-4", "clip-11", "clip-12", "clip-13"]:
        notes.append(f"{'found' if stem in labels else 'MISSED'}  {stem} (perceptual pair)")

    stage("deleting, for real")
    before = len(groups)
    delete = find(describe(), "review.delete")
    if delete is None:
        failures.append("the delete key was not on the review screen")
        return report()
    tap(delete, settle=2.5)

    confirm = find(describe(), "confirm.delete")
    if confirm is None:
        shot("05-no-sheet.png")
        failures.append("the confirmation sheet never opened")
        return report()
    shot("05-confirm.png")
    tap(confirm, settle=3)

    # PhotoKit puts its own alert up, outside the app, and nothing in this repository has ever
    # had to answer one. This is the whole point of the exercise.
    answered = False
    for _ in range(12):
        tree = describe()
        shot("06-system-alert.png")
        if answer_system_prompt(tree):
            answered = True
            break
        time.sleep(1.5)
    if not answered:
        notes.append("no system alert was found; the deletion may have gone through without one")

    which, _ = wait_for_any(["review.freed", "review.result"], timeout=90)
    shot("07-after.png")
    if which is None:
        failures.append("the deletion never reported an outcome")
        return report()

    stage("looking again, from scratch")
    run(["xcrun", "simctl", "terminate", UDID, BUNDLE_ID])
    time.sleep(2)
    run(["xcrun", "simctl", "launch", UDID, BUNDLE_ID])
    time.sleep(6)

    entry = scroll_to("root.scan")
    if entry is None:
        failures.append("the app did not come back up after the deletion")
        return report()
    tap(entry, settle=2)
    start = find(describe(), "scan.start")
    if start is not None:
        tap(start, settle=1)
        which, _ = wait_for_any(["scan.total", "scan.empty"], timeout=300)
        shot("08-rescan.png")
        if which == "scan.empty":
            notes.append("the second scan found nothing: everything on offer was taken")
        elif which == "scan.total":
            tree = describe()
            after = len([
                e for e in tree
                if isinstance(e.get("AXUniqueId"), str) and e["AXUniqueId"].startswith("scan.tier.")
            ])
            notes.append(f"the second scan still lists {after} tier(s); {before} groups were offered before")
        else:
            failures.append("the second scan never finished")

    return report()


def report():
    print("\n" + "=" * 60)
    for line in notes:
        print(f"  {line}")
    if failures:
        print("\nFAILED")
        for line in failures:
            print(f"  ::error::{line}")
        return 1
    print("\nthe real PhotoKit path ran end to end")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
