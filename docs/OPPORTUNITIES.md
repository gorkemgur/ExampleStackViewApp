# Opportunities — the research ledger

Written 14 September 2026, from a six-agent research sweep run against the iOS 26.4 SDK
(Xcode 26.4) and against competitor apps in the field. **Three of six reports are in**;
§8 names what is still outstanding.

This file exists so nobody researches this twice. It is organised by *how much we know*,
the same way `STATE-OF-PLAY.md` is, because the same rule applies: a claim nobody checked
is a slogan.

Every API below was verified by reading the SDK header and compiling a probe. Symbols that
do not exist were falsified by a compile error, not assumed. Anything not confirmed carries
the literal marker **UNVERIFIED**.

Project floor is **iOS 17.0** (`project.yml:5-6`). Availability is stated against that floor.

---

## 1. Two confirmed defects

Both found by the PhotoKit sweep, both re-verified by hand against the working tree before
being written down.

### 1.1 Burst frames are invisible to the app

`PHFetchOptions.includeAllBurstAssets` defaults to `NO` (`PHFetchOptions.h:26-27`) and is
never set:

```swift
// DupeSpace/Sources/Services/Library/PhotoKitMediaLibrary.swift:28-31
let options = PHFetchOptions()
options.includeHiddenAssets = false
options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
let assets = PHAsset.fetchAssets(with: options)   // only the representative frame arrives
```

Consequence: the largest pile of near-identical frames on an ordinary iPhone never enters
the inventory. `RegretTier.burstLeftover` exists (`RegretTier.swift:149-152`) but is fed
only by whatever perceptual edges happen to link representative frames.

Cost of the fix is one line; the cost of the *consequence* is not — inventory size and scan
time both rise materially, so it has to be accounted for in `ScanThrottling`.

### 1.2 One undeletable asset fails the entire batch

`canPerform(_:)` (`PHAsset.h:74`, `PHAssetEditOperation.delete`, iOS 8) is called **nowhere**
in the repo (grep: zero hits). Deletion is a single atomic block:

```swift
// DupeSpace/Sources/Services/Deletion/MediaDeleting.swift:157-159
try await PHPhotoLibrary.shared().performChanges {
    PHAssetChangeRequest.deleteAssets(assets as NSArray)   // all or nothing
}
```

An iTunes-synced or shared-album asset cannot be deleted. Because `performChanges` is atomic,
one such asset fails the whole confirmed deletion: the user answers the system alert, nothing
is removed, and they are handed `DeletionError.failed`.

**Not measured** — this is reasoned from the atomicity of `performChanges`, and no test
provokes it. A test that plants an undeletable asset would pin it.

Fix direction: filter with `canPerform(.delete)` at plan time and give the refused items
their own card that says why.

---

## 2. What DupeSpace already does

Verified by reading the code, not the docs. Do not re-propose these.

**Detection.** SHA-256 over every `PHAssetResource`, each prefixed `"r<type>|"`, filename
deliberately excluded (`PhotoKitAssetAnalyzer.swift:34-53`). Perceptual: hand-rolled dHash
(9×8, `PerceptualHasher.swift:26-39`) **and** pHash (32×32 DCT, DC term replaced by
coefficient `[8]`, `:50-122`), both on a 64×64 grey buffer (`GrayImageRenderer.swift:11-40`),
decoded at 4× render size on both halves. Video: 10 frames at fixed normalised positions,
pHash only, ≥6 distinct hashes required (`VideoSignature.swift:9-33`,
`VideoFrameSampler.swift:24-65`).

**Thresholds** (`ScanPipeline.swift:33-51`): `nearExactDistance 6`, `similarDistance 12`,
`aspectRatioTolerance 0.01`, `videoAverageDistance 8`, `videoWorstFrameDistance 16`,
`videoDurationTolerance 0.5`, `videoShapeTolerance 0.5`, `maxConcurrentReads 4`. User-selectable
strictness strict/balanced/loose (`ScanStrictness.swift:23-42`).

**Clustering.** Exact = digest buckets. Near-exact and similar = **star clustering** around the
highest `globalRank` member; union-find explicitly rejected because a distance threshold is not
transitive (`DuplicateClusterer.swift:45-103`).

**Keeper choice.** Metadata only, no pixel quality (`KeeperScorer.swift:19-30`): protected 1000,
edited 300, highest resolution 200, Live Photo 150, largest file 100, user-library original 80,
oldest 50, location 40, screenshot −100, cloud-only −25.

**Already strong, leave alone.** Honest savings split into immediate / deferred / cloud-only
(`SavingsCalculator.swift:9-47`). Export-originals-before-delete with a manifest
(`OriginalExporting.swift:57`). Cross-source folder↔library matching (`CompositeServices.swift`).
`isNetworkAccessAllowed = false` everywhere, cloud-only items set aside before work is scheduled
(`ScanPipeline.swift:169-170`). Thermal and Low Power throttling (`ScanThrottling.swift:27-47`).
Persistent fingerprint cache keyed on a format tag so changing the hasher invalidates it
(`FingerprintCache.swift:4-34`, `MediaItem.swift:139-143`).

**Absent.** Vision — entirely; the word appears once, in a doc comment (`AssetAnalyzing.swift:28`).
No CoreML, no CoreImage import, no `BackgroundTasks` import, no `UIBackgroundModes`. No undo
anywhere. No swipe surface. No session cursor. No blur, OCR, face, or aesthetics signal.
Live Photo video-half stripping refused as impossible (`SecondResources.swift:1-25`) — see §3.9,
it is possible by another route.

---

## 3. PhotoKit — verified against iOS 26.4 SDK

Header root:
`…/iPhoneOS26.4.sdk/System/Library/Frameworks/Photos.framework/Headers/`

### 3.1 Apple's Duplicates album is NOT readable. Settled.

Three independent checks: `PHAssetCollectionSubtype` ends at `.smartAlbumScreenRecordings = 220`
(`PhotosTypes.h:72-112`); grep for "duplicat" across every Photos and PhotosUI header returns
three unrelated prose hits; and the compile fails. The album exists in the system
(`photos://album?name=duplicates` is a literal in `PhotosUICore`) but is not vended.

**Our detection engine is the product. There is no shortcut to borrow.** Do not look again.

### 3.2 `PHAssetResource` file size — GREY ZONE, keep it

Public surface has no size property; falsified by compile. The real symbol is
`-[PHAssetResource(Private) fileSize]` — a declared property (`TQ,R,N`, ivar `_fileSize`,
`unsigned long long`), so `value(forKey: "fileSize")` goes through a genuine getter and is
stable, not ivar-poking. KVC emits the string but **no ObjC selector reference**, so Apple's
selector-literal scan does not see it. Still guideline 2.5.1 in principle.

We already do this, nil-tolerantly (`PhotoKitMediaLibrary.swift:110-117`). Keep that shape.

Public alternatives lose: `requestData` streams every byte; `requestContentEditingInput` returns
only the current rendition and needs the resource local.

### 3.3 Resource waste map — `PhotosTypes.h:176-192`

`.photo`1 `.video`2 `.audio`3 `.alternatePhoto`4 `.fullSizePhoto`5 `.fullSizeVideo`6
`.adjustmentData`7 `.adjustmentBasePhoto`8 `.pairedVideo`9 `.fullSizePairedVideo`10
`.adjustmentBasePairedVideo`11 `.adjustmentBaseVideo`12 `.photoProxy`19 (iOS 17).

Three waste classes: Live Photo movie half (9/10/11), RAW+JPEG pair (4 beside 1), edit overhead
(5/6 + 7 + 8/12 — an edited photo stores original *and* rendition *and* the adjustment blob).

`PHAssetResource.pixelWidth`/`pixelHeight` (`PHAssetResource.h:28-29`, **iOS 16**, public, free)
lets us settle per asset whether `.alternatePhoto` is the RAW half instead of assuming it, which
`PhotoKitMediaLibrary.swift:70-73` currently does.

### 3.4 Burst — Apple already ranked the frames

`burstIdentifier` `PHAsset.h:62` · `burstSelectionTypes` `:63` · `representsBurst` `:64` ·
`PHAssetBurstSelectionType .none/.autoPick/.userPick` `PhotosTypes.h:160-164` ·
`fetchAssets(withBurstIdentifier:)` `PHAsset.h:81` · `includeAllBurstAssets` `PHFetchOptions.h:27`
· `.smartAlbumBursts = 207`. All iOS 8.

`.autoPick` is Apple's own best-of-burst pick, computed on-device with signals we cannot
replicate. `.userPick` is stronger — a human chose it, so it should be near-unconditionally
protected in `KeeperScorer`.

### 3.5 Classification and deletability

`PHAssetMediaSubtype` full list `PhotosTypes.h:140-157`: `.photoPanorama` `.photoHDR`
`.photoScreenshot` `.photoLive` `.photoDepthEffect` `.spatialMedia`(iOS 16) `.videoStreamed`
`.videoHighFrameRate` `.videoTimelapse` `.videoScreenRecording`(13) `.videoCinematic`(15).
We use two of eleven.

