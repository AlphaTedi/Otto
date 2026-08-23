import AppKit
import SwiftUI

// MARK: - Onboarding design system
//
// Every number, colour, material and spring in the onboarding flow, in one
// place. The layout geometry comes from the Figma CSS exports of Sketch A
// (welcome) and Sketch B (feature grid); the MATERIALS and MOTION come from
// Apple's own — Liquid Glass, and the rules in Designing Fluid Interfaces.
//
// Where the two disagreed, Apple won, because "make it look like the sketch"
// and "make it feel like a Mac app" are different jobs and only one of them is
// about pixels. The three places that happened are marked below.
//
// Two constraints the design could not override:
//
//   Inter. The export specifies Inter throughout. Otto does not bundle it —
//   the type-system export was tried on 2026-07-26 and reverted, and the app
//   is on SF. Apple's own guidance is to reach for the system face first: it
//   already ships optical sizing, tracking tables and legibility tuning that a
//   bundled webfont would not. Sizes and weights below are the export's.
//
//   The window is 1200x800 in the export. Otto's onboarding shrinks to
//   520x300 for the practice step so the notch panel cannot cover the
//   instructions; that behaviour is kept, and the compact screen uses the same
//   tokens at a smaller size.

// MARK: Motion
//
// Apple replaced the physics triplet (mass/stiffness/damping) with two
// designer-facing numbers: DAMPING, which controls overshoot, and RESPONSE,
// which is how fast the value reaches its target — explicitly not a duration,
// since a spring has no fixed one.
//
// The rule that matters and that this flow was breaking: bounce belongs only
// where the gesture itself carried momentum. A screen that was pushed by a
// button press has no momentum, so it must be critically damped. Overshoot on
// something that merely appeared reads as decoration; overshoot on something
// you flicked reads as physics. Every spring here was under-damped before,
// including ones nobody ever touched.

enum OnbMotion {
    /// The default. Critically damped — no overshoot, graceful, and it never
    /// draws attention to itself.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// Step-to-step. Slightly slower because it moves a whole screen.
    static let screen = Animation.spring(response: 0.42, dampingFraction: 1.0)
    /// Press feedback. Fast enough to feel like the surface answered the
    /// finger rather than acknowledged it.
    static let press = Animation.spring(response: 0.14, dampingFraction: 1.0)
    /// The one place bounce is earned: something the user threw or dragged.
    static let momentum = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Reduce Motion's replacement for all of the above — a cross-fade, not a
    /// slide. Gentler, not absent: opacity still carries the comprehension.
    static let reduced = Animation.easeInOut(duration: 0.18)
}

enum OnbColor {
    /// The window itself: purple at the top falling to near-black at the foot.
    ///
    /// #7F6CC5 at 0% to #251852 at 87%.
    ///
    /// The 87 matters and is not a rounding of 100: the ramp finishes early
    /// and the last eighth of the window holds the dark tone flat, which is
    /// what keeps the foot of the window from continuing to darken under the
    /// nav bar. An earlier export quoted stops outside the box; this one is
    /// inside it and can be stated as-is.
    static let windowGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#7F6CC5"), location: 0.0),
            .init(color: Color(hex: "#251852"), location: 0.87)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Grouped surfaces — feature cards, the preference rows, the tips list.
    ///
    /// Deliberately DARK. Apple's rule for translucent materials is that a
    /// light surface must never be stacked on another light one, because
    /// legibility collapses; the glass buttons are the light layer in this
    /// flow, so everything they sit on or near is the heavy one. Weight
    /// encodes hierarchy: dark separates regions, light draws the eye to what
    /// you can actually press.
    static let card = Color.black.opacity(0.3)
    /// rgba(0,0,0,0.2) in the export — the tint carried by the glass on the
    /// preference rows, the nav bar, the indicator and the keycaps, all of
    /// which are Liquid Glass rather than flat fills.
    static let glassTint = Color.black.opacity(0.2)
    static let nav = Color.black.opacity(0.28)

    /// The pre-macOS-26 stand-in for Liquid Glass.
    static let glassFallback = Color.white.opacity(0.12)
    /// What every translucent surface collapses to under Reduce Transparency.
    static let opaque = Color(hex: "#2A2145")

    static let text = Color.white
    /// Taglines and secondary copy. Vibrancy rule: over a translucent or
    /// changing background, secondary text is high-contrast white at reduced
    /// alpha rather than flat grey, which would muddy against the gradient.
    static let subtext = Color.white.opacity(0.6)
    static let badge = Color(hex: "#E6E6E6")
    /// #413374 in the export — and on the purple gradient it is very nearly
    /// the background, so the steps you have not reached simply were not
    /// there (Marcello, 2026-08-23: "now they're just invisible"). Dimmed
    /// white instead: the same idea, actually visible.
    static let progressIdle = Color.white.opacity(0.4)

