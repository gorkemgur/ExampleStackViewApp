import SwiftUI
import DupeCore

/// The four things somebody has to believe before handing over their photo library, drawn.
///
/// Every illustration on this screen is made in code — there is not one asset — but the thing
/// being drawn is a *photograph*, and that is the correction this screen needed. It used to
/// illustrate a photo app with abstract bars laid over `DS.well` at a third of their opacity,
/// which rendered the whole panel grey: a skeleton loading state, not an illustration, and a
/// flat contradiction of the app behind it, where the same four colours are drawn at full
/// strength. The rungs are still the app's own rungs and the rails are still `DS.tier`. What
/// sits between them now is a picture.
///
/// The ask is last, and `OnboardingPage.all` is tested to keep it there.
struct OnboardingView: View {

    @StateObject private var model: OnboardingViewModel
    private let onGrantPhotos: () async -> Void
    private let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The system alert is not instant on a large library. Without this the key stays live and
    /// a second tap queues a second request behind the first.
    @State private var isAsking = false
    /// Which way the next page should come in from. A page that slides in from the left when
    /// you went forwards reads as the screen correcting itself.
    @State private var movingBack = false
    /// Live drag distance, so the layers can move at different rates under the finger. Reset to
    /// zero on release, which is what makes the page snap back when the drag was too short.
    @State private var drag: CGFloat = 0

    init(
        store: any OnboardingStoring,
        onGrantPhotos: @escaping () async -> Void,
        onFinish: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: OnboardingViewModel(store: store))
        self.onGrantPhotos = onGrantPhotos
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            DS.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header

                page
                    .id(model.page.id)
                    .transition(pageTransition)

                controls
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
        }
        .animation(reduceMotion ? nil : Motion.content, value: model.index)
        .gesture(swipe)
        // A page turn is a discrete choice, so it gets the selection tap rather than an impact.
        .sensoryFeedback(.selection, trigger: model.index)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: DS.Space.m) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.deep)
                    .accessibilityIdentifier("onboarding.skip")
            }

            // A rail rather than dots: four segments that fill, so the screen says how much of
            // this there is. Dots say "some".
            HStack(spacing: 5) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, _ in
                    Capsule(style: .continuous)
                        .fill(index <= model.index ? AnyShapeStyle(DS.deep) : AnyShapeStyle(DS.groove))
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(model.index + 1) of \(model.pages.count)")
            .accessibilityIdentifier("onboarding.rail")
        }
    }

    /// Two layers, moved at different rates under the finger.
    ///
    /// A page that slides as one rigid block is a slideshow. Letting the picture lead the words
    /// is what makes the drag feel like it has depth, and it costs one multiplier — the artwork
    /// tracks the finger at about a third, the copy at a tenth, and the rail above does not move
    /// at all because it is chrome and chrome that slides reads as a bug.
    ///
    /// The artwork is a flexible band rather than a fixed 232pt, and the `Spacer` that used to
    /// sit under this is gone. On a 13 Pro Max that pairing left about 195pt of nothing between
    /// the last sentence and the key — the single clearest reason the screen read as unfinished.
    /// The slack goes into the picture now, and on a small phone the picture gives it back
    /// rather than pushing the key off the bottom.
    private var page: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            OnboardingArtwork(pageID: model.page.id, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 360)
                .dsSlab(padding: DS.Space.l)
                .offset(x: parallax(0.32))
                // Decorative: everything it says, the copy underneath says in words.
                .accessibilityHidden(true)

            PageCopy(page: model.page, reduceMotion: reduceMotion)
                .offset(x: parallax(0.10))
        }
    }

    private var controls: some View {
        VStack(spacing: DS.Space.m) {
            Button(action: act) {
                Text(model.page.actionTitle)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.key(enabled: !isAsking))
            .disabled(isAsking)
            .accessibilityIdentifier("onboarding.primary")

            // Reserved rather than removed: a control that appears on page two pushes the key
            // it sits under, and the key is the thing the thumb is already aimed at.
            Button("Back", action: back)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.deep)
                .opacity(model.index == 0 ? 0 : 1)
                .disabled(model.index == 0)
                .accessibilityHidden(model.index == 0)
                .accessibilityIdentifier("onboarding.back")
        }
    }

    // MARK: - Movement

    private func parallax(_ rate: CGFloat) -> CGFloat {
        reduceMotion ? 0 : drag * rate
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingBack ? .leading : .trailing).combined(with: .opacity),
            removal: .move(edge: movingBack ? .trailing : .leading).combined(with: .opacity)
        )
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !reduceMotion else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Rubber-banded: a drag off either end moves a third as far, so the screen says
                // "there is nothing that way" by feel rather than by refusing to move.
                let atEnd = (value.translation.width < 0 && model.isLast)
                    || (value.translation.width > 0 && model.index == 0)
                drag = atEnd ? value.translation.width / 3 : value.translation.width
            }
            .onEnded { value in
                withAnimation(Motion.content) { drag = 0 }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard abs(value.translation.width) > 56 else { return }
                if value.translation.width < 0 {
                    movingBack = false
                    model.advance()
                } else {
                    back()
                }
            }
    }

    private func act() {
        switch model.page.action {
        case .next:
            movingBack = false
            model.advance()
        case .grantPhotos:
            // The whole reason this screen exists: the grant goes through the view model that
            // owns `access`, so the screen behind this one is already right when it appears.
            isAsking = true
            Task {
                await onGrantPhotos()
                isAsking = false
                finish()
            }
        case .finish:
            finish()
        }
    }

    private func back() {
        movingBack = true
        model.back()
    }

    private func finish() {
        model.finish()
        onFinish()
    }
}

