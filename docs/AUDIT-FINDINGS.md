# Audit findings — two expert passes over the SwiftUI notebook and the screens

Produced 15 September 2026 by two review agents asked to audit `docs/SWIFTUI-TRAPS.md` and the
screens behind it. **Nothing here is fixed.** Every item cites `file:line`; nothing was verified
by rendering a screen, and the items say so where it matters.

The deployment target is **iOS 17.0** (`project.yml:4-5`, `Packages/DupeCore/Package.swift:6`),
not 18 — which matters for case 3, since `LazyVStack` + `pinnedViews` realization changed
between 16 and 17.

---

## Part 1 — corrections to the notebook itself

### Case 2 is wrong about the mechanism

The notebook says a `Circle()` behind a wide glyph "stretched with it". `Circle` does not
stretch — Apple documents it as *"the circle's radius equals half the length of the frame
rectangle's smallest edge."* Stretching is `Ellipse`/`Capsule`/`RoundedRectangle`.

The before-state drew a **15pt circle centred in a 19pt box** — a disc smaller than the glyph's
own width, cropping tight around the symbol. The `.frame(width: 18, height: 18)` fix is right;
the stated reason is not. The correct explanation is already in the source at
`GroupRowView.swift:39-41`.

**The better trap to write:** a background shape fills the frame it is given — *except* `Circle`,
which inscribes itself in the frame's smallest edge. A wide frame gives you a small circle, not
an ellipse.

### Case 3's `.id(section.id)` experiment is void

The notebook's "did NOT fix it" table lists `.id(section.id)`. But `ReviewSection.id` is
`tier.rawValue` (`Packages/DupeCore/Sources/DupeCore/Review/ReviewBuilder.swift:77`) and
`KindSection.id` is `kind.rawValue` (`ReviewViewModel.swift:235`) — both draw from `{0,1,2,3}`.
Applying `.id(section.id)` re-declared *the same repeating Int* that was already in use. The
experiment held the variable constant, so its negative result is not evidence. Identity has
**not** been ruled out, and the notebook records it as if it had.

**Leading hypothesis for case 3 (UNVERIFIED):** id keying in the lazy realization list.
`LazyVStack` with `pinnedViews` flattens nested `ForEach`/`Section` into one realization list
keyed by composed element id; every kind section emits rungs keyed 0..3. The eager-`VStack`
result does not falsify this, because an eager stack never consults that cache.

**Falsification test, 30 minutes, runnable today:** remove the eager `VStack` at
`ReviewView.swift:351`, keep everything else, and give the rungs a globally unique id
(`"\(kind.rawValue).\(tier.rawValue)"`). Re-run
`LadderDrawingUITests.testNoKindHeadingIsFollowedByEmptySpaceWhereARungShouldBe`. If the 237.9pt
gap is gone, the mechanism is identity and the entry can be rewritten with a root cause.

**Second hypothesis (UNVERIFIED):** the rung's height is not stable across proposals. The rail
at `ReviewView.swift:653-662` is `.frame(width: 2).frame(maxHeight: .infinity)` — under a `nil`
proposal it returns the ideal 10pt, under a concrete one it returns the proposal. A container
that measures with one and places with the other gets two answers for one child.

**Missing caveat:** "absent from the accessibility tree" is not proof of "never built".
XCUITest prunes zero-frame and out-of-bounds elements identically, so a rung that *was* built
and misplaced disappears the same way. Check whether `ThumbnailView.task` fired before
concluding construction rather than placement.

### Case 3's fix has an unbounded cliff behind a button

The fix is load-bearing on `RungWindow.limit = 5`, which the case never mentions. Unfold a rung
and `RungWindow.state` returns `State(shown: groupCount, hidden: 0)` (`RungWindow.swift:30`), so
the **eager** `VStack` at `ReviewView.swift:594-598` builds every row at once — on the rung
`RungWindow.swift:6-8` says "can hold hundreds". Each row builds a `ThumbnailView` whose
`.task(id:)` fires on appear (`ThumbnailView.swift:35`) against a loader with an `NSCache` but
**no concurrency bound** (`ThumbnailLoading.swift:19-36`), and the insertion happens inside
`withAnimation(Motion.content)` (`ReviewView.swift:620`).

