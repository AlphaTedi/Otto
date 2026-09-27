import SwiftUI

// MARK: - Onboarding steps (v3 SPEC §4)
//
// Each step is two pieces: the left column's content (under the title and
// body the flow draws) and the right-hand visual panel. The flow owns layout,
// transitions and the footer; these own only what differs per step. The
// panels' mock product UI lives in OnboardingPreviews.swift.

// MARK: Copy

extension OnboardingStep {
    var title: String {
        switch self {
        case .welcome: return ""
        case .discover: return L10n.t("ob.discover.title")
        case .style: return L10n.t("ob.style.title")
        case .shortcut: return L10n.t("ob.shortcut.title")
        case .permissions: return L10n.t("ob.perm.title")
        case .done: return L10n.t("ob.done.title")
        }
    }

    var body: String {
        switch self {
        case .welcome: return L10n.t("ob.welcome.tagline")
        case .discover: return L10n.t("ob.discover.body")
        case .style: return L10n.t("ob.style.body")
        case .shortcut: return L10n.t("ob.shortcut.body")
        case .permissions: return L10n.t("ob.perm.body")
        case .done: return L10n.t("ob.done.body")
        }
    }

    var primaryTitle: String {
        switch self {
        case .welcome: return L10n.t("ob.start")
        case .discover: return L10n.t("ob.next")
        case .done: return L10n.t("ob.openOtto")
        default: return L10n.t("ob.continue")
        }
    }
}

/// The panel's glows (Direction B §5.2, v3 values from the reference HTML).
@MainActor
func onboardingGlows(_ model: OnboardingModel) -> [OBGlow] {
    let faintViolet = OBGlow(hue: .violet, x: 0.50, y: 1.15, rx: 420, ry: 220, alpha: 0.15)
    switch model.step {
    case .welcome:
        return [OBGlow(hue: .violet, x: 0.50, y: 1.15, rx: 620, ry: 420, alpha: 0.55),
                OBGlow(hue: .pink, x: 0.30, y: 1.20, rx: 420, ry: 300, alpha: 0.22),
                OBGlow(hue: .amber, x: 0.72, y: 1.25, rx: 380, ry: 260, alpha: 0.16)]
    case .discover:
        // Amber on Meetings only (v3 §4.2).
        return [OBGlow(hue: model.discoverItem == .meetings ? .amber : .violet,
                       x: 0.50, y: 0.00, rx: 460, ry: 320, alpha: 0.50),
                faintViolet]
    case .style:
        return [OBGlow(hue: .violet, x: 0.50, y: model.displayMode == .notch ? 0.00 : 0.50,
                       rx: 460, ry: 320, alpha: 0.50)]
    case .shortcut:
        return model.shortcutDetected
            ? [OBGlow(hue: .green, x: 0.50, y: 0.45, rx: 460, ry: 320, alpha: 0.50),
               OBGlow(hue: .teal, x: 0.50, y: 1.15, rx: 420, ry: 220, alpha: 0.25)]
            : [OBGlow(hue: .violet, x: 0.50, y: 0.45, rx: 420, ry: 300, alpha: 0.50),
               OBGlow(hue: .pink, x: 0.50, y: 1.10, rx: 400, ry: 220, alpha: 0.20)]
    case .permissions:
        return [OBGlow(hue: .violet, x: 0.50, y: 0.50, rx: 380, ry: 300, alpha: 0.45),
                OBGlow(hue: .amber, x: 0.50, y: 1.15, rx: 420, ry: 240, alpha: 0.20)]
    case .done:
        return [OBGlow(hue: .violet, x: 0.50, y: 0.60, rx: 420, ry: 340, alpha: 0.60),
                OBGlow(hue: .pink, x: 0.35, y: 1.10, rx: 300, ry: 220, alpha: 0.30),
                OBGlow(hue: .amber, x: 0.70, y: 1.15, rx: 300, ry: 220, alpha: 0.22)]
    }
}

// MARK: 1 · Welcome (§7.1)

struct WelcomeStepView: View {
    @ObservedObject var model: OnboardingModel
    let primary: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = [false, false, false]

    var body: some View {
        withPalette { p in
            ZStack {
                OBGlowBackground(glows: onboardingGlows(model))
                VStack(spacing: 22) {
                    OttoLogo(width: 190, color: p.logo)
                        .scaleEffect(shown[0] || reduceMotion ? 1 : 0.96)
                        .opacity(shown[0] ? 1 : 0)
                    OBText(text: OnboardingStep.welcome.body, size: 17, lineHeight: 24.65,
                           alignment: .center, color: p.textPrimary.opacity(0.62))
                        .frame(width: 380)
                        .opacity(shown[1] ? 1 : 0)
                    OttoButton(title: OnboardingStep.welcome.primaryTitle,
                               shortcutDescription: "Return", action: primary)
                        .padding(.top, 6)
                        .opacity(shown[2] ? 1 : 0)
                }
            }
            .onAppear {
                // Logo, then the tagline 80 ms later, then the button.
                for index in 0..<3 {
                    withAnimation(.easeOut(duration: 0.5).delay(Double(index) * 0.08)) {
                        shown[index] = true
                    }
                }
            }
        }
    }
}

