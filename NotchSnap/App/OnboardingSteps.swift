import SwiftUI

// MARK: - Onboarding steps (SPEC §7)
//
// Each step is two pieces: the left column's content (under the title and
// body the flow draws) and the right-hand visual panel. The flow owns layout,
// transitions and the footer; these own only what differs per step.

// MARK: Copy

extension OnboardingStep {
    var title: String {
        switch self {
        case .welcome: return ""
        case .focus: return L10n.t("ob.focus.title")
        case .notch: return L10n.t("ob.notch.title")
        case .shortcut: return L10n.t("ob.shortcut.title")
        case .permissions: return L10n.t("ob.perm.title")
        case .done: return L10n.t("ob.done.title")
        }
    }

    var body: String {
        switch self {
        case .welcome: return L10n.t("ob.welcome.tagline")
        case .focus: return L10n.t("ob.focus.body")
        case .notch: return L10n.t("ob.notch.body")
        case .shortcut: return L10n.t("ob.shortcut.body")
        case .permissions: return L10n.t("ob.perm.body")
        case .done: return L10n.t("ob.done.body")
        }
    }

    var primaryTitle: String {
        switch self {
        case .welcome: return L10n.t("ob.start")
        case .done: return L10n.t("ob.openOtto")
        default: return L10n.t("ob.continue")
        }
    }

    /// §5.2 — the panel's (or, for welcome, the window's) glows.
    var glows: [OBGlow] {
        switch self {
        case .welcome:
            return [OBGlow(hue: .violet, x: 0.50, y: 1.15, rx: 620, ry: 420, alpha: 0.55),
                    OBGlow(hue: .pink, x: 0.30, y: 1.20, rx: 420, ry: 300, alpha: 0.22),
                    OBGlow(hue: .amber, x: 0.72, y: 1.25, rx: 380, ry: 260, alpha: 0.16)]
        case .focus:
            return [OBGlow(hue: .violet, x: 0.50, y: 1.00, rx: 520, ry: 380, alpha: 0.60),
                    OBGlow(hue: .pink, x: 0.85, y: 1.10, rx: 300, ry: 240, alpha: 0.28)]
        case .notch:
            return [OBGlow(hue: .violet, x: 0.50, y: 0.00, rx: 460, ry: 320, alpha: 0.55),
                    OBGlow(hue: .amber, x: 0.50, y: 1.10, rx: 500, ry: 260, alpha: 0.14)]
        case .shortcut:
            return [OBGlow(hue: .violet, x: 0.50, y: 0.45, rx: 420, ry: 300, alpha: 0.50),
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
                OBGlowBackground(glows: OnboardingStep.welcome.glows)
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

// MARK: 2 · Focus (§7.2)

struct FocusStepContent: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(OnboardingFocus.allCases.enumerated()), id: \.element) { index, choice in
                OBOptionCard(title: L10n.t("ob.focus.\(choice.rawValue)"),
                             caption: L10n.t("ob.focus.\(choice.rawValue).caption"),
                             isSelected: model.focus == choice,
                             keyNumber: index + 1) {
                    model.selectFocus(choice)
                }
            }
        }
    }
}