Falsifiable statement of the defect, as a unit test that fails today:
`RungWindow.state(groupCount: 412, isExpanded: true).shown` returns 412 and should be bounded.

**Fix:** page the unfold — `openedRungs` stores a count, not a flag; grow by 25 a tap.

### Case 4 is overstated

`.fixedSize()` alone is sufficient: `HStack` allocates to its least-flexible children first, so
making the menu inflexible already gets it its ideal width ahead of the greedy scroll view.
`.layoutPriority(1)` is belt-and-braces. Presenting both as required has already produced three
cargo-cult copies — `ReviewView.swift:414`, `ScanView.swift:638`, `ConfirmDeleteSheet.swift:396`
— and the pair inverts at accessibility text sizes (see Part 2).

### Case 5 needs its boundary

`fixedSize(horizontal: true, vertical: true)` (`DesignSystem.swift:360`) makes `Badge` the one
element in its row that cannot yield, opposite a select-all button with `lineLimit(1)` and no
scale floor (`ReviewView.swift:709`). Correct at default type; at AX5 every point of compression
lands on the control beside it. The rule needs "…while the badge is small relative to its row".

### Case 6 is half-closed, and its floor is cited wrongly — **FIXED 15 September 2026**

Both figures reproduce exactly (5.050:1 and 4.414:1). Three problems:

**Fixed, and the prescription here was wrong too.** The point-samples were replaced by a
sweep over sixty-four frame luminances, and the tokens moved to `0.85 / 0.90`. But the item below
asks each token to clear 3:1 against mid-grey, and **no single colour can clear a floor against
every frame** — whatever it is, some photograph matches its luminance. The invariant that is
achievable, and now enforced, is about the pair: for any frame, either the ground separates or the
hairline does. The old pair's floor was **2.35:1** at `#6F6F6F`, not the 2.02:1 cited; the new
pair's is **3.73:1** at `#7C7C7C`.

1. **The extremes are not the worst case.** `PaletteTests` samples only `over: 1` and `over: 0`
   (`DupeSpaceTests/PaletteTests.swift:189, 198`). Against mid-grey (#808080): the hairline
   measures **2.02:1** and the disc ground **2.69:1** — both under the 3:1 the case claims is
   held. Adding an `over: 0.5` case goes red today.
2. **Wrong floor cited.** 3:1 is the non-text floor; the thing carried is an 8pt SF Symbol,
   which is text-sized, so 4.5:1 applies. It passes anyway at 5.05, but the justification is the
   wrong rule.
3. **The other mark on the same thumbnail was left untouched** — see Part 2 item 1.

### The preamble overclaims

Line 6 — *"Every one was found by measuring frames with `app.debugDescription`, not by reading
the code"* — is false for case 2 (found in a screenshot) and case 6 (computed from tokens). Say
"three of six" or drop the sentence.

### "The thing they have in common" teaches a one-sided assertion

Its example measures a *gap* (`gap < 40`). That catches reserved-but-unbuilt space and cannot
catch the inverse — overlap, clipping, a control compressed to an ellipsis. A layout test needs
both directions: a floor on emptiness and a ceiling on collision.

---

## Part 2 — defects proposed in the screens

Ranked roughly by consequence. Contrast figures were computed from the tokens, not measured off
a rendered screen.

### 1. The survivor seal fails the floor case 6 introduced, on the same 52pt thumbnail — **FIXED 15 September 2026**

`GroupRowView.swift:59-64` — `.foregroundStyle(.white, DS.deep)`, no ground, no hairline, and
`DS.deep` is **adaptive**, which case 6's own closing paragraph forbids for a mark on a photo.

| | light `#0A6FE0` | dark `#3DA1FF` |
|---|---|---|
| white tick on the seal body | 4.81:1 | **2.71:1** |
| seal body vs a white sky | 4.81:1 | **2.71:1** |

The dark failure is *internal* — white tick against its own disc — so it does not even need a
bright photograph to fail. And the seal is the more meaningful of the two marks: it says which
copy survives. **Fixed** with the badge's construction, but `DS.onPictureAccent` (fixed `#0A6FE0`, white tick
at 4.81:1) rather than the neutral `DS.onPicture` ground — blue is what says *survivor* here, and
the neutral ground would have thrown that meaning away. Pinned by
`testTheSurvivorSealCarriesItsOwnTick` and `testTheSurvivorSealIgnoresTheAppearance`, both proved
by mutation. The seal also stopped being a bare `ZStack` child, which removes a latent instance of
part 1's own case 1.

