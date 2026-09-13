# State of play

Written 13 September 2026, at commit `c901e35`, branch `claude/selam-dr571g` (184 commits).

This is a handover, not a summary. It is organised by *how much we know*, because that turned
out to be the thing that mattered: this project has repeatedly had code that worked and code
that only appeared to work, and the difference was never visible from the source.

Three rules held throughout and should keep holding:

1. **The app must never delete the wrong photo or video.** Everything below is subordinate.
2. **A claim nobody checked is a slogan.** Several features passed 468 tests while being
   completely broken, because no test ran the code.
3. **A check that can only say "it did not work" costs a round trip every time it fires.**
   Every driver in `Scripts/` dumps the screen when it gives up. That was learned the hard way,
   four separate times.

---

## 1. Proven — exercised against real media, not stubs

These run in CI on every push, through the real system frameworks.

| What | How it is proven |
|---|---|
| Photo library read | `real` job: `PhotoKitMediaLibrary` indexes 28 real assets |
| Byte-identical detection | `real` job: both exact pairs found, offered, deleted |
| Perceptual detection (photos) | `real` job: both half-size re-sends found |
| Video similarity | `real` job: all three re-encoded clips found |
| Permission flow | `real` job taps the real "Allow Full Access" dialog |
| Deletion | `real` job answers the system's own Delete alert; second scan comes back clean |
| No false positives | no singleton has ever been offered |
| `GrayImageRenderer`, `VideoFrameSampler`, `FileSystemOriginalExporter` | `AdapterTests`, 13 tests, real H.264 written by `AVAssetWriter` |
| Fingerprint agreement across halves | `ResendFingerprintTests.testBothHalvesFingerprintTheSamePictureTheSameWay` |
| `DupeCore` logic | 301 tests |

Test counts by target: **DupeCore 301**, **DupeSpaceTests 172**, **DupeSpaceUITests 23**.

### The two bugs the `real` job found that nothing else could

Both were invisible to 468 passing tests, because no test ran the code.

**The filename was in the content hash.** `PhotoKitAssetAnalyzer.contentDigest` hashed
`"r\(type):\(originalFilename)|"`, so two photographs sharing every byte came out with
different digests as soon as they were called different things — which is the ordinary case,
not a corner one (`IMG_4021.JPG` and `IMG_4021 1.JPG`). The tier the app opens with,
"Identical copies — costs nothing", the one it pre-ticks because deletion provably costs
nothing, could never fire for a photograph. Fixed in `219d341`. The *file* half had always been
tested for exactly this property; the photo half had no test at all.

**Two downsamplers, one matcher.** `edges(hashes:)` compares every fingerprint against every
other in one sweep and does not know which analyzer produced each. `FileAssetAnalyzer` decoded
at `renderSize * 4`; `PhotoKitAssetAnalyzer` asked PhotoKit for `renderSize` itself — the size
of the buffer the hash is computed *on*, which leaves the hasher nothing to average away. So
(a) half-size re-sends were missed, and (b) the same photograph in Photos and in a folder could
fail to match itself. Fixed in `56bc3c9`: one decoder, with the photo side falling back to the
original resource when PhotoKit returns nothing hashable.

---

## 2. Built, but not proven

Code is written and reviewed. Nothing has run it end to end.

**Cross-source duplicates (the "C" feature).** `ReviewGroup.spansLibraryAndFolders` with four
DupeCore tests (two of which assert it is *not* set — a claim printed unconditionally is
decoration). A "Where" row in the comparison table, and a line on the group screen when a group
holds both. The engine change underneath it is proven; *that a library item and a folder item
actually land in one group* is not. See §4 for why.

**The five UI tests** that had been red for four runs. Three were the same mistake — the test
asked `app.otherElements` / `app.buttons` for an identifier that SwiftUI's accessibility
translation had filed elsewhere. `DupeSpaceUITests/ElementSearch.swift` now searches every type
at once and dumps the element tree on failure. **These have never been seen green.** Four
consecutive runs were cancelled by my own pushes before the UI job finished.

**`Badge`, the Paper palette, the budget fader rework** — screenshotted and audited (0 findings
in `docs/ui-audit.md`), never used by a person.

---

## 3. Decided and not built

Ordered. The first two share one mechanism, which is why they are ordered this way.

**RAW + JPEG pairs.** The largest per-item saving on an iPhone and Apple offers no way to take
it. In the RAW+JPEG model the JPEG is `PHAssetResourceType.photo` and the RAW is
`.alternatePhoto`; a ProRAW file is 25–75 MB against a few MB for the JPEG. Photos has no
command to delete one half — the only official route is export the pair and reimport the half
you want.

**Live Photo video weight.** A Live Photo is a still plus ~3 s of video, typically 3–5× the
still. `pairedVideoByteSize` is already read by the app and used only in arithmetic. Nobody
tells you what it costs.

