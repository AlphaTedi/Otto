import SwiftUI

// Empty state "Peekaboo" (handoff otto-empty-state, Marcello, 2026-10-04):
// the Otto logo in mint peeks up from behind an invisible edge above the
// copy, looks around, blinks once, sinks and comes back — an 8 s loop. It
// replaces the sleeping page (empty state B, 2026-09-26) in every list and
// the Notes stream, in both layouts.
//
// The layout rules of the old one stay, because they are the panel's, not
// the drawing's: it hugs in the notch container (its natural height plus its
// padding is the gap it fills — principle 2), and in the floating panels it
// takes the list budget as a minimum so it sits centred between field and
// pills. Not interactive: the caret stays in the field.
//
// The motion, the logo geometry and the copy are the handoff's, unchanged.
// One deliberate departure: the pupils. The handoff fills them with the
// colour behind the logo (black), which is right in the notch container and
// wrong on the floating panels' glass, where nothing behind is a flat colour;
// there they are erased from the logo in the same Canvas (`.destinationOut`)
// so the glass shows through. That is not the animated mask the handoff warns
// about — the Canvas redraws every frame, holes included.

struct EmptyListView: View {
    /// The notch container's short variant: a 150pt logo, smaller type.
    var compact = false
    /// False where the container has less than 180pt to give.
    var showsSubtitle = true
    var subtitleKey = "todo.emptySubtitle"
    /// Floating panels only: the list region's budget. That block is a fixed
    /// 556 with the pills pushed to its foot, so hugging left the block high
    /// with the slack all below it (Marcello, 2026-09-26). Filling the budget
    /// centres it between the capture header and the pills. Nil in the
    /// container, which hugs.
    var fillHeight: CGFloat?

    /// Animates only while the notch is open — README §7.
    @ObservedObject private var notch = NotchController.shared

    private static let titleInk = Color.dynamic(light: NSColor.black.withAlphaComponent(0.85),
                                                dark: NSColor.white.withAlphaComponent(0.90))
    private static let subtitleInk = Color.dynamic(light: NSColor.black.withAlphaComponent(0.55),
                                                   dark: NSColor.white.withAlphaComponent(0.54))