### 2. The reclaim meter's numerator and denominator are different quantities

Numerator `ReviewView.swift:820` → `ReviewViewModel.swift:377-381`, computed from
`selection.selectedIDs` with no tier or kind narrowing. Denominator `ReviewView.swift:834`
`total: max(reachableBytes, 1)` → `ReviewView.swift:274-278`, which sums only `visibleSections`
at or below `budgetDepth`. Clamped by `DesignSystem.swift:618` `min(value / total, 1)`.

Two first-class routes: depth defaults to `.inferiorCopy` (`ReviewViewModel.swift:55`) while
every rung draws a tick box (`ReviewView.swift:769-780`); or select all videos then tap the
Photos filter. Either fills the bar permanently while the number above keeps climbing.

**Pin:** extract `reclaimFraction(selection:depth:filter:)` and assert it *moves* when a
selection outside the depth is added.

### 3. `minimumScaleFactor` is not a Dynamic Type strategy — the two most consequential controls truncate — **FIXED 15 September 2026**

`ReachPicker` (`DesignSystem.swift:670-681`) gives each option an equal flexible column with
`lineLimit(1)` and `minimumScaleFactor(0.7)`. On a 393pt device: 393 − 32 − 40 = 321 inner,
minus 2×8 spacing = 305, ÷3 ≈ **101.7pt a column**. `.footnote` is 13pt at Large, 49pt at AX5;
×0.7 = 34pt. "+ similar" is nine characters — it ellipsises.

Call sites: `ReviewView.swift:259-269` (how far a plan may reach) and `ScanView.swift:225-236`,
`:491-502` (how alike counts as a copy) — by the component's own doc comment, "the two most
consequential choices in the product".

Nothing has ever looked: `docs/ui-audit.md:39` says the scan screen was never reached at large
text, and `Scripts/audit-ui.py:563` only relaunches at AX1, never AX5.

**Fix:** read `@Environment(\.dynamicTypeSize)` in `ReachPicker` and stack vertically at
`>= .accessibility1`. **Pin:** XCUITest at AX3XL asserting the chips are stacked.

**Fixed** exactly as prescribed — `AnyLayout` switching `HStackLayout` for `VStackLayout` past
`.accessibility1`, and `lineLimit`/`minimumScaleFactor` dropped in that mode, because stacked
the width is no longer the scarce thing. Measured on iPhone 13 Pro: the three steps were
100.7pt wide on one row at both sizes before, and at AX3XL are now 318pt wide at y = 314.7,
387.3 and 460.0 — a column. Pinned by
`ReviewUITests.testTheReachPickerStacksAtAccessibilitySizesRatherThanShrinkingItsLabels`, proved
by mutation (`stacked` forced to `false` → step 1 starts at 314.7 while step 0 ends at 358.7).

The test needed fixing before the code did, and the reason is worth keeping. `XCUIApplication`
has no API for the content size category, so it goes in as a launch argument — and the spelled-out
`UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge` is **not** a constant the system knows.
It does not fall back to Large either: the screen's own text came back 33.7pt against 31.3pt, a
1.07x nudge that walked straight through a `greaterThan` probe while the app sat at an ordinary
size, and the picker was blamed for a row it was drawing correctly. The short spelling,
`UICTContentSizeCategoryAccessibilityXXXL`, moves that text 1.54x. The probe now asserts a
**ratio**, so a misspelt argument fails as itself rather than as the control under test.

`ReachPicker` is shared, so the strictness picker on the scan screen gets the same fix — and
"gets it for free" is exactly the claim that deserved its own measurement, because that screen
is a card on a dark slab with an explanation underneath, which is somewhere new to overflow.
`ScanUITests.testTheStrictnessPickerFitsTheSlabAtAccessibilitySizes` asks both questions there:
stacked, **and** still inside the window's width.

