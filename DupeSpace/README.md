# DupeSpace

An iOS duplicate finder and storage analyser that answers the question a person
actually has — *"I need 10 GB back, what do I lose least by deleting?"* — instead of
handing over a list of duplicates and leaving the arithmetic to them.

## Running it

There is no `.xcodeproj` in the repository. It is generated, so it can never drift
from the sources or produce a merge conflict:

```sh
brew install xcodegen
xcodegen generate
open DupeSpace.xcodeproj
```

Tests:

```sh
swift test --package-path Packages/DupeCore          # the engine, no simulator needed
xcodebuild test -project DupeSpace.xcodeproj \
  -scheme DupeSpace -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI runs both on macOS runners on every push, plus an `idb` pass that installs the
build on a booted simulator, dumps its accessibility tree and captures a screenshot.

Launching with `-ui-testing` swaps the photo library, analyzer, deleter and
thumbnail loader for deterministic fixtures. That is what lets UI tests assert on
real numbers without a permission alert that no CI machine can tap.

## How it is laid out

`Packages/DupeCore` holds every decision that can destroy a file and contains no
PhotoKit, Vision or SwiftUI types, so all of it runs under unit test:

| Area | What lives there |
|---|---|
| `Hashing` | streaming SHA-256, dHash, DCT-based pHash over a plain grayscale buffer |
| `Matching` | the pair sweep, the video signature matcher, the star clusterer |
| `Scoring` | which copy survives, what may be pre-ticked, and the validator |
| `Budget` | regret tiers and the "I need N bytes" planner |
| `Scan` | the pipeline, its analyzer protocol, the fingerprint cache, the thermal policy and the pause gate |
| `Review` | selection state and the list the review screen reads |
| `History` | the record of what was scanned and what was removed |

`DupeSpace/Sources` is the app: PhotoKit adapters behind protocols, view models,
and SwiftUI screens.

## What it looks at

Photos and videos from the photo library, plus any folders handed over from Files — iCloud
Drive, On My iPhone, an external drive. The two sources are one library to the engine but keep
their separate permission models, so a refused photo library does not take granted folders with
it. Overlapping grants are refused: indexing one file through two of them would make it look
like its own duplicate.

Duplicates are found four ways, cheapest first. Metadata eliminates anything unique on kind,
dimensions and size. Survivors are digested. Images that byte equality did not settle are
fingerprinted twice, and both fingerprints have to agree. Videos are paired on duration — a
transcode barely moves it — and only then opened and sampled frame by frame, which is what
catches the copy that came back from a chat.

Everything expensive is remembered, keyed by a content version derived from metadata the
library already hands over, so a second scan of an unchanged library re-reads nothing. A scan
can be held rather than cancelled, and slows itself down on a hot phone or in Low Power Mode.

Every scan and every deletion leaves a record: what went, what was kept in its place, what it
was worth, and how many days remain to undo it from Recently Deleted.

## The page

`docs/index.html` is a landing page for the app: one self-contained file, no build step, and no
request to any server — system fonts, inline styles and scripts, and the same simulator
screenshots this repository already carries. To publish it, switch on GitHub Pages with the
source set to the default branch and the `/docs` folder; there is nothing to deploy.

`Scripts/check-site.py` runs in CI and catches the three faults a browser reports as nothing at
all: an asset that is not there, something loaded from a third party, and an absolute path that
works locally and resolves to the domain root once it is served from a subdirectory.

## Outside the app

A widget carries the same numbers to the Home and Lock Screens — free space, what the last scan
found, how much has been reclaimed in total — in five families, down to the inline one. It reads
a snapshot the app leaves in a shared container rather than computing anything: a widget gets a
few tens of milliseconds and no photo library access at all. The write is a file, and atomic, so
a widget reloading mid-write reads the previous snapshot instead of half of the next one.

A running scan appears as a Live Activity on the Lock Screen and in the Dynamic Island, because
a scan of a full library is minutes and nobody stares at a progress bar for minutes. Every
surface renders one state, so a scan cannot be 40% done in one place and 60% in another, and
nothing is claimed found until the scan has actually decided — a number read off a Lock Screen
with the app nowhere in sight is the worst possible place for an estimate. Updates are rationed
against ActivityKit's budget, except the ones a person would notice: a change of stage, a hold,
and the end.

Both are best-effort. No App Group, an iPad, or Live Activities switched off means no widget and
no live scan, and exactly the same scan.

## The four rules it will not break

1. **Nothing is deleted on transitive evidence.** Byte-identical copies are grouped
   by bucketing on the digest itself, which is correct because digest equality is
   transitive — every member of such a bucket equals every other by construction. A
   distance threshold is *not* transitive — A~B and B~C says nothing about A~C — so
   similar photos are clustered as stars around the copy that survives, and every
   member was measured against that copy directly.
2. **A group never loses every copy.** Checked by `CleanupValidator`, which re-runs
   from scratch immediately before the library is told to destroy anything, because
   by then the selection has passed through UI state.
3. **Favourites and album members are never pre-ticked**, and neither is anything
   above the two tiers where deletion provably costs nothing. Nor is a copy carrying edits the
   survivor does not have: a digest covers the original resource, and work done on top of it is
   not something "identical" can promise away.
4. **Nothing is downloaded to be scanned.** Every read sets
   `isNetworkAccessAllowed = false`. An original that lives in iCloud is reported as
   deliberately unread rather than pulled down over someone's data plan.

## What iOS does not allow, and what is not built yet

No app can see what another app stores; Settings › General › iPhone Storage is the
only place that breaks that down. Free space is reported as an estimate because
`volumeAvailableCapacityForImportantUsage` counts storage the system would purge.
Photo deletions land in Recently Deleted for thirty days, so the confirmation
separates space that comes back now from space that comes back then.

Background scanning is deliberately not built. A `BGProcessingTask` that requires external
power may never run, nothing about it can be verified without a device, and the result would
still be sitting there waiting to be reviewed. The fingerprint cache delivers what people
actually wanted from it — a rescan that costs almost nothing — without any of that.

What is genuinely untested: the app has never run against a real photo library. The perceptual
thresholds are calibrated against synthetic images, so how the "similar" tier behaves on real
photographs is the one thing only a device can answer.
