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
    static let windowGradient = LinearGradient(
        colors: [Color(hex: "#816BD2"), Color(hex: "#160D35")],
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
    /// The nav bar. Heavier still — a bigger surface should read as thicker.
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
    static let progressIdle = Color(hex: "#413374")

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

    /// Window controls: three 14pt circles, 9pt apart, 18pt in from the
    /// corner. Top-LEFT, because on macOS close is always top-left and
    /// familiarity is worth more here than novelty.
    static let controlDot: CGFloat = 14
    static let controlGap: CGFloat = 9
    static let controlInset: CGFloat = 18

    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 24
    static let cardGap: CGFloat = 24
    static let imageRadius: CGFloat = 16

    static let gridInset: CGFloat = 48
    static let gridTop: CGFloat = 72
    static let gridBottom: CGFloat = 168

    static let navPadding: CGFloat = 24
    static let navBottom: CGFloat = 45
    static let navIconButton: CGFloat = 48

    static let buttonPaddingH: CGFloat = 24
    static let buttonPaddingV: CGFloat = 12
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
    static let cardTitle = Font.system(size: 18, weight: .semibold)
    static let button = Font.system(size: 16, weight: .medium)
    static let badge = Font.system(size: 10, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let rowSubtitle = Font.system(size: 13.5, weight: .regular)

    static func title(compact: Bool) -> Font {
        .system(size: compact ? 22 : 34, weight: .bold)
    }
    static func tagline(compact: Bool) -> Font {
        .system(size: compact ? 13.5 : 22, weight: .medium)
    }

    /// −0.02em at display sizes, easing to 0 by body. Applied as points
    /// because SwiftUI's `kerning` is absolute.
    static func tracking(forSize size: CGFloat) -> CGFloat {
        size >= 30 ? -size * 0.02 : (size >= 20 ? -size * 0.012 : 0)
    }
    static func titleTracking(compact: Bool) -> CGFloat {
        tracking(forSize: compact ? 22 : 34)
    }
    static func taglineTracking(compact: Bool) -> CGFloat {
        tracking(forSize: compact ? 13.5 : 22)
    }
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
struct OnbGlassSurface: ViewModifier {
    var isInteractive: Bool = false
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Reduce Transparency is not a preference about taste — it is
            // someone telling the system they cannot read text on glass. The
            // surface goes solid and the blur goes away entirely.
            content.background(Capsule().fill(OnbColor.opaque))
                   .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: Capsule())
        } else {
            content.background(Capsule().fill(OnbColor.glassFallback))
                   .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base = Glass.regular.interactive(isInteractive)
        if let tint { return base.tint(tint) }
        return base
    }
}

extension View {
    /// Liquid Glass on macOS 26, a translucent capsule below it, and a solid
    /// fill under Reduce Transparency.
    func onbGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(OnbGlassSurface(isInteractive: interactive, tint: tint))
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
    var key: String? = "\u{21B5}"
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: OnbMetric.buttonGap) {
                Text(title)
                    .font(OnbFont.button)
                    .foregroundStyle(OnbColor.text)
                if let key { OnbKeyBadge(text: key) }
            }
            .padding(.horizontal, OnbMetric.buttonPaddingH)
            .padding(.vertical, OnbMetric.buttonPaddingV)
            // `interactive:` hands the press to the material itself on 26 —
            // the glass reacts, not just a transform over it.
            .onbGlass(interactive: true)
            .overlay(
                Capsule().fill(Color.white.opacity(hovering && isEnabled ? 0.06 : 0))
            )
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
struct OnbCardImageSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: OnbMetric.imageRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.imageRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where you are in the flow: the current step widens into a pill, the rest
/// stay dots. No "4 of 8" — nobody should have to count.
struct OnbProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: OnbMetric.progressGap) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? OnbColor.text : OnbColor.progressIdle)
                    .frame(width: i == current ? OnbMetric.progressPill.width
                                              : OnbMetric.progressDot,
                           height: i == current ? OnbMetric.progressPill.height
                                                : OnbMetric.progressDot)
            }
        }
        .animation(OnbMotion.standard, value: current)
        .accessibilityElement()
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

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OnbColor.text)
                .frame(width: OnbMetric.navIconButton, height: OnbMetric.navIconButton)
                .onbGlass(interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(OnbPressStyle())
        .accessibilityLabel("Back")
    }
}

/// The floating bar under the feature grid: back, progress, continue.
struct OnbBottomNav: View {
    var onBack: (() -> Void)?
    let current: Int
    let total: Int
    let continueTitle: String
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 14) {
            if let onBack {
                OnbBackButton(action: onBack)
            } else {
                Color.clear.frame(width: OnbMetric.navIconButton, height: OnbMetric.navIconButton)
            }

            Spacer(minLength: 0)

            OnbProgress(current: current, total: total)

            OnbButton(title: continueTitle, action: onContinue)
        }
        // One container for the two glass controls, so the material blends
        // them instead of each refracting on its own.
        .onbGlassGroup()
        .padding(OnbMetric.navPadding)
        // The bar itself is the HEAVY layer and the buttons on it are the
        // light one — dark under light, never light on light.
        .background(Capsule().fill(reduceTransparency ? OnbColor.opaque : OnbColor.nav))
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