Writing that second test turned up something else. `ScanUITests.swift` holds **two** classes, and
the CI shards name classes rather than files — so `ScanStripUITests`, the suite that pins the
claim that a scan survives leaving the screen that started it, has never run on CI. It is the
third suite found running nowhere, after `OnboardingUITests` and `LadderDrawingUITests`. Added to
shard b; it passes in 13.5 seconds. Every other UI test class was checked: no more orphans.

**Not fixed by this:** the other twenty-five `minimumScaleFactor` call sites. `ReachPicker` was
the one the audit named and the one whose labels carry a decision; the rest are unmeasured. The
screenshot walk that produced the evidence above also showed the review screen's bottom dock
truncating its delete key to "D…" and wrapping "3 selected" over four lines at AX3XL — a worse
defect than the one this section fixed, and untouched.

### 4. `.fixedSize()` + `.layoutPriority(1)` inverts at accessibility sizes

The unqualified `.fixedSize()` means "never wrap, never truncate, on either axis, at any cost" —
a refusal to negotiate, not "use your natural width". `Text` at `.caption` scales ~2.5x from
Large to AX5. Three sites copied from case 4: `ReviewView.swift:403-416` (the chips `ScrollView`
accepts any width ≥ 0, so it absorbs 100 % of the loss), `ScanView.swift:637-639`,
`ConfirmDeleteSheet.swift:395-397` (the title squeezed to two truncated lines on the sheet
before an irreversible delete).

**Fix:** `.fixedSize(horizontal: true, vertical: false)` and give the *other* side a floor
(`.frame(minWidth: 120)`).

### 5. `.scrollClipDisabled()` turns the chip row into an unclipped painter

`ReviewView.swift:509-519` — added for `.padding(.vertical, 2)` plus a 1pt `strokeBorder` being
clipped, but the modifier takes no axis, so the horizontal clip goes too. Chips that have
scrolled past the frame keep drawing under the sort menu, whose capsule is
`DS.deep.opacity(0.10)` (`:456`) — 90 % transparent, so the chip shows through while the `Menu`
owns the hit testing. This is the unswept half of case 4: the layout overlap was fixed, the
drawing overlap is still enabled one line below the comment describing the fix.

**Fix (iOS 17 API, keeps the clip):** `.contentMargins(.vertical, 2, for: .scrollContent)`.

### 6. `MeterTrack` animates its numerator and ignores its denominator

`DesignSystem.swift:612` — `.animation(motion, value: segments)`. Changing `model.budgetDepth`
changes only `total:` (`ReviewView.swift:816-836`); `segments` stays `Equatable`-identical, so
the bar jumps in one frame while the rest of the screen springs.

### 7. `ScanStripView` re-springs the whole strip on every progress tick

`ScanStrip.swift:74-80` — `.animation(Motion.content, value: state)` where `state` carries
`percent: Int` and `fraction: Double` (`:22-23`), changing several times a second, against a
spring (`Motion.swift:12`). `DesignSystem.swift:574-582` contains the author's own diagnosis of
exactly this failure and its fix, applied to the inner `MeterTrack` (`ScanStrip.swift:120`) —
the inner track is fixed, the container around it is not.

**Fix:** `.animation(..., value: state == nil)`. Presence only.

### 8. An animation that cannot fire on the path the architecture was built for

`ScanView.swift:86-95` — `pulse` is `@State` started from `.onChange(of: model.isScanning)` with
no initial fire, on a screen the scan is designed to outlive (`ScanView.swift:29-32`,
`ScanStrip.swift:82-85`). Start a scan, pop to root, tap the strip: `ScanView` is rebuilt,
`pulse` resets to `false`, `isScanning` is already `true`, no change event ever arrives.

**Fix:** `.onChange(of:initial: true)` or `.task(id:)`.

Same file, same family: `ScanView.swift:11-12, 436-440` — `.symbolEffect(.bounce, value:
hasSettled)` with `.onAppear { hasSettled = true }` and no reset fires once per app launch, on a
card whose sibling `rescanPanel` (`:487`) exists so the user comes back. It is also the one
`symbolEffect` not gated on Reduce Motion.

