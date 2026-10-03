import EventKit
import ServiceManagement
import SwiftUI

// MARK: - Settings — Direction A, glass-first (SETTINGS_REDESIGN_SPEC, 2026-10-01)
//
// Stock parts only: NavigationSplitView + a `.sidebar` List with three
// Sections, and a grouped `Form` per page. The split view and the form bring
// their own materials — Liquid Glass on macOS 26 — so nothing here draws a
// card, a blur or a text colour of its own. The only custom drawing is where
// macOS has no equivalent: the icon tiles and the layout / theme thumbnails,
// and even those sit inside Buttons so they keep keyboard and VoiceOver.
//
// Second pass the same day (Marcello, against System Settings itself): the
// system accent, not a teal of our own; the page title lives in the toolbar
// beside ← → history arrows, not as a header inside the page; a search field
// heads the sidebar; and every control is centred on its row — Form aligns a
// control to its label's FIRST line, which left segmented pickers and menus
// riding high beside a two-line label, so rows are `SettingRow` now.
//
// Icons are Lucide through OttoIcon, not SF Symbols as the spec's table says:
// the whole app is one icon family since 2026-09-27, and Settings is part of
// the app. The symbol NAMES are the spec's; OttoIcon maps them.
//
// Every value reads and writes the same key as before (notchsnap.settings,
// notchLayout, notchExpandedWidth/Height, notchCornerRadius,
// showNotchPresence, soundEffectsEnabled, hapticFeedback, L10n.storageKey and
// CalendarStore's own), so an upgrade keeps what the user had.

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SettingsSection = .general
    @State private var query = ""
    /// ← → like System Settings: pages visited, and pages stepped back from.
    @State private var back: [SettingsSection] = []
    @State private var forward: [SettingsSection] = []
    /// Set while a history arrow is moving the selection, so that move is not
    /// itself recorded as a visit.
    @State private var steppingHistory = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, query: query)
                .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            page(for: selection)
                .id(selection)
                .transition(.opacity)
                .navigationTitle(selection.title)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        // SF Symbols here on purpose: these are System
                        // Settings' own arrows (Marcello, 2026-10-02).
                        Button { step(&back, &forward) } label: { Image(systemName: "chevron.left") }
                            .disabled(back.isEmpty)
                            .help("Back")
                            .accessibilityLabel("Back")
                        Button { step(&forward, &back) } label: { Image(systemName: "chevron.right") }
                            .disabled(forward.isEmpty)
                            .help("Forward")
                            .accessibilityLabel("Forward")
                    }
                }
        }
        .animation(reduceMotion ? nil : NotchAnimation.contentIn, value: selection)
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        .environmentObject(appState)
        .onChange(of: selection) { [selection] _ in
            // `selection` in the capture list is the value BEFORE the change.
            guard !steppingHistory else { steppingHistory = false; return }
            back.append(selection)
            forward.removeAll()
        }
        // SU-6: the Today nudge card deep-links straight to the Calendar pane.
        .onChange(of: appState.pendingSettingsSection) { requested in
            guard let requested else { return }
            selection = requested
            appState.pendingSettingsSection = nil
        }
        .onAppear {
            if let requested = appState.pendingSettingsSection {
                selection = requested
                appState.pendingSettingsSection = nil
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
        }
    }

    /// Pop a page off `from`, remember the current one on `to`.
    private func step(_ from: inout [SettingsSection], _ to: inout [SettingsSection]) {
        guard let target = from.popLast() else { return }
        to.append(selection)
        steppingHistory = true
        selection = target
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .general:     GeneralSettingsView()
        case .appearance:  AppearanceSettingsView()
        case .opening:     OpeningSettingsView()
        case .shortcuts:   ShortcutsSettingsView()
        case .calendar:    CalendarSettingsView()
        case .storage:     StorageSettingsView()
        case .permissions: PermissionsSettingsView()
        case .privacy:     PrivacySettingsView()
        case .meetingLab:  MeetingLabSettingsView()
        case .about:       AboutSettingsView()
        }
    }
}