// MARK: 2 · Discover (v3 §4.2)

struct DiscoverStepContent: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        OBDiscoverStepper(current: model.discoverItem) { model.show($0) }
    }
}

struct DiscoverPanel: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch model.discoverItem {
                case .tasks: NotchTasksPreview()
                case .notes: NotePreview()
                case .meetings: MeetingPreview()
                }
            }
            .id(model.discoverItem)
            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack {
                Spacer()
                OBPageDots(count: DiscoverItem.allCases.count, current: model.discoverItem.rawValue)
                    .padding(.bottom, 26)
            }
        }
        .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
    }
}

// MARK: 3 · Style (v3 §4.3)

struct StyleStepContent: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        withPalette { p in
            VStack(alignment: .leading, spacing: 8) {
                OBRadioCard(title: L10n.t("ob.style.notch"), caption: L10n.t("ob.style.notch.caption"),
                            isSelected: model.displayMode == .notch, keyNumber: 1) { model.select(.notch) }
                OBRadioCard(title: L10n.t("ob.style.floating"), caption: L10n.t("ob.style.floating.caption"),
                            isSelected: model.displayMode == .floating, keyNumber: 2) { model.select(.floating) }
                Text(L10n.t("ob.style.footnote"))
                    .obFont(11.5)
                    .foregroundStyle(p.ink(0.4))
                    .padding(.top, 4)
            }
        }
    }
}

struct StylePanel: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack {
            // Cross-fade and re-play the newcomer's entrance (v3 §4.3).
            Group {
                if model.displayMode == .notch { NotchStylePreview() } else { FloatingStylePreview() }
            }
            .id(model.displayMode)
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
        .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
        .accessibilityHidden(true)
    }
}

// MARK: 4 · Shortcut (v3 §4.4)

/// No content under the body any more; the one exception is the way past a
/// shortcut this Mac cannot deliver.
struct ShortcutStepContent: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        withPalette { p in
            if !model.shortcutDetected && !HotkeyManager.shared.quickEntryRegistered {
                Button { model.skipShortcut() } label: {
                    Text(L10n.t("ob.shortcut.fallback"))
                        .obFont(12, 500)
                        .foregroundStyle(p.ink(0.55))
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("ob.shortcut.fallback") + ", \u{2318}\u{2192}")
            }
        }
    }
}

struct ShortcutPanel: View {
    @ObservedObject var model: OnboardingModel

    private var symbols: [String] { HotkeyManager.quickEntryDisplay.map(String.init) }

    var body: some View {
        withPalette { p in content(p) }
    }