- `canPerform(_:)` `PHAsset.h:74` — see §1.2.
- `hasAdjustments` `PHAsset.h:68` (iOS 15) — the direct answer; we currently infer edits by
  scanning resource types (`PhotoKitMediaLibrary.swift:76-79`). `adjustmentFormatIdentifier`
  `:70` names the app that edited it.
- `playbackStyle` `PHAsset.h:30` (iOS 11) — separates GIF (`.imageAnimated`) from Live Photo
  from looping video. GIFs are a duplicate class we do not model.

### 3.6 Smart albums we CAN use

`.smartAlbumPanoramas`201 `.smartAlbumTimelapses`204 `.smartAlbumAllHidden`205
`.smartAlbumRecentlyAdded`206 `.smartAlbumBursts`207 `.smartAlbumSlomoVideos`208
`.smartAlbumSelfPortraits`210 `.smartAlbumScreenshots`211 `.smartAlbumDepthEffect`212
`.smartAlbumLivePhotos`213 `.smartAlbumAnimated`214 `.smartAlbumLongExposures`215
`.smartAlbumUnableToUpload`216 `.smartAlbumRAW`217 `.smartAlbumCinematic`218
`.smartAlbumSpatial`219 (iOS 18) `.smartAlbumScreenRecordings`220.

**The sleeper: `.smartAlbumUnableToUpload` (216, iOS 13).** Assets iCloud refused to sync —
meaning no cloud copy exists, so deleting them is irreversible in a way ordinary deletion is not.
"These 14 items exist only on this phone" is a trust feature no competitor ships.

`PHAssetCollection.estimatedAssetCount` `PHCollection.h:48` — instant per-album counts, no
enumeration; returns `NSNotFound` when it cannot answer quickly.

### 3.7 Deletion mechanics

- One system confirmation per `performChanges` block. Our single atomic block is correct as
  built (`MediaDeleting.swift:157-159`) — except for §1.2.
- **Pre-staging is possible and public.** `PHAssetCollectionChangeRequest`
  `creationRequestForAssetCollectionWithTitle:` `:25` + `addAssets:` `:46` +
  `placeholderForCreatedAssetCollection` `:29`, all in the *same* change block as the delete.
  A named recovery album inside Photos that outlives our history log. Unused today.
  Recovering the created identifier needs `PHObjectPlaceholder` (`PHObject.h:28`).
- **Recently Deleted is neither readable nor emptiable.** grep for "trash|recentlyDeleted"
  across all Photos + PhotosUI headers: zero. `PHAsset.trashedDate` / `isTrashed` /
  `trashedReason` exist in the iOS 26.4 runtime but are absent from the SDK. Private — do not.
- **Deep link.** `photos-redirect` and `photos-navigation` are registered with
  `CFBundleURLIsPrivate: false`; the `photos` scheme is private.
  `photos://album?name=recently-deleted` is a real literal in `PhotoLibraryServices` but rides
  the private scheme. **UNVERIFIED** whether `photos-redirect://` accepts any path grammar —
  only the bare scheme string appears in the binary. Needs a device test. Until then, a plain
  "Open Photos" button with written instructions is the honest build.

### 3.8 Identity and change tracking

- **`cloudIdentifierMappings(forLocalIdentifiers:)`** `PHCloudIdentifier.h:73` (iOS 15),
  `localIdentifierMappings(for:)` `:66`. `localIdentifier` is device-scoped, so today every
  review decision and every cached fingerprint dies on a restore or a new iPhone. Header warns
  at `:63,70` that this is expensive — resolve once at load, once at save. Handle
  `identifierNotFound` 3201 and `multipleIdentifiersFound` 3202.
- **`fetchPersistentChanges(since:)` + `currentChangeToken`** `PHPhotoLibrary.h:114-116`
  (iOS 16), details in `PHPersistentObjectChangeDetails.h:21-23`. Today
  `LibraryChangeObserving.swift:46-53` receives a `PHChange` and **discards the payload**,
  forwarding a bare "something changed" that triggers a full re-enumeration
  (`OverviewViewModel.swift:99-101`). Tokens survive launches. Handle
  `persistentChangeTokenExpired` 3105 by falling back to a full pass, and note
  `PHFetchResultChangeDetails.hasIncrementalChanges` can be `NO` regardless.
- **Limited access.** Info.plist key `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` —
  without it iOS re-prompts limited users with the picker on nearly every launch. We never
  operate in limited mode, so set it to `YES`.

### 3.9 Reclaim mechanisms nobody ships

- **`revertAssetContentToOriginal`** `PHAssetChangeRequest.h:60`. Discards the rendered
  `.fullSizePhoto`/`.fullSizeVideo` **and** `.adjustmentData`, reclaiming edit overhead
  **in place** — same asset, same `localIdentifier`, same albums, same cloud identity, nothing
  enters Recently Deleted. Reclaim that is not deletion. Caveats at `:58-59`: originals must be
  downloaded locally first, and it destroys the user's edits, so it is opt-in per asset with a
  preview.
- **Live Photo → still, keeping the date.** There is no per-resource delete anywhere in the
  framework — our own comments at `SecondResources.swift:14` and `MediaItem.swift:38` are right
  about that. But `PHAssetCreationRequest.forAsset()` `:36` + `addResource(with:fileURL:options:)`
  `:42-44` + `supportsAssetResourceTypes(_:)` `:40` + `PHAssetResourceCreationOptions.shouldMoveFile`
  `:27`, then carrying `creationDate`/`location`/`isFavorite` across
  (`PHAssetChangeRequest.h:47-49`), does it by creating a replacement. State the real costs in
  the UI: new `localIdentifier`, album membership lost, cloud identity lost, and the original
  sits in Recently Deleted for 30 days so disk use temporarily **rises**.

### 3.10 Background indexing

- `BGProcessingTaskRequest` `BGTaskRequest.h:61-87` (iOS 13). `requiresExternalPower` `:85` —
  note the header: setting it also disables the CPU Monitor, which matters for a hashing
  workload. `BGTask.h:82-84` is the constraint that shapes the design: processing tasks run
  only when the device is idle and are terminated the moment the user picks the phone up.
  So background indexing must be checkpointed and resumable, never monolithic.
- **`BGContinuedProcessingTaskRequest`** `BGTaskRequest.h:136-175`, **iOS 26, iPhone only**.
  With `BGContinuedProcessingTask` (`BGTask.h:127-144`), which conforms to `NSProgressReporting`
  and carries `title`/`subtitle`/`updateTitle(_:subtitle:)`. Identifier must be wildcard-shaped
  `<bundleID>.<context>.*`. The user taps Scan, locks the phone, and the scan continues behind
  a system-presented Live Activity — the natural upgrade of the ActivityKit surface we already
  ship (`DupeSpaceWidgets/ScanLiveActivity.swift`). Tasks that appear stalled are force-expired,
  so `Progress` must genuinely advance.
- `ProcessInfo.thermalState` / `isLowPowerModeEnabled` are already used correctly
  (`ScanThrottling.swift:21-37`) — they are simply not wired to any scheduler, because there is
  no scheduler.

### 3.11 Storage measurement

`.volumeAvailableCapacityForImportantUsageKey` (`NSURL.h:361`, iOS 11) — already the right pair
with `volumeTotalCapacity` in `StorageProbe.swift:14-17`.

**There is no public API for "Photos' share of the disk."** Anyone claiming otherwise is
guessing or using private API.

The one cheap missing piece: **re-probe available capacity on next launch and show the measured
delta**, turning "we estimate you freed X" into "you actually freed X". One `URLResourceValues`
read, and it closes a loop no competitor closes.

### 3.12 Small ones

`PHAsset.addedDate` `PHAsset.h:48` (**iOS 26**) — when it landed in the library, as distinct from
`creationDate`, which is the capture date and is user-editable. Detects re-saves and re-downloads
that are otherwise metadata-identical.
`PHImageRequestOptions.allowSecondaryDegradedImage` `PHImageManager.h:61` (iOS 17) — smoother
thumbnail ramp, free.
`PHCachingImageManager.startCachingImagesForAssets` `PHImageManager.h:213` —
`ThumbnailLoading.swift:68` uses plain `PHImageManager`. Do **not** adopt
`allowsCachingHighQualityImages`, deprecated and unused as of iOS 26 (`:208`).
`PHAsset.fetchKeyAssets(in:)` `PHAsset.h:80` — album cover assets, a cheap extra protection
signal for `KeeperScorer`.
`PHAssetCollection.transientAssetCollection(with:title:)` `PHCollection.h:83-84`.

### 3.13 Availability against our iOS 17.0 floor

Measured by compiling at `-target arm64-apple-ios17.0`, not by reading annotations.

**Needs gating — exactly four:** `PHAsset.addedDate` (26), `contentType` on asset and resource
(26), `.smartAlbumSpatial` (18), `BGContinuedProcessingTaskRequest` (26).

**Compiles clean at iOS 17 with no check:** burst selection types, persistent change tokens,
cloud identifiers, transient collections, `.smartAlbumRAW` / `.smartAlbumCinematic` /
`.smartAlbumScreenRecordings` / `.smartAlbumUnableToUpload`, `.photoProxy`,
`allowSecondaryDegradedImage`, `revertAssetContentToOriginal`, `canPerform`, `hasAdjustments`,
resource `pixelWidth`/`pixelHeight`.

