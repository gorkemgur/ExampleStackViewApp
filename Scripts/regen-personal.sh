#!/usr/bin/env bash
#
# Regenerate `DupeSpace.xcodeproj` from `project.personal.yml` *without* losing the two things
# that exist nowhere on disk but in the project file itself.
#
# `DupeSpace.xcodeproj` is git-ignored, and it carries state no spec reproduces: the
# `DEVELOPMENT_TEAM` Xcode wrote when a free Apple ID was picked in Signing & Capabilities. A
# bare `xcodegen generate` throws it away — and it also regenerates from `project.yml`, whose
# `com.gorkemgur` identifiers and App Group a free team cannot sign at all. The next build to
# the phone then fails, and the reason is a file nobody is looking at.
#
# Measured, so it is not guessed at: generating from `project.personal.yml` and reading the
# result back gives four missing `DEVELOPMENT_TEAM` lines and two `CODE_SIGN_IDENTITY` lines
# already present — XcodeGen's own preset for an iOS application target writes the identity,
# and writes no team anywhere. So the team is what actually needs restoring; the identity is
# written back only as a fallback should that preset ever change.
#
# Either way the point is the *verification*: six lines have to be readable back out of the
# project, or this stops with an error rather than handing over something that looks fine
# until a phone is plugged in.
#
# What this deliberately does NOT do:
#   * call `Scripts/for-my-phone.sh` — that rewrites `project.personal.yml` from `project.yml`
#     and needs the prefix passed again; getting it wrong silently changes the bundle ID.
#   * write `project.personal.yml` — this script only reads it.
#
# Run it after adding, deleting or moving a source file. Close Xcode first, or it will reload
# the project underneath you.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=28T45Z4B66
IDENTITY="iPhone Developer"
SPEC=project.personal.yml
PBXPROJ=DupeSpace.xcodeproj/project.pbxproj

if [ ! -f "$SPEC" ]; then
  echo "$SPEC is missing. It is git-ignored and generated once:" >&2
  echo "  ./Scripts/for-my-phone.sh com.yourname" >&2
  exit 2
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed: brew install xcodegen" >&2
  exit 2
fi

xcodegen generate --spec "$SPEC"

python3 - "$PBXPROJ" "$SPEC" "$TEAM" "$IDENTITY" <<'PY'
import re
import sys

pbxproj, spec, team, identity = sys.argv[1:5]

# Which bundle identifier belongs to which target, read from the spec rather than hard-coded,
# so a different prefix in `project.personal.yml` still matches the right build settings.
TARGET = re.compile(r"^  ([A-Za-z_][\w-]*):\s*$")
SPEC_BUNDLE = re.compile(r"^\s+PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$")

identifiers, target, inside = {}, None, False
for line in open(spec).read().splitlines():
    if line.rstrip() == "targets:":
        inside = True
        continue
    if line and not line[0].isspace():
        inside = False
    if not inside:
        continue
    named = TARGET.match(line)
    if named:
        target = named.group(1)
        continue
    bundle = SPEC_BUNDLE.match(line)
    if bundle and target:
        identifiers[target] = bundle.group(1)

missing = [name for name in ("DupeSpace", "DupeSpaceWidgets") if name not in identifiers]
if missing:
    sys.exit("%s declares no PRODUCT_BUNDLE_IDENTIFIER for %s — re-run Scripts/for-my-phone.sh"
             % (spec, " and ".join(missing)))

# The app needs both keys. The widget is signed with the team but takes no explicit identity —
# that is what Xcode itself wrote, and adding one there is not something to invent here.
wanted = {
    identifiers["DupeSpace"]: {"CODE_SIGN_IDENTITY": '"%s"' % identity, "DEVELOPMENT_TEAM": team},
    identifiers["DupeSpaceWidgets"]: {"DEVELOPMENT_TEAM": team},
}

SETTING = re.compile(r"^(\t+)([A-Za-z_][\w]*) = (.*);$")
lines = open(pbxproj).read().splitlines(keepends=True)
out, index, added = [], 0, 0

while index < len(lines):
    line = lines[index]
    out.append(line)
    if line.strip() != "buildSettings = {":
        index += 1
        continue

    # The closing brace sits at the indentation of `buildSettings` itself; an array's `);` is
    # one level deeper, so matching on indentation keeps multi-line values intact.
    indent = line[: len(line) - len(line.lstrip("\t"))]
    end = index + 1
    while end < len(lines) and lines[end] != indent + "};\n":
        end += 1
    if end == len(lines):
        sys.exit("unterminated buildSettings block at line %d of %s" % (index + 1, pbxproj))

    block = lines[index + 1 : end]
    keys = {SETTING.match(b).group(2): b for b in block if SETTING.match(b)}
    bundle = keys.get("PRODUCT_BUNDLE_IDENTIFIER")
    bundle = SETTING.match(bundle).group(3) if bundle else None

    for key, value in sorted(wanted.get(bundle, {}).items()):
        if key in keys:
            continue
        # Insert in alphabetical position among the single-line settings, which is where
        # XcodeGen and Xcode both put them, so a later diff stays readable.
        at = next((n for n, b in enumerate(block)
                   if SETTING.match(b) and SETTING.match(b).group(2) > key), len(block))
        block.insert(at, "%s\t%s = %s;\n" % (indent, key, value))
        added += 1

    out.extend(block)
    index = end

open(pbxproj, "w").write("".join(out))

# Verification. Not "did the edit run" but "is the result signable" — the six lines have to be
# readable back out of the file, or this exits non-zero and nobody presses Run on a lie.
written = "".join(out)
teams = written.count("DEVELOPMENT_TEAM = %s;" % team)
identities = written.count('CODE_SIGN_IDENTITY = "%s";' % identity)
swift = written.count("lastKnownFileType = sourcecode.swift")

problems = []
if teams != 4:
    problems.append("DEVELOPMENT_TEAM = %s appears %d times, expected 4 "
                    "(app and widget, Debug and Release)" % (team, teams))
if identities != 2:
    problems.append('CODE_SIGN_IDENTITY = "%s" appears %d times, expected 2 '
                    "(app, Debug and Release)" % (identity, identities))
if swift < 50:
    problems.append("only %d Swift file references in the project — the generate step looks "
                    "wrong, not just unsigned" % swift)

if problems:
    print("regenerate produced a project that cannot be installed on a phone:", file=sys.stderr)
    for problem in problems:
        print("  * %s" % problem, file=sys.stderr)
    print("DupeSpace.xcodeproj is git-ignored, so there is nothing to revert to: fix this "
          "script, or re-run ./Scripts/for-my-phone.sh <prefix>.", file=sys.stderr)
    sys.exit(1)

print("signing restored: %d DEVELOPMENT_TEAM, %d CODE_SIGN_IDENTITY, %d added, "
      "%d Swift files in the project" % (teams, identities, added, swift))
PY

echo
echo "Confirm Signing & Capabilities in Xcode before pressing Run — a free team's"
echo "provisioning lasts seven days, and this script cannot tell you whether yours is live."
