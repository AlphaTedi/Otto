import AppKit
import CoreText
import SwiftUI

// MARK: - Onboarding theme — Direction B (docs: otto-onboarding/SPEC.md §5)
//
// Every token the onboarding draws with, in one place. The values are the
// handoff's reference HTML read literally — 1 CSS px = 1 pt — because the PNGs
// were rendered from that HTML and the PNGs are the visual source of truth.
//
// Tokens live in code rather than an asset catalog (which the spec suggests):
// they are needed as `Color` AND as raw alpha maths (the glows scale their
// alpha by 0.6 in light mode), and a catalog colour cannot be multiplied. The
// light/dark pairs are the spec's table, one line each.

// MARK: Font

/// Host Grotesk, bundled (OFL). Registered for this process on first use, so
/// nothing has to remember to call a setup function before the window opens.
enum OBFont {
    private static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "HostGrotesk-VariableFont_wght",
                                        withExtension: "ttf") else {
            print("[Onboarding] Host Grotesk missing from the bundle")
            return false
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered is fine — anything else is worth a log line.
            print("[Onboarding] font registration: \(String(describing: error?.takeRetainedValue()))")
        }
        return true
    }()

    /// The `wght` axis tag, as CoreText wants it: the four ASCII bytes.
    private static let weightAxis = 0x7767_6874

    /// The font at an exact CSS weight (300–800). A variable font answers
    /// any value on its axis, so 500 and 600 are drawn as designed rather than
    /// rounded to the nearest named instance.
    static func ns(_ size: CGFloat, _ weight: CGFloat = 400) -> NSFont {
        _ = registered
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Host Grotesk",
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                [weightAxis: weight],
        ])
        return NSFont(descriptor: descriptor, size: size)
            ?? .systemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    static func font(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        Font(ns(size, weight) as CTFont)
    }

    /// Extra leading to reach a CSS line-height from the face's own.
    static func lineSpacing(size: CGFloat, weight: CGFloat = 400, lineHeight: CGFloat) -> CGFloat {
        let f = ns(size, weight)
        let natural = f.ascender - f.descender + f.leading
        return max(0, lineHeight - natural)
    }
}

extension View {
    /// Host Grotesk at a size, weight and (optional) CSS line height.
    func obFont(_ size: CGFloat, _ weight: CGFloat = 400, lineHeight: CGFloat? = nil) -> some View {
        self.font(OBFont.font(size, weight))
            .lineSpacing(lineHeight.map { OBFont.lineSpacing(size: size, weight: weight, lineHeight: $0) } ?? 0)
    }
}

// MARK: Colour