Both are the same sentence — *this asset carries a second resource you have never used* — and
the same mechanism: create a new asset from the resource you keep, carry over creation date,
location and favourite, delete the original (which sits in Recently Deleted for 30 days).

⚠️ **Unverified assumption in both.** I could not find an API that deletes a single resource in
place; `PHAssetChangeRequest` does not appear to offer one. The recreate-and-delete route is the
only one I can evidence, and it touches the library harder than deleting a copy does. There is
an open Apple forum thread titled *"addResourceWithType not working for RAW + JPEG"* — that is
about recreating the *pair*, which is not what we would do, but it has not been ruled out.

**Screenshots by age.** Confirmed trivial:

```swift
options.predicate = NSPredicate(
    format: "(mediaSubtype & %d) != 0",
    PHAssetMediaSubtype.photoScreenshot.rawValue
)
```

`PHAssetMediaSubtype.photoScreenshot` and `smartAlbumScreenshots` both exist. The app already
carries `isScreenshot` and uses it only for keeper scoring. Apple offers no "delete screenshots
older than X".

---

## 4. Tried, and does not work

**A populated folder cannot be granted on a simulator through idb.** Two halves, and only one
of them failed:

- Getting files onto the device: **works.** There is no `simctl addfile` and the picker can
  create an empty folder but not fill one, so the route is to write into the Files app's own
  container (`simctl get_app_container <udid> com.apple.DocumentsApp data`, then
  `File Provider Storage/`). The log says `put 3 files in On My iPhone / DupeSpace Fixture`.
- Driving the picker: **blocked.** The dump at the failing step is one line long:

  ```
  --- what was on the screen at looking for 'Browse' in the picker: 1 elements
      Application: id=None label='DupeSpace'
  --- end
  ```

  `UIDocumentPickerViewController` is hosted out of process, and `idb describe-all` only sees
  the application under test. The picker's own UI is invisible to it. This is not a timing or
  scrolling problem and no amount of waiting fixes it.

  **The lead worth trying next:** XCUITest *can* reach system UI via
  `XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")`. So the cross-source
  proof probably belongs in `DupeSpaceUITests`, not in the idb driver. Untried.

**iOS has no trash inside an app's container.** `FileManager.trashItem` refuses with
`NSCocoaErrorDomain` 3328, *"Trashing is not supported since this is a non-public location"*,
for both the temporary directory and Documents. `DupeSpaceTests/FileTrashTests.swift` asserts
the refusal and its error code, so a future iOS that allows it turns the tests red. This is why
the app's four screens saying folder deletion is immediate are correct.

**Clearing other apps' caches is impossible on iOS**, the Android way. No API, no entitlement,
no accessibility route. Apple removed even its own per-app "clear data" control. Anything on the
App Store claiming to do it is clearing its own cache or showing statistics. Not worth the one
asset this app has.

---

## 5. Open — not answered, and the honest reason

**Does a Files provider allow trashing?** The 3328 refusal above names "non-public location" as
the reason, and the folders this app actually deletes from are *not* in its container — they
are served by a provider (iCloud Drive, On My iPhone, third parties), which is a public
location. So the refusal may not apply there at all. **Only a real device with a real folder
grant can settle this**, and the answer decides whether folder deletion can offer a 30-day
undo like the photo half does. This is the single most valuable unanswered question in the
project.

**Are the three video pairs actually on the review screen?** The app finds them — "Videos, 3
items, 89 KB" is on the screen and all seven items delete — but `real-library-check.py` has
reported `MISSED clip-11/12/13` in three consecutive runs. The Videos section header renders
with no rows beneath it in `describe-all`, even after the sweep taps the kind filter. Either
the rows carry no matching label or they are never laid out. **The checker is wrong, not the
app** — but it is wrong in the direction that reads as a regression, which is the worst
direction, and it has now been "fixed" twice without being fixed.

**Screenshot detection cannot be verified on a simulator** with the current technique. The
`photoScreenshot` subtype is set at capture; a file imported by `addmedia` does not carry it.
The feature is sound, the verification route is not known.

**`PhotoLibraryChangeObserver` and `LiveScanActivityController` have zero tests.** Neither can
be meaningfully exercised on a simulator. Both are reporting surfaces rather than paths to a
deletion, which is why this has been tolerated.

**Nothing has been used by a human being.** Every screenshot in `docs/screenshots` and both
GIFs in `docs/motion` come from a script driving a simulator. No person has held this app.

---

## 6. Not researched

- Whether App Review objects to a duplicate finder that deletes, and what the metadata has to
  say. Not looked at at all.