---

## 4. Private API — present in the runtime, absent from the SDK. Do not ship.

Recorded here so nobody rediscovers them and is tempted twice. All confirmed present as real
selectors on the shipping iOS 26.4 arm64 `Photos` binary, all confirmed absent from the SDK by
compile error.

- `-[PHAsset overallAestheticScore]`, `curationScore`, `highlightVisibilityScore`,
  `highlightPromotionScore` — Apple's own quality scores. The most tempting thing in the
  framework, and refused for **two** reasons, not one: they sit behind property sets
  (`PHAssetAestheticProperties`, `PHAssetCurationProperties`) reachable only through the also-private
  `-[PHFetchOptions addFetchPropertySets:]`. Reading one on a publicly-fetched asset triggers a
  synchronous Core Data fault **per asset** — a textbook N+1 that would destroy scan time on a
  50k library. A rejection risk *and* a performance trap.
- `-[PHAsset distanceIdentity]` (`NSData`) — almost certainly the perceptual identity behind
  Apple's own Duplicates album. The single most tempting symbol found.
- `-[PHAsset avalanchePickType]` / `avalancheKind` — burst internals ("avalanche" is Apple's
  internal name for a burst stack). Public `burstSelectionTypes` answers the same question
  legally.
- `-[PHAsset isDetectedScreenshot]` — ML-detected, broader than the `.photoScreenshot` subtype.
- `-[PHAsset(Syndicated) syndicatedAppDisplayName]` — "saved from WhatsApp/Messages". Genuinely
  great product material, genuinely private.
- `-[PHAsset cloudIsDeletable]`, `trashedDate`, `trashedReason`, `isRAWPlusJPEG`, `isProRes`,
  `isHEIF`.
- `-[PHAssetResource privateFileURL]` — a direct path to the backing file, giving a true `stat()`
  size and bypassing PhotoKit. **Of everything here this is the one that reads unambiguously as
  sandbox-escape shaped in review.** `fileSize` is a number; this is a filesystem path.

---

## 5. Interaction and motion — the design spec

Full research and rationale from the UX sweep. Deltas only; anything already shipped is named
as such and left alone.

### 5.1 The category's universal failure: losing your place

Slidebox users report that leaving the app restarts the sort. Swipewipe (4.7★, 47.1K ratings)
ships left/right verdicts and has live defects where deleted photos reappear or remain in the
camera roll — *state-truth* failures, where the UI said one thing and the library said another.
Gemini Photos does not swipe; it pre-checks and is reported right "90% of the time", which is
catastrophic when the population is 4,000 and the act is irreversible.

**"Remembers where you left off" has become a marketing bullet** for Offload, Photo Deleter:
Swipe Sort, Swipp and PhotoCull — which is only possible because the category's default is
losing your place. We have no cursor either. Cost: one `Int` per scan.

### 5.2 The verdict axis must be vertical

A horizontal verdict swipe fights `interactivePopGestureRecognizer`, and all three known
resolutions are compromises. Put the verdict on the vertical axis instead:

| Axis | Meaning |
|---|---|
| Drag up | Let it go |
| Drag down | Step back one card (undo) |
| Drag horizontally | Move between copies *inside* the group. Never a verdict. |
| Long press on image | Blink-compare |
| Tap LIVE badge | Play the Live Photo / video (44pt) |
| Two-finger pan in tray | Multi-select, matching Photos |

Swiping down is the safe misfire: a user reaching for Photos' "pull down to dismiss" gets an
undo, which costs nothing. The deck is a **push**, not a sheet — a sheet would put
swipe-down-to-dismiss in direct competition with the verdict axis.

**Keeping is a button, not a gesture.** Keeping is already the default state of every ambiguous
candidate, so it needs a target you can hit — which is also the VoiceOver and motor-impairment
parity path.

### 5.3 Gesture contract

| Parameter | Value |
|---|---|
| `minimumDistance` | 10pt |
| Axis lock | after 10pt, larger of abs(dx)/abs(dy) wins for the rest of the gesture |
| Intent banner opacity | 0 at 24pt → 1 at 72pt, linear, bound directly to translation |
| Commit threshold | 96pt travel, **or** `predictedEndTranslation.height` beyond 140pt |
| Arming haptic | `.impact(.light, 0.6)`, once on first crossing of 96pt, resets below it |
| Rubber band | past 160pt: `y = 160 + (raw − 160) × 0.35` |
| Rotation | `dx / 26`, clamped ±7° |
| Leading edge dead zone | 20pt, so the system pop gesture keeps priority by construction |
| Eject travel | ±(cardHeight + 120) |

**A swipe can never delete.** It writes to `CleanupSelection`; destruction stays behind
`ConfirmDeleteSheet`. Say so permanently in the dock, not as a first-run tip.

### 5.4 Haptic reservations — the anti-sleaze rule

```
.selection              a tick changing                     (already: ReviewView.swift:69)
.impact(.light, 0.6)    the drag crosses the threshold      ← the most important haptic here
.impact(.medium)        a card ejects
.impact(.heavy)         RESERVED — deletion starting        (ConfirmDeleteSheet.swift:226)
.success                RESERVED — deletion completing. NEVER on a swipe.
.error                  a refused or skipped deletion       (currently unused)
.warning                selection enters a state the validator rejects
```

A swipe firing `.success` is exactly how competitors make destruction feel rewarding. A swipe
here is a pending intent: it gets an impact, not a congratulation.

### 5.5 Motion tokens to add to `Shared/Motion.swift`

| Token | iOS 17 spelling | Applies to |
|---|---|---|
| `cardSettle` | `.spring(duration: 0.34, bounce: 0)` | released under threshold. Critically damped: overshoot would read as *rejected*, a lie about what happened |
| `cardEject` | `.spring(duration: 0.28, bounce: 0.18)` | card leaving on a verdict |
| `cardPromote` | `.spring(duration: 0.42, bounce: 0.14)` | card behind rising. Slower than the eject on purpose — the departure is the user's act, the arrival is the app's answer |
| `tally` | `.spring(duration: 0.30, bounce: 0.08)` | pending count and pending bytes |
| `meterFill` | `.spring(duration: 0.75, bounce: 0)` | the storage meter refilling *after a deletion lands* |
| `armPulse` | `.easeOut(duration: 0.12)` | intent banner border 1pt → 3pt |

**The spine of the whole design:** on a swipe the storage bar **does not move**. Nothing has
been freed. Competitors animate a gauge on every swipe, which is a lie that pays in perceived
progress. Here the gauge is inert until `MediaDeleting` returns, then fills with `meterFill` —
the only slow motion in the product, spent once, on the only thing that is true.

### 5.6 Reduce Motion

Reduce Motion is a vestibular accommodation, not a motor one. **The swipe keeps working**; only
the rendering changes. A design that disables gestures under Reduce Motion has misread the setting.

Card does not translate or rotate — the intent banner's opacity carries the drag instead;
threshold and arming haptic unchanged. Eject and promote become opacity-only easings. `meterFill`
becomes `.linear(0.30)` — a bar growing linearly is a readout, not decoration, so it survives.
The blink becomes an instant swap with no crossfade, which works better anyway. The 450ms
pre-dismiss hold at `ConfirmDeleteSheet.swift:207-211` drops to **0**, because with the ring
animation suppressed it buys nothing and is pure latency.

### 5.7 The comparison ladder

Human vision detects change at a fixed retinal position and is poor at side-by-side comparison —
which is why `CompareSliderView`'s header comment rejects side-by-side, correctly. But a wipe
costs a drag, and you cannot spend a drag on 46 cards. So:

| Rung | Cost | Mechanism | Status |
|---|---|---|---|
| 0 | free | **verdict sentence**, one line, auto-generated | new; data exists in `ComparisonMetrics.all` + `keepReason` |
| 1 | 300ms | **blink** — long-press crossfades the keeper in over 90ms | new |
| 2 | ~2s | the wipe | exists, `CompareSliderView` |
| 3 | on demand | difference heat map | exists, `DifferenceOverlay` |
| 4 | on demand | full measurement table | exists, `ComparisonTable` |

Verdict sentence priority: resolution > keep-reason > size > date. Examples:
"The one staying is 1.2 MP sharper and sits in 2 albums. This copy is 4.1 MB." ·
"Same pixels, same date. This copy is a 4.1 MB re-encode." ·
"Taken 0.4s apart. The one staying is sharper." ·
"Alike, but not provably the same shot. Your call."
`.subheadline`, `.fixedSize(horizontal: false, vertical: true)`, **no `lineLimit`, ever** —
truncating the sentence that justifies a deletion is a correctness bug, not a layout compromise.

Blink: **one** `zoom` and **one** `pan` state shared by both layers, applied outside the `ZStack`.
If the layers can drift, the blink shows a pan rather than a difference and becomes actively
misleading. `minimumDuration: 0.18`, because SwiftUI's default 0.5 is dead time repeated 46 times.

### 5.8 Two lanes, and the burst escape chip