// MARK: - The words

/// Title, lead, body — and they arrive in that order rather than all at once.
///
/// This is its own view for one reason: the caller tags it with `.id(page.id)`, so a page turn
/// builds a *new* `PageCopy` and `shown` starts false again. State on `OnboardingView` would
/// have been set once on the first page and never animated again.
///
/// The three-step ramp replaces one `.body` paragraph set in system grey. A five-line block of
/// secondary text has no entry point — nothing in it is more important than anything else, so
/// the eye has to read all of it or none. The lead is the sentence that carries the page, and
/// it is distinguished by weight and colour rather than by size, which is why it sits only a
/// point above the body.
private struct PageCopy: View {

    let page: OnboardingPage
    let reduceMotion: Bool

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            entering(at: 0) {
                Text(page.title)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .kerning(-0.3)
                    .foregroundStyle(DS.onSlab)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.title")
            }

            entering(at: 1) {
                Text(page.lead)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(DS.onSlab)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.lead")
            }

            entering(at: 2) {
                Text(page.body)
                    .font(.callout)
                    // A chosen neutral rather than `.secondary`: the system grey is the one
                    // colour on this screen nobody picked, and it sits next to five that were.
                    .foregroundStyle(DS.onSlabMuted)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.body")
            }
        }
        .onAppear { shown = true }
    }

    /// A rise, staggered in reading order. Not decoration: the stagger *is* the order the three
    /// lines are meant to be read in, and it was the one thing on the page that never moved.
    ///
    /// There was a fade here too, from zero, and it had to go. `shown` is set in `onAppear`,
    /// which fires *after* the first layout — so every frame drawn before it landed carried the
    /// slab, the rail, and no words at all. On a device slow enough for that gap to be visible
    /// the entrance turns "slow" into "broken": the screen is not late, it is empty. Starting at
    /// the final opacity and moving only a transform means a frame that arrives early still
    /// carries the content, and the motion is unchanged once it does start.
    @ViewBuilder
    private func entering(at step: Int, @ViewBuilder _ content: () -> some View) -> some View {
        let settled = shown || reduceMotion
        content()
            .offset(y: settled ? 0 : 12)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.38).delay(Double(step) * 0.07),
                value: shown
            )
    }
}

// MARK: - The four scenes

private struct OnboardingArtwork: View {

    let pageID: String
    let reduceMotion: Bool

    var body: some View {
        switch pageID {
        case "what": LadderScene(ticked: false, reduceMotion: reduceMotion)
        case "choose": LadderScene(ticked: true, reduceMotion: reduceMotion)
        case "private": ContainedScene(reduceMotion: reduceMotion)
        default: LibraryScene(reduceMotion: reduceMotion)
        }
    }
}