    private func content(_ p: OBPalette) -> some View {
        VStack(spacing: 26) {
            HStack(spacing: 10) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    OBKeycap(symbol: symbol,
                             success: model.shortcutDetected,
                             held: (index == 0 && model.controlHeld) || (index == 1 && model.shiftHeld),
                             popping: model.heldKey == index)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("ob.shortcut.keysLabel"))

            ZStack {
                if model.shortcutDetected {
                    HStack(spacing: 8) {
                        OBIconView(icon: .check, size: 15, color: p.dark ? Color(obHex: 0x7FE3A8) : p.success,
                                   lineWidth: 2.4)
                        Text(L10n.t("ob.shortcut.gotIt")).obFont(13.5, 600)
                            .foregroundStyle(p.dark ? Color(obHex: 0x9BF0BF) : p.success)
                    }
                    .transition(.opacity)
                } else {
                    Text(L10n.t("ob.shortcut.press"))
                        .obFont(13.5)
                        .tracking(0.135)
                        .foregroundStyle(p.ink(0.5))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: model.shortcutDetected)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: 5 · Permissions (§7.5)

struct PermissionsStepContent: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var permissions: PermissionsModel

    var body: some View {
        withPalette { p in
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    calendarRow(p)
                    loginRow(p)
                    usageRow(p)
                }
                if let summary = permissions.calendarSummary {
                    Text(summary)
                        .obFont(11.5)
                        .foregroundStyle(p.textTertiary)
                        .lineLimit(2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: permissions.calendar)
        }
    }

    private func calendarRow(_ p: OBPalette) -> some View {
        OBPermissionRow(icon: .calendar, tint: p.amber,
                        title: L10n.t("ob.perm.calendar"),
                        caption: L10n.t("ob.perm.calendar.caption")) {
            switch permissions.calendar {
            case .granted:
                OBGrantedPill().transition(.opacity)
            case .denied:
                OBOpenSettingsPill { permissions.openSettings() }.transition(.opacity)
            case .notDetermined:
                // G grants the first row still waiting for a grant (v3 §4.5).
                OttoButton(title: L10n.t("ob.perm.grant"), key: .text("G"), size: .small,
                           isLoading: permissions.calendarBusy, shortcutDescription: "G") {
                    permissions.grantCalendar()
                }
                .transition(.opacity)
            }
        }
    }

    /// Anonymous usage data (docs/TELEMETRY.md): on by default (Marcello,
    /// 2026-09-27), recorded when the flow finishes. `U` toggles it.
    private func usageRow(_ p: OBPalette) -> some View {
        OBPermissionRow(icon: .bolt, tint: p.violet,
                        title: L10n.t("ob.perm.usage"),
                        caption: L10n.t("ob.perm.usage.caption")) {
            OBSwitch(isOn: model.shareUsage) { model.setShareUsage(!model.shareUsage) }
                .accessibilityLabel(L10n.t("ob.perm.usage") + ", U")
                .accessibilityValue(model.shareUsage ? "on" : "off")
        }
    }

    private func loginRow(_ p: OBPalette) -> some View {
        OBPermissionRow(icon: .power, tint: p.pink,
                        title: L10n.t("ob.perm.login"),
                        caption: L10n.t("ob.perm.login.caption")) {
            OBSwitch(isOn: permissions.loginEnabled) {
                permissions.setLogin(!permissions.loginEnabled)
            }
            .accessibilityLabel(L10n.t("ob.perm.login") + ", L")
            .accessibilityValue(permissions.loginEnabled ? "on" : "off")
        }
    }
}

struct PermissionsPanel: View {
    @ObservedObject var permissions: PermissionsModel

    @ObservedObject var model: OnboardingModel

    /// A point on a ring centred in the panel; 0° is 3 o'clock, clockwise.
    static func onRing(radius: CGFloat, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: OBMetric.panelSize.width / 2 + radius * cos(a),
                       y: OBMetric.panelSize.height / 2 + radius * sin(a))
    }

    var body: some View {
        withPalette { p in
            ZStack {
                Circle().strokeBorder(p.ink(0.07), lineWidth: 1).frame(width: 302, height: 302)
                Circle().strokeBorder(p.ink(0.09), lineWidth: 1).frame(width: 222, height: 222)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(obHex: 0x7C5CFF), Color(obHex: 0x3B2A8A)],
                                         startPoint: UnitPoint(x: 0.33, y: 0.03),
                                         endPoint: UnitPoint(x: 0.67, y: 0.97)))
                    .overlay(
                        // inset 0 1 0 white @ 25%: the tile's top edge catching light.
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            .mask(LinearGradient(colors: [.white, .clear],
                                                 startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)))
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Color(obHex: 0x7C5CFF, alpha: 0.45), radius: 25, y: 20)
                    .overlay(OttoLogo(width: 68, color: .white))
                // ON the rings, centred on their strokes (they were placed
                // by the design's pixel offsets and floated off them).
                PermissionChip(icon: .calendar, tint: p.amber, granted: permissions.calendar == .granted)
                    .position(Self.onRing(radius: 150, degrees: -90))
                PermissionChip(icon: .power, tint: p.pink, granted: permissions.loginEnabled)
                    .position(Self.onRing(radius: 150, degrees: 155))
                PermissionChip(icon: .bolt, tint: p.violet, granted: model.shareUsage)
                    .position(Self.onRing(radius: 110, degrees: -20))
            }
            .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
            .accessibilityHidden(true)
        }
    }
}

private struct PermissionChip: View {
    let icon: OBIcon
    let tint: Color
    let granted: Bool
    @State private var pulse = false

    var body: some View {
        withPalette { p in
            let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
            OBIconView(icon: icon, size: 16, color: tint)
                .frame(width: 40, height: 40)
                .background(shape.fill(p.dark ? Color(obHex: 0x15131C) : .white))
                .overlay(shape.strokeBorder(granted ? p.success : p.ink(0.1),
                                            lineWidth: granted ? 1.5 : 1))
                .scaleEffect(pulse ? 1.12 : 1)
                .onChange(of: granted) { isGranted in
                    guard isGranted else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pulse = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { pulse = false }
                    }
                }
        }
    }
}

// MARK: 6 · Done (v3 §4.6)

struct DoneStepContent: View {
    var body: some View {
        withPalette { p in
            VStack(spacing: 8) {
                row(L10n.t("ob.done.add"), HotkeyManager.quickEntryDisplay, p)
                row(L10n.t("ob.done.search"), "type", p)
                row(L10n.t("ob.done.shortcuts"), "?", p)
            }
        }
    }

    private func row(_ text: String, _ key: String, _ p: OBPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(text).obFont(12.5).foregroundStyle(p.ink(0.75))
                Spacer()
                KeyCap(text: key)
            }
            .padding(.vertical, 7)
            Rectangle().fill(p.divider).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), \(key)")
    }
}

struct DonePanel: View {
    var body: some View {
        withPalette { p in
            ZStack {
                OBConfetti()
                OttoLogo(width: 170, color: p.logo)
            }
            .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
        }
    }
}