### 9. `TargetSlider` uses three coordinate mappings for one value

`Shared/DesignSystem.swift` — cap at `:833-835` travels `width - gripWidth`; the drag at `:918`
reads `drag.location.x / width`; the limit marker at `:880` uses `width * limitFraction`. At
`fraction == 1` the cap's leading edge is 18pt short of the finger that produced it, and the
marker cannot be hit exactly. **The strongest pin available** — extract the mapping and assert
`capX(for: fraction(forTouchAt: x)) + gripWidth/2 == x` across the track.

### 10. `DS.brandBottom` *is* `DS.tier(.identical)` in dark mode, both on the scan screen — **FIXED 15 September 2026**

`DesignSystem.swift:111` `brandBottom = #32D7EB` fixed; `:146` `tier(.identical)` dark =
**`#32D7EB`**. Drawn at `ScanView.swift:374` (progress fill) and `:551` (results meter), while
`ScanStrip.swift:92` paints the same measurement in `DS.deep`. This is verbatim the defect
`DesignSystem.swift:96-101` documents killing when `aqua` was deleted — the dark value came
straight back in through `brandBottom`. **Pin:**
`XCTAssertGreaterThanOrEqual(hueSeparation(DS.brandBottom, DS.tier(.identical), .dark), 12)`,
which failed at 0.0°.

**Fixed** by moving the brand, not the ladder: `brandBottom` goes `#32D7EB` → `#5AC8FF`, which is
27.7° clear of the identical rung in light and 34.9° in dark. Blue was the only direction
available — the teal end belongs to the identical rung and the green end to the inferior-copy
rung — so the icon's gradient is now a lightness and chroma ramp inside blue rather than a
blue-to-teal hue ramp. Pinned by `testTheBrandGradientIsNotTheLaddersTopRung`.

### 11. The retired chip pattern is still drawn under every comparison — **FIXED 15 September 2026**

`CompareSliderView.swift:204-216` — tint-at-14 % behind tint-as-text, uppercase, kerned; the
exact pattern `DesignSystem.swift:338-343` says was replaced and why. On `DS.inkRaised`:

| chip | on its own 14 % ground | on the bare card |
|---|---|---|
| `DS.neutral` light | **1.92:1** | 2.12:1 |
| `DS.neutral` dark | **1.77:1** | 1.92:1 |

1.92:1 on caption2 is gone, on the screen where somebody decides which photograph dies.

**Fixed** by making `chip` call `Badge`. That required fixing `Badge` first: it used `DS.onTint`,
which is right for the tier palette and only for it — those colours are dark in light mode and
bright in dark mode, so "which ink" and "which appearance" give the same answer. `DS.neutral` is a
mid grey in one appearance and a dark slate in the other, and `onTint` put white on it at 2.12:1.
`DS.onFill(_:in:)` now reads the fill's own luminance: 9.03:1 in light, 7.50:1 in dark, and it
agrees with `onTint` exactly on every tier colour. Pinned by
`testAFilledPillCarriesItsOwnLabelWhateverItIsFilledWith`.

**Still open, and newly found:** the same retired pattern is drawn in `Shared/ScanLiveViews.swift`
lines 119-122 — `DS.brandBottom` as text over `DS.brandBottom.opacity(0.15)` — on the Live Activity
and widget surfaces, which neither audit looked at. **Not measured**, because the ground behind a
Live Activity is the Lock Screen wallpaper rather than a token.

### 12. Every derived colour is invisible to the contrast harness — **PARTLY FIXED 15 September 2026**

`PaletteTests.swift:151-168` measures five opaque tokens and four rung colours. Every colour
actually drawn is `token.opacity(x)` and none is measured — **14 distinct alphas on `DS.onSlab`
alone, 35 `DS.<token>.opacity(…)` call sites.** `DS.onSlab` over `slabFill`:

| alpha | light | dark | drawn at |
|---|---|---|---|
| 0.55 | **3.97** | 4.82 | `ScanView.swift:322, 521`; `DesignSystem.swift:726` (ReachPicker unselected) |
| 0.50 | **3.41** | 4.25 | `ScanView.swift:177` — a *finished* stage |
| 0.32 | **2.06** | **2.60** | `ScanView.swift:177` — a *waiting* stage |
| 0.22 | **1.61** | **1.92** | `ScanView.swift:168` — the waiting dot |

So the ladder that exists to say "here is the whole pipeline, in order, so you can watch it"
(`ScanView.swift:109-112`) draws four of six rows at 2.06:1 with markers at 1.61:1.

**Fixed for the scan ladder only.** `DS.onSlabWaiting`, `DS.onSlabDone` and
`DS.onSlabWaitingMark` are named tokens now, measured by
`testEveryStageOfTheScanLadderIsReadable`, and lifted: the waiting stage goes `0.32` → `0.62`
(2.06:1 → 5.05:1), the finished stage `0.5` → `0.72` (3.42:1 → 7.18:1), and the waiting dot
`0.22` → `0.47` (1.61:1 → 3.13:1). Reading order survives because the hierarchy is carried by
weight, not by opacity: 18.02 for a current stage, 7.18 for a finished one, 5.05 for a waiting one.

**Still open:** the other alphas in the table — `ScanView.swift:322`, `DesignSystem.swift:726`
(`ReachPicker` unselected) — and the thirty-odd remaining `DS.<token>.opacity(…)` call sites.

### 13. Amber has four jobs, three on one screen

`DS.tier(.burstLeftover)` (`DesignSystem.swift:148`) is simultaneously: the burst rung's
identity (`ReviewView.swift:575, 580`); "this tier is a judgement call" on every non-lossless
rung including violet `.similar` ones (`DesignSystem.swift:216` → `ReviewView.swift:683`);
"needs attention" (`ReviewView.swift:229, 245, 753`; `ConfirmDeleteSheet.swift:133, 251`;
`ScanView.swift:374, 387`; `ScanStrip.swift:92`); and "these two values differ"
(`ComparisonRow.swift:124, 182`; `CompareSliderView.swift:238`).

Matching collision at the cool end: `costTint` returns `tier(.inferiorCopy)` green for lossless
rungs, so the `.identical` rung wears a teal rail with a **green** badge — green being the
identity of the rung immediately below it on the same ladder.

### 14. Reduce Motion is honoured by the components and ignored by the screens

`Motion.content/control/readout` (`Shared/Motion.swift:12, 16, 25`) are bare `Animation`
constants with no reduced variant, so honouring the setting is a per-call-site decision. Nine
sites remember. `ReviewView.swift` has **zero** reads of `accessibilityReduceMotion` with
animation at `:93, 104, 105, 216, 386, 435, 620, 770`; `ConfirmDeleteSheet.swift` has zero with
animation at `:67-70, 114, 232, 293`. SwiftUI does not disable `.animation` under Reduce Motion
— which the nine explicit branches already concede by existing.

**Fix:** move the decision into the token — a `View.dsAnimation(_:value:)` that reads the
environment and returns `nil` — and keep the bare constants private.

### 15. Two marks on one 52pt thumbnail scale in opposite directions

`GroupRowView.swift:17` tile `side: 52` fixed; `:43` badge glyph `.system(size: 8)` fixed inside
an 18pt frame; `:62` seal `.caption2` — a text style, 11pt at Large, **42pt at AX5**. At AX5 the
seal covers ~80 % of the picture it marks while the badge beside it has not moved.
`ComparisonTable.swift:154` already uses `@ScaledMetric` — the pattern exists in the repo and is
used once.

### 16. Touch targets under 44 the repo has already fixed three times elsewhere — **PARTLY FIXED 15 September 2026**

| where | size | what it does |
|---|---|---|
| `GroupDetailView.swift:113-125` | `minHeight: 34`, no `contentShape` | ticks **every copy in the group** — up to sixty |
| `CompareSliderView.swift:112-134` | `minHeight: 32` | shows the difference map |
| `RootView.swift:292-303` | `minHeight: 32` | opens History |

