import SwiftUI
import AppKit

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

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
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
    /// Raycast's own surfaces sit near #07080a-#101111 — very deep. Pushed
    /// further again after seeing the Figma beside the build: the drawing is
    /// darker than anything the blur alone was going to produce.
    static let lightScrim: Double = 0.74
    /// 0.70 exactly — the panel's background is quoted as rgba(0,0,0,0.7) in
    /// the export, so this stops being a judgement call.
    static let darkScrim: Double = 0.70
}

extension View {
    /// Real Liquid Glass on macOS 26, a faithful stand-in below it.
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: shape, tint: tint))
    }
}
