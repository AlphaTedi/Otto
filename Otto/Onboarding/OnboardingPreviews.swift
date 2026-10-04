import SwiftUI

// MARK: - Onboarding previews (v3 SPEC §4.2, §4.3, §4.6)
//
// The mock product UI the visual panel shows: the notch's to-dos, a note, a
// meeting heads-up, the two display styles, and the confetti on the last
// step. Drawn from the reference HTML's own values (1 CSS px = 1 pt). These
// mockups stay dark in both appearances (v3 §0) and show sample data only —
// generic names, never the user's own lists.

// MARK: Entrances

/// A CSS keyframe entrance: from `offset`/`scale`/transparent to rest, once,
/// on the design's overshooting curve. Reduce Motion shows the end state.
private struct OBEntrance: ViewModifier {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    var duration: Double
    var delay: Double = 0
    var curve: (Double, Double, Double, Double)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let rest = shown || reduceMotion
        content
            .opacity(rest ? 1 : 0)
            .scaleEffect(rest ? 1 : scale)
            .offset(rest ? .zero : offset)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.timingCurve(curve.0, curve.1, curve.2, curve.3, duration: duration).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// `popIn`: translateY −10 → 0, scale .97 → 1, 0.45 s after 0.3 s.
    fileprivate func obPopIn() -> some View {
        modifier(OBEntrance(offset: CGSize(width: 0, height: -10), scale: 0.97,
                            duration: 0.45, delay: 0.3, curve: (0.22, 1.2, 0.36, 1)))
    }
}

// MARK: Shared pieces

/// A black notch panel hanging from the top edge, bottom corners rounded.
private struct NotchSlab<Content: View>: View {
    let width: CGFloat
    let radius: CGFloat
    let padding: EdgeInsets
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = UnevenRoundedRect(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0)
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background(shape.fill(.black))
            .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 30)
    }
}

/// Rounded-square checkbox outline.
private struct OBBox: View {
    let side: CGFloat
    let radius: CGFloat
    let color: Color
    var lineWidth: CGFloat = 1.6
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color, lineWidth: lineWidth)
            .frame(width: side, height: side)
    }
}

private let mint = Color(obHex: 0xA8E6C1)

/// The three to-dos the style previews share, the last one opened on its steps.
private struct StyleTodoList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["ob.pv.todo1", "ob.pv.todo2", "ob.pv.todo3"], id: \.self) { key in
                HStack(spacing: 10) {
                    OBBox(side: 13, radius: 5, color: mint)
                    Text(L10n.t(key)).obFont(12)
                }
                .padding(.vertical, 5)
            }
            // The steps hang off a 1-pt guide line under the parent's box.
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(["ob.pv.step1", "ob.pv.step2"], id: \.self) { key in
                        HStack(spacing: 7) {
                            OBBox(side: 9, radius: 4, color: mint)
                            Text(L10n.t(key))
                        }
                    }
                    Text("\u{00B7}\u{00B7}\u{00B7} " + L10n.t("ob.pv.moreSteps"))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .obFont(10.5)
                .foregroundStyle(Color.white.opacity(0.62))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 6)
            .padding(.top, -1)
            .padding(.bottom, 3)
        }
        .foregroundStyle(Color(obHex: 0xF2F1F5))
    }
}

/// Notes 4 · Work 3 · Personal 5 and the gear, as in the panel's space bar.
private struct StylePillsRow: View {
    var body: some View {
        HStack(spacing: 5) {
            pill(L10n.t("filter.notes"), 4)
                .overlay(Capsule().strokeBorder(Color(obHex: 0xFFC36E, alpha: 0.55),
                                                style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 12)
            pill(L10n.t("ob.pv.work"), 3)
                .foregroundStyle(Color(obHex: 0x10261A))
                .background(Capsule().fill(mint))
            pill(L10n.t("ob.pv.personal"), 5)
            Spacer(minLength: 0)
            GearGlyph()
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .foregroundStyle(.white)
    }

    private func pill(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text("\(count)").opacity(0.55)
        }
        .obFont(10.5, 600)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 20)
    }
}

