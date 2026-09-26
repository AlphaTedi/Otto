import SwiftUI

// MARK: - Onboarding components (SPEC §6)

// MARK: KeyCap (v3 §3.1) — replaces the outlined KeyHint

/// A filled keycap: 20 pt tall, a 20×20 square for one glyph, 6 of padding
/// for more. Return is always drawn as an icon, never the `↵` character.
struct KeyCap: View {
    enum Label: Equatable {
        case returnKey
        case text(String)
    }

    enum Context { case window, inButton, inButtonDisabled, small, smallDisabled }

    let label: Label
    var context: Context = .window

    init(_ label: Label, context: Context = .window) {
        self.label = label
        self.context = context
    }

    init(text: String, context: Context = .window) {
        self.init(.text(text), context: context)
    }

    private var isSmall: Bool { context == .small || context == .smallDisabled }
    private var inButton: Bool { context != .window }
    private var side: CGFloat { isSmall ? 18 : 20 }
    private var radius: CGFloat { isSmall ? 4 : 6 }

    var body: some View {
        withPalette { p in
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let (fill, ink) = colors(p)
            content
                .foregroundStyle(ink)
                .frame(minWidth: side, minHeight: side)
                .padding(.horizontal, singleGlyph || inButton ? 0 : 6)
                .frame(height: side)
                .background(shape.fill(fill))
                // inset 0 −1 0 black @ 40%: the cap's bottom lip, on the
                // window only (v3 §3.1).
                .overlay(context == .window ? AnyView(BottomLip(shape: shape, depth: 1, alpha: p.dark ? 0.4 : 0.12))
                                            : AnyView(EmptyView()))
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch label {
        case .returnKey:
            ReturnGlyph()
                .stroke(style: StrokeStyle(lineWidth: 2.4 * 12 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
        case .text(let text):
            Text(text).obFont(isSmall ? 10.5 : 11, 600)
        }
    }

    private var singleGlyph: Bool {
        if case .text(let text) = label { return text.count <= 1 }
        return true
    }

    private func colors(_ p: OBPalette) -> (Color, Color) {
        switch context {
        case .window:
            return p.dark ? (Color.white.opacity(0.10), Color.white.opacity(0.78))
                          : (p.ink(0.07), p.ink(0.70))
        case .inButton, .small:
            return p.dark ? (Color.black.opacity(0.08), Color.black.opacity(0.60))
                          : (Color.white.opacity(0.18), Color.white.opacity(0.85))
        case .inButtonDisabled, .smallDisabled:
            return (p.ink(0.06), p.ink(0.30))
        }
    }
}

/// `M19 5v6a3 3 0 0 1-3 3H6` and `M10 10l-4 4 4 4`, on a 24 grid.
struct ReturnGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(19, 5)); path.addLine(to: p(19, 11))
        path.addArc(center: p(16, 11), radius: 3 * s, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: p(6, 14))
        path.move(to: p(10, 10)); path.addLine(to: p(6, 14)); path.addLine(to: p(10, 18))
        return path
    }
}

/// CSS `inset 0 −depth 0 black`: a dark band along the shape's bottom edge.
struct BottomLip<S: Shape>: View {
    let shape: S
    let depth: CGFloat
    let alpha: Double
    var body: some View {
        shape.fill(Color.black.opacity(alpha))
            .mask(
                ZStack {
                    shape
                    shape.offset(y: -depth).blendMode(.destinationOut)
                }
                .compositingGroup()
            )
            .allowsHitTesting(false)
    }
}

// MARK: OttoButton (v3 §3.2)

struct OttoButton: View {
    enum Size { case regular, small }

    let title: String
    var key: KeyCap.Label = .returnKey
    var size: Size = .regular
    var isEnabled = true
    var isLoading = false
    /// Spoken with the label, since the keycap itself is hidden (§8).
    var shortcutDescription: String? = nil
    let action: () -> Void

    @State private var hover = false
    @State private var cursorPushed = false

    /// Not-allowed over a disabled button — pushed once, popped once.
    private func setBlockedCursor(_ blocked: Bool) {
        guard blocked != cursorPushed else { return }
        if blocked { NSCursor.operationNotAllowed.push() } else { NSCursor.pop() }
        cursorPushed = blocked
    }