extension Color {
    init(obHex hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// The spec's token table (§5.1), resolved for one appearance.
struct OBPalette {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    /// The ink everything translucent is mixed from: white on dark, the
    /// primary text colour on light — exactly as the reference CSS does it.
    private var ink: UInt32 { dark ? 0xFFFFFF : 0x17151F }

    var window: Color { Color(obHex: dark ? 0x050507 : 0xF6F5FA) }
    var panel: Color { Color(obHex: dark ? 0x0C0B10 : 0xECEBF4) }
    var textPrimary: Color { Color(obHex: dark ? 0xF2F1F5 : 0x17151F) }
    var textSecondary: Color { Color(obHex: dark ? 0xF2F1F5 : 0x17151F, alpha: 0.55) }
    var textTertiary: Color { Color(obHex: ink, alpha: 0.45) }
    func ink(_ alpha: Double) -> Color { Color(obHex: ink, alpha: alpha) }
    var divider: Color { ink(0.07) }
    var track: Color { ink(0.10) }

    var buttonBG: Color { Color(obHex: dark ? 0xF2F1F5 : 0x6B4CF6) }
    var buttonFG: Color { Color(obHex: dark ? 0x111111 : 0xFFFFFE) }
    var logo: Color { Color(obHex: dark ? 0xFFFFFF : 0x6B4CF6) }

    var violet: Color { Color(obHex: dark ? 0xCFC4FF : 0x7B6BFF) }
    var amber: Color { Color(obHex: dark ? 0xFFC98A : 0xD9822B) }
    var pink: Color { Color(obHex: dark ? 0xFF9EC7 : 0xE0508F) }
    var success: Color { Color(obHex: dark ? 0x8FE3B0 : 0x1F9D5A) }

    /// Keycap idle fill: `bg.panel` lifted 4% in lightness.
    var keycapIdle: Color { Color(obHex: dark ? 0x16141D : 0xF7F6FB) }
}

private struct OBPaletteReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: @MainActor (OBPalette) -> Content
    var body: some View { content(OBPalette(scheme)) }
}

/// Reads the palette for the current appearance without every view having to
/// declare its own `@Environment(\.colorScheme)`.
@MainActor
func withPalette<Content: View>(@ViewBuilder _ content: @escaping @MainActor (OBPalette) -> Content) -> some View {
    OBPaletteReader(content: content)
}

// MARK: Gradients

enum OBGradient {
    /// §5.3 — the progress bar. Laid over the full 300 pt and masked to the
    /// fill, so green is only reached at the end.
    static let progress = Gradient(stops: [
        .init(color: Color(obHex: 0x7B6BFF), location: 0),
        .init(color: Color(obHex: 0xB69CFF), location: 0.45),
        .init(color: Color(obHex: 0x8FD9D0), location: 0.75),
        .init(color: Color(obHex: 0x7FE3A8), location: 1),
    ])

    /// §5.4 — the primary button on hover, at CSS 100°.
    static let hover = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(obHex: 0x9D8BFF), location: 0),
            .init(color: Color(obHex: 0xB69CFF), location: 0.40),
            .init(color: Color(obHex: 0x8FD9D0), location: 0.75),
            .init(color: Color(obHex: 0x7FE3A8), location: 1),
        ]),
        // 100° in CSS points a hair below "to right".
        startPoint: UnitPoint(x: 0, y: 0.41), endPoint: UnitPoint(x: 1, y: 0.59))

    static let hoverGlow = Color(obHex: 0xC6B4FF, alpha: 0.4)
}

// MARK: Glows (§5.2)

struct OBGlow {
    enum Hue {
        case violet, pink, amber
        var rgb: (Double, Double, Double) {
            switch self {
            case .violet: return (150, 110, 255)
            case .pink: return (255, 130, 190)
            case .amber: return (255, 190, 120)
            }
        }
    }

    let hue: Hue
    /// Centre, as a fraction of the surface (CSS `at 50% 115%`).
    let x: CGFloat
    let y: CGFloat
    /// Radii in points (CSS `620px 420px` — the two lengths are radii).
    let rx: CGFloat
    let ry: CGFloat
    /// Peak alpha in dark mode; light mode multiplies it by 0.6.
    let alpha: Double
}

/// Soft radial glows with the spec's ease-out falloff, `α·(1−t)^2.2` sampled
/// in 11 stops — never a hard edge. Drifts ±12 pt over 8 s unless Reduce
/// Motion is on.
struct OBGlowBackground: View {
    let glows: [OBGlow]
    var drifts = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        let multiplier = scheme == .dark ? 1.0 : 0.6
        // Drawn past the surface on every side, so the drift never uncovers a
        // strip of bare panel along an edge.
        let margin: CGFloat = 24
        Canvas { context, canvasSize in
            let size = CGSize(width: canvasSize.width - margin * 2,
                              height: canvasSize.height - margin * 2)
            for glow in glows {
                let (r, g, b) = glow.hue.rgb
                let base = Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
                let stops = (0...10).map { i -> Gradient.Stop in
                    let t = Double(i) / 10
                    return .init(color: base.opacity(glow.alpha * multiplier * pow(1 - t, 2.2)),
                                 location: t)
                }
                var layer = context
                layer.translateBy(x: margin + size.width * glow.x, y: margin + size.height * glow.y)
                // A circle of radius rx, squashed to ry: an ellipse whose
                // gradient follows its own shape, which is what CSS draws.
                layer.scaleBy(x: 1, y: glow.ry / glow.rx)
                let circle = CGRect(x: -glow.rx, y: -glow.rx, width: glow.rx * 2, height: glow.rx * 2)
                layer.fill(Path(ellipseIn: circle),
                           with: .radialGradient(Gradient(stops: stops), center: .zero,
                                                 startRadius: 0, endRadius: glow.rx))
            }
        }
        .padding(-margin)
        .offset(x: phase ? 12 : -12, y: phase ? 6 : -6)
        .allowsHitTesting(false)
        .onAppear {
            guard drifts, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) { phase = true }
        }
    }
}