/// A black notch panel that shows what the chosen focus puts in it.
struct FocusPanel: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        withPalette { p in
            VStack(alignment: .leading, spacing: 9) {
                if model.focus != .tasks {
                    ForEach(meetings.prefix(model.focus == .meetings ? 3 : 1)) { meeting in
                        MeetingChip(title: meeting.title, time: meeting.time)
                            .transition(.opacity)
                    }
                }
                if model.focus != .meetings {
                    ForEach(todos, id: \.self) { title in
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                            Text(title).obFont(12.5).lineLimit(1)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .foregroundStyle(Color(obHex: 0xF2F1F5))
            .padding(.top, 14)
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
            .frame(width: 300, alignment: .leading)
            .background(UnevenRoundedRect(topLeading: 0, bottomLeading: 20,
                                          bottomTrailing: 20, topTrailing: 0).fill(.black))
            .overlay(UnevenRoundedRect(topLeading: 0, bottomLeading: 20,
                                       bottomTrailing: 20, topTrailing: 0)
                .stroke(p.ink(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.25), value: model.focus)
        }
    }

    /// Real data where there is some; neutral examples otherwise (§12).
    private var todos: [String] {
        let real = store.items.filter { !$0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(3).map(\.title)
        return real.isEmpty ? ["ob.sample.todo1", "ob.sample.todo2", "ob.sample.todo3"].map(L10n.t) : Array(real)
    }

    private struct Meeting: Identifiable {
        let id: String
        let title: String
        let time: String
    }

    private var meetings: [Meeting] {
        let real = calendar.upcomingToday.prefix(3).map {
            Meeting(id: $0.id, title: $0.title,
                    time: $0.start.formatted(date: .omitted, time: .shortened))
        }
        return real.isEmpty
            ? [Meeting(id: "a", title: L10n.t("ob.sample.meeting1"), time: "14:00"),
               Meeting(id: "b", title: L10n.t("ob.sample.meeting2"), time: "16:30")]
            : Array(real)
    }
}

private struct MeetingChip: View {
    let title: String
    let time: String

    var body: some View {
        withPalette { p in
            HStack(spacing: 8) {
                OBIconView(icon: .calendar, size: 13, color: p.amber)
                Text(title).lineLimit(1)
                Spacer(minLength: 6)
                Text(time)
            }
            .obFont(12)
            .foregroundStyle(Color(obHex: 0xFFD9AD))
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(obHex: 0xFFBE78, alpha: p.dark ? 0.13 : 0.078)))
        }
    }
}

// MARK: 3 · Notch (§7.3)

struct NotchStepContent: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        withPalette { p in
            VStack(alignment: .leading, spacing: 7) {
                hint("hover", L10n.t("ob.notch.hover"))
                hint("click", L10n.t("ob.notch.click"))
                hint("?", L10n.t("ob.notch.shortcuts"))
                if model.notchTried {
                    OBSuccessPill(text: L10n.t("ob.notch.success"))
                        .padding(.top, 7)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
            .obFont(12)
            .foregroundStyle(p.ink(0.55))
        }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            KeyHint(label: key)
            Text(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key) \(text)")
    }
}

struct NotchDemoPanel: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        withPalette { p in
            ZStack(alignment: .top) {
                if reduceMotion {
                    scene(p, t: nil)
                } else {
                    TimelineView(.animation) { context in
                        let seconds = context.date.timeIntervalSinceReferenceDate
                        scene(p, t: seconds.truncatingRemainder(dividingBy: 3) / 3)
                    }
                }
                VStack {
                    Spacer()
                    OttoButton(title: model.notchArmed ? L10n.t("ob.notch.armed") : L10n.t("ob.notch.try"),
                               key: nil, kind: .secondary) { model.armNotch() }
                        .padding(.bottom, 28)
                }
            }
        }
    }

    /// One frame of the 3 s loop: the cursor climbs into the notch and the
    /// notch opens around it. `t == nil` is the still frame of the PNG.
    private func scene(_ p: OBPalette, t: Double?) -> some View {
        func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        let climb = t.map { ease(($0 - 0.05) / 0.45) } ?? 0
        let open = t.map { ease(($0 - 0.5) / 0.12) - ease(($0 - 0.84) / 0.12) } ?? 0
        let cursorOpacity = t.map { $0 < 0.05 ? $0 / 0.05 : ($0 > 0.86 ? max(0, (0.96 - $0) / 0.1) : 1) } ?? 1
        let width = 170 + 60 * open
        let height = 30 + 16 * open

        return ZStack(alignment: .topLeading) {
            Color.clear
            UnevenRoundedRect(topLeading: 0, bottomLeading: 14, bottomTrailing: 14, topTrailing: 0)
                .fill(.black)
                .overlay(UnevenRoundedRect(topLeading: 0, bottomLeading: 14, bottomTrailing: 14, topTrailing: 0)
                    .stroke(p.ink(0.08), lineWidth: 1))
                .frame(width: width, height: height)
                .shadow(color: Color(obHex: 0xC6B4FF, alpha: 0.45), radius: 20)
                .position(x: 245, y: height / 2)
            VStack(spacing: 4) {
                ForEach([0.2, 0.35, 0.55, 0.8], id: \.self) { alpha in
                    Circle().fill(p.ink(alpha)).frame(width: 4, height: 4)
                }
            }
            .opacity(1 - open)
            .position(x: 245, y: 44 + 14)
            CursorShape()
                .fill(.white)
                .overlay(CursorShape().stroke(.black, lineWidth: 1.2 * 22 / 24))
                .frame(width: 22, height: 22)
                .opacity(cursorOpacity)
                .position(x: 246 + 11, y: 84 + 11 + (t == nil ? 0 : 60 - 110 * climb))
        }
        .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
        .accessibilityHidden(true)
    }
}

