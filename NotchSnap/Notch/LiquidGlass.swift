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

struct LiquidGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Optional colour cast, used sparingly — a tinted panel stops reading as
    /// glass and starts reading as coloured plastic.
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // `.regular` already resolves per appearance on 26, so it is left
            // to do that; a tint is applied only when a caller asked for one.
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular,
                                in: shape)
        } else {
            content.background(legacy)
        }
    }

    private var legacy: some View {
        ZStack {
            // `.behindWindow` blurs the DESKTOP, not the window's own content.
            // `.withinWindow` would blur our own fill and produce nothing —
            // the panel window is transparent, which is exactly the condition
            // this mode needs. No pinned appearance: it follows the system, as
            // Spotlight's does.
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            // Takes the side of the appearance instead of always darkening.
            shape.fill(Color.dynamic(
                light: NSColor.white.withAlphaComponent(LiquidGlassTuning.lightScrim),
                dark: NSColor.black.withAlphaComponent(LiquidGlassTuning.darkScrim)
            ))

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
                Color.dynamic(
                    light: NSColor.black.withAlphaComponent(0.08),
                    dark: NSColor.white.withAlphaComponent(0.06)
                ),
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
    /// Raycast's own surfaces sit near #07080a-#101111 — considerably
    /// deeper than this was, which is why Otto's panel looked washed beside
    /// it with the same wallpaper behind both.
    static let lightScrim: Double = 0.70
    static let darkScrim: Double = 0.74
}

extension View {
    /// Real Liquid Glass on macOS 26, a faithful stand-in below it.
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: shape, tint: tint))
    }
}
