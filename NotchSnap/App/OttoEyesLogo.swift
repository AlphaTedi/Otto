// OttoEyesLogo.swift — the Otto wordmark with animated "curious" eyes
// (direction 01, otto-eyes-animation handoff, 2026-09-29).
//
// The two holes inside the "O"s are the eyes: saccades (11 s loop), drift
// (3.7 s) and single blinks (7.3 s), combined every frame. The three periods
// differ on purpose so the combination does not visibly repeat — keep them.
// Motion values are the handoff's `otto-eyes-motion.json`, unchanged; the
// reference is its `preview.html`. Static with Reduce Motion, paused when
// `isAnimating` is false. Usage: OttoEyesLogo(color: p.logo).frame(width: 160)

import SwiftUI

struct OttoEyesLogo: View {
    var color: Color = Color(red: 0.980, green: 0.976, blue: 0.961) // #FAF9F5
    var isAnimating: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(color: Color = Color(red: 0.980, green: 0.976, blue: 0.961), isAnimating: Bool = true) {
        self.color = color; self.isAnimating = isAnimating
    }

    var body: some View {
        let animate = isAnimating && !reduceMotion
        TimelineView(.animation(paused: !animate)) { ctx in
            let t = animate ? ctx.date.timeIntervalSinceReferenceDate : 0
            Canvas { gc, size in
                let s = min(size.width / 971, size.height / 473)
                gc.translateBy(x: (size.width - 971 * s) / 2, y: (size.height - 473 * s) / 2)
                gc.scaleBy(x: s, y: s)
                gc.fill(OttoEyesMotion.tPath, with: .color(color))
                let o = OttoEyesMotion.eyeOffset(at: t)
                let b = OttoEyesMotion.blink(at: t)
                for e in OttoEyesMotion.eyes {
                    var p = Path(ellipseIn: CGRect(x: e.socket.x - 158.88, y: e.socket.y - 158.88, width: 317.76, height: 317.76))
                    let r = 57.48, h = 2 * r * b
                    let bottom = e.eye.y + o.y + r
                    p.addEllipse(in: CGRect(x: e.eye.x + o.x - r, y: bottom - h, width: 2 * r, height: h))
                    gc.fill(p, with: .color(color), style: FillStyle(eoFill: true))
                }
            }
        }
        .aspectRatio(971.0 / 473.0, contentMode: .fit)
        .accessibilityLabel("Otto")
    }
}

enum OttoEyesMotion {
    struct Eye { let eye: CGPoint; let socket: CGPoint }
    static let eyes = [
        Eye(eye: CGPoint(x: 183.8, y: 253.884), socket: CGPoint(x: 158.88, y: 274.724)),
        Eye(eye: CGPoint(x: 837.043, y: 253.884), socket: CGPoint(x: 812.083, y: 274.724))
    ]
    struct K { let t: Double; let x: Double; let y: Double }

    // Layer 1 — saccades: quick ~150 ms jumps, irregular fixations. 11 s loop.
    static let saccade: [K] = [
        .init(t: 0.0, x: 0.0, y: 0.0),
        .init(t: 0.06, x: 0.0, y: 0.0),
        .init(t: 0.07400000000000001, x: 38.0, y: -30.0),
        .init(t: 0.15, x: 38.0, y: -30.0),
        .init(t: 0.16399999999999998, x: 46.0, y: -22.0),
        .init(t: 0.21, x: 46.0, y: -22.0),
        .init(t: 0.22399999999999998, x: -50.0, y: 10.0),
        .init(t: 0.33, x: -50.0, y: 10.0),
        .init(t: 0.344, x: -18.0, y: -46.0),
        .init(t: 0.37, x: -18.0, y: -46.0),
        .init(t: 0.384, x: -24.0, y: -40.0),
        .init(t: 0.46, x: -24.0, y: -40.0),
        .init(t: 0.474, x: 52.0, y: 36.0),
        .init(t: 0.58, x: 52.0, y: 36.0),
        .init(t: 0.594, x: 10.0, y: -8.0),
        .init(t: 0.64, x: 10.0, y: -8.0),
        .init(t: 0.654, x: -44.0, y: 44.0),
        .init(t: 0.71, x: -44.0, y: 44.0),
        .init(t: 0.7240000000000001, x: -36.0, y: 50.0),
        .init(t: 0.77, x: -36.0, y: 50.0),
        .init(t: 0.784, x: 58.0, y: -14.0),
        .init(t: 0.86, x: 58.0, y: -14.0),
        .init(t: 0.8740000000000001, x: -8.0, y: -54.0),
        .init(t: 0.94, x: -8.0, y: -54.0),
        .init(t: 0.9540000000000001, x: 0.0, y: 0.0),
        .init(t: 1.0, x: 0.0, y: 0.0)
    ]
    // Layer 2 — micro drift while fixating. 3.7 s loop.
    static let drift: [K] = [.init(t: 0, x: 0, y: 0), .init(t: 0.23, x: 2, y: -1.5), .init(t: 0.51, x: -1.5, y: 2), .init(t: 0.77, x: 1.5, y: 1), .init(t: 1, x: 0, y: 0)]
    // Layer 3 — blink (scaleY, anchored at eye bottom). 7.3 s loop. x = scale.
    static let blinkK: [K] = [.init(t: 0, x: 1, y: 0), .init(t: 0.31, x: 1, y: 0), .init(t: 0.322, x: 0.05, y: 0), .init(t: 0.345, x: 1, y: 0), .init(t: 0.78, x: 1, y: 0), .init(t: 0.792, x: 0.05, y: 0), .init(t: 0.814, x: 1, y: 0), .init(t: 1, x: 1, y: 0)]

    static func eyeOffset(at time: Double) -> CGPoint {
        let a = sample(saccade, time, 11.0, (0.15, 0.85, 0.3, 1))
        let d = sample(drift, time, 3.7, (0.42, 0, 0.58, 1))
        return CGPoint(x: a.x + d.x, y: a.y + d.y)
    }
    static func blink(at time: Double) -> Double { sample(blinkK, time, 7.3, (0.4, 0, 0.6, 1)).x }

    private static func sample(_ k: [K], _ time: Double, _ dur: Double, _ c: (Double, Double, Double, Double)) -> (x: Double, y: Double) {
        let p = time.truncatingRemainder(dividingBy: dur) / dur
        var i = 0
        while i < k.count - 2 && p > k[i + 1].t { i += 1 }
        let a = k[i], b = k[i + 1]
        let span = b.t - a.t
        let u = span > 0 ? min(max((p - a.t) / span, 0), 1) : 1
        let e = bezier(u, c)
        return (a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e)
    }
    // CSS cubic-bezier(x1,y1,x2,y2) easing
    private static func bezier(_ x: Double, _ c: (Double, Double, Double, Double)) -> Double {
        func bx(_ t: Double) -> Double { 3*(1-t)*(1-t)*t*c.0 + 3*(1-t)*t*t*c.2 + t*t*t }
        func by(_ t: Double) -> Double { 3*(1-t)*(1-t)*t*c.1 + 3*(1-t)*t*t*c.3 + t*t*t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 { t = (lo + hi) / 2; if bx(t) < x { lo = t } else { hi = t } }
        return by(t)
    }

    // The "tt" glyphs of the logo (viewBox 971x473).
    // Built once. `nonisolated(unsafe)`: a value type, never mutated after
    // this initialiser, read from the Canvas renderer (Swift 6 mode).
    nonisolated(unsafe) static let tPath: Path = {
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