    static let markGradient = LinearGradient(
        colors: [Color(hex: "#B5A5F0"), Color(hex: "#6338FF")],
        startPoint: .top,
        endPoint: .bottom
    )

    // Window controls. Near the system colours but not identical — the export
    // is explicit about these, so they are stated rather than inherited.
    static let close = Color(hex: "#FF736A")
    static let minimize = Color(hex: "#FEBC2E")
    static let zoom = Color(hex: "#19C332")
}

enum OnbMetric {
    static let windowWidth: CGFloat = 1200
    static let windowHeight: CGFloat = 800
    static let windowRadius: CGFloat = 26
    /// The practice screens. 640x564 in the export, replacing the old
    /// 520x300 — the window still gets out of the notch's way, at the size
    /// the design was drawn at.
    /// The practice window. Derived, not given: the spec fixes the keycaps at
    /// 52.55 and the screenshots put them at about a tenth of the window's
    /// width, which lands here. It is also small enough to sit clear of the
    /// notch panel opening above it, which is the whole reason it shrinks.
    static let compactWidth: CGFloat = 525
    /// 250, down from 300. At 300 the content ended around two-thirds up and
    /// the rest was dead height — which is what let the to-do panel cover the
    /// window on the very step that asks you to look at both (Marcello,
    /// 2026-08-23, screenshot 4).
    static let compactHeight: CGFloat = 250

    /// Everything from step 3 onward lives inside this. The feature grid
    /// (step 2) is the one screen that stays full width.
    static let columnWidth: CGFloat = 640
    static let columnTop: CGFloat = 72
    /// Enough to clear the window controls and no more.
    static let columnTopCompact: CGFloat = 40
    /// Room for the dots and the little under them — nothing like the 168 the
    /// wide screens need for a full bar.
    static let columnBottomCompact: CGFloat = 48
    /// The rail sits closer to the edge here than the full bar does.
    static let navBottomCompact: CGFloat = 22
    /// Clears the nav bar: 45 up from the bottom + 96 tall + air.
    static let columnBottom: CGFloat = 168
    /// The gap under the content column on the screens that state one.
    static let columnBottomInset: CGFloat = 40
    static let columnGap: CGFloat = 24
    /// The inset box the content sits in — 640 less 32 either side = 576.
    static let bodyPadding: CGFloat = 32

    /// A preference row: 70 tall, tighter on the left where the icon is.
    static let rowHeight: CGFloat = 70
    static let rowRadius: CGFloat = 12
    static let rowPaddingLeading: CGFloat = 12
    static let rowPaddingTrailing: CGFloat = 20
    static let rowPaddingV: CGFloat = 8
    static let rowGap: CGFloat = 6
    static let rowIcon: CGFloat = 48
    static let rowTextGap: CGFloat = 4
    static let radioSize: CGFloat = 18
    static let radioStroke: CGFloat = 2

    /// The keycaps on the practice screens.
    /// 52.55 and 12.19 are the design's own numbers, not rounded — I had
    /// been measuring these off screenshots and landing somewhere else each
    /// time. They DO overlap, by 8.
    static let keycap: CGFloat = 52.55
    static let keycapRadius: CGFloat = 12.19
    static let keycapGap: CGFloat = -8

    static let navWidth: CGFloat = 640
    static let navHeight: CGFloat = 96
    /// Indicator-only, on the practice screens.
    static let navCompactWidth: CGFloat = 154
    static let navCompactHeight: CGFloat = 56
    /// The rail's own width inside that pill.
    static let navCompactContentWidth: CGFloat = navCompactWidth - navPadding * 2

    /// Window controls: three 14pt circles, 9pt apart, 18pt in from the
    /// corner. Top-LEFT, because on macOS close is always top-left and
    /// familiarity is worth more here than novelty.
    static let controlDot: CGFloat = 14
    static let controlGap: CGFloat = 9
    static let controlInset: CGFloat = 18

    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 24
    /// A card is an image with its title laid ON it, 32 down from the top —
    /// not a title above a separate picture, which is how I had built it.
    static let cardTitleTop: CGFloat = 32
    /// Screens 5 and 6: one 576x454 visual inside a 32pt-padded box.
    static let heroWidth: CGFloat = 576
    static let heroHeight: CGFloat = 454
    static let cardGap: CGFloat = 24
    static let imageRadius: CGFloat = 16

    static let gridInset: CGFloat = 48
    static let gridTop: CGFloat = 72
    static let gridBottom: CGFloat = 168