// MARK: - A photograph, drawn

/// One synthetic photograph: a sky, a light, two ridges.
///
/// Six palettes, and they are deliberately *not* `DS.adaptive` pairs. Every other colour on
/// this screen resolves against the appearance, because every other colour is interface. A
/// photograph is not interface — a sunset does not become a different sunset in dark mode —
/// and holding these fixed is what makes them the only fully saturated objects on the panel.
/// That is the point: the panel used to have exactly one saturated object on it, the key at
/// the bottom of the screen, and the illustration read as a placeholder waiting to load.
///
/// The three differences below are not styling. They are the three ways a duplicate differs
/// from its original, which is the whole argument of the first two pages: the same file, a
/// worse re-encode, the next frame of the burst, and a picture that merely resembles it.
private struct DrawnPhoto: View {

    /// Which palette. Wrapped, so callers can count without checking bounds.
    let scene: Int
    /// Moves the light and the crests without touching the palette: two pictures of the same
    /// place, a minute apart. This is `similar` — alike, and not the same shot.
    var composition: Int = 0
    /// The same picture, framed a fraction tighter. This is `burstLeftover`.
    var reframed: Bool = false
    /// A worse re-encode of the picture beside it. This is `inferiorCopy`.
    var degraded: Bool = false
    /// `DS.wellCorner` is drawn for a thumbnail well at thumbnail size. On the 46pt tiles inside
    /// the phone on page three it rounds away a third of the picture and the grid reads as a row
    /// of pills, so the radius has to come down with the tile.
    var corner: CGFloat = DS.wellCorner

    private struct Palette {
        let skyTop: Color
        let skyBottom: Color
        let light: Color
        let far: Color
        let near: Color
    }

    private static let palettes: [Palette] = [
        Palette(skyTop: Color(dsRGB: 0xF2884B), skyBottom: Color(dsRGB: 0xFBD9A3),
                light: Color(dsRGB: 0xFFF3D0), far: Color(dsRGB: 0x3B5468), near: Color(dsRGB: 0x1E3445)),
        Palette(skyTop: Color(dsRGB: 0x4A3A93), skyBottom: Color(dsRGB: 0xE8657F),
                light: Color(dsRGB: 0xFFD7A6), far: Color(dsRGB: 0x2A2050), near: Color(dsRGB: 0x150F2C)),
        Palette(skyTop: Color(dsRGB: 0x2C93E8), skyBottom: Color(dsRGB: 0xA8DFF7),
                light: Color(dsRGB: 0xFFFFFF), far: Color(dsRGB: 0x35845C), near: Color(dsRGB: 0x1F5E40)),
        Palette(skyTop: Color(dsRGB: 0x1580AC), skyBottom: Color(dsRGB: 0x78D6DA),
                light: Color(dsRGB: 0xEBFCFF), far: Color(dsRGB: 0x0F5570), near: Color(dsRGB: 0x073545)),
        Palette(skyTop: Color(dsRGB: 0x6FBE9B), skyBottom: Color(dsRGB: 0xDCF1DC),
                light: Color(dsRGB: 0xFFFFFF), far: Color(dsRGB: 0x35734B), near: Color(dsRGB: 0x204A33)),
        Palette(skyTop: Color(dsRGB: 0x16274F), skyBottom: Color(dsRGB: 0x40619B),
                light: Color(dsRGB: 0xDFE8FF), far: Color(dsRGB: 0x101B36), near: Color(dsRGB: 0x070C1C))
    ]

