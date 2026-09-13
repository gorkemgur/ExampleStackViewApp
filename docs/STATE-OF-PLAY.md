# State of play

Written 13 September 2026. Updated after CI run 146, the first fully green run, and again
after **run 157 — the first run in which the app's one distinctive claim was proven against a
real device rather than asserted.** Branch `claude/selam-dr571g`.

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
| **Cross-source duplicates (the "C" feature)** | `crossing` job: a real folder granted through Apple's own document picker, 31 real items scanned, and a group that holds a library photograph and its folder copy *and says so*. Green from run 157 |
| `DupeCore` logic | 301 tests |
| Every screen and the whole path through them | 23 UI tests, all green in run 146 |

Test counts by target: **DupeCore 301**, **DupeSpaceTests 172**, **DupeSpaceUITests 23**.

### The three bugs the device jobs found that nothing else could

All three were invisible to a green test suite, because no test ran the code the way the app
runs it.

**The filename was in the content hash.** `PhotoKitAssetAnalyzer.contentDigest` hashed
`"r\(type):\(originalFilename)|"`, so two photographs sharing every byte came out with
different digests as soon as they were called different things — which is the ordinary case,
not a corner one (`IMG_4021.JPG` and `IMG_4021 1.JPG`). The tier the app opens with,
"Identical copies — costs nothing", the one it pre-ticks because deletion provably costs
nothing, could never fire for a photograph. Fixed in `219d341`. The *file* half had always been
tested for exactly this property; the photo half had no test at all.

**The keeper was not counted, so the crossing was never announced.** Found by the `crossing`
job in run 156. `ReviewGroup.items` is not the group's media, it is the *candidates'* — the
builder fills it with `ordered.compactMap { items[$0.id] }`, and `ordered` is the candidate
list, which by definition excludes the copy that is staying. `spansLibraryAndFolders` iterated
only that, so the commonest crossing there is — a library photograph keeping, one folder copy
on offer, which is exactly what "exported once" looks like — saw one source and returned false.
The flag could only fire when the line was crossed *among the candidates*, the rarer case.

Four unit tests covered the flag and all four passed: their helper built groups with
`items: items`, keeper included, which is not the shape `ReviewBuilder` produces. **A fixture
more generous than the code hides the bug it was written to catch.** The helper now builds what
the builder builds, and three tests cover the real shapes.

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

**The five UI tests are green** as of run 146, and what they cost is worth keeping. Three
separate causes, none of which was the thing it looked like:

*An `accessibilityIdentifier` on a container is inherited by everything inside it and overrides
the identifiers set there.* Ten elements wore the name `scan.plan` and four wore `review.order`,
so `scan.plan.summary` and `review.order.biggest` — both set in the source, both waited for by a
test — did not exist on the screen at all. `.accessibilityElement(children: .contain)` on the
container is the fix. **An accessibility defect, not only a test problem:** VoiceOver read those
two rows as flattened as the query did, and no screenshot or layout audit could have caught it.
Sweeping the element tree for identifiers worn by more than one element found exactly these two;
worth re-running whenever a container gets a name.

*`confirmationDialog`'s Cancel is not in the element tree.* `GroupDetailView` passes
`Button("Cancel", role: .cancel)` and the dialog comes back as a `Sheet` holding its title, its
message and `Select them all` — nothing else. The system owns that affordance and does not
publish it where a query can reach. The test backs out with a tap above the sheet, the way a
person would, and then checks the sheet actually went away.

*Two "failures" were the runner giving up* — `Failed to launch <XCUIApplicationImpl…>` and
`Error getting main window kAXErrorServerNotFound`. Resource pressure wearing a test failure's
clothes: two shards times two parallel workers is four cloned simulators across two runners.
One simulator per shard, no clones. See §7.

*And one was arithmetic*: `("43.99999999999994") is less than ("44.0")`. A point is not an
integer on a 3x screen.

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

**A populated folder cannot be granted on a simulator through idb** — and that is the *only*
thing here that stayed impossible. The folder is granted, by XCUITest, every run; what follows
is the record of what each half cost to learn. Two halves, and only one of them failed:

- Getting files onto the device: **solved, but the log said it was solved for days before it
  was.** There is no
  `simctl addfile` and the picker can create an empty folder but not fill one, so the route is
  to write into a file provider's storage from the host. The path used was the Files app's own
  container (`simctl get_app_container <udid> com.apple.DocumentsApp data`, then
  `File Provider Storage/`), and the driver printed `put 3 files in On My iPhone /
  DupeSpace Fixture` on every run. Run 149 opened the picker and looked:

  ```
  Other, identifier: 'DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage,
                      Title: On My iPhone'
  StaticText, label: 'On My iPhone is Empty'
  ```

  That location is served by `com.apple.FileProvider.LocalStorage`, which is not the Files
  app's data container. The copy succeeded into a directory nothing reads. **A log line that
  says what a script did is not evidence about what happened** — this one was believed for
  three days because nothing had ever opened the picker to check.

  `local_storage_directories()` now searches the device's own data root for every
  `File Provider Storage` directory, writes the fixture into all of them, and prints each one.
  On a stock iOS 18 simulator there are three, all of the form
  `<device>/Containers/Shared/AppGroup/<uuid>/File Provider Storage`. **Runs 150 and 151 walked
  the picker into the folder and came back with a grant**, so the placement is solved; only the
  naming of it was ever wrong.
- Driving the picker: **blocked.** The dump at the failing step is one line long:

  ```
  --- what was on the screen at looking for 'Browse' in the picker: 1 elements
      Application: id=None label='DupeSpace'
  --- end
  ```

  `UIDocumentPickerViewController` is hosted out of process, and `idb describe-all` only sees
  the application under test. The picker's own UI is invisible to it. This is not a timing or
  scrolling problem and no amount of waiting fixes it.

  **Which process hosts the picker: the app's own.** Settled by run 149, which printed
  `Path to element: →Application … label: 'DupeSpace'`. `UIDocumentPickerViewController` is a
  remote view controller, but a remote view's accessibility tree is bridged into its *host*, so
  the picker answers to plain `XCUIApplication()` and `com.apple.DocumentManagerUICore` never
  comes to the front at all. Asserting that it did cost run 148. The useful identifiers, all
  from that dump: `DOC.browsingModeTabBar`, `File View`,
  `FullDocumentManagerViewControllerNavigationBar`. Note that *Browse* is both a tab and the
  back button, so an unscoped `buttons["Browse"].firstMatch` is a coin toss between forward and
  back.

  **The split that came out of it.** XCUITest *can* reach system UI, so
  the work is divided along the line the tools actually draw: the Python driver keeps the
  placement, because writing into another process's container is a `simctl` job and it works,
  and `DupeSpaceUITests/CrossSourceUITests` does the granting, because walking Apple's picker
  needs `XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")`.

  `real-library-check.py --setup-only` is the seam: media into Photos, the permission granted,
  the folder written, stop. The `crossing` job runs that, then the XCUITest, on its own
  simulator — not folded into `real`, because `real` deletes from the library it just built and
  a proof that must run *before* the deletions has to run somewhere else. The picker walk was
  deleted from the driver rather than left failing: it was searching for three labels twelve
  times apiece, every run, to reach a conclusion already in hand.

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

**Why did one history test start failing?** `testADeletionLeavesAReceiptYouCanOpen` passed for
days and failed in run 140 after 194 seconds against its usual 110. The fixture changed in the
same window (EXIF dates, two new piles), so the ordering it walks may have moved — or the
runner was simply loaded. Instrumented, not diagnosed.

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

**Nothing has been used by a human being.** Every screenshot in `docs/screenshots` comes from
a script driving a simulator. No person has held this app.

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

Eight jobs (`.github/workflows/ci.yml`). Run 157's wall clock was **14 m 35**. `concurrency.cancel-in-progress: true` — **a push
cancels the run in flight**, which cost five separate answers in one day. Batch changes; push
once. The times below are the jobs' own; run 140 sat in the queue for eighteen minutes before
any of them started, which no table can predict.

| Job | What it is for | Run 146 |
|---|---|---|
| `site` | `docs/index.html` structure check | 7 s |
| `core` | `DupeCore`, platform-free, 301 tests | 43 s |
| `compile` | the one-minute verdict, and the only Release build | 2 m 20 |
| `app` | simulator unit tests, 172 tests | 6 m 00 |
| `ui` ×2 | XCUITest, sharded by measured cost | 6 m 48 / 7 m 14 |
| `crossing` | the library/folder line, through the real document picker | 11 m 22 |
| `real` | **the one that finds real bugs** — real media, real PhotoKit, real deletion | 10 m 52 |
| `idb` | screenshots and the layout/motion audit | 11 m 59 |

