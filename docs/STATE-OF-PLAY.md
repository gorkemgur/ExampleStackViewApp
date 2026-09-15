# State of play

Written 13 September 2026. Updated after CI run 146, the first fully green run, and again
after **run 157 — the first run in which the app's one distinctive claim was proven against a
real device rather than asserted** — and last after run 162. Branch `claude/selam-dr571g`.

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

**Where the research lives.** `docs/OPPORTUNITIES.md` is the research ledger: every Apple API
worth having, verified against the iOS 26.4 SDK by compiling a probe rather than by reading
annotations; the private symbols we found and refused, recorded so nobody rediscovers them; the
interaction and motion spec; and two confirmed defects in shipped code. Read it before
proposing a feature — it exists so nobody researches this twice.

---

## 1. Proven — exercised against real media, not stubs

These run in CI on every push, through the real system frameworks.

| What | How it is proven |
|---|---|
| Photo library read | `real` job: `PhotoKitMediaLibrary` indexes 28 real assets |
| Byte-identical detection | `real` job: both exact pairs found, offered, deleted |
| Perceptual detection (photos) | `real` job: both half-size re-sends found |
| Video similarity | `real` job, run 159: all three re-encoded clip pairs **and** a byte-identical one, found through PhotoKit. Plus `AdapterTests.testTheSameFootageReEncodedStillMatchesItself` on files |
| Permission flow | `real` job taps the real "Allow Full Access" dialog |
| Deletion | `real` job answers the system's own Delete alert; second scan comes back clean |
| No false positives | no singleton has ever been offered |
| `GrayImageRenderer`, `VideoFrameSampler`, `FileSystemOriginalExporter` | `AdapterTests`, 13 tests, real H.264 written by `AVAssetWriter` |
| Fingerprint agreement across halves | `ResendFingerprintTests.testBothHalvesFingerprintTheSamePictureTheSameWay` |
| Second resources — RAW halves and Live Photo video | `SecondResourcesTests`, 5 tests, green from run 162, including that an asset which *claims* to be a Live Photo but has no measured video is not counted |
| **Cross-source duplicates (the "C" feature)** | `crossing` job: a real folder granted through Apple's own document picker, 31 real items scanned, and a group that holds a library photograph and its folder copy *and says so*. Green from run 157 |
| `DupeCore` logic | 307 tests |
| Every screen and the whole path through them | 24 UI tests, **21 green** — 23 against stubs, plus `CrossSourceUITests` against the real thing. See the three reds below. |

Test counts by target, counted rather than remembered: **DupeCore 307**, **DupeSpaceTests 191**,
**DupeSpaceUITests 24, of which 3 fail**.