    var body: some View {
        let palette = Self.palettes[((scene % Self.palettes.count) + Self.palettes.count) % Self.palettes.count]
        let nudge = CGFloat(((composition % 3) + 3) % 3) * 0.15

        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [palette.skyTop, palette.skyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(palette.light)
                    .frame(width: geo.size.height * 0.28, height: geo.size.height * 0.28)
                    .position(
                        x: geo.size.width * (0.26 + nudge),
                        y: geo.size.height * (0.32 - nudge * 0.35)
                    )
                    .blur(radius: 1)

                Crest(peak: 0.30 + nudge, rise: 0.46).fill(palette.far)
                Crest(peak: 0.76 - nudge * 0.6, rise: 0.31).fill(palette.near)
            }
            // A burst frame is the same photograph with the camera a hair further on, so it is
            // a reframe of this picture and not a different one. Anchored rather than centred,
            // or the two tiles read as one zooming and nothing moving.
            .scaleEffect(reframed ? 1.16 : 1, anchor: .bottomTrailing)
        }
        // Desaturated and soft: what a re-send actually looks like beside the original it was
        // made from. Applied outside the clip so the softness is cut off by the frame edge
        // rather than fading past it.
        .saturation(degraded ? 0.5 : 1)
        .blur(radius: degraded ? 1.6 : 0)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
        )
    }
}

/// A ridge that meets both edges and peaks somewhere between them. Two of these at different
/// heights are all a landscape needs to read as one at forty points across.
private struct Crest: Shape {

    let peak: CGFloat
    let rise: CGFloat

    func path(in rect: CGRect) -> Path {
        let base = rect.maxY
        let apexX = rect.minX + rect.width * peak
        let apexY = base - rect.height * rise

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: base))
        path.addLine(to: CGPoint(x: rect.minX, y: base - rect.height * rise * 0.38))
        path.addQuadCurve(
            to: CGPoint(x: apexX, y: apexY),
            control: CGPoint(x: rect.minX + (apexX - rect.minX) * 0.58, y: apexY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: base - rect.height * rise * 0.2),
            control: CGPoint(x: apexX + (rect.maxX - apexX) * 0.42, y: apexY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: base))
        path.closeSubpath()
        return path
    }
}

/// What one rung does on the way in. Two properties, two curves, one timeline.
///
/// There was a third, `opacity`, starting at zero — gone for the same reason the copy's fade is.
/// `shown` arrives with `onAppear`, after the first layout, so the panel drew empty until it
/// landed. A rung that starts at full opacity and merely slides is present in every frame,
/// including the ones that arrive before the timeline does.
private struct RungEntry {
    var x: CGFloat = -16
    var scale: CGFloat = 0.96
}

/// The regret ladder, twice.
///
/// Page one shows the four rungs; page two puts the ticks on them. Same scene, one argument
/// apart, because that *is* the argument: these are the four kinds, and only two of them arrive
/// already decided. Drawing them as two unrelated pictures would have hidden the sentence.
///
/// Each rung is now a *pair of photographs* rather than a bar whose width encoded a share the
/// app never shows on this screen. The pair is the duplicate, and how the right-hand one
/// differs from the left is which rung it is — identical, a worse re-encode, the next frame,
/// or merely alike. Four sentences of copy, four pictures of exactly those four sentences.
private struct LadderScene: View {

    let ticked: Bool
    let reduceMotion: Bool

    @State private var shown = false