    static let navPadding: CGFloat = 24
    static let navBottom: CGFloat = 45
    static let navIconButton: CGFloat = 48
    static let navInnerGap: CGFloat = 14
    /// 640 less 24 either side. Stated, because `.padding` then
    /// `.frame(width:)` sizes the row to its CONTENT and centres it — the
    /// controls ended up clustered instead of reaching the bar's ends.
    static let navContentWidth: CGFloat = navWidth - navPadding * 2

    static let buttonPaddingH: CGFloat = 24
    static let buttonPaddingV: CGFloat = 12
    /// 12 above and below a 19pt line comes to 43, and the design says 48.
    /// Stated rather than derived, so it cannot drift with the type again.
    static let buttonHeight: CGFloat = 48
    static let buttonGap: CGFloat = 12
    /// How far a button gives under the pointer. Small — the press has to
    /// read as the surface answering, not as the button shrinking.
    static let pressScale: CGFloat = 0.97

    static let badgeRadius: CGFloat = 6
    static let badgePaddingH: CGFloat = 7.5
    static let badgePaddingV: CGFloat = 2

    static let progressPill = CGSize(width: 40, height: 8)
    static let progressDot: CGFloat = 8
    static let progressGap: CGFloat = 14
}

// MARK: Type
//
// Tracking is SIZE-SPECIFIC, never one value for everything. Letters read too
// far apart as they grow, so large text is tightened and body text sits near
// zero. A single letter-spacing across a type ramp is wrong somewhere by
// definition — and the flow had exactly that: none at all, at every size.

enum OnbFont {
    /// Marked Semi Bold in the design but exporting at weight 700 — bold.
    static let cardTitle = Font.system(size: 18, weight: .bold)
    static let button = Font.system(size: 16, weight: .medium)
    static let badge = Font.system(size: 10, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let rowSubtitle = Font.system(size: 13.5, weight: .regular)

    /// 30/36 SemiBold, at both sizes. The compact screens in the export use
    /// the SAME headline as the wide ones — they are 640 wide either way, so
    /// there is nothing to shrink for.
    /// 34/600 — and on the two practice screens a SECONDARY 20/600, which is
    /// a different style in the design rather than the same one shrunk.
    ///
    /// The design calls for Bricolage Grotesque here and Inter everywhere
    /// else. Otto bundles neither, so both resolve to SF at the stated size
    /// and weight. Both faces are openly licensed and could be bundled — that
    /// is a real decision about binary size and licence files, not something
    /// to slip in silently.
    static func title(compact: Bool) -> Font {
        .system(size: compact ? 20 : 34, weight: .semibold)
    }
    /// Inter 14/400, full white.
    static func tagline(compact: Bool) -> Font {
        .system(size: 14, weight: .regular)
    }
    static let rowTitleType = Font.system(size: 14, weight: .medium)
    static let rowSubtitleType = Font.system(size: 11, weight: .medium)

    /// −0.02em at display sizes, easing to 0 by body. Applied as points
    /// because SwiftUI's `kerning` is absolute.
    static func tracking(forSize size: CGFloat) -> CGFloat {
        size >= 30 ? -size * 0.02 : (size >= 20 ? -size * 0.012 : 0)
    }
    static func titleTracking(compact: Bool) -> CGFloat { tracking(forSize: compact ? 20 : 34) }
    static func taglineTracking(compact: Bool) -> CGFloat { 0 }
}

// MARK: - Liquid Glass
//
// The real API: `glassEffect(_:in:)`, `Glass.interactive()`, and
// `GlassEffectContainer`, all `@available(macOS 26.0, *)` and living in
// SwiftUICore. Otto is built against the macOS 26 SDK and deploys lower, so
// every use is behind an availability check with a fallback that is a plain
// translucent capsule rather than a pretend refraction.
//
// `.interactive()` is the part that matters for buttons: it is Apple's own
// press response for the material — the glass itself reacts to being pressed,
// on pointer-DOWN, which is the rule this flow was breaking everywhere by
// only responding to hover.

/// Three ways a surface can be drawn, chosen by OS and accessibility settings
/// rather than by each call site guessing.
///
/// Generic over the shape, because Liquid Glass in this flow is not only on
/// pills: the preference rows are 12pt rounded rects, the keycaps are 32pt
/// ones, and the nav bar is a full capsule. All of them are the real material.
struct OnbGlassSurface<S: Shape & InsettableShape>: ViewModifier {
    let shape: S
    var isInteractive: Bool = false
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Reduce Transparency is not a preference about taste — it is
            // someone telling the system they cannot read text on glass. The
            // surface goes solid and the blur goes away entirely.
            content.background(shape.fill(OnbColor.opaque))
                   .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(shape.fill(fallbackFill))
                   .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    /// Below 26 there is no refraction to tint, so the tint IS the fill.
    private var fallbackFill: Color {
        tint ?? OnbColor.glassFallback
    }