Only `burstLeftover` and `similar` enter the deck. Lossless tiers never do — sending a provably
free deletion through a judgement gesture is the interaction-cost failure that kills these apps.

The fast lane earns trust three ways: the **byte figure is the headline and the button is
secondary** (a cleaner that leads with a green CTA is selling; one that leads with the quantity
is reporting); a **"Show me a pair"** button samples three lossless pairs into the existing
`CompareSliderView`, where `DifferenceOverlay` reports "No visible difference" — the app offers
to show its work, which no competitor does; and the two lane cards are the only objects above
the fold, with the existing budget fader demoted below them.

**The burst-batch escape chip** is the highest-value control in the design: after three
consecutive "let it go" verdicts inside one burst, an inline 44pt chip offers "Let the rest of
this burst go too (14)". It converts the slow lane back into the fast lane the moment the user
has *demonstrated* a pattern, rather than the app *assuming* one. Scoped to one burst, never
across groups, reversible from the tray.

### 5.9 Colour-independent tier meaning

`ReviewView.swift:527-548` draws every tier node as `Circle().fill(tint)` at 11pt, so tier
identity is carried by hue alone. Replace with a `TierNode` shape at the same size and tint:

```
.identical / .inferiorCopy  →  filled disc   ●
.burstLeftover              →  half disc     ◐
.similar                    →  hollow ring   ○
```

### 5.10 Undo, and one honest absence

**In the deck:** swipe down or tap a header control. Unlimited depth — it is a stack of
`(candidateID, wasSelected)` pairs and nothing has been destroyed, so there is nothing to bound.

**After deleting: deliberately no Undo button.** `deleteAssets` moves to Recently Deleted;
`FileManager` removal of a security-scoped file is final. An Undo that half-works on half the
selection is the exact category of lie the house rule forbids. What appears instead is the
recovery *path*, with its limits stated.

### 5.11 The honesty card, promoted to the overview

Currently a caption (`ReviewView.swift:863-869`) and one card on a pushed screen
(`HistoryView.swift:100-120`). It should be a persistent card on `RootView`, above the fold,
surviving until the album is emptied: a two-segment meter reading "1.36 GB back now / 4.81 GB
held for 27 days", with the held portion drawn in `DS.neutral` — the token whose own doc comment
reads "a filled neutral, for the part of a measurement this app cannot act on"
(`DesignSystem.swift:34`). Not amber, not red: this is a measurement, not a warning.

And the sentence **"DupeSpace cannot empty it for you"** printed at full weight. It is the app's
single biggest limitation.

### 5.12 Accessibility

A drag is unreachable to VoiceOver, and `accessibilityCustomActions` are not discoverable — so
the deck's two 56pt buttons are the **primary** path and the swipe is an accelerator on top.
That is also the discoverability fix for sighted first-timers and the RSI fix for everyone: a
56pt tap costs a thumb flex, a 96pt drag costs a wrist arc, and 200 of those is an injury.

Card is one element with custom actions (Let it go / Keep it / Step back / Hear the differences /
Open this group) and an `accessibilityAdjustableAction` mapping the filmstrip to
increment/decrement. After each verdict, announce state **and position**: "Let go. 49 ticked,
2.14 gigabytes pending. Card 13 of 46." A VoiceOver user has no header to glance at.

At `dynamicTypeSize >= .accessibility3`: image clamps to 220pt `scaledToFit`, evidence block
becomes a `ScrollView`, dock buttons stack, filmstrip dots become "3 of 17" plus 44pt arrows.
**Consequence:** that `ScrollView` competes with the vertical verdict drag, so at AX5 the drag is
claimed only by the image region and the buttons carry the load.

### 5.13 New files this implies

`DeckView.swift` · `DeckCardView.swift` · `PendingTrayView.swift` · `LosslessProofSheet.swift`;
edits to `Motion.swift`, `DesignSystem.swift`, `ReviewView.swift`, `ComparisonRow.swift`,
`CompareSliderView.swift`, `ReviewViewModel.swift` (+`deckCursor`, undo stack,
`selectionProvenance`, cheap running tally), `RootView.swift`, `ConfirmDeleteSheet.swift`.

---

## 6. Ranked — the unfair advantage

1. **Burst frames** — `includeAllBurstAssets` + `burstSelectionTypes`. A defect fix and a feature
   at once, and it hands us Apple's own best-shot pick for free. Highest value-to-effort here.
2. **`revertAssetContentToOriginal`** — "discard edits, reclaim 3.1 GB" without deleting a single
   photograph. No competitor ships a non-destructive reclaim mode.
3. **`BGContinuedProcessingTaskRequest`** (iOS 26) — scan continues with the phone in the pocket,
   behind a system Live Activity. The most visible product difference available.
4. **`fetchPersistentChanges(since:)`** — kills the full re-enumeration, and is the precondition
   that makes (3) affordable, because a background pass needs bounded work.
5. **Resource-level waste ledger** — Live Photo movie halves, edit overhead, RAW pairs, sized
   individually. Competitors report one number per asset.
6. **`canPerform(.delete)` + `.smartAlbumUnableToUpload`** — two trust features and one latent
   bug fix.
7. **`cloudIdentifierMappings`** — decisions and fingerprints survive a restore or a new phone.
   Invisible until the day it matters.
8. **`PHAsset.addedDate`** (iOS 26) — separates "when taken" from "when it landed here", which
   `creationDate` cannot do because users can edit it.

---

## 7. Open questions — need a device or a measurement

1. Does `photos-redirect://` accept any path grammar? Only the bare scheme string is in the
   binary. Until tested, do not promise a Recently Deleted deep link.
2. Is `.alternatePhoto` reliably the RAW rather than the JPEG half? `PHAssetResource.pixelWidth`/
   `pixelHeight` can now settle it empirically.
3. `matchedGeometryEffect` from an ejecting card to a tray chip, when the source is removed in
   the same transaction. Fallback: a hand-rolled overlay flight on the same spring.
4. `.matchedTransitionSource` surviving `LazyVStack` row recycling at `ReviewView.swift:328`.
5. Parity between `.spring(response:dampingFraction:)` and `.spring(duration:bounce:)`.
   `bounce = 1 − dampingFraction` is documented; `duration ≈ response` is perceptual. Tune on device.
6. `.sensoryFeedback` firing reliably at a single mid-drag threshold crossing at 120Hz.
   Fallback: a `UIImpactFeedbackGenerator` in `@State` with `prepare()`.
7. Does a `DragGesture` on the image region win against an enclosing `ScrollView` at AX5 without
   `.highPriorityGesture`?
8. Does `ReviewViewModel.invalidateDerived()` (`:179`) recompute cheaply enough to drive a 60fps
   deck dock, or does the tally need its own counter?

---

## 8. Still outstanding

All six research areas landed. §9 is the Vision / ML / AV sweep, §10 the Apple Photos
user-complaint survey, §11 the competitor teardown.

**Nothing here is outstanding except device tests** — collected in §7, §9.9, §10.7 and §11.8.
Those cannot be answered from a desk.

---

## 9. Vision, ML and video — measured, not estimated

Verified against iPhoneOS26.4.sdk (Xcode 26.4 / 17E192). The Swift-native Vision rewrite lives at
`Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-ios.swiftinterface` (3340 lines) — the
`usr/lib/swift` copy is a 9-line re-export shim, not the rewrite.

**Every timing below was produced by compiling and running the code on an M1 Pro Mac**, not
estimated. Two caveats the agent would not paper over and neither should we: the corpus was
**one scene plus one control (N=1)**, so margins are directional rather than a benchmark; and a
Mac is not a phone. Re-run against a real library on-device before hard-coding any threshold.
Scratch harnesses are in the session scratchpad (`fp.swift`, `hashcmp.swift`, `shz.swift`,
`av.swift`, `lap.swift`, `iio.swift`, …).

### 9.1 Our perceptual matcher cannot tell a crop from a different photograph

This is the strongest result in the whole sweep and it is a **measured weakness in shipped code**,
not an opportunity. The agent reimplemented `PerceptualHasher` exactly — including the
`block[0] = coefficients[8]` DC patch — and ran it beside Vision feature prints on one corpus:

```
variant                   dHash  pHash  max(d,p)   featurePrint
05_crop90.jpg  (10% crop)    11     16        16       0.0299
06_crop70.jpg  (30% crop)    20     34        34       0.1036
08_letterbox_4x3.jpg         21     16        21       0.1638
09_different.jpg             25     34        34       1.6697
```

A 30 % crop scores **34/64 — bit-for-bit identical to a completely different photograph.** No
threshold can separate them. Separation margin: **ours 1.00×, feature print 10.19×.**

And against the shipped `similarDistance: 12` (`ScanPipeline.swift:33-51`), a **10 % crop scores
16 and is already missed today**.

### 9.2 Feature prints — the metric, decoded

`VNGenerateImageFeaturePrintRequest` `VNGenerateImageFeaturePrintRequest.h:21` (**iOS 13**),
`Revision2` `:50` (iOS 17). `VNFeaturePrintObservation` `VNObservation.h:559`,
`computeDistance:` `:580`. Swift-native `GenerateImageFeaturePrintRequest` swiftinterface:1711 /
`FeaturePrintObservation` :56 with `distance(to:)` — both **iOS 18+**, so on our iOS 17 floor we
use the ObjC API.