Wall clock for the whole run: **12 m 32**, against roughly 25 minutes before the trim. What
bought it, in order: deleting the recordings and the GIF conversion (−15 min off `idb`),
sharding the UI suite and dropping the simulator clones (14 min → two parallel ~7s), and
removing the document-picker walk from `real` (−4 min). Two of my other "optimisations" made
things worse and were reverted; see the commit log for both.

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
- `AVAssetImageGenerator.copyCGImage` opens a decode per call. Asking it for a frame at a time
  cost sixteen minutes a run before the recordings were dropped; `generateCGImagesAsynchronously`
  takes the whole list and walks the file once. Worth knowing if anything here ever films the
  app again.
- `CGContext` draws origin-at-bottom-left; `GrayImage` indexes from the top. A flipped renderer
  produces perfectly stable, perfectly wrong fingerprints — and every hashing test still passes,
  because both sides of every comparison are flipped identically.
- `try XCTUnwrap(await …)` does not compile: autoclosures cannot carry `await`.
- GitHub refuses any file over 100 MB. Do not commit `.mov`.
- **`simctl privacy grant <service> <bundle>` needs the app already installed.** It exits 0
  either way. The `crossing` job granted photo access before xcodebuild installed the app, so
  every run of it scanned from behind the permission wall and offered two groups where the
  `real` job — which installs first — offers four. A short library looks exactly like a broken
  matcher.
- **`ReviewView` is a `LazyVStack`, so only the rows that have been on screen exist in the
  accessibility tree.** Counting `review.open.` elements without scrolling counts what fits on
  the screen, not what was found — run 155 read two where there were four. This is §5's rule
  about membership checks over visible lists, and it caught me in a test I wrote after writing
  the rule down.
- The DupeCore test factory is `Fixtures`, not `TestSupport`.
- **"On My iPhone" is not the Files app's data container.** It is served by
  `com.apple.FileProvider.LocalStorage`, and on a simulator the directories are
  `<device>/Containers/Shared/AppGroup/<uuid>/File Provider Storage` — three of them on a stock
  iOS 18 device. `Scripts/real-library-check.py` finds them rather than naming one.
- **The document picker's Open grants the directory you are looking at.** Tapping a folder
  *starts* a navigation; tap Open in the same breath and you get a grant on the parent, silently
  and correctly. Wait for the navigation bar's title to become the folder's name first.
- **The picker is inside the app's own accessibility tree.** So is its dismissal animation: for
  a moment after Open, a search of the app for the folder's name finds the sheet's breadcrumb
  rather than anything on the screen behind it.
- **Reading a property off an XCUIElement query with no match throws.** `firstMatch.label` on
  an empty query is not an empty string, it is a test failure — and run 153's was raised by a
  `print` written to explain a *different* failure, after the picker it was asking about had
  closed. Guard every such read with `.exists`. A line printed to explain a failure must not be
  able to cause one.
- **A failure message that prints `app.debugDescription` is a failure message nobody can read.**
  The overview's tree is four hundred lines and CI serves a job's log only once it has finished,
  so the line that matters ends up far above the tail. `screen(_:)` in `ElementSearch.swift`
  caps it; the full tree is in the result bundle for anyone who wants it.

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

1. ~~Get `ui` green.~~ Done in run 146.
2. ~~Move the folder grant into `DupeSpaceUITests` and close the cross-source proof.~~ **Done,
   green from run 157**, and it found a real bug on the way (§1). Nine runs, 148–157: four of
   them learning what Apple does not document — which process hosts the picker, where "On My
   iPhone" is served from, what Open actually grants — and five of them my own mistakes, of
   which the sharpest was reading a `LazyVStack` without scrolling it, a rule written in §5 of
   this very document. **On a machine with Xcode this would have been half an hour.** Every
   question here costs a fifteen-minute round trip; that is the single biggest tax on this
   project and the reason to run the suite locally at least once before trusting it.
3. **Now the first item.** Fix `real-library-check.py` so it stops reporting the clips as missing — or find out they
   genuinely are.
4. Run it on a phone and answer the trashing question.
5. Then RAW+JPEG, then Live Photo, then screenshots.
