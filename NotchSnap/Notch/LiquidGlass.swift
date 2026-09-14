import SwiftUI
import AppKit
import CoreImage

// MARK: - Liquid Glass, with a floor under it
//
// The panels were filled with pure black, which vanishes on a dark desktop:
// "su altre superfici ho sfondi scuri, non si vede semplicemente" (Marcello,
// 2026-08-22). Glass fixes that, because what separates a glass panel from its
// background is not its fill — it is the blur and the lit edge.
//
// ── Why there are two implementations ───────────────────────────────────────
//
// `glassEffect(_:in:)` is the real Liquid Glass API and it is annotated
// `@available(macOS 26.0, *)`. This Mac runs 15.7.4. So on the machine the app
// is being designed on, the real API can never run — shipping only that would
// have looked like nothing changed at all, on the one screen that matters most
// during design.
//
// So macOS 26 gets the genuine article and everything from 13.0 up gets a
// hand-built equivalent. Not a degraded placeholder: the same three things
// Apple's material does, by the means available before it existed.
//
//   1. BLUR of what is behind the window — NSVisualEffectView with
//      `.behindWindow`, which is what makes the panel sit ON the desktop
//      rather than over it.
//   2. A SCRIM that takes the side of the appearance. Light: white over the
//      blur, so the panel brightens and the dark system label colours win on
//      it. Dark: black, so it deepens and the light label colours win. This
//      was pinned to dark, which meant Light mode drew pale panels while the
//      text stayed white — nothing readable at all (Marcello, 2026-08-22).
//   3. A UNIFORM HAIRLINE — Raycast's documented rgba(255,255,255,0.06), one
//      value all the way round. An earlier version ran a specular gradient up
//      to 0.95; side by side with Raycast that read as a hard drawn edge next
//      to one that is barely implied, and at a 40pt radius it looked like a
//      rendering artefact rather than like light.
//
// The material's appearance is NOT pinned. Pinning it was half of why Light
// mode was unusable: the surface stayed dark while the text tokens, now
// semantic, correctly turned dark too. Left alone, the material resolves the
// way Spotlight's does — from the appearance the view is actually drawn in.
//
// The notch silhouette deliberately does NOT use this. It is pretending to be
// a hole in the hardware, and hardware is not translucent.

/// Forces the material to look again.
///
/// A blur samples what is behind its WINDOW. Two situations change that
/// without the window moving, and in both the material can keep showing what
/// it sampled the first time:
///
///   * A Space switch. The window is `.canJoinAllSpaces` + `.stationary`, so
///     it does not move — the wallpaper underneath is simply replaced. Open
///     the notch over a dark Space, switch to a light one, and the glass stays
///     dark (Marcello, Tahoe, 2026-08-22).
///   * Reopening the panel. The first open sampled correctly; the second came
///     back flat and desaturated.
///
/// One counter drives both paths. Nothing here changes how the glass LOOKS —
/// it only makes it re-resolve.
@MainActor
final class GlassRefresh: ObservableObject {
    static let shared = GlassRefresh()

    @Published private(set) var token: Int = 0

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in GlassRefresh.shared.bump() }
        }
    }

    func bump() { token &+= 1 }
}