    /// `.interactive()` is an iOS behaviour — the material scales and shimmers
    /// under a finger. On macOS it is a no-op, which is why every pressable
    /// surface here also carries OnbPressStyle: the press feedback cannot come
    /// from the material on this platform.
    @available(macOS 26.0, *)
    private var glass: Glass {
        let base = Glass.regular.interactive(isInteractive)
        if let tint { return base.tint(tint) }
        return base
    }
}

extension View {
    /// Liquid Glass on macOS 26, a translucent shape below it, and a solid
    /// fill under Reduce Transparency.
    func onbGlass<S: Shape & InsettableShape>(
        _ shape: S,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(OnbGlassSurface(shape: shape, isInteractive: interactive, tint: tint))
    }

    /// The common case: a pill.
    func onbGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(OnbGlassSurface(shape: Capsule(), isInteractive: interactive, tint: tint))
    }

    /// Groups nearby glass elements so the material can blend them the way
    /// Apple's does, instead of each one refracting in isolation.
    @ViewBuilder
    func onbGlassGroup(spacing: CGFloat = 20) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

// MARK: - Pieces

/// The small bordered key hint that rides next to a button — "↵".
///
/// It stays a hairline-bordered chip rather than becoming its own glass
/// surface: putting light glass on top of a light glass button is the exact
/// stacking Apple's material guidance forbids.
struct OnbKeyBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OnbFont.badge)
            .foregroundStyle(OnbColor.badge)
            .padding(.horizontal, OnbMetric.badgePaddingH)
            .padding(.vertical, OnbMetric.badgePaddingV)
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.badgeRadius, style: .continuous)
                    .strokeBorder(OnbColor.badge, lineWidth: 1)
            )
    }
}

/// Press feedback that lands on pointer-DOWN.
///
/// "The moment lag appears, the feeling of directness falls off a cliff."
/// Every button in this flow used to respond to HOVER and then do nothing at
/// all when clicked — the press, the one moment the user is asking a question,
/// went unanswered until the next screen arrived.
struct OnbPressStyle: ButtonStyle {
    var scale: CGFloat = OnbMetric.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(OnbMotion.press, value: configuration.isPressed)
    }
}

/// The one button shape in the flow: a Liquid Glass pill carrying the key that
/// also triggers it.
struct OnbButton: View {
    let title: String
    /// No badge by default. The ⏎ chip is gone from the buttons (Marcello,
    /// 2026-08-23) — Return still works, it just is not advertised on the
    /// pill. Kept as an option rather than deleted so a screen that genuinely
    /// needs to teach a key can still ask for one.
    var key: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var label: some View {
        HStack(spacing: OnbMetric.buttonGap) {
            Text(title)
                .font(OnbFont.button)
                .foregroundStyle(OnbColor.text)
            if let key { OnbKeyBadge(text: key) }
        }
    }

    var body: some View {
        // A custom view carrying real glass, not `.buttonStyle(.glass)`.
        //
        // The system style was the more canonical control, but it brings
        // Apple's metrics with it and this design is explicit about its own:
        // 48pt tall, 24 either side. Through the style the pills came out
        // around a third shorter and read as thin bars hugging their text
        // (Marcello, 2026-08-23). Applying the material to a custom view is
        // Apple's other documented path, and it is the one that can be sized.
        Button(action: action) {
            label
                .padding(.horizontal, OnbMetric.buttonPaddingH)
                // HEIGHT, not vertical padding. Padding leaves the result at
                // the mercy of whatever the label's line box happens to be;
                // the design states 48, so this states 48.
                .frame(height: OnbMetric.buttonHeight)
                .onbGlass()
                .overlay(
                    Capsule().fill(Color.white.opacity(hovering && isEnabled ? 0.06 : 0))
                )
                // Glass registers hits on its CONTENT, not its area, so the
                // shape has to be stated or the pill's edges are dead.
                .contentShape(Capsule())
        }
        .buttonStyle(OnbPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(OnbMotion.standard, value: hovering)
    }
}

/// A quiet text action — "Skip this step". No glass: it is deliberately not
/// the thing you are meant to press.
struct OnbQuietButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? OnbColor.text : OnbColor.subtext)
        }
        .buttonStyle(OnbPressStyle(scale: 0.94))
        .onHover { hovering = $0 }
        .animation(OnbMotion.standard, value: hovering)
    }
}