/// `circle r3` and eight rays, on a 24 grid.
private struct GearGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + 9 * s, y: rect.minY + 9 * s, width: 6 * s, height: 6 * s))
        let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (12, 2, 12, 5), (12, 19, 12, 22), (4.2, 4.2, 6.3, 6.3), (17.7, 17.7, 19.8, 19.8),
            (2, 12, 5, 12), (19, 12, 22, 12), (4.2, 19.8, 6.3, 17.7), (17.7, 6.3, 19.8, 4.2),
        ]
        for ray in rays {
            path.move(to: p(ray.0, ray.1)); path.addLine(to: p(ray.2, ray.3))
        }
        return path
    }
}

// MARK: Discover · Tasks (C2.1)

struct NotchTasksPreview: View {
    var body: some View {
        NotchSlab(width: 320, radius: 20, padding: EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14),
                  spacing: 9) {
            row(L10n.t("ob.pv.task1"), done: false)
            row(L10n.t("ob.pv.task2"), done: false)
            row(L10n.t("ob.pv.task3"), done: true)
        }
        .accessibilityHidden(true)
    }

    private func row(_ title: String, done: Bool) -> some View {
        HStack(spacing: 9) {
            if done {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(obHex: 0x7FE3A8))
                    .frame(width: 13, height: 13)
                    .overlay(OBIconView(icon: .check, size: 9, color: Color(obHex: 0x0B1A12)))
            } else {
                OBBox(side: 13, radius: 4, color: Color.white.opacity(0.35), lineWidth: 1.5)
            }
            Text(title)
                .obFont(12.5)
                .strikethrough(done)
                .foregroundStyle(done ? Color.white.opacity(0.35) : Color(obHex: 0xF2F1F5))
                .lineLimit(1)
        }
    }
}

// MARK: Discover · Notes (C2.2)

struct NotePreview: View {
    var body: some View {
        NotchSlab(width: 360, radius: 24, padding: EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14),
                  spacing: 12) {
            header
            // 12 pt at a 1.7 line height: 20.4 per line, glyphs centred in it.
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("ob.pv.noteAgenda")).foregroundStyle(Color.white.opacity(0.85))
                    .frame(height: 20.4)
                ForEach(["ob.pv.noteLine1", "ob.pv.noteLine2"], id: \.self) { key in
                    Text("\u{2022} " + L10n.t(key)).frame(height: 20.4)
                }
                HStack(spacing: 1) {
                    Text("\u{2022} " + L10n.t("ob.pv.noteLine3"))
                    Rectangle().fill(.white).frame(width: 1.5, height: 13)
                }
                .frame(height: 20.4)
            }
            .obFont(12)
            .foregroundStyle(Color.white.opacity(0.6))
            .padding(.horizontal, 6)
            HStack {
                toolbar
                Spacer()
                Text(L10n.t("ob.pv.words")).obFont(10.5).foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .foregroundStyle(Color(obHex: 0xF2F1F5))
        .obPopIn()
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ChevronLeft()
                .stroke(Color(obHex: 0x7FD8E0), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
            Text(L10n.t("ob.pv.noteTitle")).obFont(12.5, 600)
            Spacer(minLength: 0)
            Text(L10n.t("ob.pv.saved")).obFont(10.5).foregroundStyle(Color.white.opacity(0.4))
            Text("\u{2318}[")
                .obFont(9.5)
                .foregroundStyle(Color.white.opacity(0.6))
                .padding(.vertical, 1)
                .padding(.horizontal, 5)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            tool(Text("Aa"))
            // Host Grotesk has no ≡: three strokes, drawn.
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Color.white.opacity(0.7)).frame(width: 8, height: 1.1)
                }
            }
            .frame(width: 18)
            tool(Text("1."))
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 10)
            tool(Text("B"), weight: 700)
            // No italic in the face either: a slant, as the browser drew it.
            tool(Text("I"))
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 1.6, ty: 0))
            tool(Text("U").underline())
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func tool(_ text: Text, weight: CGFloat = 400) -> some View {
        text.obFont(11, weight).foregroundStyle(Color.white.opacity(0.7)).frame(width: 18)
    }
}