struct LiquidGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Optional colour cast, used sparingly — a tinted panel stops reading as
    /// glass and starts reading as coloured plastic.
    var tint: Color?

    @ObservedObject private var refresh = GlassRefresh.shared
    /// SwiftUI's own idea of the appearance, not AppKit's.
    ///
    /// The scrim used to be a `Color.dynamic(...)` backed by an NSColor
    /// dynamic provider, which resolves whenever and wherever SwiftUI happens
    /// to ask. Around activation — ⌃⇧N calls `NSApp.activate`, and closing
    /// flips the policy back — it sometimes resolved LIGHT while the panel was
    /// plainly in Dark, and the whole notch came back washed out (Marcello,
    /// 2026-08-22: "way more light than it actually is", exactly on the
    /// keyboard summon and on close).
    ///
    /// `colorScheme` is resolved once for the view hierarchy and handed down,
    /// so there is no ambient moment for it to be asked in. The scrim below is
    /// a CONCRETE colour chosen from it — nothing left to re-resolve.
    @Environment(\.colorScheme) private var colorScheme

    /// Someone telling the system they cannot read text on translucency.
    ///
    /// The notch had no answer to this at all: the panel stayed glass whatever
    /// the setting said, which for a person who turns it on is the one surface
    /// in the app they most need solid — everything they read lives on it.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // No blur, no refraction, no scrim over a sample: an opaque fill
            // and a defined edge. Apple's own escape hatch for this is
            // `Glass.identity`, but that still leaves the surface to the
            // material — a stated colour is the thing the setting asks for.
            content.background(shape.fill(opaque))
                   .overlay(shape.strokeBorder(solidEdge, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            // Tinted with the SAME scrim the pre-26 path paints, and that is
            // the whole point of this line.
            //
            // Bare `.regular` is a light material. On macOS 26 the panels came
            // out far lighter than on 15.7, where the fallback lays down a 74%
            // black scrim — so the app looked like two different apps
            // depending on which Mac opened it, and the newer one was the
            // wrong one (Marcello, 2026-08-22, comparing a Tahoe MBP against
            // this machine). Tinting makes the two paths land in the same
            // place: 26 gets Apple's real refraction AND our depth, rather
            // than choosing between them.
            // The alpha jitter is the refresh. `Glass` is Equatable, so the
            // effect is only re-resolved when its value changes — and half a
            // thousandth of an alpha is far below anything visible while
            // still being a different value. Blunt, but contained to one line
            // and it does not touch the content's identity, so nothing being
            // typed into loses its caret when a Space changes.
            // Apple's material for the refraction, and OUR scrim on top of it
            // for the depth — not the material tinted and left to its own
            // devices.
            //
            // `glassEffect` draws a lighter, desaturated variant when its
            // window is not key, and the notch panel is not key on a plain
            // hover-open. That is the washed-out notch: nothing had changed
            // except whether the window held focus (Marcello, 2026-08-22 —
            // "it seems like an input field that is disabled"). A tint alone
            // rides that variation, because it only shifts whatever the
            // material decided to be.
            //
            // A scrim painted ON TOP does not. It is our layer, at our
            // opacity, unaffected by focus — so the panel has a guaranteed
            // floor and the material's key-state swing is reduced to a
            // subtlety underneath it.
            content
                .glassEffect(Glass.regular
                    .tint(Color.clear.opacity(refresh.token % 2 == 0 ? 1.0 : 0.9995)),
                             in: shape)
                .background(scrimLayer)
        } else {
            content.background(legacy)
        }
    }

    /// One scrim, used by BOTH paths — tinting the real glass on 26 and
    /// painting over the blur below it. Two numbers here would mean two looks.
    private var scrim: Color {
        colorScheme == .dark
            ? Color.black.opacity(LiquidGlassTuning.darkScrim)
            : Color.white.opacity(LiquidGlassTuning.lightScrim)
    }

    /// Same reasoning for the hairline: concrete, not ambient.
    private var hairline: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.08)
    }

    /// The scrim and its hairline, identical on every macOS version — the
    /// thing that makes the panel look the same whatever the material does.
    private var scrimLayer: some View {
        shape.fill(scrim)
            .overlay(shape.strokeBorder(hairline, lineWidth: 1))
    }

    /// What the panel becomes under Reduce Transparency. Chosen from the same
    /// invariant the scrims are: always further from the text colour than the
    /// desktop behind it.
    private var opaque: Color {
        colorScheme == .dark ? Color(hex: "#0B0B0E") : Color(hex: "#F2F2F5")
    }

    /// A real border, not a hairline — with no blur to separate the panel from
    /// the desktop, the edge has to do that job alone.
    private var solidEdge: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.22)
    }

    private var legacy: some View {
        ZStack {
            // `.behindWindow` blurs the DESKTOP, not the window's own content.
            // `.withinWindow` would blur our own fill and produce nothing —
            // the panel window is transparent, which is exactly the condition
            // this mode needs. No pinned appearance: it follows the system, as
            // Spotlight's does.
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow,
                             refreshToken: refresh.token)

            // The same colour macOS 26 is tinted with, so neither path can
            // drift from the other.
            shape.fill(scrim)

            if let tint {
                shape.fill(tint.opacity(0.12))
            }
        }
        .clipShape(shape)
        .overlay(
            // Raycast's card border is documented as a flat
            // rgba(255,255,255,0.06) — ONE value, all the way round.
            //
            // Otto had a gradient running 0.30 to 0.95, up to sixteen times
            // stronger at the bright corner, which is what made the two look
            // so different stacked on top of each other: a hard drawn edge
            // next to one that is barely implied. The specular idea was mine,
            // not Apple's and not Raycast's, and at this radius it reads as a
            // rendering artefact rather than as light.
            shape.strokeBorder(
                hairline,
                lineWidth: 1
            )
        )
    }

}