The header says only "larger is more dissimilar". Measured: the vectors are **768 float32
(3072 bytes), L2-normalised**, and the distance is **squared Euclidean**, confirmed to five
decimals against a manual computation and exactly equal to 2 × cosine distance. Range [0, 4];
cosine similarity = 1 − dist/2. **It is not a metric** — no triangle inequality — so take `sqrt`
before any metric-tree pruning. (We removed a BK-tree as useless at our radii; this is the note
that stops someone reintroducing one incorrectly.)

Measured distances at 224 px both sides: JPEG q40 re-encode 0.0013 · 1280 px downscale 0.0031 ·
brutal q15 0.0175 · 10 % crop 0.0299 · 640 px downscale 0.0367 · 30 % crop 0.1036 ·
letterboxed 0.1638 · rotated 90° 1.0434 · different photo 1.6697.

**Cost.** dHash+pHash at 64 px = 14.9 ms/image; feature print at 224 px = 26.9 ms/image — both
dominated by the shared JPEG decode, so the **marginal** cost of adding feature prints is ~12 ms.
Revision 1 is 2048 floats / 139.6 ms; **revision 2 is 768 floats / 20.9 ms — smaller and ~7×
faster. Always pin revision 2.**

**Persistence works.** `FeaturePrintObservation: Codable` (swiftinterface:74, iOS 18+). Encoded in
one process, decoded in another: bytes identical, distance exactly 0.0, and
`originatingRequestDescriptor` survived as `…revision2` — a built-in staleness key that belongs
next to our `fingerprintFormat` tag (`MediaItem.swift:139-143`). Cross-revision comparison
**throws** rather than returning garbage. Stability across OS versions is **UNVERIFIED** — one OS
was testable. Pin the revision, treat a descriptor mismatch as cache invalidation.

**Three footguns, all measured.**
- `cropAndScaleOption` is part of the comparability contract: `scaleToFill` vs `scaleToFit` on the
  *same image* differ by **0.452**, larger than most "different image" thresholds. Never mix.
- **Decode size changes the distance.** The 640 px variant scored 0.143 against a 1024 px decode
  but 0.037 against a 224 px decode. Normalise both sides to one decode size — the same class of
  bug as the two-downsamplers defect in `STATE-OF-PLAY.md` §1.
- Bridging a `VNFeaturePrintObservation` into the Swift type yields
  `originatingRequestDescriptor = nil` and `distance(to:)` then throws, even though the bytes are
  identical. Stay in one API family. Upside: an iOS 17 ObjC build produces byte-identical
  descriptors, so the cache survives a later Swift-API migration.

**Rotation is the one failure, and the fix is free.** Rotated 90° scores 1.0434; re-running with
`CGImagePropertyOrientation.left` gives **0.0001**. Read EXIF orientation, or try four
orientations and take the min at 4× cost. Apple's Duplicates misses rotated copies too.

### 9.3 Picking the better copy