/// The heavy grouped surface: feature cards, preference rows, the tips list.
struct OnbCard<Content: View>: View {
    var padding: CGFloat = OnbMetric.cardPadding
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: OnbMetric.cardRadius, style: .continuous)
                    .fill(reduceTransparency ? OnbColor.opaque : OnbColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Where the image for a feature card goes. Deliberately a marked, empty slot:
/// the five cards need one bespoke visual each — a small real interface
/// preview, the way Raycast's "Out of the box" screen does it — and that is
/// copy and art direction, not layout. Dropping a real image in here later
/// changes nothing around it.
struct OnbCardImageSlot<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content = { EmptyView() }) {
        self.content = content()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: OnbMetric.imageRadius, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .overlay(content.padding(10))
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.imageRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: OnbMetric.imageRadius,
                                        style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One feature card: a cover image, a 50% black wash, and the title laid ON
/// it 32pt down from the top.
///
/// Not a title above a separate picture in a box, which is how I had it —
/// that is why the cards read as a caption with a hole under it rather than
/// as artwork with a name on it.
struct OnbFeatureCard<Art: View>: View {
    let title: String
    @ViewBuilder var art: Art

    init(title: String, @ViewBuilder art: () -> Art) {
        self.title = title
        self.art = art()
    }

    var body: some View {
        ZStack(alignment: .top) {
            art
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            // The wash is what keeps the title legible over any artwork.
            Color.black.opacity(0.5)
            Text(title)
                .font(OnbFont.cardTitle)
                .foregroundStyle(OnbColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OnbMetric.cardPadding)
                .padding(.top, OnbMetric.cardTitleTop)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: OnbMetric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnbMetric.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Confetti for the final step.
///
/// Drawn rather than shipped as the design's 1200x926 bitmap: at that size it
/// would be a megabyte of asset for four seconds of screen, and drawn pieces
/// start from the top edge of whatever the window actually is instead of
/// assuming one height.
///
/// Driven by a TIMELINE, not by an implicit animation. The first version set
/// a `fallen` flag in `onAppear` and let `.animation(_:value:)` carry it — and
/// that state change lands in the same layout pass the view first appears in,
/// so the animation never ran: every piece jumped straight to its end state,
/// which was off-screen at zero opacity. Confetti that is always already over
/// looks exactly like no confetti at all (Marcello, 2026-08-23). A timeline
/// computes each frame from elapsed time, so there is no transition to be
/// swallowed.
///
/// It fires ONCE and stops — the view removes itself when the last piece
/// lands, which also stops the timeline rather than leaving it ticking behind
/// a finished screen.
struct OnbConfetti: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false
    @State private var pieces: [Piece] = OnbConfetti.make()

    private static let palette: [Color] = [
        Color(hex: "#FF5A5F"), Color(hex: "#FFC93C"), Color(hex: "#37D67A"),
        Color(hex: "#3B9EFF"), Color(hex: "#C86DD7"), Color(hex: "#FF8A4C")
    ]

    struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat          // 0...1 across the window
        let delay: Double
        let duration: Double
        let spin: Double
        let size: CGSize
        let color: Color
        let drift: CGFloat
    }

    private static func make() -> [Piece] {
        (0..<70).map { i in
            Piece(x: CGFloat.random(in: 0.02...0.98),
                  delay: Double.random(in: 0...0.9),
                  duration: Double.random(in: 1.8...3.0),
                  spin: Double.random(in: -540...540),
                  size: CGSize(width: CGFloat.random(in: 6...11),
                               height: CGFloat.random(in: 10...17)),
                  color: palette[i % palette.count],
                  drift: CGFloat.random(in: -70...70))
        }
    }

    private var life: Double {
        (pieces.map { $0.delay + $0.duration }.max() ?? 3) + 0.2
    }

    var body: some View {
        // Reduce Motion gets nothing: confetti is pure motion, so a gentler
        // version of it is still confetti, and there is no information in it
        // to preserve.
        if reduceMotion || finished {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSince(start)
                    for piece in pieces {
                        let t = now - piece.delay
                        guard t > 0 else { continue }
                        let progress = t / piece.duration
                        guard progress < 1 else { continue }

                        var layer = context
                        layer.translateBy(
                            x: piece.x * size.width + piece.drift * progress,
                            y: -20 + progress * (size.height + 60)
                        )
                        layer.rotate(by: .degrees(piece.spin * progress))
                        // Only the last stretch fades, so a piece is solid for
                        // almost the whole way down.
                        layer.opacity = progress > 0.8 ? (1 - (progress - 0.8) / 0.2) : 1

                        let rect = CGRect(x: -piece.size.width / 2,
                                          y: -piece.size.height / 2,
                                          width: piece.size.width,
                                          height: piece.size.height)
                        layer.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                   with: .color(piece.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .onAppear {
                start = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + life) {
                    finished = true
                }
            }
        }
    }
}

/// Stand-in art for the two features that have no visual yet.
///
/// Visible on purpose. The slot used to be white at 6% — present in the
/// layout and invisible on screen, so those two cards read as broken rather
/// than as unfinished. This says "something goes here" out loud.
struct OnbPlaceholderArt: View {
    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(OnbColor.markGradient)
                    .frame(width: unit * 1.1, height: unit * 1.1)
                    .offset(x: -unit * 0.25, y: -unit * 0.1)
                    .opacity(0.28)
                RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous)
                    .fill(Color.white)
                    .frame(width: unit * 0.9, height: unit * 0.62)
                    .offset(x: unit * 0.3, y: unit * 0.18)
                    .opacity(0.14)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .blur(radius: unit * 0.03)
        }
        .accessibilityHidden(true)
    }
}