/// How far the glass leans, in each appearance.
///
/// THE knobs. If the panels wash out, these are the numbers to move —
/// everything else in LiquidGlassSurface is edge treatment. Both are chosen so
/// the panel always ends up further from the text colour than the desktop is:
/// Light brightens toward white under dark labels, Dark deepens toward black
/// under light ones. That is the invariant, not the specific values.
enum LiquidGlassTuning {
    /// The system glass already contributes a bright base in Light mode.
    /// A heavy white layer on top turns it into an opaque white card and
    /// erases the desktop colours that Liquid Glass is supposed to refract.
    static let lightScrim: Double = 0.20
    /// Same rule in Dark mode: enough floor for readable labels, not enough
    /// black to hide the material and make the panel look painted.
    static let darkScrim: Double = 0.42
}

extension View {
    /// Real Liquid Glass on macOS 26, a faithful stand-in below it.
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: shape, tint: tint))
    }

    /// For controls that FLOAT over content — the annotation toolbar, the
    /// capture action bar — rather than for a panel you read from.
    ///
    /// Same material, none of the notch's scrim: that scrim exists so a
    /// reading surface stays legible, and putting it on a toolbar hovering
    /// over a screenshot would bury the screenshot the toolbar is for. This is
    /// the navigation layer doing what Liquid Glass is actually for.
    func floatingGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(FloatingGlassSurface(shape: shape, tint: tint))
    }

    /// Glass for the space-bar pills — section chips, Notes, Calendar.
    ///
    /// Same three tiers as `floatingGlass` (real tinted glass on 26,
    /// `.ultraThinMaterial` below it, opaque under Reduce Transparency) but
    /// WITHOUT the hairline: each pill draws its own edge — Notes a dashed
    /// stroke, Calendar a solid one, the section chips none — so a shared
    /// stroke here would double every outline.
    ///
    /// The tint is used AS GIVEN, because "active" means different depths in
    /// different places: a section chip needs a strong cast under dark
    /// on-accent text, while Notes/Calendar carry the signal in coloured text
    /// plus stroke and only want a whisper of fill. Pass nil for the resting
    /// state — plain glass, no cast.
    func pillGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(PillGlassSurface(shape: shape, tint: tint))
    }
}