// MARK: Logo (§6.7)

/// The approved canvas vector, a 400×300 viewBox stroked at 30 with round
/// caps and joins. Drawn as a shape so it is crisp at every size it appears
/// (190, 170, 68) and takes whatever colour the appearance asks for.
struct OttoLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 400, rect.height / 300)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + (85 - 68) * s, y: rect.minY + (205 - 68) * s,
                                   width: 136 * s, height: 136 * s))
        path.move(to: p(140, 70)); path.addLine(to: p(182, 282))
        path.move(to: p(188, 18)); path.addLine(to: p(236, 276))
        path.move(to: p(104, 108)); path.addLine(to: p(252, 74))
        path.addEllipse(in: CGRect(x: rect.minX + (318 - 68) * s, y: rect.minY + (200 - 68) * s,
                                   width: 136 * s, height: 136 * s))
        path.move(to: p(290, 190)); path.addLine(to: p(318, 218)); path.addLine(to: p(378, 92))
        return path
    }
}

struct OttoLogo: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        OttoLogoShape()
            .stroke(color, style: StrokeStyle(lineWidth: 30 * width / 400,
                                              lineCap: .round, lineJoin: .round))
            .frame(width: width, height: width * 0.75)
            .accessibilityLabel("Otto")
    }
}

// MARK: Icons — the handoff's 24-pt stroke glyphs

enum OBIcon {
    case calendar, bolt, power, check, circle

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        switch self {
        case .calendar:
            path.addRoundedRect(in: CGRect(x: rect.minX + 3 * s, y: rect.minY + 5 * s,
                                           width: 18 * s, height: 16 * s),
                                cornerSize: CGSize(width: 3 * s, height: 3 * s))
            path.move(to: p(3, 10)); path.addLine(to: p(21, 10))
            path.move(to: p(8, 3)); path.addLine(to: p(8, 7))
            path.move(to: p(16, 3)); path.addLine(to: p(16, 7))
        case .bolt:
            path.move(to: p(13, 2)); path.addLine(to: p(4, 14)); path.addLine(to: p(11, 14))
            path.addLine(to: p(10, 22)); path.addLine(to: p(19, 10)); path.addLine(to: p(12, 10))
            path.closeSubpath()
        case .power:
            path.move(to: p(12, 3)); path.addLine(to: p(12, 12))
            // `M6.3 7 a8 8 0 1 0 11.4 0`: the long way round a circle of
            // radius 8 whose centre sits 5.61 below the chord.
            let cx: CGFloat = 12, cy: CGFloat = 12.61, r: CGFloat = 8
            let start = atan2(7 - cy, 6.3 - cx)
            let end = atan2(7 - cy, 17.7 - cx) - 2 * .pi
            let steps = 48
            for i in 0...steps {
                let a = start + (end - start) * CGFloat(i) / CGFloat(steps)
                let point = p(cx + r * cos(a), cy + r * sin(a))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        case .check:
            path.move(to: p(5, 12)); path.addLine(to: p(10, 17)); path.addLine(to: p(19, 7))
        case .circle:
            path.addEllipse(in: CGRect(x: rect.minX + 4 * s, y: rect.minY + 4 * s,
                                       width: 16 * s, height: 16 * s))
        }
        return path
    }
}

struct OBIconView: View {
    let icon: OBIcon
    let size: CGFloat
    let color: Color
    var lineWidth: CGFloat = 1.9