/// Where you are in the flow: the current step widens into a pill, the rest
/// stay dots. No "4 of 8" — nobody should have to count.
struct OnbProgress: View {
    let current: Int
    let total: Int
    /// Tapping a step you have already been through goes back to it. On the
    /// practice screens this is the ONLY way back, because those two carry no
    /// buttons at all — so the rail stops being a readout and becomes the
    /// navigation.
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: OnbMetric.progressGap) {
            ForEach(0..<total, id: \.self) { i in
                let isCurrent = i == current
                Capsule()
                    .fill(isCurrent ? OnbColor.text : OnbColor.progressIdle)
                    .frame(width: isCurrent ? OnbMetric.progressPill.width
                                            : OnbMetric.progressDot,
                           height: isCurrent ? OnbMetric.progressPill.height
                                             : OnbMetric.progressDot)
                    // Forward is not offered: a step you have not reached has
                    // not asked its question yet.
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { if i < current { onSelect?(i) } }
                    .accessibilityAddTraits(i < current ? [.isButton] : [])
            }
        }
        .animation(OnbMotion.standard, value: current)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

/// The three window controls.
///
/// The real ones are hidden — they have been since this window was written —
/// so these are not decoration over working buttons; they ARE the controls,
/// and each is wired to the window action it depicts. Their colours are the
/// export's, which sit a shade off the system's on purpose.
struct OnbWindowControls: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: OnbMetric.controlGap) {
            dot(OnbColor.close, symbol: "xmark", label: "Close") {
                OnboardingWindowController.dismiss()
            }
            dot(OnbColor.minimize, symbol: "minus", label: "Minimize") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            dot(OnbColor.zoom, symbol: "arrow.up.left.and.arrow.down.right", label: "Zoom") {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .onHover { hovering = $0 }
        .animation(OnbMotion.standard, value: hovering)
        .padding(OnbMetric.controlInset)
    }

    private func dot(_ color: Color, symbol: String, label: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: OnbMetric.controlDot, height: OnbMetric.controlDot)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                // The glyph appears on hover, the way the real ones do.
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.5))
                        .opacity(hovering ? 1 : 0)
                )
        }
        .buttonStyle(OnbPressStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

/// A back affordance, on every screen that has somewhere to go back to.
///
/// Wayfinding: every screen must answer "how do I get out of here". It used to
/// exist on exactly one screen, which meant the other seven were one-way — and
/// a flow you cannot reverse is one you have to finish before you can find out
/// whether you wanted to.
struct OnbBackButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OnbColor.text)
                .frame(width: OnbMetric.navIconButton, height: OnbMetric.navIconButton)
                // rgba(0,0,0,0.004) in the design: a hit target, not a fill.
                // It had glass on it, which made a quiet secondary action look
                // like a second primary one. The only thing it shows now is a
                // faint answer to the pointer.
                .background(Circle().fill(Color.white.opacity(hovering ? 0.08 : 0.001)))
                .contentShape(Circle())
        }
        .buttonStyle(OnbPressStyle())
        .onHover { hovering = $0 }
        .animation(OnbMotion.standard, value: hovering)
        .accessibilityLabel("Back")
    }
}

/// The bar at the foot of every screen: back, where you are, what's next.
///
/// It is drawn by the FLOW, not by each screen, which is why it can be
/// promised to always be there. Before, it existed on exactly one screen and
/// the other seven each invented their own footer.
///
/// Liquid Glass, tinted to the export's rgba(0,0,0,0.2), with the two controls
/// inside one GlassEffectContainer so the material blends them rather than
/// refracting each alone.
struct OnbBottomNav: View {
    var onBack: (() -> Void)?
    let current: Int
    let total: Int
    /// nil on the practice screens, where the action is the shortcut itself
    /// and a button would be a second, wrong way to do it.
    var primary: (title: String, action: () -> Void)?
    var onSelectStep: ((Int) -> Void)? = nil