extension View {
    /// Groups neighbouring glass surfaces so the material samples them
    /// together. Glass cannot sample other glass, and ungrouped neighbours
    /// each open their own region and drift apart visually.
    @ViewBuilder
    func glassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// Glass for floating chrome. Three tiers, like everything else: the real
/// material on 26, `.ultraThinMaterial` below it, and an opaque fill when the
/// user has asked for one.
struct FloatingGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    /// A restrained cast lets glass remain legible when it is hosted over a
    /// deliberately dark surface such as Otto's simulated notch.
    var tint: Color?
    @ObservedObject private var refresh = GlassRefresh.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color(hex: "#1C1C1E")))
                   .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(Glass.regular
                    .tint((tint ?? Color.clear)
                        .opacity(refresh.token % 2 == 0 ? 1.0 : 0.9995)),
                             in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill((tint ?? .clear).opacity(0.13)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
}

/// Glass for the space-bar pills. Same tiers as `FloatingGlassSurface`, minus
/// the hairline (each pill draws its own edge) and with the tint used as
/// given — see `pillGlass(in:tint:)`.
struct PillGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    /// nil ⇒ resting pill: plain glass, no colour cast.
    var tint: Color?
    @ObservedObject private var refresh = GlassRefresh.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color(hex: "#1C1C1E")))
                   .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(Glass.regular
                    .tint((tint ?? Color.clear)
                        .opacity(refresh.token % 2 == 0 ? 1.0 : 0.9995)),
                             in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tint ?? .clear))
        }
    }
}

// MARK: - Surfaces that are dark whatever the system is set to
//
// Two rules, and every colour decision in the app falls under one of them.
//
//  1. A surface that FOLLOWS the appearance — the glass panels, Settings, the
//     to-do panel drawn on them — takes its colours from DSColor and never
//     writes a raw white or black. Those tokens have an opposite; a literal
//     does not, which is precisely how Light mode ended up with white text on
//     a white panel.
//
//  2. A surface that CARRIES ITS OWN DARK GROUND is exempt, on the condition
//     that it says so. There are two of them:
//
//       * the notch silhouette, which is filled `Color.black` on purpose — it
//         is pretending to be a hole in the hardware, and hardware is not
//         translucent, so it cannot lighten in Light mode and neither can
//         anything drawn inside it;
//       * chrome floating over the user's own content — the annotation
//         toolbar, the capture bar, the text-extraction overlay — which keeps
//         one familiar look over a screenshot that might be any brightness.
//
//     Both pin the appearance rather than each view hand-picking whites, so
//     the semantic tokens underneath resolve to their dark values and a view
//     can be moved between the two worlds without being rewritten.
//
// The notch PANEL WINDOW is pinned in AppKit as well (NotchController), not
// only here: in the container layout every pixel in that window sits on the
// black silhouette, and an NSAppearance is the one thing both AppKit
// materials and SwiftUI's semantic colours agree to read.

extension View {
    /// Marks a surface that supplies its own dark ground — see the two rules
    /// above. Everything inside resolves as if the system were in Dark.
    func darkGroundSurface() -> some View {
        environment(\.colorScheme, .dark)
    }
}

// MARK: - Progressive (variable) blur
//
// TRUE progressive blur: the blur RADIUS itself ramps along a gradient —
// sharp where the list runs free, fully blurred behind the pills — not one
// uniform blur faded in with opacity. That distinction is the whole lesson
// of Tim Oliver's BlurUIKit (MIT): it holds the private `variableBlur`
// CAFilter iOS composes its own frosted bars from. On macOS the same effect
// is reachable through PUBLIC API: the `CIMaskedVariableBlur` Core Image
// filter as the layer's `backgroundFilters`, driven by a grayscale mask
// image. No private API, no snapshotting, live every frame the list scrolls.

/// Which end of the view carries full blur.
enum ProgressiveBlurDeepEnd {
    /// Sharp at the top, fully blurred at the bottom (list above pills).
    case bottom
    /// Fully blurred at the top, sharp at the bottom (list below pills).
    case top
}

