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
//   2. A DARK SCRIM over that blur. The first attempt lifted the surface with
//      white instead, reasoning that black-on-black is invisible — and it was
//      unreadable: "il liquid glass è veramente troppo chiaro e non si legge
//      niente" (Marcello, 2026-08-22). The reasoning was wrong. Legibility
//      here is white text on the panel, so the panel must stay DARKER than the
//      text no matter what is behind it; a light surface under white type has
//      no contrast left to give. What separates the panel from a dark desktop
//      is the blur and the rim, not the fill being brighter.
//   3. A SPECULAR RIM — brightest at the top-left, fading round to almost
//      nothing. An even border reads as a stroke; an uneven one reads as light
//      catching an edge, and it is what makes the shape legible against a
//      background of any brightness. It carries the separation that the white
//      lift was wrongly asked to carry.
//
// The material is also pinned to the DARK appearance. `.hudWindow` otherwise
// resolves against the system appearance, so on a light desktop it came back
// light and took the text with it — half of why the first attempt washed out.
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
            // Tinted dark for the same reason the fallback is: untinted
            // `.regular` is a LIGHT material, and white text on it loses.
            content.glassEffect(
                Glass.regular.tint(tint ?? Color.black.opacity(0.55)),
                in: shape
            )
        } else {
            content.background(legacy)
        }
    }

    private var legacy: some View {
        ZStack {
            // `.behindWindow` blurs the DESKTOP, not the window's own content.
            // `.withinWindow` would blur our own fill and produce nothing —
            // the panel window is transparent, which is exactly the condition
            // this mode needs.
            VisualEffectBlur(material: .hudWindow,
                             blendingMode: .behindWindow,
                             appearance: .darkAqua)

            // The scrim. This is the number to move if it is still not dark
            // enough — everything else here is edge treatment.
            shape.fill(Color.black.opacity(LiquidGlassTuning.scrimOpacity))

            if let tint {
                shape.fill(tint.opacity(0.12))
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.30),   // light catches here
                        .white.opacity(0.08),
                        .white.opacity(0.05),
                        .white.opacity(0.12),   // faint bounce on the far edge
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
        )
    }

}

/// How dark the glass sits over whatever is behind it.
///
/// THE knob. If the panels are still washing out, this is the number to move —
/// everything else in LiquidGlassSurface is edge treatment. Dark enough that
/// white type always wins; Raycast's panels sit around here, unmistakably
/// see-through and never in a fight with their own text.
enum LiquidGlassTuning {
    static let scrimOpacity: Double = 0.62
}

extension View {
    /// Real Liquid Glass on macOS 26, a faithful stand-in below it.
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: shape, tint: tint))
    }
}