- **`VNDetectFaceCaptureQualityRequest`** `VNDetectFaceCaptureQualityRequest.h:25` (**iOS 13**),
  `Revision3` `:44` (iOS 17); `faceCaptureQuality` `VNObservation.h:120`, range **0.0–1.0**. The
  header doc at `:118` describes lighting, blur and position and says the score is for comparing
  *"the capture quality of a face against other captures of the same face in a given set"* —
  which is exactly the keeper problem, and the feature users feel most ("it kept the one where
  nobody blinked"). **Value distribution UNVERIFIED** — no face imagery existed in the sandbox
  (1628 system images scanned, zero faces). Measure on-device before setting a threshold.
- **`VNCalculateImageAestheticsScoresRequest`** `:19`, **iOS 18**;
  `VNImageAestheticsScoresObservation` `VNObservation.h:974`, `isUtility` `:979`, `overallScore`
  `:983-984`, range −1…1. ~8–17 ms at 512 px.

  **`isUtility` works and is worth having**: it flagged both the screenshot and the receipt,
  and neither photograph. A cheap, genuine screenshot/document detector.

  **`overallScore` is a trap and is deliberately NOT recommended.** Measured: pristine original
  0.6958, the same image brutally recompressed at q15 0.6763, downscaled to 640 px 0.6782. It
  barely moves under savage degradation because it scores *content and composition*, not
  technical quality. It cannot tell you which copy is better. This is the most inviting wrong
  turn in the API set — recorded here so we do not take it.
- **There is no general public sharpness/blur/exposure signal.** Grepped every Vision header: the
  only hits are the face-scoped score above and `DetectLensSmudgeRequest` (swiftinterface:1348,
  **iOS 26**), which exposes only `confidence`, and whose model bundle was missing on the test
  machine.
- **Roll our own: vImage Laplacian variance, measured at 0.13 ms** (`vImageConvolve_Planar8` +
  `vDSP_normalize`, 512 px, excluding decode) — effectively free, and monotonic in blur:
  246.9 sharp → 218.6 (σ=1) → 121.5 (σ=3) → 23.8 (σ=8). Two hard caveats from the same run: the
  **screenshot scored 586.7, the highest of everything** (sharp text edges), so it is comparable
  only *within* a group of the same scene, never across content; and it barely moved for
  overexposure (210.5) or q15 recompression (243.7), so it detects neither.
- **`VNGenerateAttentionBasedSaliencyImageRequest`** `:20` (iOS 13), 9–34 ms at 512 px, one
  salient box. Does nothing for matching; it makes the compare screen legible, which is where
  trust is won.

### 9.4 Video — ShazamKit is the unfair advantage

**Frame sampling tolerance is a 10× cost lever**, measured on a 40 s 1080p H.264, 10 frames at
160 px: `.zero` 75.4 ms/frame (0.000 s drift) · 0.4 s → 21.0 ms (0.375 s drift) · `.infinity` →
7.5 ms (0.500 s drift). Our current `min(0.4, seconds/20)` (`VideoFrameSampler.swift:41-42`) is
in the sweet spot, and the reason to keep scaling it is measured: 0.5 s drift is 1.25 % of a
40 s clip but **10 % of a 5 s clip**.

**Visual temporal fingerprints are workable but not decisive.** 10 frames at 512 px: 209 ms to
extract, 343 ms for 10 feature prints, 30 720 bytes. Against a 640×360/crf32 re-encode: mean
**0.2306**, worst 0.2769. Same-pixels control: exactly 0.0000. That 0.23 sits uncomfortably close
to a loose threshold.

**ShazamKit custom catalogue — no entitlement, no network, and it matched everything visual
struggled with.** `SHSignatureGenerator.generateSignatureFromAsset:` `SHSignatureGenerator.h:47`
(**iOS 16**) · `SHCustomCatalog` `SHCustomCatalog.h:20` (iOS 15) ·
`addReferenceSignature(_:representing:)` `:34` · `dataRepresentation` `:23` /
`init(dataRepresentation:)` `:65` (both iOS 18) · `SHSession(catalog:)` `SHSession.h:104`.
Decisive line at `SHSession.h:58-60`: *"If you are using a custom catalog, you don't need to
enable ShazamKit."*

Measured end to end:

| | |
|---|---|
| `minimumQuerySignatureDuration` | **1.0 s** |
| `maximumQuerySignatureDuration` | **12.0 s** |
| signature generation | ~**1.5 ms per second** of audio (40 s → 62.5 ms) |
| signature size | ~**180 bytes/s** (40 s → 7144 B); catalogue ~337 B per 4 s entry |
| lookup against a 79-entry catalogue | **1.44 ms** |
| 640×360 / crf32 / 64 kbps mono 32 kHz re-encode | **MATCHED** |
| 12 s trim, re-encoded | **MATCHED**, and `predictedCurrentMatchOffset` returned **14.00 s — the exact trim point** |
| −40 dB near-inaudible audio | **MATCHED** |
| 1.05× speed and pitch change | **MATCHED** |
| different audio | correctly **not** matched — no false positive |

That trim offset is a product feature, not just a match: "this is a 12-second clip cut from that
40-second original, starting at 14 s."

**Where it fails, stated plainly.** A video with **no audio track throws** (`com.apple.ShazamKit`
code 100, "audio format is not supported") — that is a branch, not a no-match. Digital silence
*with* a track signs fine but never matches. Silent screen recordings, time-lapses and muted
exports all fall back to the visual route. Also, the catalogue rejects a duplicate signature with
`SHError 300`, so signatures carry identity.

**Re-encode tells from `AVAsset`**, measured: `estimatedDataRate` separated the variants sharply
(11 172 / 121 / 396 kbps) and audio sample-rate plus channel count is a strong tell
(44 100 Hz 2ch → 32 000 Hz 1ch). **`nominalFrameRate` is unreliable — it reported 240.00 for all
three**, a container artifact. Do not trust it alone. The `AVMetadataItem` keys real messengers
leave behind are **UNVERIFIED** — the test files were ffmpeg-generated. Test against genuine
WhatsApp/Telegram exports.

### 9.5 Content understanding

- **`VNRecognizeTextRequest`** `:31` (iOS 13). Measured: **`.fast` returned 0 lines** on both the
  receipt and the screenshot; `.accurate` returned 13 and 45 lines at 548 / 613 ms (1024 px).
  Budget for `.accurate` or skip OCR — `.fast` is close to useless for this content.
- **`VNClassifyImageRequest`** `:23` (iOS 13), ~10–30 ms. **Taxonomy measured at 1303 labels.**
  Present: `receipt`, `screenshot`, `document`, `printed_page`, `whiteboard`, `food`, `people`.
  **Absent: `text`, `menu`, `business_card`, `id_card`, `selfie`, `pet`, `landscape`.**
- **`VNDetectDocumentSegmentationRequest`** `:18` (iOS 15). Found the screenshot (0.76 conf,
  6.8 ms) but **not** a full-bleed receipt (372.8 ms) — it looks for a document *within* a scene,
  not a page filling the frame.
- **`RecognizeDocumentsRequest`** swiftinterface:501, **iOS 26** — `DocumentObservation.Container`
  with title, paragraphs, tables, lists, barcodes, and `text.detectedData` carrying DataDetector
  semantic matches. On a receipt: 932.7 ms, returned the title, 13 paragraphs, a parsed
  `calendarEvent` and measurements. Expensive — only for assets already classified as utility.
- **`VNDetectBarcodesRequest`** `:21` (iOS 11), **25 symbologies**, 85 ms.

### 9.6 FoundationModels — build last, never on the critical path

`FoundationModels.framework/…/arm64e-apple-ios.swiftinterface`, 1503 lines, **iOS 26+**.
`SystemLanguageModel` :514 · `LanguageModelSession.respond(to:generating:)` :378 with
`@Generable`/`@Guide` · `prewarm(promptPrefix:)` :343 · `SystemLanguageModel.UseCase.contentTagging`
:526 (purpose-built for cluster naming) · `supportedLanguages` / `supportsLocale()` :551 — which
we must check, given the Turkish UI.

**Availability on the test machine: `.unavailable(.appleIntelligenceNotEnabled)`.** The three
failure reasons are `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` (:560-562).
**Latency and output quality UNVERIFIED** — the model would not load, and the agent declined to
invent numbers.

Genuinely zero-network and zero-cost, and guided generation into a `@Generable` struct is the
right shape for a cluster name or a one-line keep-reason. But it is unavailable on much of the
installed base, needs a three-state fallback, and every string it produces needs a deterministic
template behind it. **The keep-decision stays deterministic; the model may phrase the reason,
never compute it.**

### 9.7 Decode economics — one decode, shared

Measured, best-of-5 on a 1.8 MB 3840×2160 JPEG:

| operation | ms |
|---|---|
| `CGImageSourceCopyPropertiesAtIndex` (no pixels) | **0.21** |
| thumb 224, `…FromImageIfAbsent` | **0.29** |
| thumb 64 / 128 / 224, `…FromImageAlways` | 12.99 / 13.14 / 13.81 |
| thumb 512 / 1024 | 17.12 / 20.00 |
| full decode, `ShouldCacheImmediately` | 22.42 |

Three consequences. **Metadata is ~65× cheaper than any pixel path** — gate everything on it.
**The cost floor from 64 → 224 px is flat (~13 ms)** because JPEG entropy decode dominates, so
**going below 224 px buys nothing — hash at 224.** And `…FromImageIfAbsent` was 47× faster only
because it lifts the embedded EXIF thumbnail, which is ~160×120 and differently compressed —
since decode size demonstrably shifts feature-print distance (§9.2), **mixing embedded and
re-decoded thumbnails in one index would silently corrupt matching.** Do not use it for hashing.

Benchmarking gotcha: a naive `CGImageSourceCreateImageAtIndex` reports 0.09 ms because it is lazy.
Without `kCGImageSourceShouldCacheImmediately: true` you are measuring nothing.

### 9.8 Ranked — Vision/AV

1. **Feature prints (revision 2)** replacing or augmenting dHash+pHash. The 10.19× vs 1.00×
   separation margin is the whole ballgame. ~12 ms marginal, 3 KB/asset, `Codable`,
   cache-versionable. Works on our iOS 17 floor via the ObjC API with byte-identical output.
2. **ShazamKit custom-catalogue audio fingerprinting for video.** No entitlement, no network,
   ~1.5 ms/s to build, 1.44 ms to query, survives brutal re-encoding and returns the trim offset.
   Apple Photos does not do this.
3. **Orientation normalisation before fingerprinting** — 1.0434 → 0.0001, nearly free.
4. **`isUtility` + `ClassifyImageRequest`** for screenshot/document triage — turns "5 000
   screenshots" from the pathological case our O(n²) sweep fears into a separate, cheaper lane.
5. **vImage Laplacian variance** as the keeper's sharpness signal — 0.13 ms, fills the biggest
   hole in `KeeperScorer`, which today has no image-quality signal at all.
6. **`faceCaptureQuality`** for people shots — Apple's own metric for exactly this question.
   Verify the distribution on-device first.
7. **Metadata-first gating + one normalised 224 px decode shared by hash, feature print,
   Laplacian and aesthetics** — removes the duplicated decode the current split between
   `GrayImageRenderer` and the analyzer implies.
8. **Saliency** for compare-UI thumbnails.

Below the line: `RecognizeDocumentsRequest` (iOS 26, 932 ms), `DetectLensSmudgeRequest` (iOS 26,
confidence only), FoundationModels (cosmetic, unavailable on much of the base).

**Deliberately not recommended:** aesthetics `overallScore` as a keeper signal — see §9.3.

### 9.9 What is UNVERIFIED in §9

`faceCaptureQuality` value distribution · `DetectLensSmudgeRequest` behaviour with its model
present · FoundationModels latency and quality · the `AVMetadataItem` keys real messengers leave ·
cross-OS feature-print stability. Everything else in §9 was compiled and executed.


---

## 10. Apple's Duplicates — what users actually report

Evidence is **Apple Support Communities threads, Apple's own docs, and App Store review text**
pulled from the iTunes review RSS. **Reddit was hard-blocked** from the research environment
(403/502 on every route and mirror), so it is absent — that is a gap, not an absence of evidence.

One discipline note worth keeping: most search hits for these queries are **marketing from
competing cleaner apps** (`luminaclean.app`, `cleanor.app`, `nektony.com`, `cisdem.com`). Their
quotable lines — "only catches pixel-identical copies", "80%+ of wasted storage is not exact
duplicates", "third-party finds 3–5× more" — have **no user or Apple source** and were excluded.
They are a fair read on how competitors *position*, nothing more. Do not recycle them as evidence.

### 10.1 Indexing takes weeks, not the "few days" Apple claims

Apple's own wording ([HT102260](https://support.apple.com/en-us/102260)): *"The detection process
requires iPhone to be locked and connected to power… could happen quickly or take up to a few
days."* Field reports, consistent across many independent threads:

| Library | Reported | Thread |
|---|---|---|
| ~50 000 | "more than three weeks, until Photos has shown the first duplicates" | 254730579 |
| 50 000 | "nearly three weeks, before the first duplicates have been shown" | 255828647 |
| ~55 000 | "more than two weeks for the duplicates album to appear" | 254371799 |
| 50 000 | "left Photos running for over 20 hours but it hasn't found any duplicates" | 254969869 |
| 20 000 | "plugged in for the last week… I'm now in week three" | 255974193 |
| 7 500 + video | "over a day to get the duplicates into the Duplicates folder" | 254665661 |
| 3 500 | "appeared after approx 8 hours" | 254174762 |

**Stalls at zero and never completes** (thread 253174169): *"both my iPhone 11 Pro and M1 iPad Pro
are stuck at '0 photos scanned'"* · *"My phone is locked and on its charger every single night"* ·
*"I have 90,058 photos… it shows 0 Photos scanned."* · *"reducing by a tiny amount every few days."*

**The gating chain users only discover by suffering it:** duplicate detection will not start until
iCloud sync completes *and* the object/face analysis pass finishes (254371799, 254630050).

**No progress UI, no manual trigger, no completion signal.** The coping behaviour is the tell:
*"My Duplicates album finally appeared, but only after I created an 'exact' copy of a photo"*
(254174762) and *"Each morning I restarted the Mac, opened photos and activity monitor"* (254912419).

Reported restart after an iOS update (iOS 18.1 cluster, 255824295) — **symptom confirmed across
iPhone 13/14/15/16 PM, mechanism UNVERIFIED.** The in-thread explanation is a user's guess. To
confirm: watch the analysis counter across a major-version upgrade.

### 10.2 What it misses

**Best-quantified miss**, one user, 25 000-photo library (254665661): Photos found **42**; the same
user then hand-found *"a further 288 duplicates so far."*

**HEIC vs JPEG is a total miss** (254618455). Same user created deliberate exact copies as a
control: *"the duplicate function is still not picking them up (on any of my devices)"*, against a
library that grew from ~60 K to 90 K. The widely-quoted principle that Photos "checks for identical
files, not identical images" traces to a search summary of 253906722 and **could not be found on
direct fetch — UNVERIFIED wording**, though the behaviour is independently confirmed.

**Small libraries find nothing**, which kills the "it's just slow" defence (255828647): 2 510 photos,
*"about two dozen real duplicates"*, none found.

**Similar / burst is out of scope and users expect otherwise** (254174762, 256008771):
*"Doesn't catch similar shots, like burst mode spam or slightly different angles."*

**Apple's own community contradicts itself** on whether "similar" is even in scope — 254730579 and
256021424 describe a similar-photos path; users' lived result is that there isn't one. That
contradiction is itself a positioning opportunity.

**Rotated:** *"I've never seen a rotated version be detected as a duplicate"* (255735331) — which
lines up exactly with §9.2, where a 90° rotation scores 1.0434 until orientation is normalised.

**Video is the weakest area by far** (252730537): *"Photos doesn't have a built in function to
remove duplicate videos"* · *"finding duplicate videos is way harder than photos, as a video should
be analyzed as sequence of frames"* · *"There are no apps that I'm aware of that will compare videos
frame by frame."* The in-thread workaround is fully manual. **That last sentence is the market gap
§9.4 fills.**

**WhatsApp re-compression: UNVERIFIED.** No confirmed report exists. What does exist is a separate
real WhatsApp bug on iOS 17.4 that double-saved attachments as *exact* copies (255523425), fixed by
WhatsApp. Needs a device test. Screenshots-of-photos: **UNVERIFIED**, no report either way.

### 10.3 Merge picks the wrong copy — the sharpest wedge

The strongest and most emotive cluster in the corpus, across many users, multiple threads,
2022 → 2024, photos **and** video.

Keeps the *worse* copy (255557484): *"Photos tells me it will keep the highest quality photo and
delete the lower quality one, but I have found this to be untrue."* · *"keeping the Jpeg with the
smaller file size - the one with the higher lossy compression rate."* · *"There is not much point
having a Duplicate-removal function if it can't be trusted to retain the best photo."* · **"it is a
major bug which has the potential to degrade peoples' life memories."**

Same on video (255194802): *"the Photos app appears to be selecting the larger sized video file for
deletion and keeping the smaller sized video file."* Corroborated by a MacRumors thread titled
*"Photos Duplicates Merge deletes larger version"* (Nov 2022) — **body UNVERIFIED**, MacRumors 403s.

One user's hypothesis worth testing (255564931): *"it seems to keep the photo on the left"* — i.e.
positional rather than quality-based selection.

**Wrong date survives, with no override UI** (254379372): *"Photos correctly keeps the 2008 image
when merging, but applies the 2020 date metadata to the file."* · *"I can find no way to choose the
correct date to apply before the merge."* Consequence at scale (254903998, 5 000+ merged photos):
*"photos are sorted as if they are today's date."*

**Metadata is lost on conflict** (255000523): *"different locations, different titles or captions,
different capture dates, one of them will be lost."* Apple's stated rule — keep the version with the
most metadata (256021424) — is contradicted by field reports where the keeper was metadata-*poorer*.

**No way to say "these are not duplicates"** (254342142): *"There is no way to tell Photos that a
pair of apparent duplicates are not duplicates."* · *"Most of the duplicates shown by Photos in my
library are duplicates I created intentionally, because I need differently edited versions."*

And on taste (255000523, 256008771): *"in a group photo I would want to pick the version where the
people important to me are looking best."* · *"I strongly recommend to pick the 'keepers' yourself
and not to trust photos to have the same taste."*

Apple's only mitigation is Recently Deleted for 30 days. **Nobody reports an audit trail** — every
wrong-keeper bug above was caught by manual spot-checking.

### 10.4 Why people buy third-party

By recurrence: (1) can't trust merge — §10.3; (2) exact-only, no "similar"; (3) recall — *"it's
missed quite a lot and i ran PowerPhotos and it found thousands"* (254969869); (4) **it hides rather
than frees** — *"The duplicate detection is only used to hide the duplicates from the view… they are
still there and are taking up storage"* (251854889); (5) no video dedupe; (6) speed of the human
pass — Slidebox 5★ *"Ten times quicker than iphone builtin tools… Really should make Apple ashamed"*;
(7) *"the default photos app can't sort by size."*

**Competitors fail the same way, and their reviews say so** — these are the openings:
Remo 1★ *"The 'duplicates' had 3 correct out of over 1400… It took over 18 hours to scan"* ·
Remo 2★ *"the 'similar' ones were actually all completely different things"* ·
Cleanup 1★ *"it wanted to delete the good photo and keep the blurry"* ·
CleanMyPhone 4★ *"Given 2 similar photos the one I have saved to multiple albums shouldn't be the
one autoselected for deletion. **This alone prevents me from 'trusting' the smart suggestions.**"*

That last review is our `KeeperScorer` `protectedItem 1000` weight, described by a stranger as the
reason they distrust a competitor. We already do the thing they are asking for; we have never said so.

### 10.5 Shared Library and Optimise Storage

**Shared Library:** the Duplicates album appears only in the *combined* view (254174762) — a
discoverability trap. Real failures after merging two people's libraries (254371799): *"We created a
shared library and we have insane amounts of duplicate photos."*

**Optimise Storage:** whether **Apple's own** scan needs full-resolution originals is **UNVERIFIED** —
no user report or doc either way. It matters directly for us, because we set
`isNetworkAccessAllowed = false` everywhere and set cloud-only items aside. Third-party finders
definitely need originals (253812925). **This is the single highest-value unknown in §10.**

### 10.6 The three sharpest wedges

1. **Merge trust has been broken for 3+ years**, at an unusually high emotional register for a
   support forum. Our answer already exists and is unstated: a named keeper, a printed reason, an
   override, and export-before-delete.
2. **No progress, no ETA, no manual trigger, no completion signal.** Users restart their Mac daily
   and fake a duplicate to force the album into existence. Our answer is §3.10 — a scan that runs in
   the pocket behind a Live Activity, with a real `Progress`.
3. **Video is effectively unserved**, and the community's own conclusion is that nobody compares
   videos frame by frame. §9.4 does better than frame-by-frame.

### 10.7 Device tests this section demands

1. Does Apple's scan work off optimised proxies, or does it need resident originals? (highest value)
2. Does an iOS major update genuinely discard analysis state?
3. WhatsApp round-trip: does Duplicates catch a re-compressed copy?
4. Screenshot-of-a-photo: caught or not?
5. Is merge's keeper selection positional rather than quality-based?


---

## 11. The competitor market — measured from Apple's own feeds, 14 September 2026

Chart data from `itunes.apple.com/us/rss/...` and `rss.marketingtools.apple.com`, feed timestamps
2026-09-14. **Reddit was blocked**, so App Store review text was pulled from the public review RSS
and counted by hand rather than quoted from secondary sources.

### 11.0 Two premise corrections

Both of my original assumptions were wrong. Recorded so they are not repeated.

**"Cleanup: Phone Storage Cleaner" is not a Bending Spoons app — it is Codeway's, and Codeway is
Turkish.** `itunes.apple.com/lookup?id=1510944943` returns seller **DEEP FLOW SOFTWARE SERVICES –
FZCO**, `sellerUrl` codeway.co, bundle ID **`com.codeway.cleanerplus`**, copyright "© Codeway
2020". Codeway (Istanbul + Barcelona, "600M+ downloads, 60+ apps, bootstrapped") lists it as
"#1 in its category six years on". **Bending Spoons publishes no cleaner app at all** — checked
their dev account, their support portal's 22 products, and their SEC F-1, which has zero hits for
"cleaner", "cleanup" or "duplicate photo".

**"Boldly" does not exist as a cleaner.** iTunes Search (US, 200 results), Apple's search-hints
API (empty array), and both Utilities and Photo & Video Top 100s: nothing. Probably a garbled
**Cleanly**, a family of microscopic non-charting apps.

### 11.1 The market, and where it actually lives

**There is not one dedicated cleaner in the Photo & Video Top Free 100 or Top Grossing 100.
Twelve sit in Utilities Top Grossing.** If we categorise ourselves as Photo & Video we are
invisible to the people buying this.

| App | Seller | Utilities grossing | Rating (n) |
|---|---|---|---|
| **Cleanup: Phone Storage Cleaner** | DEEP FLOW FZCO / © Codeway (TR) | **#1** (#3 free, #87 overall) | 4.65 (716 277) |
| Cleaner Guru | GM UniverseApps Ltd | #4 | 4.52 (148 581) |
| AI Cleaner | GRIMLAX TRADE, S.L. (ES) | #12 | 4.58 (208 641) |
| **Swipewipe** | MWM SAS (FR) | #13 (#38 free) | 4.69 (92 450) |
| Cleaner Kit | BP Mobile LLC | #17 | 4.44 (349 968) |
| Clean Up Storage: CleanX | TAPSUITE YAZILIM A.Ş. (TR) | #27 (#34 free) | 4.55 (24 401) |
| Cleaner Neat | Smart Tool Studio | #45 | 4.58 (113 627) |
| **Clever Cleaner** | CleverFiles (Disk Drill) | *Productivity-primary, not charted in Utilities* | **4.78 (81 940)** |

Market size — Appfigures, **published June 2025, so 15 months stale; treat as a floor**:
~$40M/month consumer spend on storage cleaners; ~1 500 such apps across both stores; >95% of the
revenue is on the App Store; 161 apps grossed ≥$1 000/mo, 42 over $100 K, **only 7 over $1M**;
the top ten grossed $197M in 2024. Their named top ten is ~90% identical to today's live chart —
**incumbency is extremely sticky, and the money is concentrated in about seven apps.**

### 11.2 Primary evidence: the star-rating vs written-review gap

Pulled the most-recent US *written* reviews per app from Apple's review RSS, deduplicated, counted.

| App | n | Mean of recent written | Displayed lifetime | 1★ share | 5★ reviews under 25 chars |
|---|---|---|---|---|---|
| Cleanup | 500 | **3.84** | 4.65 | 21.2% | 136/310 (44%) |
| Cleaner Guru | 100 | **2.10** | 4.52 | **66.0%** | 9/23 (39%) |
| Swipewipe | 194 | 3.23 | 4.69 | 30.9% | 11/83 (13%) |
| AI Cleaner | 200 | 3.17 | 4.58 | 38.5% | 51/95 (54%) |
| Cleaner Kit | 200 | 4.12 | 4.44 | 12.0% | 88/125 (70%) |
| **Clever Cleaner** | 150 | **4.63** | **4.78** | **4.7%** | 55/122 (45%) |

**Read this honestly.** A gap is structurally expected — the displayed average includes silent
taps on the in-app rating prompt, while the RSS feed returns only written reviews, which skew
negative. It does **not** prove review farming, and **no documented manipulation allegation or
Apple enforcement exists against any of these publishers. Do not make that accusation.**

What it does show is the *shape* of each app's pain. Cleaner Guru's 2.10 against a displayed 4.52
is a two-and-a-half-star divergence and the bodies are billing complaints, not feature complaints.
Clever Cleaner's 4.63 vs 4.78 is a rounding error — and it is the one app with two SKUs and no
price ladder.

### 11.3 The category leader's playbook, and its central dark pattern

Cleanup: swipe left/right, grid multi-select, auto-selection with a "Best" keeper, a final review
screen, duplicates + similar + blurry + screenshots + large videos + contacts + a PIN vault.

**The scan result is free; the action is paywalled, and the limit is disclosed only after the
work is done.** This is the most repeated complaint in the corpus:

> *"I get to getting rid of duplicate photos and after i finally went through 500 photos and
> picked what i wanted gone then clicked delete, they tell me i can only delete FIVE videos or
> photos per day."*
> *"I spent an hour selecting duplicates to delete… it only let me delete 5 out of the 2000
> pictures I selected. **Didn't even tell me beforehand.**"*

**Pricing is a live A/B test.** The IAP block shows *five simultaneous weekly cells* —
$5.95 / $7.39 / $7.99 / $9.99 / $11.99 — plus $29.99 annual. At $11.99/week that is **$623/year**.
CleanX runs a **$14.99 weekly**, the highest found anywhere: $779/year. Billing and cancellation
complaints dominate every app in the paid cohort, with an ugly recurring note:
*"It preys upon the tech ignorant and elderly!!"*

**The privacy claim contradicts the privacy label on the same page.** Description: *"No internet
connection needed. No files leave your phone. No tracking."* Label: **Data Used to Track You —
Purchases, Identifiers, Usage Data.** An independent teardown captured six SDKs (Adjust, Firebase,
Cerebro, Admost, Facebook, Unity Ads) still transmitting while paid.

### 11.4 The "freed X GB" lie — the clearest opening in the market

> *"Says it freed up 10GB of storage and it didn't even free up half a gigabyte."*
> *"After I payed and cleaned my storage I checked my settings and the storage notification was
> still there at the same percent."*

The mechanism is Recently Deleted holding the bytes for 30 days. **Not one app examined explains
this in its store listing or in-product.** That single omission generates the most common trust
failure in the category.

We already model this correctly — `SavingsCalculator.swift:9-47` splits immediate / deferred /
cloud-only, and `ReviewView.swift:849` states the caveat. §5.11 promotes it to the overview.
**This is the thing to lead with, not a footnote.** And §3.11's next-launch re-probe of
`volumeAvailableCapacityForImportantUsage` turns "we estimate" into "you actually freed X",
which nobody does.

### 11.5 The other sharp complaints — each one a requirement

- **No batching at scale**, the single best product insight in the corpus:
  *"it suggests to delete 20,000 similar images but you couldn't possibly review that many at a
  time. They need to batch them into smaller groups… Reviewing 20 photos at a time, or 100, is
  much more reasonable… I had to manually select each photo because the only other option is to
  delete all 20,000 at once."* — our two-lane model plus the burst escape chip (§5.8) is exactly
  this, and nobody ships it.
- **Best-shot picks the worst shot**: *"its AI keep picking the worst photos as 'best' — think
  eyes half closed, blurry head."* That is `faceCaptureQuality` (§9.3) described as an absence.
- **Crash during selection loses all the work**: *"Crashes constantly while you're selecting pics
  to delete. Can't even confirm the deletion and have to start all over. Every single time."* —
  the session cursor in §5.1 is a correctness feature, not a convenience.
- **Live Photos handled badly**: *"Instead of taking a frame out of live photos, they delete the
  entire photo."* — §3.9 does it properly.
- **Swipe direction is a footgun**: *"By accident I deleted some videos, as going to the right
  does that, and I don't see anywhere where I can recover those."*
- **Swipewipe replaced the delete button with an ad**: *"instead of being able to delete photos
  immediately, they replaced the button with an ad… the devs who added this 'functionality'
  should be ashamed."* Price path $4.99/wk (Jan 2024) → $9.99/wk (Jan 2025) after MWM acquired it.

### 11.6 Clever Cleaner is the counter-example, and the closest thing to a competitor

Best rating in the category (4.78), best written sentiment (4.63), lowest 1★ share (4.7%).
**Two SKUs only** — $6.99 weekly with trial, **$39.99 lifetime** — no ladder, no price cells.
*"Swipe has no daily limit."* Praise names the pricing model directly.

Its feature list overlaps ours more than anyone else's, and two items matter:

- **It already does Live Photo → still conversion**, deleting only the video component. §3.9 is
  therefore not unique to us; our differentiator there is the honest cost disclosure (new
  identifier, album membership lost, disk temporarily rises), which they do not state.
- Sorted large videos, screenshots sorted by size, one-tap Smart Cleanup.

**Its failure mode is a redesign, not billing:** *"the Aug 2026 update destroyed what had been a
great and sleek photo clean process… less intuitive & more glitchy - risking losing good
photos."* Worth watching: the one competitor that got trust right then spent it on a redesign.

**Cleaner Kit is the only app with a soft-delete staging tier** — an "archive" to review later.
Our pending tray (§7.1) is the same idea, better named.

### 11.7 Similar-VIDEO dedupe — the biggest blind spot in the market

Cleanup, CleanX and Cleaner Neat all *claim* "similar/lookalike videos". **No vendor discloses
the method, and nobody has tested whether any of them match a re-encoded copy of the same clip.**
The only evidence is negative and behavioural:

> *"while reviewing similar videos it suggests a soccer game and last nights dinner — these are
> not similar."*
> *"some of the videos flagged as similar that it wanted to remove had nothing to do with each
> other."*

Set beside §10.2 — Apple's own community concluding *"There are no apps that I'm aware of that
will compare videos frame by frame"* — and §9.4, where ShazamKit matched a 640×360/crf32/64 kbps
re-encode and returned the exact trim offset: **this is the single clearest place to be
categorically better, not incrementally better.**

### 11.8 What could not be verified, and must not be asserted

- Whether **any** competitor actually dedupes re-encoded video. Requires running their apps
  against a controlled corpus. Not answerable from public sources.
- Taps-from-launch-to-freed-space for any app (none were installed).
- Sensor Tower per-app revenue figures (~$10M/mo Cleanup, ~$5M/mo Cleaner Guru) came from indexed
  meta descriptions, not rendered pages, with an undated window. **Directional only.**
- Apple exposes only the top 10 IAPs per app, so every price ladder above is partial.
- **No review-manipulation evidence, no regulator action, no class action** against any cleaner
  publisher or against Bending Spoons. Those lines of attack do not exist — drop them.
- Reddit, for the cleaner apps specifically. Blocked; substituted with primary review data.

### 11.9 The positioning this implies

1. **Category:** Utilities, not Photo & Video. The money is not where we would instinctively file.
2. **Lead with honest accounting.** Every competitor lies about freed space by omission; we
   already compute the truth and have never said so out loud.
3. **Price like Clever Cleaner, not like Cleanup.** The one app with a flat two-SKU model has the
   best rating in the category by a wide margin, and its users name the pricing as the reason.
4. **Never paywall the action after the work.** The most-hated pattern in the corpus, and it is
   free to avoid.
5. **Win on video**, where the whole market — Apple included — is provably weak.