/// An NSView that variable-blurs its BACKDROP (everything composited
/// underneath it in the window) with a radius ramping from 0 at the shallow
/// end to `radius` at the deep end, across `rampPoints`.
///
/// The mask image is drawn once per bounds size and rebuilt on resize only —
/// same caching discipline as BlurUIKit's gradient masks.
final class ProgressiveBlurView: NSView {
    var radius: CGFloat = 24 { didSet { refreshFilter() } }
    /// How many points the 0→full ramp spans, measured from the deep end.
    /// Everything past the ramp (behind the pills) stays at full blur.
    var rampPoints: CGFloat = 40 { didSet { refreshFilter() } }
    var deepEnd: ProgressiveBlurDeepEnd = .bottom { didSet { refreshFilter() } }

    private var maskSize: CGSize = .zero
    private var maskImage: CGImage?
    private var didInstallFallback = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        refreshFilter()
    }

    fileprivate func refreshFilter() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard let filter = CIFilter(name: "CIMaskedVariableBlur") else {
            installFallbackBlur()
            return
        }
        filter.setDefaults()
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        if maskSize != bounds.size || maskImage == nil {
            maskImage = makeMask(size: bounds.size)
            maskSize = bounds.size
        }
        if let maskImage {
            // `CIMaskedVariableBlur` uses its own `inputMask` parameter.
            // `kCIInputMaskImageKey` is for filters such as blends and is
            // not part of this filter's schema; using it throws an Objective-C
            // exception during AppKit layout, which makes a Debug run appear
            // to be an Xcode crash.
            filter.setValue(CIImage(cgImage: maskImage), forKey: "inputMask")
        }
        wantsLayer = true
        layer?.backgroundFilters = [filter]
    }

    /// Grayscale mask in Core Image coordinates (origin bottom-left):
    /// white = full `radius`, black = sharp. Ramps across `rampPoints` from
    /// the shallow end; the deep end stays white past the ramp.
    private func makeMask(size: CGSize) -> CGImage? {
        // 2x: a 1px/point mask bands visibly across a 40pt ramp.
        let scale: CGFloat = 2
        let w = max(1, Int(size.width * scale))
        let h = max(1, Int(size.height * scale))
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gradient = CGGradient(
                  colorsSpace: space,
                  colors: [CGColor(gray: 0, alpha: 1),
                           CGColor(gray: 1, alpha: 1)] as CFArray,
                  locations: [0, 1])
        else { return nil }

        let hh = CGFloat(h)
        let rampPx = min(rampPoints * scale, hh)
        // Full-blur base everywhere.
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Then carve the ramp back toward sharp at the shallow end.
        switch deepEnd {
        case .bottom:
            // Shallow end is the TOP: black at y=hh fading to white rampPx below it.
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: hh),
                                   end: CGPoint(x: 0, y: hh - rampPx),
                                   options: [])
        case .top:
            // Shallow end is the BOTTOM: white rampPx above y=0 fading to black at y=0.
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: rampPx),
                                   end: CGPoint(x: 0, y: 0),
                                   options: [])
        }
        return ctx.makeImage()
    }

    /// Should never trigger (`CIMaskedVariableBlur` ships since macOS 10.12),
    /// but a frosted foot must never render as a hard band: a plain
    /// within-window blur degrades to uniform frost instead of nothing.
    private func installFallbackBlur() {
        guard !didInstallFallback else { return }
        didInstallFallback = true
        let effect = NSVisualEffectView(frame: bounds)
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
    }
}

/// SwiftUI host for `ProgressiveBlurView`. Sizes like any view — the mask
/// follows bounds automatically.
struct ProgressiveBlur: NSViewRepresentable {
    var radius: CGFloat = 24
    var rampPoints: CGFloat = 40
    var deepEnd: ProgressiveBlurDeepEnd = .bottom

    func makeNSView(context: Context) -> ProgressiveBlurView {
        let view = ProgressiveBlurView(frame: .zero)
        view.radius = radius
        view.rampPoints = rampPoints
        view.deepEnd = deepEnd
        return view
    }

    func updateNSView(_ view: ProgressiveBlurView, context: Context) {
        view.radius = radius
        view.rampPoints = rampPoints
        view.deepEnd = deepEnd
    }
}