The fix is written three times with a comment explaining it (`ReviewView.swift:458-462, 553-555,
715-718`; `DesignSystem.swift:676-680`). `GroupDetailView`'s select-all is the same control as
`ReviewView`'s and got the opposite decision. `Scripts/audit-ui.py:38` already has
`MIN_TAP_TARGET = 44.0` — the walk simply never opens a group.

**Fixed for the two on the group screen**, by the pattern this repo already had: the pill keeps
its own height and a 44pt frame goes around it, so the hit area grows outside the pill rather
than the pill growing to meet the finger. Measured 34.0 → 44.0 and 32.0 → 44.0, pinned by
`GroupUITests.testTheControlsOnTheGroupScreenAreAFullFingerTall`, both halves proved by mutation.

The difference toggle is the one worth reading twice. It already carried
`.contentShape(Capsule())`, which reads like the fix and is its opposite: a content shape
*confines* the touch to the shape it is handed and cannot make a target taller than the frame
underneath it. The audit's framing — "`minHeight: 32`" with no mention of the content shape —
was right about the number and would have been dismissed by anyone who read the next line. A hit
shape is not a hit size.

**`RootView.swift:292-303` is deliberately left.** It sits in a `ToolbarItem(placement:
.topBarTrailing)`, and the navigation bar's own 44pt may already be carrying the target — the
row is 32 in the *view*, which is not the same claim. Nobody has measured it. It stays open
rather than being changed on the strength of a line number, which is how
`ReviewView.swift:454` nearly got "fixed" while it was already correct.

### 17. A disabled control styled exactly like a live one

`CompareSliderView.swift:112-137` — only the string and symbol change; `.disabled(...)` at
`:136` has no effect on a `.buttonStyle(.plain)` label that never reads `\.isEnabled`. The app
already knows this is wrong: `DesignSystem.swift:498-503`.

### 18. `GroupDetailView` is case 3's shape, unprotected, on the screen with the most rows

`GroupDetailView.swift:61-80` — a `ForEach` producing rows as direct children of a `LazyVStack`
with heterogeneous siblings around it, on a screen that can hold "sixty copies in one group"
(`:62-63`). Not byte-identical to the case-3 before-state (no `Section`, no `pinnedViews`), and
it may be fine — but `LadderDrawingUITests` only walks the Review ladder, and the notebook's own
argument is that existence assertions cannot see this class of defect. **Measure first.**

### 19. Smaller

- **The sheet puts the irreversible key above the fold and the safety copy below it.**
  `ConfirmDeleteSheet.swift:26` opens at `.medium`; `deleteKey` is a pinned bottom
  `safeAreaInset` (`:81-83`) while `judgementWarning` (`:43-45`) and `keepACopy` (`:47`) are
  inside the scroll body. Reasoned from the code, not rendered.
- **The filter scrolls away; the label pins.** `listControls` is a plain lazy-stack child
  (`ReviewView.swift:335-337`) while `kindHeader` is pinned (`:379-383`). The pinning argument
  at `:380-381` applies with more force to the control than to the label.
- **The pinned kind header is 96 % opaque.** `ReviewView.swift:495` — rows are visible at 4 %
  under it, and the header's `DS.ink` differs from the panels' `DS.inkRaised`, so the tint
  shifts as rows pass.
- **The one empty state the app draws is the one it never lets you read.**
  `GroupDetailView.swift:44-56` draws a `ContentUnavailableView` then pops from a `.task` on the
  same view — a flash of a state nobody can read, and the only stock component in an app that
  argues against stock components three times in `DesignSystem.swift`.
- **`.task(id: items.count)`** (`ScanView.swift:80`) — a library edit that replaces one asset
  with another keeps the count and leaves the ledger describing the previous library. Different
  notebook, same species: an identity cheaper than the thing it identifies.

---

## Not exposed here — general guidance only

Landscape/iPad (nothing cited); RTL (the `TargetSlider` `capX` maths at `DesignSystem.swift:830-835`
is the one plausible site, no concrete failure found by reading); a headings rotor for the pinned
kind headers; whether `Image(systemName:)` supplies a default VoiceOver label for the kind badge
at `GroupRowView.swift:42-45` — **UNVERIFIED**, thirty seconds with Accessibility Inspector.