    var body: some View {
        // Measured rather than proposed: the panel is a flexible band now, and a rung whose
        // photographs are sized by `aspectRatio` alone can be squeezed to nothing by the
        // `Spacer` beside it. Two constraints, one `min`, no surprises at either end.
        GeometryReader { geo in
            let gap = DS.Space.m
            let rowHeight = (geo.size.height - gap * 3) / 4
            // Rail, four gaps, the badge, the tick and the seam between the pair. The badge's
            // share is an estimate rather than a measurement, and it is deliberately generous:
            // getting it wrong high costs a few points of photograph, getting it wrong low
            // pushes the tick off the edge of the panel on a small phone.
            let chrome = DS.railWidth + DS.Space.s * 4 + 100 + 22 + 6
            let photoWidth = min(rowHeight * 4 / 3, (geo.size.width - chrome) / 2)

            VStack(spacing: gap) {
                ForEach(Array(RegretTier.allCases.enumerated()), id: \.element) { index, tier in
                    entering(
                        row(tier, at: index, height: rowHeight, photoWidth: photoWidth),
                        at: index
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { shown = true }
    }

    /// A keyframe timeline rather than one curve with a delay.
    ///
    /// The two things a rung does on the way in do not share a shape: it slides, and it settles.
    /// One `.snappy` animating both gave the settle the same overshoot as the slide, which reads
    /// as a flicker at the end. Separate tracks let each keep its own spring. The leading hold on
    /// each track is the stagger — a delay expressed as part of the timeline rather than as a
    /// modifier the animation has to be re-applied through.
    @ViewBuilder
    private func entering(_ content: some View, at index: Int) -> some View {
        if reduceMotion {
            content
        } else {
            let hold = max(Double(index) * 0.07, 0.01)
            content.keyframeAnimator(initialValue: RungEntry(), trigger: shown) { view, entry in
                view
                    .offset(x: entry.x)
                    .scaleEffect(entry.scale, anchor: .leading)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    LinearKeyframe(-16, duration: hold)
                    SpringKeyframe(0, duration: 0.46, spring: .snappy)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.96, duration: hold)
                    SpringKeyframe(1, duration: 0.5, spring: .bouncy)
                }
            }
        }
    }

    private func row(
        _ tier: RegretTier,
        at index: Int,
        height: CGFloat,
        photoWidth: CGFloat
    ) -> some View {
        let photoHeight = photoWidth * 3 / 4

        return HStack(spacing: DS.Space.s) {
            Capsule(style: .continuous)
                .fill(DS.tier(tier))
                .frame(width: DS.railWidth, height: height)

            HStack(spacing: 6) {
                DrawnPhoto(scene: index)
                    .frame(width: photoWidth, height: photoHeight)
                copy(of: index, for: tier)
                    .frame(width: photoWidth, height: photoHeight)
            }

            Spacer(minLength: DS.Space.s)

            // The app's own badge, in the app's own words, tinted by the app's own rule. A pair
            // of 4:3 photographs sized by the row's height cannot fill a row this wide — there
            // were about ninety-six points of nothing to the right of every rung — and the thing
            // that belongs in that space is the one fact the pair does not carry: what deleting
            // it costs. It is also, on page two, the picture of that page's sentence.
            Badge(DS.cost(tier), tint: DS.costTint(tier))

            mark(tier)
                .frame(width: 22)
        }
        .frame(height: height)
    }

    /// The right-hand photograph: the same picture, differing in exactly the way its rung says.
    private func copy(of index: Int, for tier: RegretTier) -> DrawnPhoto {
        switch tier {
        case .identical: return DrawnPhoto(scene: index)
        case .inferiorCopy: return DrawnPhoto(scene: index, degraded: true)
        case .burstLeftover: return DrawnPhoto(scene: index, reframed: true)
        case .similar: return DrawnPhoto(scene: index, composition: 2)
        }
    }

    @ViewBuilder
    private func mark(_ tier: RegretTier) -> some View {
        if ticked {
            // `costTint` is the app's existing two-state answer: green for "costs nothing",
            // the ladder's amber for "your call". Not the rung's own colour, which would only
            // repeat what the rail beside it already said.
            Image(systemName: tier.isLossless ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(DS.costTint(tier))
                // Only the ticks bounce. A glyph that means "not decided" must not celebrate.
                .symbolEffect(.bounce, value: tier.isLossless && shown)
        } else {
            Color.clear
        }
    }
}

/// The promise that nothing leaves, drawn as the one thing a promise like that can be drawn as:
/// something that expands and then stops at an edge.
///
/// The clip is the whole illustration. Rings that faded out on their own would say "it spreads
/// and gets weaker"; rings cut off by the phone's own outline say "it does not leave".
///
/// What is inside the outline is photographs, because that is what the sentence is about. An
/// empty well with a lock on it made the promise about nothing in particular.
///
/// Deliberately *not* a `phaseAnimator`. This is one continuous expansion repeated at three
/// offsets, not a walk through discrete states, and `repeatForever` with a stagger is still the
/// right tool for that.
private struct ContainedScene: View {

    let reduceMotion: Bool

    @State private var pulsing = false

    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
    private static let nominal = CGSize(width: 122, height: 214)

    var body: some View {
        // Drawn at one size and scaled, so the phone, its corner radius, its stroke and the
        // photographs inside it stay in proportion at either end of the band.
        //
        // It scales *up* as well as down, and that is the correction. Clamped at 1 it sat at its
        // drawing height of 214pt in a 338pt panel, leaving the emptiest picture on the screen
        // on the page whose whole job is to be believed. The ceiling is there so it cannot grow
        // past the panel's width on a tall, narrow phone.
        GeometryReader { geo in
            let scale = min(geo.size.height / Self.nominal.height, geo.size.width / Self.nominal.width)
            phone
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var phone: some View {
        shape
            .fill(DS.well)
            .overlay(shape.strokeBorder(DS.slabEdge, lineWidth: 2))
            .frame(width: Self.nominal.width, height: Self.nominal.height)
            .overlay {
                ZStack {
                    library
                    rings
                    lock
                }
                .clipShape(shape)
            }
            // `task` rather than `onAppear`: the loop has to start after the first layout, and
            // an `onAppear` that lands before it leaves the rings sitting at their start value
            // with nothing to animate towards.
            .task { pulsing = true }
    }

    private var library: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { column in
                        DrawnPhoto(scene: row * 2 + column, corner: 5)
                            .frame(width: 46, height: 34)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rings: some View {
        if reduceMotion {
            // One ring, held at the size where it is clearly inside the edge.
            Circle()
                .stroke(DS.brand, lineWidth: 2.5)
                .frame(width: 86, height: 86)
                .shadow(color: .black.opacity(0.45), radius: 3)
        } else {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(DS.brand, lineWidth: 2.5)
                    .frame(width: 44, height: 44)
                    // A stroke laid over photographs loses the fight without this; the rings
                    // used to be drawn over a flat `DS.well` where nothing competed with them.
                    .shadow(color: .black.opacity(0.45), radius: 3)
                    .scaleEffect(pulsing ? 3.4 : 0.5)
                    .opacity(pulsing ? 0 : 0.95)
                    .animation(
                        .easeOut(duration: 2.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(ring) * 0.87),
                        value: pulsing
                    )
            }
        }
    }

    private var lock: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.deep)
            .frame(width: 34, height: 34)
            .background(Circle().fill(DS.slab))
            .overlay(Circle().strokeBorder(DS.slabEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }
}

/// The library, being read.
///
/// Nine photographs and one pass over them, corner to corner. Deliberately not
/// `SweeperRingView`: that is a figure sweeping a floor, the app's picture of *deleting*, and
/// on the screen that asks permission to *look* it would say the photographs were being swept
/// up.
///
/// One pass, not a loop. The cells used to blink a `DS.deep` border on and off forever through
/// five phases, which is the motion for something being *selected* and reads as decoration the
/// moment you have watched it twice — the user's exact complaint, that the animation does not
/// explain the app. A single reveal that runs once and holds says the only true thing there is
/// to say here: it reads your library, once, and then it has read it. The page is rebuilt on
/// every turn, so coming back to it plays the pass again.
private struct LibraryScene: View {

    let reduceMotion: Bool

    @State private var read = false

    var body: some View {
        GeometryReader { geo in
            let gap = DS.Space.s
            let side = min(
                (geo.size.width - gap * 2) / 3,
                (geo.size.height - gap * 2) / 3
            )

            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { column in
                            tile(row * 3 + column).frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { read = true }
    }

    /// Row plus column: the cells on one anti-diagonal share a step, so the pass runs corner to
    /// corner instead of left to right.
    private func diagonal(of cell: Int) -> Int { cell % 3 + cell / 3 }

    /// Grey to colour, not invisible to visible.
    ///
    /// The tiles used to start at a tenth of their opacity, so the grid was effectively blank
    /// until `read` was set in `onAppear` — and `onAppear` lands after the first layout, so a
    /// slow launch showed an empty panel on the very page that asks for the library.
    /// Desaturation carries the same idea and costs nothing in legibility: an unread photograph
    /// is still a photograph, and colour arriving is a better picture of "it has been read" than
    /// existence arriving.
    private func tile(_ cell: Int) -> some View {
        let revealed = read || reduceMotion

        return DrawnPhoto(scene: cell)
            .saturation(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 0.9)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.45).delay(Double(diagonal(of: cell)) * 0.11),
                value: read
            )
    }
}
