# SwiftUI layout traps, measured in this app

Five of them, all the same family: **the view takes up space and does not draw what you expect.**
A sixth, at the end, is the colour version of the same complaint: the mark is drawn and cannot be
read.
Every one was found by measuring frames with `app.debugDescription`, not by reading the code.

---

## 1. A `ZStack` child asking for infinite width

The badge was drawn ~90pt to the left of the 52pt thumbnail it belongs to.

**Before**

```swift
ZStack(alignment: .bottomTrailing) {
    ThumbnailView(item: group.keeper, side: 52, loader: loader)

    if group.keeper.kind != .image {
        Image(systemName: "video")
            .padding(3)
            .background(Circle().fill(.black.opacity(0.55)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

**After**

```swift
ThumbnailView(item: group.keeper, side: 52, loader: loader)
    .overlay(alignment: .topLeading) {
        if group.keeper.kind != .image {
            Image(systemName: "video")
                .padding(3)
                .background(Circle().fill(.black.opacity(0.55)))
        }
    }
```

**Why.** A `ZStack` sizes itself to its largest child. A child asking for `maxWidth: .infinity`
takes every point on offer, so the stack grows far past the thumbnail and `.topLeading` becomes
the top-left of *that* inflated area. An `.overlay` inherits the size of what it is attached to.

---

## 2. `Circle()` behind a wide glyph

The "circle" rendered as a stretched ellipse, which reads as a rounded rectangle.

**Before**

```swift
Image(systemName: "video")
    .font(.system(size: 8, weight: .bold))
    .padding(4)
    .background(Circle().fill(.black.opacity(0.55)))
```

**After**

```swift
Image(systemName: "video")
    .font(.system(size: 8, weight: .bold))
    .frame(width: 18, height: 18)
    .background(Circle().fill(.black.opacity(0.55)))
```

**Why.** A background shape fills the frame it is given. The `video` symbol is wider than it is
tall, so the frame was wide and the circle stretched with it. Fix the frame to a square first.

---

## 3. A row that is a direct child of `LazyVStack`

237.9 points of empty screen under a heading, with the whole rung absent from the accessibility
tree. Measured: heading ended at y 395.4, next element at 633.3.

**Before**

```swift
LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
    ForEach(model.kindSections) { kindSection in
        Section {
            ForEach(kindSection.sections) { section in
                rung(section)
            }
        } header: {
            kindHeader(kindSection)
        }
    }
}
```

**After**

```swift
LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
    ForEach(model.kindSections) { kindSection in
        Section {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(kindSection.sections) { section in
                    rung(section)
                }
            }
        } header: {
            kindHeader(kindSection)
        }
    }
}
```

**Why.** The lazy stack reserved one child's height and never built its content. Wrapping each
group of rows in an eager `VStack` moves laziness up one level: the stack now has three children
instead of twelve, and anything it builds, it builds whole.

**These did NOT fix it** — each was tried and measured:

```swift
.id(section.id)                      // no change
.padding(.top, 12)                   // moved off the ForEach onto the rung: no change
LazyVStack(alignment: .leading)      // pinnedViews removed: no change
```

Why SwiftUI behaves this way is **unverified**. This is a behavioural characterisation only.

---

## 4. A control next to a horizontal `ScrollView`

The sort menu was drawn on top of the last filter chip.

**Before**

```swift
HStack(spacing: 8) {
    kindFilter          // contains ScrollView(.horizontal)
    Spacer(minLength: 0)
    orderMenu
}
```

**After**

```swift
HStack(spacing: 8) {
    kindFilter
    orderMenu
        .fixedSize()
        .layoutPriority(1)
}
```

**Why.** A horizontal `ScrollView` asks for every point of width offered to it. Anything sharing
the row has to state its own width (`fixedSize`) and claim it first (`layoutPriority`).

---

## 5. A badge that wraps

"Costs nothing" broke onto two cramped lines inside its capsule.

**Before**

```swift
Text(text)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Capsule().fill(tint))
    .fixedSize(horizontal: false, vertical: true)
```

**After**

```swift
Text(text)
    .lineLimit(1)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Capsule().fill(tint))
    .fixedSize(horizontal: true, vertical: true)
```

**Why.** `horizontal: false` means "take whatever width is left", and in a row that had already
spent its width there was almost none. A two-word badge asks for the width it needs.

---

## The thing they have in common

Every one of these passed the whole test suite. The tests ask *does this element exist*, and a
view that is never built is never queried for. The tests that catch this class measure instead:

```swift
let gap = firstRung.frame.minY - heading.frame.maxY
XCTAssertLessThan(gap, 40, "\(Int(gap)) points reserved for something nobody drew")
```

---

## 6. A fixed colour drawn on top of somebody's photograph

The kind badge on a 52-point thumbnail wore `.black.opacity(0.55)`. On a bright frame it read as a
sticker; on a night frame there was no badge at all, only a floating glyph.

**Before**

```swift
Image(systemName: KindCopy.symbolName(for: group.keeper.kind))
    .foregroundStyle(.white)
    .frame(width: 18, height: 18)
    .background(Circle().fill(.black.opacity(0.55)))
```

**After**

```swift
Image(systemName: KindCopy.symbolName(for: group.keeper.kind))
    .foregroundStyle(.white)
    .frame(width: 18, height: 18)
    .background(Circle().fill(DS.onPicture))
    .overlay(Circle().strokeBorder(DS.onPictureEdge, lineWidth: 0.5))
```

**Why.** A translucent colour is not one colour — the number that decides legibility is its
composite with whatever is behind it, and behind this one is any photograph at all. So the ground
carries the glyph at the bright end and the hairline carries the badge at the dark end, and both
ends are held to Apple's 3:1 floor for a meaningful UI element. Computed from the tokens: white on
the ground over pure white is **5.05:1**, the hairline over pure black is **4.41:1**.

`DS.onPicture` is also **deliberately not adaptive**, alone in `DS`. Every other token flips with
the appearance because every other token sits on the app's own chrome. Dark mode says nothing
about whether the photograph behind this one is a white sky.

**What pins it.** Three tests in `PaletteTests`, each proved by mutation, each run on its own:

| Mutation | Contrast it produces | Test that went red |
|---|---|---|
| ground `0.62` → `0.20` | 1.54:1 | `testTheKindBadgeStaysReadableOnTheBrightestFrameThereIs` |
| hairline `0.45` → `0.10` | 1.20:1 | `testTheKindBadgeKeepsAnEdgeOnTheDarkestFrameThereIs` |
| token made `adaptive(light:dark:)` | — | `testTheMarkOnAPictureIgnoresTheAppearance` |

**Not verified:** both numbers are computed from the tokens, by the same arithmetic the tests run.
Neither has been checked against a real photograph in a screenshot.