    var body: some View {
        withPalette { p in
            Button(action: action) { label(p) }
                .buttonStyle(OttoPressStyle())
                .disabled(!isEnabled)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.35)) { hover = hovering && isEnabled }
                    setBlockedCursor(hovering && !isEnabled)
                }
                .onChange(of: isEnabled) { enabled in
                    if !enabled { hover = false }
                    if enabled { setBlockedCursor(false) }
                }
                .onDisappear { setBlockedCursor(false) }
                .animation(.easeInOut(duration: 0.2), value: isEnabled)
                .accessibilityLabel(shortcutDescription.map { "\(title), \($0)" } ?? title)
        }
    }

    private var regular: Bool { size == .regular }
    private var height: CGFloat { regular ? 30 : 24 }
    private var radius: CGFloat { regular ? 8 : 6 }

    @ViewBuilder
    private func label(_ p: OBPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: regular ? 8 : 7) {
            ZStack {
                // Loading keeps the width: the label stays, invisibly.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().controlSize(.small).scaleEffect(0.7) }
            }
            .obFont(regular ? 13 : 11.5, 600)
            .foregroundStyle(foreground(p))
            KeyCap(key, context: regular ? (isEnabled ? .inButton : .inButtonDisabled)
                                         : (isEnabled ? .small : .smallDisabled))
        }
        // 14 / 5: the gap around the keycap is the same on every side.
        .padding(.leading, regular ? 14 : 10)
        .padding(.trailing, regular ? 5 : 3)
        .frame(height: height)
        .background(
            ZStack {
                shape.fill(isEnabled ? p.buttonBG : p.ink(0.08))
                shape.fill(OBGradient.hover).opacity(hover ? 1 : 0)
            }
        )
        .contentShape(shape)
        .shadow(color: hover ? OBGradient.hoverGlow
                             : (isEnabled && !p.dark ? Color(obHex: 0x6B4CF6, alpha: 0.3) : .clear),
                radius: hover ? 11 : 7, x: 0, y: hover ? 0 : 4)
    }

    private func foreground(_ p: OBPalette) -> Color {
        if !isEnabled { return p.ink(0.35) }
        if hover { return Color(obHex: 0x111111) }
        return p.buttonFG
    }
}

/// Pressed = scale 0.97 over 80 ms (§6.1).
private struct OttoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: Back

struct OBBackButton: View {
    let action: () -> Void
    var body: some View {
        withPalette { p in
            Button(action: action) {
                Text(L10n.t("ob.back"))
                    .obFont(12, 500)
                    .foregroundStyle(p.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("ob.back") + ", \u{2318}[")
        }
    }
}

// MARK: Pill (§6.5)

struct OBPill<Leading: View>: View {
    let text: String
    let foreground: Color
    let background: Color
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 5) {
            leading
            Text(text).obFont(11.5, 500)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
        .fixedSize()
    }
}

// MARK: RadioCard (v3 §3.3) — replaces the checkbox option card

/// Transparent in both states: the selected card only gets a white stroke.
struct OBRadioCard: View {
    let title: String
    let caption: String
    let isSelected: Bool
    let keyNumber: Int
    let action: () -> Void

