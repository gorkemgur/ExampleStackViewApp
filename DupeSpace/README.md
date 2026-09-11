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
| `Matching` | BK-tree, pigeonhole-banded index, union-find, the clusterer |
| `Scoring` | which copy survives, what may be pre-ticked, and the validator |
| `Budget` | regret tiers and the "I need N bytes" planner |
| `Scan` | the pipeline, its analyzer protocol and the thermal policy |
| `Review` | selection state and the list the review screen reads |

`DupeSpace/Sources` is the app: PhotoKit adapters behind protocols, view models,
and SwiftUI screens.

## The four rules it will not break

1. **Nothing is deleted on transitive evidence.** Byte-identical copies are grouped
   with union-find, which is correct because digest equality is transitive. A
   distance threshold is *not* transitive — A~B and B~C says nothing about A~C — so
   similar photos are clustered as stars around the copy that survives, and every
   member was measured against that copy directly.
2. **A group never loses every copy.** Checked by `CleanupValidator`, which re-runs
   from scratch immediately before the library is told to destroy anything, because
   by then the selection has passed through UI state.
3. **Favourites and album members are never pre-ticked**, and neither is anything
   above the two tiers where deletion provably costs nothing.
4. **Nothing is downloaded to be scanned.** Every read sets
   `isNetworkAccessAllowed = false`. An original that lives in iCloud is reported as
   deliberately unread rather than pulled down over someone's data plan.

## What iOS does not allow, and what is not built yet

No app can see what another app stores; Settings › General › iPhone Storage is the
only place that breaks that down. Free space is reported as an estimate because
`volumeAvailableCapacityForImportantUsage` counts storage the system would purge.
Photo deletions land in Recently Deleted for thirty days, so the confirmation
separates space that comes back now from space that comes back then.

Still to come: video keyframe similarity (`VideoMatcher` exists but the pipeline
only matches videos byte-for-byte), scanning folders picked from Files, incremental
rescans via `PHPhotoLibraryChangeObserver`, and background scanning.
