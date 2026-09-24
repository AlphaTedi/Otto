import SwiftUI

// MARK: - Onboarding components (SPEC §6)

// MARK: KeyHint (§6.2)

struct KeyHint: View {
    enum Context { case window, inButton, inButtonHover }

    let label: String
    var context: Context = .window

    var body: some View {
        withPalette { p in
            let (border, text) = colors(p)
            // CSS content-box, as the PNGs were rendered: a 16×16 minimum
            // content, 4 pt of padding each side, then the 1-pt border —
            // 26×18 for a single glyph.
            Text(label)
                .obFont(10, 500)
                .foregroundStyle(text)
                .frame(minWidth: 16, minHeight: 16)
                .padding(.horizontal, 4)
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(border, lineWidth: 1))
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private func colors(_ p: OBPalette) -> (Color, Color) {
        switch context {
        case .window:
            return (p.textPrimary.opacity(0.20), p.textPrimary.opacity(0.65))
        case .inButtonHover:
            return (Color.black.opacity(0.22), Color.black.opacity(0.55))
        case .inButton:
            return p.dark ? (Color.black.opacity(0.22), Color.black.opacity(0.55))
                          : (Color.white.opacity(0.30), Color.white.opacity(0.75))
        }
    }
}

// MARK: OttoButton (§6.1)

struct OttoButton: View {
    enum Size { case regular, small }
    enum Kind { case primary, secondary }

    let title: String
    var key: String? = "\u{21B5}"
    var size: Size = .regular
    var kind: Kind = .primary
    var isLoading = false
    /// Bumped from outside to pulse the button once (a saved to-do, §7.4).
    var pulse = 0
    /// Spoken with the label, since the key hint itself is hidden (§8).
    var shortcutDescription: String? = nil
    let action: () -> Void

    @State private var hover = false
    @State private var pulsing = false

    var body: some View {
        withPalette { p in
            Button(action: action) { label(p) }
                .buttonStyle(OttoPressStyle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.35)) { hover = hovering }
                }
                .scaleEffect(pulsing ? 1.06 : 1)
                .onChange(of: pulse) { _ in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pulsing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulsing = false }
                    }
                }
                .accessibilityLabel(shortcutDescription.map { "\(title), \($0)" } ?? title)
        }
    }

    private var height: CGFloat { size == .regular ? 30 : 24 }
    private var radius: CGFloat { size == .regular ? 8 : 6 }

    @ViewBuilder
    private func label(_ p: OBPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: 8) {
            ZStack {
                // Loading keeps the width: the label stays, invisibly.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().controlSize(.small).scaleEffect(0.7) }
            }
            .obFont(size == .regular ? 13 : 11.5, 600)
            .foregroundStyle(foreground(p))
            if let key {
                KeyHint(label: key,
                        context: hover ? .inButtonHover : (kind == .primary ? .inButton : .window))
            }
        }
        .padding(.leading, size == .regular ? 14 : 9)
        // 7 trailing even without a key hint: the reference's `.btn` keeps its
        // padding when the hint is absent ("Try it now").
        .padding(.trailing, size == .regular ? 7 : 5)
        .frame(height: height)
        .background(
            ZStack {
                shape.fill(fill(p))
                shape.fill(OBGradient.hover).opacity(hover ? 1 : 0)
            }
        )
        .overlay(kind == .secondary && !hover
                 ? shape.strokeBorder(p.ink(0.12), lineWidth: 1) : nil)
        .contentShape(shape)
        .shadow(color: hover ? OBGradient.hoverGlow
                             : (kind == .primary && !p.dark ? Color(obHex: 0x6B4CF6, alpha: 0.3) : .clear),
                radius: hover ? 11 : 7, x: 0, y: hover ? 0 : 4)
    }

    private func fill(_ p: OBPalette) -> Color {
        kind == .primary ? p.buttonBG : p.ink(0.08)
    }

    private func foreground(_ p: OBPalette) -> Color {
        if hover { return Color(obHex: 0x111111) }
        if kind == .secondary { return p.dark ? .white : p.textPrimary }
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

/// The green-check success pill ("Shortcut detected", "Nice, that's it").
struct OBSuccessPill: View {
    let text: String
    @State private var pop = false
    var body: some View {
        withPalette { p in
            OBPill(text: text, foreground: p.success,
                   background: Color(obHex: 0x8FE3B0, alpha: 0.1)) {
                OBIconView(icon: .check, size: 12, color: p.success)
                    .scaleEffect(pop ? 1 : 0.4)
            }
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55).delay(0.05)) { pop = true }
            }
        }
    }
}

// MARK: OptionCard (§6.3)

struct OBOptionCard: View {
    let title: String
    let caption: String
    let isSelected: Bool
    let keyNumber: Int
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        withPalette { p in
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    checkbox(p).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).obFont(13, 600).foregroundStyle(p.textPrimary)
                        OBText(text: caption, size: 12, color: p.ink(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(p.ink(isSelected ? 0.06 : (hover ? 0.05 : 0.025))))
                .overlay(shape.strokeBorder(p.ink(isSelected ? 0.22 : 0.07), lineWidth: 1))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { hover = hovering } }
            .accessibilityLabel("\(title), \(caption), \(keyNumber)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func checkbox(_ p: OBPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack {
            shape.fill(isSelected ? p.textPrimary : .clear)
            shape.strokeBorder(isSelected ? p.textPrimary : p.ink(0.3), lineWidth: 1.5)
            if isSelected {
                OBIconView(icon: .check, size: 11, color: p.window)
            }
        }
        // 16 of content inside a 1.5 border (CSS content-box).
        .frame(width: 19, height: 19)
    }
}

// MARK: Keycap (§6.6)

struct OBKeycap: View {
    let symbol: String
    let active: Bool

    var body: some View {
        withPalette { p in
            let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
            Text(symbol)
                .obFont(22, 600)
                .foregroundStyle(active ? Color(obHex: p.dark ? 0xFFFFFF : 0x2A2145)
                                        : p.textPrimary.opacity(0.6))
                // 58 of content plus the 1-pt border (CSS content-box).
                .frame(width: 60, height: 60)
                .background(
                    ZStack {
                        shape.fill(p.keycapIdle)
                        shape.fill(LinearGradient(
                            colors: p.dark ? [Color(obHex: 0x2C2540), Color(obHex: 0x1A1627)]
                                           : [.white, Color(obHex: 0xF0ECFF)],
                            startPoint: .top, endPoint: .bottom))
                            .opacity(active ? 1 : 0)
                    }
                )
                // inset 0 −3 0 black @ 45%: the cap's bottom lip.
                .overlay(
                    shape.fill(Color.black.opacity(0.45))
                        .mask(
                            ZStack {
                                shape
                                shape.offset(y: -3).blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        )
                        .opacity(active ? 1 : 0)
                )
                .overlay(shape.strokeBorder(active ? Color(obHex: 0xC6B4FF, alpha: 0.65) : p.divider,
                                            lineWidth: 1))
                .shadow(color: active ? Color(obHex: 0xC6B4FF, alpha: 0.4) : .clear, radius: 11)
                .accessibilityHidden(true)
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
                        Text(caption).obFont(11.5).foregroundStyle(p.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
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