The three reds, measured on 14 September 2026 and **not caused by anything in this session** —
the same three fail with the onboarding wiring stashed out:
`GroupUITests.testTheGroupScreenShowsWhatStaysAndWhyEachCopyIsOffered` ("the survivor has to be
named"), `GroupUITests.testDeletingAWholeGroupIsBehindAConfirmation`, and
`CrossSourceUITests.testAPictureInBothHalvesIsFoundAndSaidToBeInBoth`, which fails at a
different line on each run and drives the system Files picker — flaky rather than merely
broken. Undiagnosed. The line above used to say "all green", which had stopped being true
without anyone re-counting.

**15 September 2026 — the `GroupUITests` flakiness, measured rather than assumed.** Both of its
tests went red once inside a five-class shard, which looked like a regression from the
deletion-refusal work landing in the same tree. Five runs settled it:

| # | Tree | Scope | `GroupUITests` |
|---|---|---|---|
| 1 | with the change | shard b, 5 classes | **red ×2** |
| 2 | clean | alone | green |
| 3 | with the change | alone | green |
| 4 | clean | shard b, 5 classes | green |
| 5 | with the change | shard b, 5 classes | green |

Run 5 repeats run 1 exactly and disagrees with it, so the failure is non-deterministic and the
change is not implicated — run 4 rules out the shard, run 3 rules out the code. **Still no root
cause**, but it is no longer "it failed once when I was doing something else": the same
configuration has now produced both answers, which is the definition the word was being used
loosely for before. `DupeSpaceTests` is **249** as of this date, not the 191 above.

**15 September 2026 — rows that were given space and never drawn.** A person looking at the app
on their phone reported "a huge gap under the Photos heading". Measured rather than guessed, with
`app.debugDescription` frames: on the burst rung the explanation ended at y −191 and the single
row that had been built sat at y −19, with **172 points of nothing** between them and the
ladder's rail running straight through it. Cause: the rung's rows sat in a `LazyVStack` nested
inside the list's own `LazyVStack`; the inner one reserved every row's height and built almost
none of them. At one scroll position it built **zero of three**.

Two things about this are worth keeping. First, the total heights were always correct, which is
why comparing section positions before and after the fix showed no difference and briefly made
the right diagnosis look wrong — the space was never missing, the content was. Second, **every
one of the 250 tests passed throughout**: they ask whether an element exists, and a row that is
never built is simply never queried for. `testEveryRowOfARungIsDrawnAndNotJustSpacedFor` counts
them instead, and with the lazy stack put back it reports 0 where it wants 3.

**15 September 2026 — a whole rung given space and never drawn, one level up from the last
one.** A person looking at the app reported "a huge gap under the Photos heading" again, after
the nested-`LazyVStack` fix. Measured with `app.debugDescription` frames, with the heading
scrolled properly into view: the heading ended at y 395.4, the next element on screen was at
633.3, and `review.section.image.1` — the whole "Lower-quality re-sends" rung, one item, half a
megabyte — was **absent from the accessibility tree**. The heading said the kind held four items
and the screen showed three.

Four candidates were tested and three were exonerated by measurement: adding `.id(section.id)`
to each rung changed nothing; moving the padding off the `ForEach` changed nothing; removing
`pinnedViews` changed nothing. Replacing the list's `LazyVStack` with a plain `VStack` made the
rung appear 11.9 points below the heading, which is what pinned the cause: the rungs were the
lazy stack's own children and it reserved one child's height without building its content. Why
SwiftUI does that is **UNVERIFIED** — there is a behavioural characterisation here and no more
than that.

The fix keeps both the laziness and the pinned headings: each kind's rungs now sit in an eager
`VStack`, so the lazy stack has three children rather than twelve and anything it builds, it
builds whole. `LadderDrawingUITests` measures the gap rather than asking whether elements exist,
because "does this exist" is precisely the question that let this through twice.

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

**RAW + JPEG and Live Photo weight — the half that could be built is built; the half that
cannot, is not.** Both are the same sentence: *this asset carries a second resource you have
never used.* In a RAW+JPEG asset the JPEG is `PHAssetResourceType.photo` and the RAW is
`.alternatePhoto`, 25–75 MB against a few; a Live Photo carries ~3 s of video, typically 3–5×
the still.

**Built:** `SecondResources` in DupeCore tallies both (5 tests), `PhotoKitMediaLibrary` reads
the `.alternatePhoto` size at inventory time — it was not being read at all, so a ProRAW
photograph reported the few megabytes of its JPEG — and `SecondResourcesCardView` says the
number on the overview, with what to do instead. No button, because there is nothing to press.

**Not built, and now known to be unbuildable from here:** deleting one half.
~~⚠️ Unverified assumption~~ — checked, September 2026. `PHAssetChangeRequest` has no request
that removes one resource of an asset; nothing in PhotoKit does. And the recreate-and-delete
workaround is worse than this document feared: the Apple forum thread
*"addResourceWithType not working for RAW + JPEG"* reports that recreating such an asset does
not work at all. So the only evidenceable route destroys somebody's original in order to
rebuild it, on a path other developers report as broken — which is exactly what rule 1 forbids.
**It needs a device, a real ProRAW library and a person who accepts the risk, or it needs an
API Apple has not shipped.**

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

**PhotoKit cannot delete one resource of an asset.** Checked rather than assumed, September
2026: `PHAssetChangeRequest` offers no such request, and the workaround — recreate the asset
from the resource you keep — is reported broken for RAW+JPEG in Apple's own forums. This is why
§3 ships the sentence and not the button, and it is the difference between "we have not got to
it" and "it is not there".

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

**Does a Files provider allow trashing?** Researched properly, September 2026, and the shape of
the answer is now known even though the answer itself still needs a device.

**It is the provider's decision, not ours.** A file provider supports trashing only if its
`NSFileProviderItem.capabilities` includes `.allowsTrashing`; providers that do not simply have
no trash. So there is no single yes or no — iCloud Drive is reported to work with
`FileManager.trashItem`, a third-party provider may not, and "On My iPhone" is its own case.
The app cannot assume; it has to try and read the result.

**Failure is safe, which matters more than the answer.** Where there is no trash, `trashItem`
fails with `NSFeatureUnsupportedError` and *leaves the file where it was*. So a
try-trash-then-remove fallback cannot lose anybody's file: its worst case is today's behaviour.

⚠️ **Succeeding is what costs something, and that is why it has not been built.** A trashed file
still occupies the disk until the trash is emptied. This app's promise is a number — "you got
back 540 MB" — and counting a trashed file as freed would make that number precisely the kind of
unearned claim §1 exists to record. Recoverable folder deletion means changing what "reclaimed"
counts and what the receipt says, not swapping one call for another. That is a design decision
with somebody's trust attached to it.

What genuinely still needs a device is narrow: **which capability the providers people actually
use report.**

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

## 5b. What the first real phone found

**14 September 2026. The first time a person held this app.** §5 ended with "nobody has used
this app"; this is the first hour of somebody doing so, on an iPhone 13 Pro Max with a real
library. One launch produced more findings than the last twenty CI runs, which is the whole
argument for §9's "needs a person" in one line.

**Fixed — the permission wall outlived the permission.** The system alert appeared at launch,
the user allowed it, and the card stayed. `access` is written in exactly two places —
`refresh()`, which had already run, and `requestAccess()`, which only the card's button
reaches — so a grant arriving by any other route left the screen describing a state that had
stopped being true until the app was relaunched. Two ordinary routes lead there: the Settings
round trip *the card's own second button offers*, and a permission revoked while the app was
in the background. `refreshAccess()` on `scenePhase == .active` now re-reads it, and reloads
only when it actually moved — an app switch must not re-enumerate fifty thousand assets.

The alert itself was almost certainly raised by `PHPhotoLibrary.shared().register(_:)` in
`beginObservingLibrary()`, which the launch ran *after* reading the status. Registering a
change observer is not a passive subscription; it is a PhotoKit call, and it was asking for
permission before anybody had read the card that explains what the app wants. Observation is
now gated on `.authorized`, so the only thing that asks is the button — the route that
updates state. ⚠️ **Unverified**: that `PHPhotoLibrary.shared()` is what prompts. The SDK
header does not document it and it was reached by elimination — it is the only launch-time
PhotoKit call that is not a pure status read. The fix does not depend on the answer.

**Why nothing caught it.** Every UI test runs behind `-ui-testing`, which pins
`StubMediaLibrary(access: .authorized)` — the permission is already granted before the first
frame. The `real` job grants through `simctl privacy` during setup. Nothing in 503 tests ever
ran the transition from unanswered to answered, which is the only moment the bug exists in.

**Built — the screen that makes the promises before the ask.** The alert used to arrive at
launch, raised by a change-observer registration, ahead of the card written to earn it.
`DupeSpace/Sources/Features/Onboarding/Onboarding.swift` is four pages ending in the permission, and
`OnboardingTests` pins the ordering as a contract rather than a layout preference: one ask, on
the last page, and nothing before it may ask for anything. The grant routes through
`OverviewViewModel.requestAccess()`, which is why the cover is presented from `RootView` and
not from `AppShell` — `AppShell` has no `model`, so the screen would have had to raise the
alert against a second library instance and leave the first still showing a wall.

`OnboardingGate` decides who sees it, and it is a three-input decision because `-ui-testing`
has to veto the screen (every UI test and the screenshot walk launch into what looks like a
first run) while `-onboarding` has to be able to ask for it back, or this becomes the one
screen that ships unmeasured. `Scripts/audit-ui.py` now walks it last.

**Fixed — the artwork was grey, and drawing photographs was the answer.** The four scenes drew
the tier colours at `opacity(0.32)` over `DS.well`, which rendered them grey: a skeleton loading
state rather than an illustration, contradicting the app behind it where those same colours are
drawn at full strength, and leaving the key at the bottom as the only saturated object on the
screen. The pictures are photographs now — `DrawnPhoto`, six palettes of sky, light and two
ridges, made of gradients and a `Shape` with no asset anywhere — and they are deliberately *not*
`DS.adaptive` pairs. Everything else on the screen is interface and resolves against the
appearance; a sunset does not become a different sunset in dark mode, and holding these fixed is
what makes them read as photographs rather than as painted UI.

That turned each rung into a sentence instead of a bar. A rung is a *pair* of photographs and
how the right one differs from the left is which rung it is: identical, the same picture twice;
`inferiorCopy`, desaturated and soft, which is what a re-send looks like beside its original;
`burstLeftover`, the same frame a hair further on; `similar`, the same place photographed twice.
The `barWidths` array went with it — it encoded a share of the library that this screen never
had and the app never shows here. What fills the ninety-six points a height-sized pair cannot
reach is the app's own `Badge` carrying `DS.cost(tier)`, which also makes the picture on page
two an illustration of page two's sentence.

**Fixed — about 195pt of nothing between the copy and the key.** The artwork was pinned at
`frame(height: 232)` with a `Spacer` underneath swallowing whatever a large phone had left. It
is a band now, 130 to 360, and the slack goes into the picture; on a small phone the picture
gives it back rather than pushing the key off the bottom. Page three needed the same correction
in reverse — its phone was clamped at `min(1, …)` and sat at its 214pt drawing height in a 338pt
panel, the emptiest picture on the screen on the page whose whole job is to be believed.

**Fixed — the copy had no entry point and never moved.** One `.body` paragraph in system grey,
five lines, nothing in it more important than anything else. `OnboardingPage` has a `lead` now
— one of the body's own sentences, lifted out and set apart by weight and colour rather than by
size — and `PageCopy` stages title, lead and body seventy milliseconds apart, which is the order
they are meant to be read in. It is its own view so that `.id(page.id)` rebuilds it and the
stagger fires on every turn.

**Fixed — one animation was decoration and is now an argument.** The library grid lit a
`DS.deep` border on and off forever through five phases: the motion for something being
*selected*, on the screen that asks permission to *look*. It is one pass now, corner to corner,
that runs once and holds — measured at the last tile of the pass, saturation 0.210 at t=0.35s
against 0.544 settled.

Still open and older than any of this: `DS.destructive` (#E5342B) and `DS.tier(.similar)`
(#BC4127) are both reds carrying two different meanings — "this control destroys files" and
"deleting this costs you something" — the same collision the retired `aqua` token caused and
that `DesignSystem.swift:80` records. Fixing it touches the whole app, not this screen. So does
the wider complaint that the app reads as gloomy throughout.

**Fixed — a test that passed once per simulator.** `testTheAccessCardIsFullWidthAfterTheCover-
Dismissed` launched with no arguments and relied on `hasSeenOnboarding` being false. The first
test in the file that taps Skip writes it to `true`, and it survives every reinstall — so the
test passed on a fresh simulator and failed on every run after, with a message blaming the app
for state the test had left behind itself. Proven rather than argued: the flag read `true` in
the container's plist, and `simctl uninstall` followed by the unchanged test turned it green. It
launches with `-onboarding` now, which beats the store while leaving `-ui-testing` off, so the
library is still the real one and the cover is there whatever the simulator has been through.
Two consecutive runs against a dirty simulator, both green.

**Fixed — the three UI reds that had been carried as "not ours".** They had been recorded for
sessions as pre-existing and nobody had opened them. Two were one defect.

`GroupUITests` ×2 never reached the group screen at all. `ReviewView` draws its dock through
`safeAreaInset(edge: .bottom)` as a floating panel the list scrolls under — deliberately, and
`ReviewView.swift:786` says so — and at the scroll position `openFirstGroup()` arrives at, the
first group row is entirely beneath it: the row measures `{{87, 713}, {287, 72}}`, the dock's
key `{{209, 758}, {163, 52}}`, and the panel reaches about fifty points higher again. `tap()`
sends the touch to the element's centre, so the touch went into the dock, armed the plan and
opened the confirmation sheet; the assertion two lines later then reported that the group screen
had no survivor named on it, which was true, because the group screen had never been opened. The
screenshot at the moment of failure was the review screen with a delete sheet over it.

`isHittable` is not the guard for this, and the first attempt at the fix proved it: it answered
*true* for a row covered end to end, and changed nothing. The guard is geometry — scroll until
the row clears the dock, and refuse to tap if it never does.

The third, `CrossSourceUITests`, is two separate things. There was a real defect: the test tapped
the picker's Browse tab unconditionally, and two element trees dumped a frame apart show what
that did. Before the tap the picker was already at `DOC.browsingRoot Source:
com.apple.FileProvider.LocalStorage, Title: On My iPhone` with `File View` in it — it reopens
where it was last, which this file's own comment further down already knew. After the tap it was
at `DOC.sidebar` showing Locations. The tap did not open the list, it navigated back out of one.
Tapping only when the list is absent moves the failure from line 178 to line 220.

What remains at 220 is not a defect at all: the fixture folder is written by
`real-library-check.py --setup-only`, and `ci.yml:493` runs this suite in the `real` job and
nowhere else. Neither UI shard includes it. A bare `xcodebuild test` runs it and it fails — the
invocation being wrong, not the test. Also corrected: the note that this one "fails at a
different line each run" no longer describes it. Three consecutive runs failed on the same line.

**Fixed — four tests that ran nowhere.** `OnboardingUITests` was in neither UI shard, so the
four tests guarding the one screen that stands between a person and the permission alert had
never been executed by CI. It is in the short shard now: twenty-seven seconds for all four,
against the two hundred and twenty that already anchors the other.

### 5c. The second hour on a real phone — 14 September 2026, evening

iPhone 13 Pro Max, iOS 26.6.1, **a debug build signed with a free personal team**. That last
clause is load-bearing for the first two findings and must not be forgotten when they are
chased. Reported by the user as he went; recorded before they are understood, so they are not
re-found.

**Launch takes thirty to forty seconds on a black screen. NOT MEASURED.** No instrumentation was
running and no hypothesis below has been tested. The candidates, in the order they are worth
eliminating: a debug build is `-Onone` and SwiftUI on device is dramatically slower unoptimised;
a free-team development build is signature-validated on first launch; and something may be
holding the main actor before the first frame — `AppEnvironment`'s statics, `StorageProbe`, or
`RootView`'s `.task { await model.refresh() }`. **The one measurement that splits this three
ways is a Release build to the same phone, timed.** Do that before touching a line of code.

**The onboarding drew with no text and no artwork, and everything arrived very late. Half of
this is the redesign's own doing and it has to be said plainly.** Every scene and every line of
copy on that screen starts *invisible* and becomes visible only when `onAppear` fires:
`PageCopy` holds `opacity(0)` until `shown`, `LadderScene`'s `keyframeAnimator` starts at
`RungEntry(opacity: 0)`, `LibraryScene`'s tiles sit at `opacity(0.1)` until `read`. When the main
thread is saturated at launch, `onAppear` lands late and the screen is *literally empty* until it
does. The entrance animation converts "slow" into "broken", which is a worse failure than the
slowness it is drawn over. The fix is not to remove the motion: start at the final opacity and
animate a transform, so a frame that arrives before the animation still carries the content.

**Granting photo access leaves the person sitting on the onboarding screen. ROOT CAUSE FOUND —
this one is not a hypothesis.** `OnboardingView.act()` awaits the grant closure and only then
calls `finish()`, with the key disabled the whole time. `RootView.swift:146` wires that closure
to `model.requestAccess()`, and `OverviewViewModel.swift:116` is:

    func requestAccess() async {
        access = await library.requestAccess()
        startObservingIfReadable()
        await loadInventory()          // the entire library, before this returns
    }

So the cover cannot come down until every asset has been enumerated. On a library this app is
explicitly *for* — fifty thousand assets — that is tens of seconds of a screen that looks hung.

The fix is small and the reason the grant was routed this way survives it. `RootView.swift:139`
records why the cover dismisses through `requestAccess()` and not around it: it must not dismiss
onto a screen still showing a permission wall. But `access` is already set at line 117, *before*
`loadInventory()` — so finishing between the two satisfies that requirement exactly. Dismiss on
the grant; let the inventory arrive behind the overview, which already has a loading state.

**The History chip carries two backgrounds.** `RootView.swift:251` gives it its own
`RoundedRectangle(cornerRadius: 9).fill(DS.deep.opacity(0.13))`, and the element tree puts the
chip inside the `NavigationBar` — where iOS 26 draws its own background behind a bar item. Two
rectangles, two radii, one control. ⚠️ **Unverified**: that the outer one is the system's own
iOS 26 bar chrome rather than something else of ours. The same tinted-rectangle pattern is used
elsewhere — `ReviewView.swift:396` and `:497`, `GroupDetailView.swift:171`,
`CompareSliderView.swift:127` — but every one of those is a *selection* state on a plain ground,
where a background is the point. The chip is the only one sitting inside system chrome.

**Leaving a scan kills it, and the user hit it on the phone. MECHANISM CONFIRMED.** He pressed
Back mid-scan and the scan cancelled. §5b had this as a report; it is now reproduced and the code
says exactly why:

    ScanView.swift:9    @StateObject private var model: ScanViewModel   // the scan's life is the view's
    ScanView.swift:95   .onDisappear { … model.cancel() }               // leaving it ends it
    RootView.swift:126, :289                                            // built in two places, fresh each time

Both halves have to go. The `@StateObject` means the model is *owned* by the view, so the scan
cannot survive a pop even with the `onDisappear` removed — it would be deallocated anyway.

**And the thing that was asked for is the other half of the same change.** "Put progress at the
top of the screen so it is visible while walking around the app" is not a UI addition on top of
this; it is only *possible* once the scan outlives `ScanView`. The order is: move ownership up
(a shared scan object at `AppEnvironment` or `RootView` level, with `ScanView` observing rather
than owning), stop cancelling on disappear, decide what a backgrounded scan does — iOS suspends
the process, so either a `BGTask` or an explicit "it pauses" — and only then draw the bar. Drawing
the bar first would produce a strip that reports on a scan that no longer exists.

**Start Scan: the progress bar began at about a quarter, the labels stuttered, then it advanced.
NOT MEASURED.** A bar that starts at 25% is either a weighting whose first stage is already
counted complete, or a first published value that only arrives after enumeration has finished.
`ScanView` is already on the §5b list for replacing its ledger with a progress card the moment
work starts; this belongs with that work.

### Reported, not yet diagnosed — a screenshot is coming for these

Written down before they are understood, so they are not re-found:

- **The scan screen is one card on a near-black field.** `ScanView.swift:33-42` replaces the
  intro card with `progressCard` the moment scanning starts, so the plan ledger — the one
  thing a waiting person would want to read — disappears exactly when the waiting begins.
  `DS.ink` is `0x080C11` in dark mode. `SweeperRingView` already exists and is used in
  `ConfirmDeleteSheet` and `ReviewView`, but not on the only screen where anybody waits.
- **A scan cannot be left.** `ScanView.swift:80-84` cancels on `onDisappear`, and the model is
  a `@StateObject` on the view. "Show progress at the top of every screen and let people walk
  around the app" is therefore not a UI addition — it means moving scan ownership out of the
  view and deciding what a backgrounded scan does.
- **The review meter shows no colour** when *Lower-quality re-sends* and *Burst leftovers* are
  the selection. `ReviewView.swift:709-719` draws `value: savings.onDeviceBytes` over
  `total: maxReclaimableBytes`, tinted by the deepest selected tier. Both tier colours exist
  (`DesignSystem.swift:120-121`), so the suspicion is a bar near zero width rather than a
  missing hue — cloud-only or small originals contributing nothing on-device. **Not measured.**
- **Thumbnails do not appear in group detail.** The horizontally scrolling comparison strip is
  there and moves; the photographs are not in it. On a device with a real library this is the
  most serious of the five — every screenshot in `docs/screenshots` comes from a stub loader.
- **"Similar shots" scrolls without end and nothing in it is ticked.** By design the bottom
  rung is unticked and one-by-one, but at real-library scale that reads as an endless list of
  work rather than a considered default. The tier is right; the presentation of a large one is
  not.
- **No video section appeared at all.** §5 and §8 record `sweep()` being unable to reach the
  video sections and conclude the checker was wrong, not the app. A person now reports the same
  absence on a device. That does not overturn the conclusion — the library may simply hold no
  video duplicates — but it is the second time this has been seen and it is no longer only a
  script's opinion.

---

## 5b-bis. Two expert audits — read `docs/AUDIT-FINDINGS.md`

Two review agents went over `docs/SWIFTUI-TRAPS.md` and the screens behind it on 15 September
2026. **Nothing they found is fixed.** The notebook itself has errors — case 2's mechanism is
wrong (`Circle` does not stretch), case 3's `.id(section.id)` experiment held its own variable
constant, and case 6 covers one of the two marks on that thumbnail. Everything is in
`docs/AUDIT-FINDINGS.md` with `file:line`; do not re-derive it.

---

## 5c. What a big library found — measured 15 September 2026

Every number this project had came from a twenty-eight item fixture. `ScanScaleTests` in
`DupeCore` builds a synthetic camera roll — a fifth of it in near-duplicate pairs, the rest
photographs of unrelated things, feature prints dense in all 768 elements so the early exit in
`proximity(within:)` behaves as it does on real vectors. No simulator: `swift test` runs it.
The measurements are gated behind `DUPESPACE_SCALE=1` because the heaviest one takes five
minutes; the correctness tests run every time.

Debug build, Apple silicon, `swift test`. **A Mac, not a phone.**

### The sweep is quadratic and feature prints cost seventy times the hashes

| items | pairs | prints on | prints off | ratio |
|---|---|---|---|---|
| 500 | 124,750 | **1.52 s** | 0.023 s | 65x |
| 1,000 | 499,500 | **6.03 s** | 0.085 s | 71x |
| 2,000 | 1,999,000 | **24.25 s** | 0.313 s | 77x |

Four times the pairs, four times the time, at both settings: `ScanPipeline.edges` is n-squared
exactly as written, and nothing in the measurement is amortised or cached away.

Extrapolating the prints-on column on that curve — **not measured, arithmetic**:

| library | pairs | projected |
|---|---|---|
| 5,000 | 12.5 M | ~2.5 min |
| 10,000 | 50 M | ~10 min |
| 20,000 | 200 M | ~40 min |
| 50,000 | 1.25 B | ~4 h |

Fifty thousand is the number this repo's own notes use for a large library. On a phone, slower.
The hashes alone would do the same fifty thousand in about **13 minutes** on this curve, which
is the size of the trade feature prints bought: `docs/OPPORTUNITIES.md` §9.1 measured them
separating a 30 % crop from an unrelated photograph 10.19x better than the hashes, and §9.2 is
why the bottom rung works at all. The cost of that was never measured until now.

Two things make the real figure worse rather than better:

- The synthetic unrelated vectors sit ~2.0 apart; Vision's measured ~1.67. A closer pair
  accumulates more slowly and **exits later**, so real vectors cost more per pair, not less.
- The early exit only helps pairs that are *far apart*. Every pair inside the threshold is
  summed over all 768 elements. A pile of near-identical photographs therefore pays full price
  on every pair of itself — which is why the 2,000-copy pile below takes five minutes on its
  own.

**Not decided.** A pre-filter — the LSH sketch that was refused in an earlier round for being an
optimisation without a measurement — now has its measurement. Whether to build one is open.

### A pile above the neighbour cap fragments, and every fragment keeps a copy

`ScanPipeline.maximumNeighboursPerItem` is 256, and it drops edges to bound memory at n x 256
instead of n squared. `DuplicateClusterer.similarGroups:69` is seed-first: it takes one seed's
neighbours, forms a group, and moves on. Above the cap, no single seed can reach a whole pile.

| copies of one screenshot | groups | reachable | left after cleaning |
|---|---|---|---|
| 300 | 1 | 300 | **1** |
| 1,000 | 5 | 1,000 | **5** |
| 2,000 | 10 | 2,000 | **10** |

Nothing is lost — every copy is reachable and offered — and 995 of 1,000 is most of the win.
But the rung's promise is "keep one", and above the cap the app keeps roughly one per two
hundred. The comment on the cap names "five thousand screenshots of the same app screen" as the
case it exists for; on this curve that case leaves about twenty-five.

Pinned by `testHowManyCopiesSurviveCleaningOnePile` under `XCTExpectFailure`, so the assertion
in the file is what the app promises and the test goes red the day somebody fixes it.

**Not fixed, and deliberately not fixed quietly.** The obvious repairs all change what a group
means: transitive closure can chain A~B~C where A and C are not alike, which is the failure this
app cannot have. Raising the cap moves the cliff without removing it. This is a decision, not a
patch.

### What is still right up there

- 50 planted pairs among 500 photographs: all 50 found, and exactly 50 groups — no unrelated
  photograph joined to anything, across ~160,000 non-duplicate pairs.
- No `solo-` item was ever offered for deletion.
- Cancellation is honoured inside the sweep at 2,000 items.

### Not measured

Memory. The figures above are wall time and counts only; nothing has watched the peak. The
scan's own throttling (`ScanThrottling`) was bypassed with `UnthrottledScan` so the numbers
describe the algorithm rather than the scheduler. The list's scrolling at this size has not
been looked at.

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
| `core` | `DupeCore`, platform-free, 307 tests | 43 s |
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
- **`sweep()` in `real-library-check.py` reaches the photo sections and not the video ones.**
  It reported four groups where the app was offering eight, and named the four it could not
  reach as the app's failures — three clip re-sends and a byte-identical clip that had all in
  fact been found. **A checker that cannot see half the screen must not be the thing that says
  the app is broken.** The count on the "Everything" chip is the assertion now; the per-name
  lines are notes, and they say "not seen by the sweep" rather than MISSED.
- **`FileManager.trashItem` coordinates the file access itself.** Calling it inside
  `NSFileCoordinator.coordinate(writingItemAt:)` can deadlock — the same URL is coordinated
  twice and the call never returns. If folder trashing is ever built, it goes in uncoordinated.
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
- **Scrolling a fixed number of times is a bet on the length of the screen, and screens grow.**
  `scroll_to` in both simulator walks swiped eight times and gave up. The live surfaces entry
  is the last thing on the overview; run 162 added the second-resources card above it, and by
  run 167 — a commit that changed nothing but documentation — eight swipes no longer reached
  the bottom. The walk reported "not reachable", which reads like a control that had been
  renamed or removed, and the tree dump was the only thing that said otherwise: the button was
  there, at y=1057 on a 956pt screen. Both scripts now stop when the content stops moving
  instead. A screen has a bottom; arriving at it is the only honest reason to stop looking.

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
   project.

   **And it is avoidable — there is a Mac with Xcode.** `docs/RUN-ON-YOUR-PHONE.md` now carries
   the commands: `swift test --package-path Packages/DupeCore` alone runs 307 tests in seconds
   with no simulator at all, and the UI suites run one at a time against a local device. Run
   those before pushing and CI stops being where anything is discovered.
3. ~~Fix `real-library-check.py` so it stops reporting the clips as missing.~~ Answered in runs
   159 and 160: the clips were never missing. The app offers all eight items the fixture builds
   — both byte-identical photographs, both photo re-sends, all three clip re-sends and the
   byte-identical clip — and `sweep()` could only reach four of the group rows, so it named the
   four it could not see as failures. The count on the "Everything" chip is the assertion now
   and it passes; the per-name lines say "not seen by the sweep".

   **What is left of it is small and bounded**: the kind chips sit in a horizontal `ScrollView`
   and idb cannot reach the Videos one, so the video sections are still unswept. Nothing about
   the app depends on that — the count covers it — but a driver that could reach them would let
   the per-name checks mean something again.
4. **Now the first item, and it cannot be done from here.** Run it on a phone and answer the
   trashing question in §5 — whether a Files provider allows `trashItem` where an app's own
   container does not. That decides whether folder deletion can offer the 30-day undo the photo
   half already has, and it is the most valuable unanswered question left.
   `docs/RUN-ON-YOUR-PHONE.md` and `Scripts/for-my-phone.sh` are ready for it; §9 says what a
   person has to do.
5. Then RAW+JPEG, then Live Photo, then screenshots by age.
6. And the standing one: **nobody has used this app.** 470-odd tests, a green pipeline and a
   measured layout are not the same as one person with ten thousand photographs of their own.