- Localisation. The app is English-only and there is no String Catalog.
- Performance at scale. `maximumNeighboursPerItem = 256` bounds the edge set and the reasoning
  is written down, but nothing has ever been run against more than 28 items. A 50,000-asset
  library is the case this app is *for* and it has never seen one.
- Accessibility beyond identifiers and tap targets: VoiceOver has never been switched on,
  Dynamic Type has never been raised.
- iCloud-heavy libraries. The cloud-only path is coded and unit-tested against stubs; no real
  library with optimised storage has been scanned.
- Battery and thermals during a long scan. `ScanThrottling` exists and is untested in anger.

---

## 7. The pipeline

Seven jobs (`.github/workflows/ci.yml`). `concurrency.cancel-in-progress: true` — **a push
cancels the run in flight**, which cost four separate answers today. Batch changes; push once.

| Job | What it is for | Rough time |
|---|---|---|
| `compile` | the one-minute verdict, and the only Release build | 4 min |
| `core` | `DupeCore`, platform-free, 301 tests | 30 s |
| `app` | simulator unit tests, 172 tests | 5 min |
| `ui` | XCUITest, parallel over two cloned simulators | 20 min |
| `site` | `docs/index.html` structure check | 5 s |
| `real` | **the one that finds real bugs** — real media, real PhotoKit, real deletion | 9 min |
| `idb` | screenshots, layout/motion audit, deletion recording, both tour GIFs | 25 min |

`app` and `ui` were one job until `56bc3c9`. GitHub serves a job's log only once the job has
*finished*, so a unit verdict known at minute six could not be read until minute twenty-six.
Splitting them also deleted a step: the UI half clones the simulator to parallelise, and a
clone taken from a device the unit half left live comes back as `SBMainWorkspace` denying the
launch, with no assertion in the log to explain it.

**Still to trim** (task #20, half done): three separate `xcodebuild` invocations build the same
thing; 7 jobs should be 4–5.

### Reading a failure

- `Scripts/why-tests-failed.py` reads the result bundle, because a parallel XCUITest run prints
  only `Test case '...' failed on 'Clone 1 of ...'` — the assertion, file and line go into the
  `.xcresult` and nowhere else. Five tests were red for three runs with an empty failure report
  before this existed.
- The `core` job has no equivalent step. A compile error there surfaces as `error: fatalError`
  with no location, seven hundred lines below the real errors. **Worth adding.**

---

## 8. Traps, so they are not rediscovered

- `idb describe-all` returns scroll-view children that are *below* the glass with the frame they
  would have. Tapping their centre is a no-op that looks like a tap. `is_on_glass()` exists in
  three scripts for this reason.
- `scroll_to()` only swipes one way, so it assumes the screen starts at the top. It resets to
  the top first now; before that, one search leaving the screen at the bottom broke the next.
- A membership check that reads only the visible part of a list gets *more* wrong as the app
  finds more. See §5.
- `simctl privacy grant photos` exits 0 and iOS asks anyway. The driver taps the dialog.
- `AVAssetImageGenerator` with `.zero` time tolerance forces a keyframe decode per request —
  nine minutes for one GIF. Only the frames actually written need exact seeks.
- `CGContext` draws origin-at-bottom-left; `GrayImage` indexes from the top. A flipped renderer
  produces perfectly stable, perfectly wrong fingerprints — and every hashing test still passes,
  because both sides of every comparison are flipped identically.
- `try XCTUnwrap(await …)` does not compile: autoclosures cannot carry `await`.
- GitHub refuses any file over 100 MB. Do not commit `.mov`.
- The DupeCore test factory is `Fixtures`, not `TestSupport`.

---

## 9. Needs a person

- **A device.** `docs/RUN-ON-YOUR-PHONE.md` + `Scripts/for-my-phone.sh`: free Apple ID, no paid
  membership, seven-day provisioning, App Group stripped (so no widget shared data, no Live
  Activity). Needs a Mac with Xcode and a cable. This unblocks the trashing question in §5 and
  screenshot verification.
- **A paid Apple Developer account** for App Group, Live Activity on device, TestFlight and the
  App Store.
- **The landing page is live** at https://gorkemgur.github.io/ExampleStackViewApp/ — deploying
  from `claude/selam-dr571g`, not `main`. Merging and deleting the branch takes the site down
  until the Pages source is repointed.
- **Someone to actually use the app.**

---

## 10. If you pick this up

In order, and the first one is the one that matters:

1. Get `ui` green. The fixes are written and have never been seen to work.
2. Move the folder grant into `DupeSpaceUITests` using
   `XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")`. That closes the
   cross-source proof, which is the app's one distinctive claim.
3. Fix `real-library-check.py` so it stops reporting the clips as missing — or find out they
   genuinely are.
4. Run it on a phone and answer the trashing question.
5. Then RAW+JPEG, then Live Photo, then screenshots.