/// The sidebar: three groups, a tile per page, the Permissions warning.
/// A query narrows it to the pages whose title or settings match.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    var query: String = ""
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsGroup.allCases) { group in
                let sections = group.sections.filter { $0.matches(query) }
                if !sections.isEmpty {
                    // No group titles: the gap between the groups is the
                    // separation (Marcello, 2026-10-01).
                    Section {
                        ForEach(sections) { section in
                            Label {
                                HStack {
                                    Text(section.title)
                                    Spacer()
                                    if section == .permissions, SettingsPermissions.needsAttention(calendar) {
                                        OttoIcon("exclamationmark.triangle.fill", pointSize: 11)
                                            .foregroundStyle(.orange)
                                            .accessibilityLabel("Needs attention")
                                    }
                                }
                            } icon: {
                                SettingsIconTile(section: section)
                            }
                            .tag(section)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Information architecture

enum SettingsGroup: String, CaseIterable, Identifiable {
    case otto, connections, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .otto:        return "Otto"
        case .connections: return "Connections"
        case .system:      return "System"
        }
    }

    var sections: [SettingsSection] {
        switch self {
        case .otto:        return [.general, .appearance, .opening, .shortcuts]
        case .connections: return [.calendar, .storage]
        case .system:
            // The lab only exists where fake meetings are allowed.
            return [.permissions, .privacy] + (CalendarStore.labEnabled ? [.meetingLab] : []) + [.about]
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, opening, shortcuts
    case calendar, storage
    case permissions, privacy, meetingLab, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .appearance:  return "Appearance"
        case .opening:     return "Opening"
        case .shortcuts:   return "Shortcuts"
        case .calendar:    return "Calendar & Meetings"
        case .storage:     return "Storage"
        case .permissions: return "Permissions"
        case .privacy:     return "Privacy"
        case .meetingLab:  return "Meeting Lab"
        case .about:       return "About"
        }
    }

    /// What the search field finds a page by, besides its title.
    private var keywords: [String] {
        switch self {
        case .general:     return ["launch", "login", "dock", "language", "sound", "haptic"]
        case .appearance:  return ["layout", "notch", "floating", "panels", "theme", "dark", "light", "size", "presence"]
        case .opening:     return ["hover", "click", "delay", "auto-close", "menu bar", "restore", "defaults"]
        case .shortcuts:   return ["keyboard", "hotkey", "keys"]
        case .calendar:    return ["meeting", "alert", "snooze", "account", "calendars", "disconnect", "refresh"]
        case .storage:     return ["markdown", "folder", "finder", "obsidian", "files", "vault"]
        case .permissions: return ["access", "calendar", "sync", "internet accounts", "privacy & security"]
        case .privacy:     return ["usage", "data", "analytics", "anonymous", "id"]
        case .meetingLab:  return ["test", "fake", "meeting", "alert", "debug", "simulate"]
        case .about:       return ["version", "update", "onboarding", "feedback"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return title.lowercased().contains(q) || keywords.contains { $0.contains(q) }
    }

    /// SF Symbol names, drawn as Lucide by OttoIcon. About draws the logo.
    var icon: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .appearance:  return "paintpalette.fill"
        case .opening:     return "cursorarrow.rays"
        case .shortcuts:   return "keyboard"
        case .calendar:    return "calendar"
        case .storage:     return "folder.fill"
        case .permissions: return "checkmark.shield.fill"
        case .privacy:     return "lock.fill"
        case .meetingLab:  return "video.fill"
        case .about:       return ""
        }
    }

    /// The tile's gradient, top → bottom. The only fixed colours in Settings:
    /// a tile is the same object in light and dark, like System Settings'.
    var tileColors: [Color] {
        let pair: (String, String)
        switch self {
        case .general:     pair = ("#8E8E96", "#5B5B63")
        case .appearance:  pair = ("#B59BFF", "#7C5CFF")
        case .opening:     pair = ("#7CC7FF", "#2F8CF0")
        case .shortcuts:   pair = ("#8A95A8", "#4B5568")
        case .calendar:    pair = ("#7FDCCD", "#21A596")
        case .storage:     pair = ("#FFD27A", "#F0A020")
        case .permissions: pair = ("#FFAD85", "#F0642D")
        case .privacy:     pair = ("#8FB6FF", "#3D6CF0")
        case .meetingLab:  pair = ("#FF9CC2", "#E0457B")
        case .about:       pair = ("#3A3A40", "#141416")
        }
        return [Color(hex: pair.0), Color(hex: pair.1)]
    }
}

// MARK: - Building blocks

/// A rounded, gradient-filled icon tile for the sidebar.
struct SettingsIconTile: View {
    let section: SettingsSection
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 6 / 22, style: .continuous)
        shape
            .fill(LinearGradient(colors: section.tileColors, startPoint: .top, endPoint: .bottom))
            // A hairline of light along the top edge only.
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            )
            .overlay {
                if section == .about {
                    OttoEyesLogo(color: .white, isAnimating: false)
                        .padding(size * 0.16)
                } else {
                    OttoIcon(section.icon, pointSize: size * 11 / 22)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// One settings page: grouped sections from the top, like System Settings.
/// The page's name is the window's title, beside the history arrows.
struct SettingsPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
    }
}

/// A row: title and optional one-line subtitle on the left, the control on
/// the right, CENTRED on the row whatever the label's height. Form's own
/// label slot aligns a control with the label's first line instead.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            control()
        }
    }
}