    var body: some View {
        // The logo is 200pt wide (150 in the container); its visible window
        // is 1.3× that.
        let logoWidth: CGFloat = compact ? 150 : 200
        VStack(spacing: 18) {
            OttoPeekLogo(pupilColor: compact ? .black : nil,
                         isAnimating: notch.state == .expanded)
                .frame(width: logoWidth * 1.3)
            VStack(spacing: 8) {
                Text(L10n.t("todo.emptyTitle"))
                    .font(.system(size: compact ? 22 : 26, weight: .bold))
                    .foregroundStyle(Self.titleInk)
                if showsSubtitle {
                    Text(L10n.t(subtitleKey))
                        .font(.system(size: compact ? 14 : 16))
                        .foregroundStyle(Self.subtitleInk)
                        .frame(maxWidth: 340)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        // The container sits right on the panel's rounded foot and read as
        // cramped there, so it takes a deeper bottom margin (2026-09-26).
        .padding(.top, compact ? 22 : 32)
        .padding(.bottom, compact ? 44 : 32)
        .frame(maxWidth: .infinity, minHeight: fillHeight)
        // The budget reserves room under the region that the empty list never
        // draws into; −33 puts the block on the middle of the visible gap
        // (measured on the live panel, 2026-09-26).
        .offset(y: fillHeight == nil ? 0 : -33)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("todo.emptyA11y") + " " + L10n.t(subtitleKey))
    }

    /// Comes in on the project's spring, leaves in 150ms — the new row takes
    /// its place.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96))
                .animation(Motion.contentHug),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }
}

// MARK: - Peeking logo

struct OttoPeekLogo: View {
    var color: Color = Color(red: 0x9E/255, green: 0xDD/255, blue: 0xB0/255)   // Otto mint #9EDDB0
    /// The colour behind the logo, for the pupils; nil erases them instead
    /// (the floating panels' glass — see the file comment).
    var pupilColor: Color? = .black
    var isAnimating: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = isAnimating && !reduceMotion
        TimelineView(.animation(paused: !animate)) { ctx in
            let t = animate ? ctx.date.timeIntervalSinceReferenceDate : P.restTime
            Canvas { gc, size in
                // size = the visible window (clips the lower part of the logo)
                let s = size.width / P.windowWidthRatio / 971      // logo scale
                let logoW = 971 * s, logoH = 473 * s
                let rise = P.rise(at: t)                           // fraction of logo height
                gc.translateBy(x: (size.width - logoW) / 2, y: rise * logoH)
                gc.scaleBy(x: s, y: s)
                gc.fill(OttoPeekShapes.tPath, with: .color(color))
                gc.fill(Path(ellipseIn: CGRect(x: 0, y: 115.844, width: 317.76, height: 317.76)), with: .color(color))
                gc.fill(Path(ellipseIn: CGRect(x: 653.203, y: 115.844, width: 317.76, height: 317.76)), with: .color(color))
                let o = P.look(at: t), d = P.drift(at: t), b = P.blink(at: t)
                let r = 57.48, h = 2 * r * b
                if pupilColor == nil { gc.blendMode = .destinationOut }
                for cx in [183.8, 837.043] {
                    let x = cx + o.x + d.x, bottom = 253.884 + o.y + d.y + r
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: bottom - h, width: 2 * r, height: h)),
                            with: .color(pupilColor ?? .black))
                }
            }
            .clipped()   // the invisible edge — no line drawn
        }
        // visible window = 1.3 × logo width wide, 0.825 × logo height tall
        .aspectRatio(P.windowWidthRatio * 971 / (473 * P.windowHeightRatio), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Motion (all values match the approved design; do not tweak)

private enum P {
    static let windowWidthRatio = 1.3      // 260 / 200
    static let windowHeightRatio = 0.825   // 80 / 97
    static let restTime = 4.0              // static frame used with Reduce Motion (logo up, eyes centered)

    struct K { let t: Double; let x: Double; let y: Double }

    // Rise — 8 s loop. y = vertical offset as a fraction of logo height (1.2 = hidden, 0.04 = peeking).
    static let riseK: [K] = [.init(t: 0, x: 0, y: 1.2), .init(t: 0.08, x: 0, y: 1.2), .init(t: 0.16, x: 0, y: 0.04),
                             .init(t: 0.78, x: 0, y: 0.04), .init(t: 0.86, x: 0, y: 1.2), .init(t: 1, x: 0, y: 1.2)]
    // Look — 8 s loop, in logo units (viewBox 971×473). Fast saccades, then holds.
    static let lookK: [K] = [.init(t: 0, x: 0, y: -40), .init(t: 0.18, x: 0, y: -40), .init(t: 0.194, x: -52, y: -30), .init(t: 0.34, x: -52, y: -30), .init(t: 0.354, x: 50, y: -34), .init(t: 0.52, x: 50, y: -34), .init(t: 0.534, x: 0, y: -50), .init(t: 1, x: 0, y: -50)]
    // Drift — 3.7 s loop, micro movement while fixating.
    static let driftK: [K] = [.init(t: 0, x: 0, y: 0), .init(t: 0.33, x: 2, y: -1.5), .init(t: 0.66, x: -1.5, y: 2), .init(t: 1, x: 0, y: 0)]
    // Blink — 8 s loop, single blink. x = scaleY, eyelid falls from the top (bottom edge fixed).
    static let blinkK: [K] = [.init(t: 0, x: 1, y: 0), .init(t: 0.60, x: 1, y: 0), .init(t: 0.615, x: 0.05, y: 0), .init(t: 0.635, x: 1, y: 0), .init(t: 1, x: 1, y: 0)]

    static func rise(at t: Double) -> Double { sample(riseK, t, 8, (0.3, 1.25, 0.4, 1)).y }
    static func look(at t: Double) -> (x: Double, y: Double) { sample(lookK, t, 8, (0.15, 0.85, 0.3, 1)) }
    static func drift(at t: Double) -> (x: Double, y: Double) { sample(driftK, t, 3.7, (0.42, 0, 0.58, 1)) }
    static func blink(at t: Double) -> Double { sample(blinkK, t, 8, (0.4, 0, 0.6, 1)).x }

    private static func sample(_ k: [K], _ time: Double, _ dur: Double, _ c: (Double, Double, Double, Double)) -> (x: Double, y: Double) {
        let p = time.truncatingRemainder(dividingBy: dur) / dur
        var i = 0
        while i < k.count - 2 && p > k[i + 1].t { i += 1 }
        let a = k[i], b = k[i + 1], span = b.t - a.t
        let u = span > 0 ? min(max((p - a.t) / span, 0), 1) : 1
        let e = bezier(u, c)
        return (a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e)
    }
    // CSS cubic-bezier(x1, y1, x2, y2); y may overshoot 1 (used for the rise bounce)
    private static func bezier(_ x: Double, _ c: (Double, Double, Double, Double)) -> Double {
        func bx(_ t: Double) -> Double { 3*(1-t)*(1-t)*t*c.0 + 3*(1-t)*t*t*c.2 + t*t*t }
        func by(_ t: Double) -> Double { 3*(1-t)*(1-t)*t*c.1 + 3*(1-t)*t*t*c.3 + t*t*t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 { t = (lo + hi) / 2; if bx(t) < x { lo = t } else { hi = t } }
        return by(t)
    }
}

// MARK: - Logo geometry (the "tt" glyphs, viewBox 971×473)

private enum OttoPeekShapes {
    static let tPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 665.717, y: 161.72))
        p.addLine(to: CGPoint(x: 665.717, y: 81.68))
        p.addCurve(to: CGPoint(x: 657.717, y: 73.68), control1: CGPoint(x: 665.717, y: 77.28), control2: CGPoint(x: 662.117, y: 73.68))
        p.addLine(to: CGPoint(x: 616.277, y: 73.68))
        p.addCurve(to: CGPoint(x: 608.277, y: 65.68), control1: CGPoint(x: 611.877, y: 73.68), control2: CGPoint(x: 608.277, y: 70.08))
        p.addLine(to: CGPoint(x: 608.277, y: 8.0))
        p.addCurve(to: CGPoint(x: 600.277, y: 0.0), control1: CGPoint(x: 608.277, y: 3.6), control2: CGPoint(x: 604.677, y: 0.0))
        p.addLine(to: CGPoint(x: 514.877, y: 0.0))
        p.addCurve(to: CGPoint(x: 506.877, y: 8.0), control1: CGPoint(x: 510.477, y: 0.0), control2: CGPoint(x: 506.877, y: 3.6))
        p.addLine(to: CGPoint(x: 506.877, y: 65.68))
        p.addCurve(to: CGPoint(x: 498.877, y: 73.68), control1: CGPoint(x: 506.877, y: 70.08), control2: CGPoint(x: 503.277, y: 73.68))
        p.addLine(to: CGPoint(x: 448.837, y: 73.68))
        p.addCurve(to: CGPoint(x: 440.837, y: 65.68), control1: CGPoint(x: 444.437, y: 73.68), control2: CGPoint(x: 440.837, y: 70.08))
        p.addLine(to: CGPoint(x: 440.837, y: 8.0))
        p.addCurve(to: CGPoint(x: 432.837, y: 0.0), control1: CGPoint(x: 440.837, y: 3.6), control2: CGPoint(x: 437.237, y: 0.0))
        p.addLine(to: CGPoint(x: 347.437, y: 0.0))
        p.addCurve(to: CGPoint(x: 339.437, y: 8.0), control1: CGPoint(x: 343.037, y: 0.0), control2: CGPoint(x: 339.437, y: 3.6))
        p.addLine(to: CGPoint(x: 339.437, y: 65.68))
        p.addCurve(to: CGPoint(x: 331.437, y: 73.68), control1: CGPoint(x: 339.437, y: 70.08), control2: CGPoint(x: 335.837, y: 73.68))
        p.addLine(to: CGPoint(x: 309.797, y: 73.68))
        p.addCurve(to: CGPoint(x: 301.797, y: 81.68), control1: CGPoint(x: 305.397, y: 73.68), control2: CGPoint(x: 301.797, y: 77.28))
        p.addLine(to: CGPoint(x: 301.797, y: 161.72))
        p.addCurve(to: CGPoint(x: 309.797, y: 169.72), control1: CGPoint(x: 301.797, y: 166.12), control2: CGPoint(x: 305.397, y: 169.72))
        p.addLine(to: CGPoint(x: 331.437, y: 169.72))
        p.addCurve(to: CGPoint(x: 339.437, y: 177.72), control1: CGPoint(x: 335.837, y: 169.72), control2: CGPoint(x: 339.437, y: 173.32))
        p.addLine(to: CGPoint(x: 339.437, y: 314.16))
        p.addCurve(to: CGPoint(x: 489.797, y: 472.8), control1: CGPoint(x: 339.437, y: 398.92), control2: CGPoint(x: 406.157, y: 468.36))
        p.addCurve(to: CGPoint(x: 498.277, y: 464.8), control1: CGPoint(x: 494.397, y: 473.04), control2: CGPoint(x: 498.277, y: 469.4))
        p.addLine(to: CGPoint(x: 498.277, y: 379.12))
        p.addCurve(to: CGPoint(x: 491.077, y: 371.16), control1: CGPoint(x: 498.277, y: 375.0), control2: CGPoint(x: 495.157, y: 371.68))
        p.addCurve(to: CGPoint(x: 440.797, y: 314.16), control1: CGPoint(x: 462.797, y: 367.6), control2: CGPoint(x: 440.797, y: 343.4))
        p.addLine(to: CGPoint(x: 440.797, y: 177.72))
        p.addCurve(to: CGPoint(x: 448.797, y: 169.72), control1: CGPoint(x: 440.797, y: 173.32), control2: CGPoint(x: 444.397, y: 169.72))
        p.addLine(to: CGPoint(x: 498.837, y: 169.72))
        p.addCurve(to: CGPoint(x: 506.837, y: 177.72), control1: CGPoint(x: 503.237, y: 169.72), control2: CGPoint(x: 506.837, y: 173.32))
        p.addLine(to: CGPoint(x: 506.837, y: 314.16))
        p.addCurve(to: CGPoint(x: 657.197, y: 472.8), control1: CGPoint(x: 506.837, y: 398.92), control2: CGPoint(x: 573.557, y: 468.36))
        p.addCurve(to: CGPoint(x: 665.677, y: 464.8), control1: CGPoint(x: 661.797, y: 473.04), control2: CGPoint(x: 665.677, y: 469.4))
        p.addLine(to: CGPoint(x: 665.677, y: 379.12))
        p.addCurve(to: CGPoint(x: 658.477, y: 371.16), control1: CGPoint(x: 665.677, y: 375.0), control2: CGPoint(x: 662.557, y: 371.68))
        p.addCurve(to: CGPoint(x: 608.197, y: 314.16), control1: CGPoint(x: 630.157, y: 367.6), control2: CGPoint(x: 608.197, y: 343.4))
        p.addLine(to: CGPoint(x: 608.197, y: 177.72))
        p.addCurve(to: CGPoint(x: 616.197, y: 169.72), control1: CGPoint(x: 608.197, y: 173.32), control2: CGPoint(x: 611.797, y: 169.72))
        p.addLine(to: CGPoint(x: 657.637, y: 169.72))
        p.addCurve(to: CGPoint(x: 665.637, y: 161.72), control1: CGPoint(x: 662.037, y: 169.72), control2: CGPoint(x: 665.637, y: 166.12))
        p.addLine(to: CGPoint(x: 665.717, y: 161.72))
        p.closeSubpath()
        return p
    }()
}


struct EmptyListView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            EmptyListView()
            EmptyListView(compact: true)
            EmptyListView(compact: true, showsSubtitle: false)
        }
        .frame(width: 600)
        .background(Color.black)
    }
}