/// `M15 18l-6-6 6-6`.
private struct ChevronLeft: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 15 * s, y: rect.minY + 18 * s))
        path.addLine(to: CGPoint(x: rect.minX + 9 * s, y: rect.minY + 12 * s))
        path.addLine(to: CGPoint(x: rect.minX + 15 * s, y: rect.minY + 6 * s))
        return path
    }
}

// MARK: Discover · Meetings (C2.3)

struct MeetingPreview: View {
    private let amber = Color(obHex: 0xF5C542)

    var body: some View {
        ZStack(alignment: .top) {
            wing
            card
                .padding(.horizontal, 22)
                .padding(.top, 66)
                .obPopIn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color(obHex: 0xF2F1F5))
        .accessibilityHidden(true)
    }

    private var wing: some View {
        let shape = UnevenRoundedRect(topLeading: 0, bottomLeading: 14, bottomTrailing: 14, topTrailing: 0)
        return HStack {
            MeetLogo(size: 16)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(amber).frame(width: 7, height: 7)
                Text("in 34\u{2032}").obFont(11.5, 500)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 240, height: 30)
        .background(shape.fill(.black))
        .overlay(shape.stroke(Color.white.opacity(0.05), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(alignment: .top, spacing: 14) {
            MeetLogo(size: 22)
                .frame(width: 24, height: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("9:30 \u{2013} 10:30 AM").obFont(11.5).foregroundStyle(amber)
                    Spacer()
                    Text(L10n.t("ob.pv.inMinutes")).obFont(11).foregroundStyle(Color.white.opacity(0.45))
                }
                Text(L10n.t("ob.pv.meeting")).obFont(17, 500).tracking(-0.17)
                HStack(spacing: 8) {
                    actionPill(L10n.t("ob.pv.join"), hint: "\u{2318}\u{21B5}", primary: true)
                    actionPill(L10n.t("ob.pv.snooze"), hint: "S", primary: false)
                    Spacer(minLength: 0)
                    avatars
                }
                .padding(.top, 7)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .background(shape.fill(Color(.sRGB, red: 8 / 255, green: 8 / 255, blue: 10 / 255, opacity: 0.94)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 25, y: 24)
    }

    private func actionPill(_ title: String, hint: String, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).obFont(12.5, primary ? 600 : 500)
            Text(hint)
                .obFont(10.5)
                .foregroundStyle(primary ? Color.black.opacity(0.55) : .white)
                .padding(.horizontal, hint.count > 1 ? 6 : 0)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(primary ? Color.black.opacity(0.08) : Color.white.opacity(0.1)))
        }
        .foregroundStyle(primary ? Color(obHex: 0x111111) : .white)
        .padding(.leading, 13)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(Capsule().fill(primary ? Color.white : .clear))
        .overlay(primary ? nil : Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    /// Three illustrated placeholders overlapping by 7, each ringed in the
    /// card's own dark so they separate, then "+2".
    private var avatars: some View {
        HStack(spacing: -7) {
            ForEach(OBAvatar.samples.indices, id: \.self) { index in
                OBAvatar.samples[index]
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .background(Circle().fill(Color(obHex: 0x0A0A0C)).padding(-2))
            }
            Text("+2")
                .obFont(10, 600)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .background(Circle().fill(Color(obHex: 0x0A0A0C)).padding(-2))
        }
    }
}

/// The official Google Meet mark, from the handoff's assets.
private struct MeetLogo: View {
    let size: CGFloat
    var body: some View {
        Image("GoogleMeet")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// The handoff's avatar illustrations, drawn from their SVG paths.
private struct OBAvatar: View {
    let background: UInt32
    let shirt: UInt32
    let skin: UInt32
    let hair: UInt32
    var hairPath: String?
    var hairCircles: [(CGFloat, CGFloat, CGFloat)] = []

    static let samples: [OBAvatar] = [
        OBAvatar(background: 0x8FB2E8, shirt: 0x2F3B58, skin: 0xE9C3A0, hair: 0x3B2A22,
                 hairPath: "M7 11.5c0-4 2.3-6.2 5-6.2s5 2.2 5 6.2c-.6-1.8-1.8-3-5-3s-4.4 1.2-5 3z"),
        OBAvatar(background: 0xE8A7B8, shirt: 0x5A3848, skin: 0xC98E68, hair: 0x1E1513,
                 hairPath: "M6.3 16c-.4-6 1.6-10.7 5.7-10.7s6.1 4.7 5.7 10.7h-1.9c.4-3 .1-5.4-.8-6.8-.9 1-2.6 1.6-5.9 1.6-.6 1.5-.7 3.3-.4 5.2z"),
        OBAvatar(background: 0xA8D8B8, shirt: 0x2C4A3A, skin: 0x8A5A3C, hair: 0x15100D,
                 hairCircles: [(8.3, 8.6, 2.3), (12, 6.8, 2.6), (15.7, 8.6, 2.3)]),
    ]

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.width / 24)
            context.fill(Path(CGRect(x: 0, y: 0, width: 24, height: 24)), with: .color(Color(obHex: background)))
            context.fill(SVGPath.parse("M3.5 24c.8-4.6 4.2-7 8.5-7s7.7 2.4 8.5 7z"), with: .color(Color(obHex: shirt)))
            context.fill(Path(roundedRect: CGRect(x: 10.3, y: 13.5, width: 3.4, height: 4), cornerRadius: 1.5),
                         with: .color(Color(obHex: skin)))
            context.fill(Path(ellipseIn: CGRect(x: 12 - 4.2, y: 10.8 - 4.7, width: 8.4, height: 9.4)),
                         with: .color(Color(obHex: skin)))
            if let hairPath {
                context.fill(SVGPath.parse(hairPath), with: .color(Color(obHex: hair)))
            }
            for (x, y, r) in hairCircles {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Color(obHex: hair)))
            }
        }
    }
}