    /// The practice steps show the rail and nothing else. It is one bar
    /// throughout, narrowing rather than being replaced, so the change reads
    /// as the chrome getting out of the way for a step that wants the screen.
    private var isMinimal: Bool { onBack == nil && primary == nil }

    var body: some View {
        ZStack {
            // Centred in the BAR, independent of how wide the two buttons
            // happen to be. It used to sit next to the primary button, which
            // is why it looked off-centre — and it moved whenever the button's
            // label changed length.
            OnbProgress(current: current, total: total, onSelect: onSelectStep)

            if !isMinimal {
                HStack(spacing: OnbMetric.navInnerGap) {
                    if let onBack {
                        OnbBackButton(action: onBack)
                    } else {
                        Color.clear.frame(width: OnbMetric.navIconButton,
                                          height: OnbMetric.navIconButton)
                    }

                    Spacer(minLength: 0)

                    if let primary {
                        OnbButton(title: primary.title, action: primary.action)
                    } else {
                        Color.clear.frame(width: OnbMetric.navIconButton,
                                          height: OnbMetric.navIconButton)
                    }
                }
                .onbGlassGroup()
                .transition(.opacity)
            }
        }
        // NO TRAY.
        //
        // The bar used to sit in its own dark capsule. The newer designs drop
        // it entirely — the controls float straight on the window, which is
        // also why the back button is a bare hit target and the primary is
        // the only thing carrying a surface. The tray was making the footer
        // read as a slab bolted to the bottom of every screen.
        .frame(width: isMinimal ? nil : OnbMetric.navContentWidth,
               height: OnbMetric.navIconButton)
        .animation(OnbMotion.screen, value: isMinimal)
    }
}