    var body: some View {
        OBIconShape(icon: icon)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * size / 24,
                                              lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct OBIconShape: Shape {
    let icon: OBIcon
    func path(in rect: CGRect) -> Path { icon.path(in: rect) }
}

// MARK: Metrics

enum OBMetric {
    static let windowSize = CGSize(width: 860, height: 460)
    static let windowRadius: CGFloat = 36
    static let columnWidth: CGFloat = 360
    static let progressWidth: CGFloat = 300
    static let panelSize = CGSize(width: 490, height: 440)
    static let panelShape = UnevenRoundedRect(topLeading: 14, bottomLeading: 14,
                                              bottomTrailing: 26, topTrailing: 26)
}

/// Rounded rectangle with a radius per corner — `UnevenRoundedRectangle` is
/// macOS 14, and this app still runs on 13.
struct UnevenRoundedRect: Shape {
    var topLeading: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat
    var topTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let tl = min(topLeading, w / 2, h / 2), tr = min(topTrailing, w / 2, h / 2)
        let bl = min(bottomLeading, w / 2, h / 2), br = min(bottomTrailing, w / 2, h / 2)
        // Quadratic-ish continuous corners via cubic curves (the 0.552 circle
        // constant pushed out a little, which is what "continuous" looks like).
        let k: CGFloat = 0.62
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                      control1: CGPoint(x: rect.maxX - tr * (1 - k), y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + tr * (1 - k)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - br * (1 - k)),
                      control2: CGPoint(x: rect.maxX - br * (1 - k), y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl),
                      control1: CGPoint(x: rect.minX + bl * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - bl * (1 - k)))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + tl * (1 - k)),
                      control2: CGPoint(x: rect.minX + tl * (1 - k), y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: Text that breaks lines like the reference

/// A paragraph laid out the way the handoff's HTML lays it out.
///
/// SwiftUI's `Text` avoids leaving a single word on the last line, so it broke
/// "What should Otto help with first?" before "with" where the design breaks
/// before "first?" — and there is no SwiftUI switch for it. This draws and
/// measures with the same NSStringDrawing call (no orphan avoidance), puts the
/// CSS line height's half-leading above and below each line, and draws without
/// font smoothing, the way the reference PNGs were rendered.
struct OBText: NSViewRepresentable {
    let text: String
    let size: CGFloat
    var weight: CGFloat = 400
    var lineHeight: CGFloat? = nil
    var tracking: CGFloat = 0
    var alignment: NSTextAlignment = .left
    let color: Color

    final class TextView: NSView {
        var string = NSAttributedString()
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
            string.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
        override func accessibilityValue() -> Any? { string.string }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private var attributed: NSAttributedString {
        let font = OBFont.ns(size, weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = []
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(color),
        ]
        // `.tracking`, not `.kern`: any `.kern` value — even 0 — switches the
        // font's pair kerning off, which set every line ~2% wider than the
        // reference and moved its line breaks.
        if tracking != 0 { attributes[.tracking] = tracking }
        if let lineHeight {
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            // TextKit sits the glyphs at the bottom of a tall line; CSS centres
            // them in it. Lift by half the extra.
            let natural = font.ascender - font.descender
            attributes[.baselineOffset] = (lineHeight - natural) / 2
        }
        attributes[.paragraphStyle] = paragraph
        return NSAttributedString(string: text, attributes: attributes)
    }

    func makeNSView(context: Context) -> TextView {
        let view = TextView()
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ view: TextView, context: Context) {
        view.string = attributed
        view.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TextView, context: Context) -> CGSize? {
        let limit = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .greatestFiniteMagnitude
        let rect = attributed.boundingRect(with: NSSize(width: limit, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        let width = alignment == .left ? min(limit, ceil(rect.width)) : (limit.isFinite && limit < .greatestFiniteMagnitude ? limit : ceil(rect.width))
        return CGSize(width: width, height: ceil(rect.height))
    }
}