/// The switch of a SettingRow.
struct RowSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// A Label whose icon is one of the app's (Lucide) glyphs.
struct StatusLabel: View {
    let text: String
    let icon: String

    var body: some View {
        Label { Text(text) } icon: { OttoIcon(icon, pointSize: 12) }
    }
}

/// A shortcut as one keycap per key — ⌃ ⇧ N, not "⌃⇧N" squeezed into a
/// single chip, where the glyphs ran together (Marcello, 2026-10-01).
private struct KeycapChip: View {
    let keys: String

    /// "Esc" is one key; everything else here is one key per character.
    private var caps: [String] {
        keys.count > 1 && keys.allSatisfy(\.isLetter) ? [keys] : keys.map(String.init)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 14)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys)
    }
}

/// Equal-width selectable thumbnails — Layout and Theme. Buttons, so Tab
/// reaches them and VoiceOver reads the selected state; ←/→ move the choice.
struct VisualPicker<Option: Hashable, Thumbnail: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    @ViewBuilder let thumbnail: (Option) -> Thumbnail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 8) {
                        thumbnail(option)
                            .frame(maxWidth: .infinity)
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? AnyShapeStyle(Color.accentColor)
                                                           : AnyShapeStyle(Color(nsColor: .separatorColor)),
                                                  lineWidth: selected ? 3 : 1)
                            }
                        Text(label(option))
                            .font(selected ? .headline : .body)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The picker as a whole takes focus (←/→ below); a focus
                // ring per Button drew a square around the rounded
                // thumbnail (Marcello, 2026-10-01).
                .focusable(false)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .focusable()
        .modifier(NoFocusRing())
        .onMoveCommand { direction in
            guard let index = options.firstIndex(of: selection) else { return }
            switch direction {
            case .left where index > 0:                  selection = options[index - 1]
            case .right where index < options.count - 1: selection = options[index + 1]
            default: break
            }
        }
        .animation(reduceMotion ? nil : NotchAnimation.expand, value: selection)
    }
}

/// `focusEffectDisabled` is macOS 14+.
private struct NoFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.focusEffectDisabled() } else { content }
    }
}

// MARK: - Helper: binding to AppSettings