/// Just enough of SVG path syntax for the avatars: M L H V C S Z, absolute
/// and relative, with implicit repeats.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for ch in d {
            if ch.isLetter {
                flush(); tokens.append(String(ch))
            } else if ch == "-" {
                flush(); number = "-"
            } else if ch == "." && number.contains(".") {
                flush(); number = "."
            } else if ch == "," || ch == " " {
                flush()
            } else {
                number.append(ch)
            }
        }
        flush()

        var path = Path()
        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        func next() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { command = c; i += 1 }
            let rel = command.isLowercase
            let base = rel ? current : .zero
            switch Character(command.uppercased()) {
            case "M":
                current = CGPoint(x: base.x + next(), y: base.y + next())
                start = current
                path.move(to: current)
                command = rel ? "l" : "L"
                lastControl = nil
            case "L":
                current = CGPoint(x: base.x + next(), y: base.y + next())
                path.addLine(to: current)
                lastControl = nil
            case "H":
                current = CGPoint(x: (rel ? current.x : 0) + next(), y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                current = CGPoint(x: current.x, y: (rel ? current.y : 0) + next())
                path.addLine(to: current)
                lastControl = nil
            case "C":
                let c1 = CGPoint(x: base.x + next(), y: base.y + next())
                let c2 = CGPoint(x: base.x + next(), y: base.y + next())
                let end = CGPoint(x: base.x + next(), y: base.y + next())
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = CGPoint(x: base.x + next(), y: base.y + next())
                let end = CGPoint(x: base.x + next(), y: base.y + next())
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                i += 1
            }
        }
        return path
    }
}

// MARK: Style · In the notch (C3, 03a)

/// The notch opening around the panel's own UI: 150×30 → 340 × its content,
/// radius 10 → 26, then the content fades up into it.
struct NotchStylePreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var contentShown = false
    /// The content's own height: the notch ends where it does, so there is
    /// never empty black under the last row (v3 §4.3).
    @State private var contentHeight: CGFloat = 244

    var body: some View {
        let isOpen = open || reduceMotion
        let radius: CGFloat = isOpen ? 26 : 10
        let shape = UnevenRoundedRect(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0)
        content
            .opacity(contentShown || reduceMotion ? 1 : 0)
            .offset(y: contentShown || reduceMotion ? 0 : -6)
            .frame(width: isOpen ? 340 : 150, height: isOpen ? contentHeight : 30, alignment: .top)
            .clipShape(shape)
            .background(shape.fill(.black))
            .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.timingCurve(0.22, 1.25, 0.36, 1, duration: 0.75).delay(0.45)) { open = true }
                withAnimation(.easeOut(duration: 0.3).delay(1.05)) { contentShown = true }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                OBBox(side: 13, radius: 5, color: mint)
                Text(L10n.t("ob.pv.whatNeedsDoing")).obFont(12)
                Spacer(minLength: 0)
                Text(L10n.t("todo.switchSpace")).obFont(9.5)
                Text("Tab")
                    .obFont(9)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 5)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(obHex: 0xA8E6C1, alpha: 0.45), lineWidth: 1))
            StylePillsRow()
            StyleTodoList()
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 340, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { contentHeight = proxy.size.height }
        })
    }
}