/// The 640pt column every screen from step 3 onward lives in.
///
/// The feature grid is the one exception and stays full width; everything
/// after it is this. Stated once so no screen can drift out of the column.
struct OnbScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.onbCompact) private var compact

    var body: some View {
        VStack(spacing: OnbMetric.columnGap) {
            VStack(spacing: OnbMetric.columnGap) {
                Text(title)
                    .font(OnbFont.title(compact: compact))
                    .kerning(OnbFont.titleTracking(compact: compact))
                    .foregroundStyle(OnbColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                if let subtitle {
                    Text(subtitle)
                        .font(OnbFont.tagline(compact: compact))
                        .foregroundStyle(OnbColor.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }

            content
                .padding(compact ? 0 : OnbMetric.bodyPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The compact window is 525x300. The full column would put a 640pt
        // frame inside a 525pt window and 240pt of padding inside 300pt of
        // height — which is exactly what pushed the headline up under the
        // traffic lights and crushed everything under it (Marcello,
        // 2026-08-23). Compact gets its own numbers rather than the big
        // screen's, scaled by hope.
        .frame(width: compact ? nil : OnbMetric.columnWidth)
        .padding(.horizontal, compact ? 24 : 0)
        .padding(.top, compact ? OnbMetric.columnTopCompact : OnbMetric.columnTop)
        .padding(.bottom, compact ? OnbMetric.columnBottomCompact : OnbMetric.columnBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One choice on the preference screen: icon, two lines, and a radio.
///
/// Liquid Glass at the export's 12pt radius and 0.2 black tint — a card you
/// press, so the material is `interactive` and answers the pointer itself.
struct OnbPreferenceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OnbMetric.rowGap) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(OnbColor.text)
                    .frame(width: OnbMetric.rowIcon, height: OnbMetric.rowIcon)

                VStack(alignment: .leading, spacing: OnbMetric.rowTextGap) {
                    Text(title)
                        .font(OnbFont.rowTitleType)
                        .foregroundStyle(OnbColor.text)
                    Text(subtitle)
                        .font(OnbFont.rowSubtitleType)
                        .foregroundStyle(OnbColor.subtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The radio fills rather than swapping to a different glyph,
                // so the control keeps its shape and only its state changes.
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: OnbMetric.radioStroke)
                    .frame(width: OnbMetric.radioSize, height: OnbMetric.radioSize)
                    .overlay(
                        Circle()
                            .fill(OnbColor.text)
                            .frame(width: OnbMetric.radioSize - 8,
                                   height: OnbMetric.radioSize - 8)
                            .opacity(isSelected ? 1 : 0)
                    )
            }
            .padding(.leading, OnbMetric.rowPaddingLeading)
            .padding(.trailing, OnbMetric.rowPaddingTrailing)
            .padding(.vertical, OnbMetric.rowPaddingV)
            .frame(height: OnbMetric.rowHeight)
            .onbGlass(RoundedRectangle(cornerRadius: OnbMetric.rowRadius, style: .continuous),
                      interactive: true,
                      tint: OnbColor.glassTint)
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.rowRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.5 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: OnbMetric.rowRadius, style: .continuous))
        }
        .buttonStyle(OnbPressStyle(scale: 0.99))
        .animation(OnbMotion.standard, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A key, as a physical object: 138pt of Liquid Glass at 32pt radius, tilted a
/// few degrees so a row of them reads as placed rather than laid out.
struct OnbKeycap: View {
    let glyph: String
    let rotation: Double
    var glyphSize: CGFloat = 66
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            pane
            Text(glyph)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(OnbColor.badge)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: OnbMetric.keycap, height: OnbMetric.keycap)
    }

    @ViewBuilder
    private var pane: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            // AppKit, deliberately.
            //
            // `rotationEffect` on a SwiftUI `glassEffect` view makes the glass
            // SHAPE morph rather than rotate — a documented artifact, and the
            // caps in this design are all tilted a few degrees. NSGlassEffectView
            // takes the rotation as a layer transform instead, which is a plain
            // affine transform the material never sees.
            OnbGlassPane(cornerRadius: OnbMetric.keycapRadius,
                         tint: NSColor.black.withAlphaComponent(0.2),
                         rotation: rotation)
        } else {
            RoundedRectangle(cornerRadius: OnbMetric.keycapRadius, style: .continuous)
                .fill(reduceTransparency ? OnbColor.opaque : OnbColor.glassTint)
                .overlay(
                    RoundedRectangle(cornerRadius: OnbMetric.keycapRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .rotationEffect(.degrees(rotation))
        }
    }
}

/// A rotatable pane of Liquid Glass, bridged from AppKit.
///
/// The SwiftUI modifier cannot be rotated without the material deforming; this
/// can, because the rotation is applied to the layer rather than to the shape
/// the effect is drawn in.
@available(macOS 26.0, *)
struct OnbGlassPane: NSViewRepresentable {
    let cornerRadius: CGFloat
    let tint: NSColor?
    let rotation: Double

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tint

        // Around the CENTRE, composed by hand rather than by moving the
        // layer's anchor point: on a layer-backed NSView AppKit derives the
        // layer's position from the view's frame, so changing the anchor
        // shifts the view instead of just changing what it turns about.
        let b = view.bounds
        guard b.width > 0, b.height > 0 else { return }
        let angle = CGFloat(rotation) * .pi / 180
        var t = CATransform3DMakeTranslation(b.midX, b.midY, 0)
        t = CATransform3DRotate(t, angle, 0, 0, 1)
        t = CATransform3DTranslate(t, -b.midX, -b.midY, 0)
        view.layer?.transform = t
    }
}

/// The Otto mark, from the real vector.
///
/// Imported as a template asset and filled with the flow's own gradient rather
/// than carrying the SVG's — the two are the same ramp (#B5A5F0 to #6338FF),
/// and going through `foregroundStyle` means it cannot render flat if Xcode's
/// SVG support ever declines to resolve the gradient itself.
struct OttoWordmark: View {
    /// White for now, per Marcello 2026-08-23. The gradient is kept a line
    /// away rather than deleted — the asset is a template either way, so this
    /// is the only thing that decides how the mark reads.
    var body: some View {
        Image("OttoWordmark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            // The mark is 302x211 in the vector. Stating BOTH stops it being
            // sized by whatever space happens to be going: with only a height
            // it took the full window width to fit into and came out huge and
            // off-centre.
            .frame(width: 302, height: 211)
            .foregroundStyle(OnbColor.text)
            .accessibilityLabel("Otto")
    }
}

// MARK: - Compact

/// True on the practice step, where the window shrinks to 520x300 so the notch
/// panel cannot cover the instructions.
///
/// The design is drawn at 1200x800 and its type is sized for it — a 34pt
/// headline is right there and far too big in a window a quarter the size.
/// Rather than each screen guessing, the flow states which mode it is in and
/// the shared header answers to it.
private struct OnbCompactKey: EnvironmentKey {
    static let defaultValue = false
}

/// Which way the flow is currently moving, so a screen leaves along the path
/// it arrived on. See OnboardingFlowView.stepTransition.
private struct OnbGoingBackKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onbCompact: Bool {
        get { self[OnbCompactKey.self] }
        set { self[OnbCompactKey.self] = newValue }
    }
    var onbGoingBack: Bool {
        get { self[OnbGoingBackKey.self] }
        set { self[OnbGoingBackKey.self] = newValue }
    }
}
