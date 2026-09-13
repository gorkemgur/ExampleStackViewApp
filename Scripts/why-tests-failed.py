#!/usr/bin/env python3
"""Say which tests failed and what they said, from the result bundle rather than the log.

    python3 Scripts/why-tests-failed.py TestResults.xcresult [xcodebuild.log]

WHY THIS EXISTS. A parallel UI test run farms the suites out to cloned simulators, and what
reaches stdout is one line per test:

    Test case 'ReviewUITests.testTheListControlsAreBigEnoughToHit()' failed on
    'Clone 1 of iPhone 17 Pro Max - DupeSpaceUITests-Runner (24036)' (36.084 seconds)

Not the assertion, not the file, not the line — those go into the result bundle and nowhere
else. So the step that was supposed to put the four lines that matter at the bottom of a
three-thousand-line log printed an empty group under `Test failures` while five tests were
red, and the only way to find out why was to download a 225 MB artifact. Which the network
policy here will not fetch.

`xcresulttool` has the failures, with their text. This asks it, and falls back to scraping the
log if the bundle is missing or the tool's output shape has moved again — a diagnostic that
fails to diagnose is worse than none, because it reads like an absence of failures.
"""
import json
import subprocess
import sys


def xcresult(path, *arguments):
    command = ["xcrun", "xcresulttool", "get", "test-results", *arguments, "--path", path, "--format", "json"]
    finished = subprocess.run(command, capture_output=True, text=True)
    if finished.returncode != 0:
        return None, (finished.stderr or "").strip()
    try:
        return json.loads(finished.stdout), None
    except json.JSONDecodeError as error:
        return None, f"could not read the tool's json: {error}"


def from_bundle(path):
    summary, problem = xcresult(path, "summary")
    if summary is None:
        return None, problem

    failures = summary.get("testFailures") or []
    lines = []
    for failure in failures:
        where = failure.get("targetName") or ""
        name = failure.get("testName") or failure.get("testIdentifier") or "(unnamed test)"
        text = (failure.get("failureText") or "").strip() or "(the bundle recorded no message)"
        lines.append(f"{where}.{name}" if where else name)
        for line in text.splitlines():
            lines.append(f"    {line}")
        lines.append("")

    counts = "  ".join(
        f"{key}: {summary[key]}"
        for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
        if key in summary
    )
    if counts:
        lines.append(counts)
    return lines, None


def from_log(path):
    """Whatever the console said, when the bundle cannot answer."""
    try:
        with open(path, errors="replace") as handle:
            text = handle.read()
    except OSError as error:
        return [f"and the log could not be read either: {error}"]

    wanted = ("XCTAssert", "XCTFail", " failed on '", "' failed (", "Failing tests:", "error:")
    hits = [line.rstrip() for line in text.splitlines() if any(token in line for token in wanted)]
    return hits[-60:] or ["nothing in the log looked like a failure either"]


def main():
    if len(sys.argv) < 2:
        print("usage: why-tests-failed.py TestResults.xcresult [xcodebuild.log]")
        return 2

    bundle = sys.argv[1]
    log = sys.argv[2] if len(sys.argv) > 2 else "xcodebuild.log"

    lines, problem = from_bundle(bundle)
    if lines is None:
        print(f"the result bundle could not be read ({problem}), falling back to the log")
        lines = from_log(log)
    elif not lines:
        print("the bundle recorded no test failures — the run died outside a test")
        lines = from_log(log)

    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
