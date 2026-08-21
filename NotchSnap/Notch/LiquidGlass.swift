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
//   2. A LIFT — a whisper of white over the blur. This is the part that
//      actually answers the complaint: black on black is invisible no matter
//      how much you blur it, so the surface has to read brighter than what it
//      covers.
//   3. A SPECULAR RIM — brightest at the top-left, fading round to almost
//      nothing. An even border reads as a stroke; an uneven one reads as light
//      catching an edge, and it is what makes the shape legible against a
//      background of any brightness.
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
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular,
                                in: shape)
        } else {
            content.background(legacy)
        }
    }

    private var legacy: some View {
        ZStack {
            // `.behindWindow` blurs the DESKTOP, not the window's own content.
            // `.withinWindow` would blur our own black fill and produce
            // nothing — the panel window is transparent, which is exactly the
            // condition this mode needs.
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            // The lift. Small numbers: at 0.14 it stops looking like glass and
            // starts looking like grey plastic, and at 0.02 it is invisible
            // over a dark wallpaper, which is the bug.
            shape.fill(Color.white.opacity(0.07))

            if let tint {
                shape.fill(tint.opacity(0.10))
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.38),   // light catches here
                        .white.opacity(0.10),
                        .white.opacity(0.05),
                        .white.opacity(0.14),   // faint bounce on the far edge
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
        )
    }
}

extension View {
    /// Real Liquid Glass on macOS 26, a faithful stand-in below it.
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: shape, tint: tint))
    }
}