private struct CursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 5 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 11 * s))
        path.addLine(to: CGPoint(x: 13 * s, y: 13 * s))
        path.addLine(to: CGPoint(x: 10 * s, y: 19 * s))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

// MARK: 4 · Shortcut (§7.4)

struct ShortcutStepContent: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.shortcutDetected {
                OBSuccessPill(text: L10n.t("ob.shortcut.detected"))
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
    }
}

struct ShortcutPanel: View {
    @ObservedObject var model: OnboardingModel
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        withPalette { p in
            VStack(spacing: 26) {
                HStack(spacing: 10) {
                    OBKeycap(symbol: "\u{2303}", active: model.controlHeld)
                    OBKeycap(symbol: "\u{21E7}", active: model.shiftHeld)
                    OBKeycap(symbol: "N", active: model.nHeld)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("ob.shortcut.keysLabel"))

                HStack(spacing: 9) {
                    OBIconView(icon: .circle, size: 14, color: Color(obHex: 0x777777))
                    TextField("", text: $text,
                              prompt: Text(L10n.t("ob.shortcut.placeholder"))
                                .foregroundColor(p.textPrimary.opacity(0.4)))
                        .textFieldStyle(.plain)
                        .obFont(13)
                        .foregroundStyle(p.textPrimary)
                        .focused($fieldFocused)
                        .onSubmit(submit)
                    KeyHint(label: "\u{21B5}")
                }
                .frame(width: 300)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .padding(1)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(p.dark ? Color.black : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(p.dark ? Color(obHex: 0xC6B4FF, alpha: 0.4)
                                         : Color(obHex: 0x7B6BFF, alpha: 0.45), lineWidth: 1))
                .shadow(color: p.dark ? .clear : Color(obHex: 0x503CA0, alpha: 0.12), radius: 12, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.fieldFocusRequest) { _ in fieldFocused = true }
        }
    }

    private func submit() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty ↵ is the step's own ↵: carry on.
        guard !title.isEmpty else { fieldFocused = false; model.advance(); return }
        if model.saveFirstTodo(title) {
            text = ""
            // Give ↵ back to the window, so the next press continues.
            fieldFocused = false
        }
    }
}

// MARK: 5 · Permissions (§7.5)

struct PermissionsStepContent: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var permissions: PermissionsModel
    @ObservedObject private var calendarStore = CalendarStore.shared

    var body: some View {
        withPalette { p in
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    calendarRow(p)
                    loginRow(p)
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
                        caption: String(format: L10n.t("ob.perm.calendar.caption"),
                                        calendarStore.alertLeadMinutes),
                        highlighted: model.focus == .meetings) {
            switch permissions.calendar {
            case .granted:
                OBGrantedPill().transition(.opacity)
            case .denied:
                OBOpenSettingsPill { permissions.openSettings() }.transition(.opacity)
            case .notDetermined:
                OttoButton(title: L10n.t("ob.perm.grant"), key: "C", size: .small,
                           isLoading: permissions.calendarBusy, shortcutDescription: "C") {
                    permissions.grantCalendar()
                }
                .transition(.opacity)
            }
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
                PermissionChip(icon: .calendar, tint: p.amber, granted: permissions.calendar == .granted)
                    .position(x: 226 + 20, y: 44 + 20)
                PermissionChip(icon: .power, tint: p.pink, granted: permissions.loginEnabled)
                    .position(x: 92 + 20, y: 268 + 20)
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

// MARK: 6 · Done (§7.6)

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
                KeyHint(label: key)
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
            OttoLogo(width: 170, color: p.logo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