@MainActor
private func settingsBinding<T>(_ appState: AppState, _ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
    Binding(
        get: { appState.settings[keyPath: keyPath] },
        set: { newValue in
            var settings = appState.settings
            settings[keyPath: keyPath] = newValue
            // No animation: a row appearing or leaving (Hover delay) was
            // cross-faded in place, so for a moment two rows' text sat on top
            // of each other (Marcello, 2026-10-01). System Settings swaps
            // rows instantly too.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { appState.updateSettings { $0 = settings } }
        }
    )
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    // @AppStorage publishes changes so the toggles actually re-render.
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage(L10n.storageKey) private var appLanguage = "system"

    var body: some View {
        SettingsPage(section: .general) {
            Section("Startup") {
                SettingRow(title: "Launch at login", subtitle: "Open Otto automatically when you sign in.") {
                    RowSwitch(label: "Launch at login", isOn: Binding(
                        get: { appState.settings.launchAtLogin },
                        set: { newValue in
                            appState.updateSettings { $0.launchAtLogin = newValue }
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else        { try SMAppService.mainApp.unregister() }
                            } catch {
                                print("[Settings] Login item error: \(error)")
                            }
                        }
                    ))
                }
                SettingRow(title: "Show in Dock", subtitle: "Off keeps Otto in the menu bar only.") {
                    RowSwitch(label: "Show in Dock", isOn: Binding(
                        get: { appState.settings.showInDock },
                        set: { newValue in
                            appState.updateSettings { $0.showInDock = newValue }
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        }
                    ))
                }
            }

            Section {
                SettingRow(title: L10n.t("settings.language"), subtitle: L10n.t("settings.language.subtitle")) {
                    Picker(L10n.t("settings.language"), selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            Section("Feedback") {
                SettingRow(title: "Interface sounds", subtitle: "Subtle clicks when the notch opens and closes.") {
                    RowSwitch(label: "Interface sounds", isOn: $soundEffectsEnabled)
                }
                SettingRow(title: "Haptics", subtitle: "Trackpad taps on hover, open and close.") {
                    RowSwitch(label: "Haptics", isOn: $hapticFeedback)
                }
            }
        }
    }
}

// MARK: - Appearance

enum NotchSizePreset: String, CaseIterable, Identifiable {
    case compact, wide, extraWide

    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact:   return "Compact"
        case .wide:      return "Wide"
        case .extraWide: return "Extra Large"
        }
    }
    var width: Double {
        switch self {
        case .compact: 520; case .wide: 680; case .extraWide: 820
        }
    }
    var height: Double {
        switch self {
        case .compact: 160; case .wide: 200; case .extraWide: 240
        }
    }
    var radius: Double { 10 }

    static func match(width: Double, height: Double) -> NotchSizePreset {
        allCases.min(by: {
            abs($0.width - width) + abs($0.height - height)
            < abs($1.width - width) + abs($1.height - height)
        }) ?? .wide
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("showNotchPresence") private var showNotchPresence: Bool = true
    @AppStorage("notchCornerRadius")   private var cornerRadius: Double = 10
    @AppStorage("notchExpandedWidth")  private var expandedWidth: Double = 680
    @AppStorage("notchExpandedHeight") private var expandedHeight: Double = 200
    @AppStorage("notchLayout")         private var notchLayout: NotchLayout = .panels

    var body: some View {
        SettingsPage(section: .appearance) {
            Section {
                VisualPicker(
                    options: [NotchLayout.container, .panels],
                    selection: Binding(
                        get: { notchLayout },
                        set: { newValue in
                            guard newValue != notchLayout else { return }
                            appState.setNotchLayout(newValue)
                        }
                    ),
                    label: { $0 == .container ? "Notch" : "Floating panels" },
                    thumbnail: { LayoutThumbnail(layout: $0) }
                )
                if notchLayout == .container {
                    SettingRow(title: "Size") {
                        Picker("Size", selection: Binding(
                            get: { NotchSizePreset.match(width: expandedWidth, height: expandedHeight) },
                            set: { preset in
                                expandedWidth = preset.width
                                expandedHeight = preset.height
                                cornerRadius = preset.radius
                            }
                        )) {
                            ForEach(NotchSizePreset.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text(notchLayout.summary)
            }

            Section("Theme") {
                VisualPicker(
                    options: AppTheme.allCases,
                    selection: Binding(
                        get: { appState.settings.appTheme },
                        set: { theme in appState.updateSettings { $0.appTheme = theme } }
                    ),
                    label: { $0.label },
                    thumbnail: { ThemeThumbnail(theme: $0) }
                )
            }

            Section {
                SettingRow(title: "Presence in the notch", subtitle: "A small always-on dot for what's next.") {
                    RowSwitch(label: "Presence in the notch", isOn: $showNotchPresence)
                }
            }
        }
    }
}

/// Wallpaper for the thumbnails, from system colours so it follows the
/// appearance and Increase Contrast like everything else.
private struct ThumbnailWallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(nsColor: .systemTeal).opacity(0.55),
                                Color(nsColor: .systemBlue).opacity(0.75),
                                Color(nsColor: .systemOrange).opacity(0.35)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct LayoutThumbnail: View {
    let layout: NotchLayout

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                ThumbnailWallpaper()
                switch layout {
                case .container:
                    // The notch grown into the panel.
                    UnevenRoundedRectangleCompat(bottomRadius: h * 0.16)
                        .fill(Color.black)
                        .frame(width: w * 0.47, height: h * 0.54)
                case .panels:
                    VStack(spacing: h * 0.06) {
                        Capsule().fill(Color.black).frame(width: w * 0.17, height: h * 0.1)
                            .padding(.bottom, h * 0.04)
                        RoundedRectangle(cornerRadius: h * 0.1, style: .continuous)
                            .fill(.white.opacity(0.55))
                            .frame(width: w * 0.53, height: h * 0.25)
                        RoundedRectangle(cornerRadius: h * 0.1, style: .continuous)
                            .fill(.white.opacity(0.55))
                            .frame(width: w * 0.53, height: h * 0.33)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Square top corners, rounded bottom ones (UnevenRoundedRectangle is
/// macOS 14+; the deployment target is 13).
private struct UnevenRoundedRectangleCompat: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.width / 2, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A tiny window in the theme's own appearance — semantic colours resolved
/// under a forced colour scheme, so nothing is hard-coded.
private struct ThemeThumbnail: View {
    let theme: AppTheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ThumbnailWallpaper()
                switch theme {
                case .light:  window(.light)
                case .dark:   window(.dark)
                case .system:
                    HStack(spacing: 0) {
                        window(.light).frame(width: geo.size.width / 2).clipped()
                        window(.dark).frame(width: geo.size.width / 2).clipped()
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func window(_ scheme: ColorScheme) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(.primary.opacity(0.75)).frame(width: 34, height: 6)
                Capsule().fill(.primary.opacity(0.3)).frame(width: 54, height: 5)
                Capsule().fill(.primary.opacity(0.3)).frame(width: 44, height: 5)
            }
            .padding(14)
        }
        .padding(10)
        .environment(\.colorScheme, scheme)
    }
}

// MARK: - Opening

struct OpeningSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("notchCornerRadius")   private var cornerRadius: Double = 10
    @AppStorage("notchExpandedWidth")  private var expandedWidth: Double = 680
    @AppStorage("notchExpandedHeight") private var expandedHeight: Double = 200

    var body: some View {
        SettingsPage(section: .opening) {
            Section {
                SettingRow(title: "Open the notch", subtitle: "Shortcuts always work.") {
                    Picker("Open the notch", selection: settingsBinding(appState, \.notchTrigger)) {
                        Text("Hover").tag(NotchTrigger.hover)
                        Text("Click").tag(NotchTrigger.click)
                        Text("Menu bar only").tag(NotchTrigger.never)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if appState.settings.notchTrigger == .hover {
                    SettingRow(title: "Hover delay", subtitle: "How long the pointer rests first.") {
                        HStack(spacing: 10) {
                            Slider(
                                value: Binding(
                                    get: { Double(appState.settings.hoverDelayMs) },
                                    // 25 ms steps, rounded here rather than with
                                    // `step:`, which draws a row of tick marks.
                                    set: { newVal in
                                        appState.updateSettings { $0.hoverDelayMs = Int((newVal / 25).rounded()) * 25 }
                                    }
                                ),
                                in: 0...500
                            )
                            .labelsHidden()
                            .frame(width: 180)
                            .accessibilityLabel("Hover delay")
                            Text(appState.settings.hoverDelayMs == 0 ? "Instant" : "\(appState.settings.hoverDelayMs) ms")
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }

                SettingRow(title: "Auto-close", subtitle: "After the pointer leaves an open notch.") {
                    Picker("Auto-close", selection: settingsBinding(appState, \.autoCollapseSeconds)) {
                        Text("3 seconds").tag(Optional(3))
                        Text("5 seconds").tag(Optional(5))
                        Text("10 seconds").tag(Optional(10))
                        Text("Never").tag(Optional<Int>.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            Section {
                SettingRow(title: "Restore defaults", subtitle: "Opening, hover delay, auto-close and the notch size.") {
                    Button("Restore") {
                        let p = NotchSizePreset.wide
                        expandedWidth = p.width
                        expandedHeight = p.height
                        cornerRadius = p.radius
                        appState.updateSettings { s in
                            s.notchTrigger = .hover
                            s.hoverDelayMs = 0
                            s.autoCollapseSeconds = 5
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shortcuts

/// Read-only, and exactly what HotkeyManager registers — the earlier list
/// advertised a ⌃⇧F tray and a ⌥Space that were never bound.
struct ShortcutsSettingsView: View {
    var body: some View {
        SettingsPage(section: .shortcuts) {
            Section {
                row("New to-do", HotkeyManager.quickEntryDisplay)
                row("Show or hide the new to-do field", "\u{2325}\u{2318}N")
                row("Open To-dos", "\u{2303}\u{21E7}T")
                row("Open Notes", "\u{2303}\u{21E7}E")
                row("Join meeting (while an alert is up)", "\u{2318}\u{21A9}")
            } header: {
                Text("Anywhere")
            } footer: {
                Text("These work from any app.")
            }

            Section("In Otto") {
                row("Close the notch", "Esc")
                row("Every shortcut in the panel", "?")
                row("Settings", "\u{2318},")
                row("Quit", "\u{2318}Q")
            }
        }
    }

    private func row(_ action: String, _ keys: String) -> some View {
        SettingRow(title: action) { KeycapChip(keys: keys) }
    }
}

// MARK: - Storage

/// Where the Markdown copy of everything lives — every to-do and note, always
/// on disk as plain .md, findable without the app. See MarkdownVault.
struct StorageSettingsView: View {
    @EnvironmentObject var appState: AppState

    private var vaultPath: String {
        appState.settings.vaultDirectory.path
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path,
                                  with: "~")
    }

    var body: some View {
        SettingsPage(section: .storage) {
            Section {
                SettingRow(title: "Folder") {
                    Text(vaultPath)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .help("One .md file per section, Notes.md for quick notes, and Archive/ with completed to-dos by day.")
                HStack {
                    Button("Choose Folder\u{2026}") { chooseFolder() }
                    Button("Show in Finder") {
                        let dir = appState.settings.vaultDirectory
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([dir])
                    }
                    Spacer()
                    Button("Use Default") { setDirectory(MarkdownVault.defaultDirectory) }
                        .disabled(appState.settings.vaultDirectory == MarkdownVault.defaultDirectory)
                }
            } header: {
                Text("Markdown folder")
            } footer: {
                Text("Everything you write is also saved here as plain Markdown, after every change. These files are Otto's copy: edits made elsewhere are overwritten; your own files are never touched.")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.settings.vaultDirectory
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Otto keeps the Markdown copy of your to-dos and notes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setDirectory(url)
    }

    private func setDirectory(_ url: URL) {
        appState.updateSettings { $0.vaultDirectory = url }
        // Write the current state to the new location immediately, so the
        // choice visibly did something.
        MarkdownVault.shared.locationChanged()
    }
}

// MARK: - Permissions

/// What macOS lets Otto do, in one place. Calendar access is the only grant
/// Otto asks for; the stale-sync warning lives here too because the fix is a
/// system setting, not an Otto one.
@MainActor
enum SettingsPermissions {
    static var calendarStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    static var calendarGranted: Bool {
        if #available(macOS 14.0, *) { return calendarStatus == .fullAccess }
        return calendarStatus == .authorized
    }

    /// Refused, or granted but macOS has stopped syncing. Never asked is not
    /// a problem: Otto works without a calendar.
    static func needsAttention(_ calendar: CalendarStore) -> Bool {
        let refused = !calendarGranted && calendarStatus != .notDetermined
        return refused || calendar.syncLooksStale
    }

    static let calendarPrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let internetAccountsURL = URL(string: "x-apple.systempreferences:com.apple.systempreferences.InternetAccounts")!
}

struct PermissionsSettingsView: View {
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        SettingsPage(section: .permissions) {
            Section {
                SettingRow(title: "Calendar", subtitle: "Read-only, for meetings in Today and alerts.") {
                    if SettingsPermissions.calendarGranted {
                        StatusLabel(text: "Allowed", icon: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if SettingsPermissions.calendarStatus == .notDetermined {
                        Text("Not requested").foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            StatusLabel(text: "Not allowed", icon: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Link("Open System Settings", destination: SettingsPermissions.calendarPrivacyURL)
                        }
                    }
                }
            } header: {
                Text("Access")
            }

            if calendar.syncLooksStale, let last = calendar.lastSyncedAt {
                Section {
                    SettingRow(
                        title: "macOS isn't syncing your calendars",
                        subtitle: "Newest event on this Mac: \(last.formatted(date: .abbreviated, time: .shortened)). Anything created since hasn't arrived."
                    ) {
                        Link("Open Internet Accounts", destination: SettingsPermissions.internetAccountsURL)
                    }
                } header: {
                    Text("Calendar sync")
                } footer: {
                    Text("In Internet Accounts, turn Calendars off and on for your Google account; if that doesn't help, remove and re-add the account.")
                }
            }
        }
    }
}

// MARK: - Privacy

struct PrivacySettingsView: View {
    @EnvironmentObject var appState: AppState
    /// Bumped by Reset ID so the shown ID redraws.
    @State private var idRefresh = 0

    var body: some View {
        SettingsPage(section: .privacy) {
            Section {
                SettingRow(title: L10n.t("privacy.toggle"), subtitle: L10n.t("ob.perm.usage.caption")) {
                    RowSwitch(label: L10n.t("privacy.toggle"), isOn: Binding(
                        get: { appState.settings.analyticsConsent == .granted },
                        set: { Analytics.setConsent($0) }
                    ))
                    .disabled(!AppBuild.analyticsEnabled)
                }
                // In full: it is what to quote when asking for your data to be deleted.
                SettingRow(title: L10n.t("privacy.id")) {
                    Text(Analytics.installID)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .id(idRefresh)
                }
                HStack {
                    Button(L10n.t("privacy.show")) {
                        // The file is exactly what leaves the Mac.
                        let url = Analytics.queueFileURL
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            NSWorkspace.shared.open(url.deletingLastPathComponent())
                        }
                    }
                    Spacer()
                    Button(L10n.t("privacy.reset")) { Analytics.resetID(); idRefresh += 1 }
                }
            } header: {
                Text("Usage data")
            } footer: {
                Text(L10n.t("privacy.subtitle"))
            }
        }
    }
}

// MARK: - Meeting Lab

/// Fake meetings on demand, to watch the whole meeting flow — the dot in the
/// notch, the card, the self-opening alert, Join, Snooze — without waiting
/// for a real invite. In memory only; see CalendarStore's Meeting Lab.
struct MeetingLabSettingsView: View {
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var title = "Design sync"
    @State private var startsIn = 60
    @State private var duration = 30
    @State private var link: CalendarStore.LabLink = .meet
    @State private var attendees = 3

    private var lead: Int { calendar.alertLeadMinutes }

    private let startOptions: [(String, Int)] = [
        ("Now", 0), ("In 20 seconds", 20), ("In 1 minute", 60), ("In 2 minutes", 120),
        ("In 5 minutes", 300), ("In 10 minutes", 600), ("In 20 minutes", 1200),
    ]

    var body: some View {
        SettingsPage(section: .meetingLab) {
            Section {
                // Timed against the alert lead, so "in 1 minute" means the
                // ALERT opens in a minute, whatever the lead is set to.
                SettingRow(title: "Alert in 1 minute",
                           subtitle: "Google Meet, 3 people, starting \(lead + 1) min from now.") {
                    Button("Schedule") { calendar.labSchedule(title: "Design sync", inSeconds: (lead + 1) * 60) }
                }
                SettingRow(title: "Starting right now", subtitle: "Zoom, 6 people: the notch should open at once.") {
                    Button("Schedule") { calendar.labSchedule(title: "Stand-up", inSeconds: 0, minutes: 15, link: .zoom, attendees: 6) }
                }
                SettingRow(title: "Back-to-back", subtitle: "Two alerts, 1 and 3 minutes from now.") {
                    Button("Schedule") {
                        calendar.labSchedule(title: "1:1 with Rose", inSeconds: (lead + 1) * 60, minutes: 2, link: .meet, attendees: 1)
                        calendar.labSchedule(title: "Roadmap review", inSeconds: (lead + 3) * 60, link: .teams, attendees: 8)
                    }
                }
                SettingRow(title: "No video link", subtitle: "In a room, alert in 1 minute: no Join button.") {
                    Button("Schedule") { calendar.labSchedule(title: "Lunch with the team", inSeconds: (lead + 1) * 60, link: .none, attendees: 4) }
                }
            } header: {
                Text("Quick tests")
            } footer: {
                Text("The ambient dot appears \(calendar.ambientLeadMinutes) min before a meeting and the alert opens the notch \(calendar.alertLeadMinutes) min before — change both in Calendar & Meetings.")
            }

            Section("Custom meeting") {
                SettingRow(title: "Title") {
                    TextField("Title", text: $title)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                SettingRow(title: "Starts", subtitle: "The alert opens \(calendar.alertLeadMinutes) min before the start.") {
                    Picker("Starts", selection: $startsIn) {
                        ForEach(startOptions, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingRow(title: "Length") {
                    Picker("Length", selection: $duration) {
                        Text("2 minutes").tag(2)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingRow(title: "Call") {
                    Picker("Call", selection: $link) {
                        ForEach(CalendarStore.LabLink.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingRow(title: "People") {
                    Picker("People", selection: $attendees) {
                        Text("Just you").tag(0)
                        Text("1").tag(1)
                        Text("3").tag(3)
                        Text("8").tag(8)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                HStack {
                    Spacer()
                    Button("Replace All") {
                        calendar.labSchedule(title: title, inSeconds: startsIn, minutes: duration,
                                             link: link, attendees: attendees, replacing: true)
                    }
                    Button("Add Meeting") {
                        calendar.labSchedule(title: title, inSeconds: startsIn, minutes: duration,
                                             link: link, attendees: attendees)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

            Section {
                if calendar.labMeetings.isEmpty {
                    Text("No test meetings.").foregroundStyle(.secondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(calendar.labMeetings) { meeting in
                                SettingRow(title: meeting.title,
                                           subtitle: [meeting.platform ?? "No link",
                                                      "\(meeting.attendees.count) people"].joined(separator: " \u{00B7} ")) {
                                    Text(Self.countdown(to: meeting, now: context.date))
                                        .monospacedDigit()
                                        .foregroundStyle(calendar.activeAlert?.id == meeting.id ? .orange : .secondary)
                                }
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Clear Test Meetings", role: .destructive) { calendar.labClear() }
                    }
                }
            } header: {
                Text("Scheduled")
            } footer: {
                Text("Test meetings live only in Otto's memory — nothing is added to any calendar — and vanish when they end, when cleared, or when Otto quits.")
            }
        }
    }

    private static func countdown(to meeting: DetectedMeeting, now: Date) -> String {
        let left = Int(meeting.start.timeIntervalSince(now))
        if left <= 0 {
            return CalendarStore.shared.activeAlert?.id == meeting.id ? "Alerting · started" : "Started"
        }
        let text = String(format: "in %d:%02d", left / 60, left % 60)
        return CalendarStore.shared.activeAlert?.id == meeting.id ? "Alerting · " + text : text
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @ObservedObject private var updates = UpdateController.shared

    /// "Version 1.8.0 (72)" — marketing version plus build, both straight from
    /// the bundle so a screenshot of this row identifies the exact build.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        SettingsPage(section: .about) {
            Section {
                HStack(spacing: 14) {
                    // The app's real icon, so About cannot drift from the artwork.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Otto").font(.headline)
                        Text(Self.versionText).foregroundStyle(.secondary)
                        Text("Your to-dos and today's meetings, in the notch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                SettingRow(
                    title: String(format: L10n.t("update.version"), UpdateController.currentVersion),
                    subtitle: String(format: L10n.t("update.lastChecked"), updates.lastCheckDescription)
                ) {
                    Button(updates.canCheck ? L10n.t("update.check") : L10n.t("update.checking")) {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheck)
                }
                SettingRow(title: L10n.t("update.automatic"), subtitle: "Once a day; updates install in place.") {
                    RowSwitch(label: L10n.t("update.automatic"), isOn: Binding(
                        get: { updates.automaticallyChecks },
                        set: { updates.automaticallyChecks = $0 }
                    ))
                }
            } header: {
                Text(L10n.t("update.section"))
            }

            Section {
                // Onboarding runs once and never again; replaying it is how
                // the flow gets reviewed without reinstalling.
                SettingRow(title: "Onboarding", subtitle: "Walk through the welcome flow again.") {
                    Button("Show Again") {
                        UserDefaults.standard.set(0, forKey: "onboardingVersion")
                        OnboardingWindowController.show()
                    }
                }
                if FeedbackWindowController.isAvailable {
                    SettingRow(title: "Feedback", subtitle: "A bug, an idea, a screenshot — straight to us.") {
                        Button("Send Feedback\u{2026}") { FeedbackWindowController.show() }
                    }
                }
            } footer: {
                Text("\u{00A9} 2026 Otto")
            }
        }
    }
}

#if DEBUG
/// One page on its own, for DebugDriver's settings-snap.
struct SettingsPageDebugHost: View {
    let section: SettingsSection

    var body: some View {
        switch section {
        case .general:     GeneralSettingsView()
        case .appearance:  AppearanceSettingsView()
        case .opening:     OpeningSettingsView()
        case .shortcuts:   ShortcutsSettingsView()
        case .calendar:    CalendarSettingsView()
        case .storage:     StorageSettingsView()
        case .permissions: PermissionsSettingsView()
        case .privacy:     PrivacySettingsView()
        case .meetingLab:  MeetingLabSettingsView()
        case .about:       AboutSettingsView()
        }
    }
}
#endif