// MARK: Style · Floating panel (C3, 03b)

struct FloatingStylePreview: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(mint).frame(width: 7, height: 7).frame(width: 13)
                Text(L10n.t("ob.pv.addTodo")).obFont(13.5).foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            StyleTodoList()
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            StylePillsRow()
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        }
        .frame(width: 340)
        // CSS 170°: a hair off vertical.
        .background(shape.fill(LinearGradient(
            stops: [.init(color: Color(obHex: 0x1B1F35), location: 0),
                    .init(color: Color(obHex: 0x1D2230), location: 0.45),
                    .init(color: Color(obHex: 0x1C3324), location: 1)],
            startPoint: UnitPoint(x: 0.41, y: 0), endPoint: UnitPoint(x: 0.59, y: 1))))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 30)
        // `floatIn`: scale .92 → 1, 3% lower → centred, fading in.
        .modifier(OBEntrance(offset: CGSize(width: 0, height: 11), scale: 0.92,
                             duration: 0.5, curve: (0.22, 1.2, 0.36, 1)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Done · confetti (C6)

/// Played once on "You're set.": the pieces drop in from above the panel,
/// fall under gravity with a little sway and spin, and fade out before they
/// reach the bottom — confetti that falls and is gone, not a burst that
/// freezes mid-air (Marcello, 2026-09-27). The reference layout supplies
/// each piece's colour, size, column and turn. Reduce Motion shows none.
struct OBConfetti: View {
    struct Piece {
        let x, y, w, h: CGFloat
        let color: UInt32
        let rotation: Double
        let opacity: Double
        init(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
             _ color: UInt32, _ rotation: Double, _ opacity: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
            self.color = color; self.rotation = rotation; self.opacity = opacity
        }
    }

    /// The reference's scattered layout (06-done.html), in panel points.
    static let pieces: [Piece] = [
        Piece(175, 87, 7, 9, 0xB69CFF, 101, 1),
        Piece(58, 197, 5, 13, 0x7FE3A8, 149, 0.6),
        Piece(54, 232, 5, 9, 0xB69CFF, 107, 1),
        Piece(227, 40, 5, 9, 0x7B6BFF, 144, 1),
        Piece(308, 41, 7, 11, 0xB69CFF, 147, 0.6),
        Piece(33, 295, 6, 11, 0x7FE3A8, 34, 1),
        Piece(70, 302, 7, 13, 0x7FE3A8, 78, 0.6),
        Piece(307, 302, 5, 11, 0xB69CFF, 163, 1),
        Piece(374, 42, 5, 13, 0x7FE3A8, 144, 0.8),
        Piece(358, 282, 6, 11, 0xFFD6A3, 109, 0.8),
        Piece(195, 163, 5, 13, 0x7FE3A8, 63, 0.6),
        Piece(304, 163, 6, 11, 0x7B6BFF, 134, 0.8),
        Piece(157, 321, 5, 13, 0x8FD9D0, 18, 0.6),
        Piece(397, 185, 6, 11, 0xB69CFF, 38, 1),
        Piece(49, 401, 7, 11, 0xFF9EC7, 142, 1),
        Piece(189, 314, 7, 11, 0xB69CFF, 127, 0.6),
        Piece(148, 252, 7, 9, 0xB69CFF, 178, 1),
        Piece(369, 168, 7, 13, 0x8FD9D0, 165, 0.8),
        Piece(376, 207, 6, 9, 0x8FD9D0, 171, 0.8),
        Piece(96, 322, 6, 9, 0x7FE3A8, 29, 0.8),
        Piece(76, 388, 6, 11, 0x8FD9D0, 63, 0.6),
        Piece(95, 239, 7, 11, 0x7FE3A8, 102, 0.8),
        Piece(452, 291, 7, 11, 0xFF9EC7, 71, 1),
        Piece(462, 204, 5, 9, 0x7FE3A8, 59, 0.6),
        Piece(128, 347, 5, 11, 0xFFD6A3, 59, 0.6),
        Piece(144, 154, 5, 11, 0xFFD6A3, 1, 0.8),
        Piece(322, 299, 5, 13, 0xFFD6A3, 81, 1),
        Piece(345, 356, 6, 13, 0xFFD6A3, 13, 0.8),
        Piece(213, 214, 5, 11, 0x7B6BFF, 100, 0.8),
        Piece(41, 107, 5, 11, 0x7FE3A8, 17, 0.6),
        Piece(184, 317, 5, 9, 0xFFD6A3, 13, 0.6),
        Piece(284, 61, 7, 9, 0xB69CFF, 93, 0.6),
        Piece(324, 202, 7, 11, 0xFF9EC7, 38, 1),
        Piece(196, 252, 5, 11, 0x8FD9D0, 31, 0.8),
        Piece(257, 169, 5, 9, 0x7B6BFF, 21, 0.8),
        Piece(389, 145, 7, 9, 0xFFD6A3, 122, 0.6),
        Piece(115, 280, 5, 13, 0xFFD6A3, 92, 0.6),
        Piece(398, 280, 7, 9, 0x7B6BFF, 76, 0.8),
        Piece(275, 197, 6, 9, 0xFFD6A3, 42, 1),
        Piece(408, 267, 7, 9, 0xFFD6A3, 84, 0.6),
        Piece(422, 132, 7, 9, 0x7FE3A8, 102, 1),
        Piece(262, 192, 5, 11, 0x8FD9D0, 7, 0.8),
        Piece(109, 364, 6, 11, 0x7B6BFF, 154, 0.8),
        Piece(196, 51, 5, 9, 0x8FD9D0, 56, 0.6),
        Piece(182, 114, 7, 13, 0xB69CFF, 123, 0.8),
        Piece(475, 344, 7, 9, 0x7B6BFF, 88, 0.6),
    ]

    /// Long enough for the slowest, latest piece to fall past the fade.
    private static let duration: Double = 3.2
    private static let gravity: Double = 320  // pt/s² — a leisurely drop, ~2 s to the fade

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var finished = false

    var body: some View {
        Group {
            if !reduceMotion && !finished {
                TimelineView(.animation) { context in
                    let elapsed = start.map { context.date.timeIntervalSince($0) } ?? 0
                    canvas(time: elapsed)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            start = Date()
            // Nothing left on screen after this: stop redrawing an empty canvas.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { finished = true }
        }
    }

    private func canvas(time t: Double) -> some View {
        Canvas { context, size in
            let height = Double(size.height)
            for (index, piece) in Self.pieces.enumerated() {
                // Fixed per-piece variety, so the fall is the same every time.
                let seed = Double((index * 73 + 19) % 97) / 97
                let seed2 = Double((index * 37 + 11) % 89) / 89
                let local = t - seed * 0.7            // staggered release
                guard local > 0 else { continue }
                // Start just above the panel, a little higher for some.
                let y0 = -20 - seed2 * 60
                let v0 = 20 + seed * 60
                let y = y0 + v0 * local + 0.5 * Self.gravity * local * local
                guard y < height + 20 else { continue }
                let x = Double(piece.x + piece.w / 2) + 14 * sin(local * (1.6 + seed * 1.4) + seed2 * 6)
                // Fade over the lower third, gone before the bottom edge.
                let fadeStart = height * 0.55, fadeEnd = height * 0.92
                let fade = y < fadeStart ? 1 : max(0, 1 - (y - fadeStart) / (fadeEnd - fadeStart))
                guard fade > 0 else { continue }
                var layer = context
                layer.opacity = piece.opacity * fade * min(1, local / 0.15)
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .degrees(piece.rotation + (seed - 0.5) * 540 * local))
                let rect = CGRect(x: -piece.w / 2, y: -piece.h / 2, width: piece.w, height: piece.h)
                layer.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color(obHex: piece.color)))
            }
        }
    }
}