    var body: some View {
        withPalette { p in
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .strokeBorder(isSelected ? p.textPrimary : p.ink(0.3),
                                      lineWidth: isSelected ? 5 : 1.5)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).obFont(13.5, 600).foregroundStyle(p.textPrimary)
                        OBText(text: caption, size: 12, lineHeight: 16.8, color: p.ink(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(shape.strokeBorder(p.ink(isSelected ? 0.78 : 0.07), lineWidth: 1))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(caption), \(keyNumber)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

// MARK: Discover stepper (v3 §4.2)

struct OBDiscoverStepper: View {
    let current: DiscoverItem
    let select: (DiscoverItem) -> Void

    var body: some View {
        withPalette { p in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(DiscoverItem.allCases, id: \.self) { item in
                    Button { select(item) } label: { row(item, p) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("ob.discover.\(item)"))
                        .accessibilityAddTraits(item == current ? .isSelected : [])
                }
            }
        }
    }

    private func row(_ item: DiscoverItem, _ p: OBPalette) -> some View {
        let isCurrent = item == current
        let isDone = item.rawValue <= current.rawValue
        return HStack(alignment: isCurrent ? .top : .center, spacing: 12) {
            ZStack {
                if isDone {
                    Circle().fill(Color(obHex: 0x34C77B))
                    OBIconView(icon: .check, size: 10, color: Color(obHex: 0x06140C), lineWidth: 3.2)
                } else {
                    Circle().strokeBorder(p.ink(0.25), lineWidth: 1.5)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("ob.discover.\(item)"))
                    .obFont(14.5, isCurrent ? 600 : 500)
                    .foregroundStyle(isCurrent ? p.textPrimary : p.ink(isDone ? 0.55 : 0.4))
                if isCurrent {
                    OBText(text: L10n.t("ob.discover.\(item).caption"), size: 12.5,
                           lineHeight: 18.1, color: p.ink(0.55))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: Page dots (v3 §4.2)

struct OBPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        withPalette { p in
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(p.ink(index == current ? 0.85 : 0.25))
                        .frame(width: index == current ? 18 : 5, height: 5)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
        .accessibilityHidden(true)
    }
}

// MARK: Big keycap (v3 §4.4)

/// One of the three 62-pt caps on the shortcut step. Violet while waiting,
/// green once the shortcut has been seen; a held modifier brightens its cap.
struct OBKeycap: View {
    let symbol: String
    var success = false
    var held = false
    var popping = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // Dark: the v3 values. Light: Direction B's light keycap, tinted green
        // on success.
        let top = dark ? Color(obHex: success ? 0x1F3A2C : 0x2C2540) : .white
        let bottom = dark ? Color(obHex: success ? 0x13251C : 0x1A1627)
                          : Color(obHex: success ? 0xE3F7EB : 0xF0ECFF)
        let edge = success ? Color(obHex: dark ? 0x7FE3A8 : 0x1F9D5A, alpha: 0.7)
                           : Color(obHex: dark ? 0xC6B4FF : 0x7B6BFF, alpha: 0.7)
        let glow = success ? Color(obHex: 0x7FE3A8, alpha: 0.4) : Color(obHex: 0xC6B4FF, alpha: 0.4)
        return glyph
            .foregroundStyle(dark ? Color.white : Color(obHex: 0x2A2145))
            .frame(width: 62, height: 62)
            .background(shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.fill(Color.white.opacity(held ? 0.07 : 0)))
            // inset 0 −3 0 black @ 45%: the cap's bottom lip.
            .overlay(BottomLip(shape: shape, depth: 3, alpha: dark ? 0.45 : 0.08))
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
            .shadow(color: glow, radius: 11)
            .scaleEffect(popping ? 1.06 : 1)
            .accessibilityHidden(true)
    }

    /// Host Grotesk has no ⌃ or ⇧. The reference PNGs drew them with the
    /// browser's fallback — a small caret and a tall-stemmed arrow — and of
    /// the faces macOS ships, Arial Unicode MS is the one that matches
    /// (compared side by side, 2026-09-26). The system face if it is absent.
    @ViewBuilder
    private var glyph: some View {
        if symbol.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            Text(symbol).obFont(23, 600)
        } else if symbol == "\u{2303}" {
            // The caret alone is drawn small, heavy and high in the reference.
            Text(symbol).font(.system(size: 15, weight: .heavy)).offset(y: -3)
        } else if NSFont(name: "Arial Unicode MS", size: 23) != nil {
            // The face has one weight; two copies half a point apart give
            // the stroke the reference's heft.
            ZStack {
                Text(symbol).offset(x: -0.35)
                Text(symbol).offset(x: 0.35)
            }
            .font(.custom("Arial Unicode MS", size: 25))
        } else {
            Text(symbol).font(.system(size: 23, weight: .semibold))
        }
    }
}

// MARK: Toggle (§6.4)

struct OBSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        withPalette { p in
            Button(action: action) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? p.success : p.ink(0.16))
                    Circle().fill(.white)
                        .frame(width: 15, height: 15)
                        .padding(2)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                }
                .frame(width: 32, height: 19)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
        }
    }
}

// MARK: PermissionRow (§6.4)

struct OBPermissionRow<Trailing: View>: View {
    let icon: OBIcon
    let tint: Color
    let title: String
    let caption: String
    var highlighted = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        withPalette { p in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    OBIconView(icon: icon, size: 16, color: tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).obFont(13, 600).foregroundStyle(p.textPrimary)
                        // One line, always: the captions are short, and a
                        // wide trailing control ("Open Settings ↗") was
                        // breaking "Heads-up before meetings" in two.
                        Text(caption).obFont(11.5).foregroundStyle(p.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Spacer(minLength: 8)
                    trailing
                }
                .padding(.vertical, 11)
                .padding(.horizontal, highlighted ? 8 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(highlighted ? p.ink(0.035) : .clear)
                )
                .padding(.horizontal, highlighted ? -8 : 0)
                Rectangle().fill(p.divider).frame(height: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// "✓ Granted" — the neutral pill with a green check.
struct OBGrantedPill: View {
    @State private var pop = false
    var body: some View {
        withPalette { p in
            OBPill(text: L10n.t("ob.perm.granted"), foreground: p.ink(0.75),
                   background: p.ink(0.06)) {
                OBIconView(icon: .check, size: 12, color: p.success)
                    .scaleEffect(pop ? 1 : 0.3)
            }
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) { pop = true }
            }
        }
    }
}

/// "Open Settings ↗" for a permission that was already refused.
struct OBOpenSettingsPill: View {
    let action: () -> Void
    var body: some View {
        withPalette { p in
            Button(action: action) {
                OBPill(text: L10n.t("ob.perm.openSettings") + " \u{2197}", foreground: p.ink(0.75),
                       background: p.ink(0.06)) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }
}
