import SwiftUI
import ServiceManagement

// MARK: - Settings View — standard macOS sidebar layout
//
// Rebuilt on NavigationSplitView (Marcello, 2026-07-28), replacing a
// hand-rolled HStack with its own frosted background, custom sidebar rows and
// an inset "content sheet" with uneven corners.
//
// The point of using the system's split view rather than reproducing it: a
// real `.sidebar`-styled List gets the window-blending material for free, and
// gets whatever macOS decides that material should be. On macOS 26 that is the
// Liquid Glass treatment, and it arrives without this file knowing anything
// about it — the same reason Atlas looks native despite being SwiftUI. A
// hand-drawn approximation can only ever match the OS it was drawn against.
//
// The sidebar deliberately extends under the titlebar (the window is
// fullSizeContentView with a transparent titlebar), which is what puts the
// traffic lights on the sidebar material instead of on a separate strip.

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ScrollView {
                Group {
                    switch selection {
                    case .general:    GeneralSettingsView()
                    case .appearance: AppearanceSettingsView()
                    case .notch:      NotchSettingsView()
                    case .capture:    CaptureSettingsView()
                    case .calendar:   CalendarSettingsView()
                    case .shortcuts:  ShortcutsSettingsView()
                    case .about:      AboutSettingsView()
                    }
                }
                .id(selection)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .navigationTitle(selection.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        .environmentObject(appState)
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
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, notch, capture, calendar, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .notch:      return "Notch"
        case .capture:    return "Capture"
        case .calendar:   return "Calendar"
        case .shortcuts:  return "Shortcuts"
        case .about:      return "About"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintpalette"
        case .notch:      return "macbook"
        case .capture:    return "camera.viewfinder"
        case .calendar:   return "calendar"
        case .shortcuts:  return "keyboard"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - Reusable building blocks

struct SettingsSection_Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(GlassTile(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct PageTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold))
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
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
            appState.updateSettings { $0 = settings }
        }
    )
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    // @AppStorage publishes changes so the toggles actually re-render.
    // (Raw UserDefaults bindings looked "stuck" — the value changed but
    // SwiftUI never knew to redraw the checkbox.)
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage(L10n.storageKey) private var appLanguage = "system"
    @AppStorage("showLegacyPanels") private var showLegacyPanels = false

    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "General", subtitle: "Startup, feedback and clipboard behavior.")

            // Updates first: it is the thing a person looks for when they hear
            // a fix exists, and it states the running version so "am I current?"
            // is answerable without leaving the window.
            SettingsSection_Card(title: L10n.t("update.section")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            updates.checkForUpdates()
                        } label: {
                            Text(updates.canCheck ? L10n.t("update.check")
                                                  : L10n.t("update.checking"))
                        }
                        .disabled(!updates.canCheck)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: L10n.t("update.version"),
                                        UpdateController.currentVersion))
                                .font(.system(size: 11))
                            Text(String(format: L10n.t("update.lastChecked"),
                                        updates.lastCheckDescription))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Toggle(isOn: Binding(
                        get: { updates.automaticallyChecks },
                        set: { updates.automaticallyChecks = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("update.automatic"))
                            Text(L10n.t("update.automaticHelp"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            SettingsSection_Card(title: "Panels") {
                Toggle(isOn: Binding(
                    get: { showLegacyPanels },
                    set: { newValue in
                        showLegacyPanels = newValue
                        // AppState reads the flag via computed properties —
                        // nudge observers so the notch re-renders right away.
                        appState.objectWillChange.send()
                    }
                )) {
                    rowText("Show legacy panels",
                            "Bring back the Tray, Notes, Shots and Clipboard tabs alongside To-dos. Off, the notch is a focused to-do list.")
                }
            }

            SettingsSection_Card(title: "Startup") {
                Toggle(isOn: Binding(
                    get: { appState.settings.launchAtLogin },
                    set: { newValue in
                        appState.updateSettings { $0.launchAtLogin = newValue }
                        if #available(macOS 13.0, *) {
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else        { try SMAppService.mainApp.unregister() }
                            } catch {
                                print("[Settings] Login item error: \(error)")
                            }
                        }
                    }
                )) {
                    rowText("Launch at login", "Open Otto automatically when you sign in.")
                }
                Divider()
                Toggle(isOn: Binding(
                    get: { appState.settings.showInDock },
                    set: { newValue in
                        appState.updateSettings { $0.showInDock = newValue }
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
                )) {
                    rowText("Show in Dock", "Hide to keep Otto as a menu-bar-only app.")
                }
            }

            SettingsSection_Card(title: "Feedback") {
                Toggle(isOn: settingsBinding(appState, \.playSound)) {
                    rowText("Capture sound", "Play the system shutter sound on capture.")
                }
                Divider()
                Toggle(isOn: $soundEffectsEnabled) {
                    rowText("Interface sound effects", "Subtle clicks for the notch and clipboard tiles.")
                }
                Divider()
                Toggle(isOn: $hapticFeedback) {
                    rowText("Haptic feedback", "Trackpad taps when the notch expands or you copy.")
                }
            }

            SettingsSection_Card(title: "Clipboard") {
                Toggle(isOn: settingsBinding(appState, \.autoCopyToClipboard)) {
                    rowText("Auto-copy to clipboard", "Copy every new screenshot automatically.")
                }
            }

            SettingsSection_Card(
                title: L10n.t("settings.language"),
                subtitle: L10n.t("settings.language.subtitle")
            ) {
                Picker("", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func rowText(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Appearance", subtitle: "Choose how Otto looks. Follows your system by default.")

            SettingsSection_Card(
                title: "Theme",
                subtitle: "Pick a theme or follow the system preference."
            ) {
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: appState.settings.appTheme == theme
                        ) {
                            appState.updateSettings { $0.appTheme = theme }
                        }
                    }
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ThemePreview(theme: theme)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(theme.label).font(.system(size: 12, weight: .medium))
                    Spacer()
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// Tiny representation of light/dark/system styling shown inside the theme card.
private struct ThemePreview: View {
    let theme: AppTheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch theme {
                case .light:
                    previewWindow(bg: .white, fg: .black)
                case .dark:
                    previewWindow(bg: Color(red: 0.10, green: 0.11, blue: 0.13),
                                  fg: .white)
                case .system:
                    HStack(spacing: 0) {
                        previewWindow(bg: .white, fg: .black)
                            .frame(width: geo.size.width / 2)
                        previewWindow(bg: Color(red: 0.10, green: 0.11, blue: 0.13),
                                      fg: .white)
                            .frame(width: geo.size.width / 2)
                    }
                }
            }
        }
    }

    private func previewWindow(bg: Color, fg: Color) -> some View {
        ZStack(alignment: .top) {
            bg
            // Tiny notch on top
            Capsule()
                .fill(Color.black)
                .frame(width: 36, height: 8)
                .offset(y: -2)
            // Mock content lines
            VStack(alignment: .leading, spacing: 5) {
                Spacer().frame(height: 14)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(fg.opacity(0.85)).frame(width: 32, height: 5)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(fg.opacity(0.35)).frame(width: 50, height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(fg.opacity(0.35)).frame(width: 42, height: 4)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Notch

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
    var subtitle: String {
        switch self {
        case .compact:   return "Minimal — fits a single tile"
        case .wide:      return "Balanced — recommended"
        case .extraWide: return "Spacious — more room for tiles"
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

struct NotchSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("notchCornerRadius")   private var cornerRadius: Double = 10
    @AppStorage("notchExpandedWidth")  private var expandedWidth: Double = 680
    @AppStorage("notchExpandedHeight") private var expandedHeight: Double = 200

    private var currentPreset: NotchSizePreset {
        NotchSizePreset.match(width: expandedWidth, height: expandedHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Notch", subtitle: "How the notch looks and when it opens.")

            SettingsSection_Card(title: "Preview") {
                NotchLivePreview(
                    cornerRadius: cornerRadius,
                    width: expandedWidth,
                    height: expandedHeight
                )
                .frame(height: 130)
                .frame(maxWidth: .infinity)
            }

            SettingsSection_Card(
                title: "Size",
                subtitle: "Choose a preset. Width, height and curvature adapt together."
            ) {
                VStack(spacing: 8) {
                    ForEach(NotchSizePreset.allCases) { preset in
                        SizePresetRow(
                            preset: preset,
                            isSelected: currentPreset == preset
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                expandedWidth  = preset.width
                                expandedHeight = preset.height
                                cornerRadius   = preset.radius
                            }
                        }
                    }
                }
            }

            SettingsSection_Card(
                title: "Activation",
                subtitle: "Decide how the notch opens."
            ) {
                Picker("", selection: settingsBinding(appState, \.notchTrigger)) {
                    Text("Cursor hover").tag(NotchTrigger.hover)
                    Text("Click").tag(NotchTrigger.click)
                    Text("Never (menu bar only)").tag(NotchTrigger.never)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if appState.settings.notchTrigger == .hover {
                    Divider()
                    SettingsRow(
                        title: "Hover delay",
                        subtitle: appState.settings.hoverDelayMs == 0 ? "Instant" : "\(appState.settings.hoverDelayMs)ms"
                    ) {
                        Slider(
                            value: Binding(
                                get: { Double(appState.settings.hoverDelayMs) },
                                set: { newVal in appState.updateSettings { s in s.hoverDelayMs = Int(newVal) } }
                            ),
                            in: 0...500, step: 25
                        )
                        .frame(width: 200)
                    }
                }
            }

            SettingsSection_Card(title: "Behavior") {
                SettingsRow(title: "Auto-close after") {
                    Picker("", selection: settingsBinding(appState, \.autoCollapseSeconds)) {
                        Text("3 seconds").tag(Optional(3))
                        Text("5 seconds").tag(Optional(5))
                        Text("10 seconds").tag(Optional(10))
                        Text("Never").tag(Optional<Int>.none)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider()
                Toggle(isOn: settingsBinding(appState, \.showBadgeCounter)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Counter badge").font(.system(size: 13))
                        Text("Show how many screenshots are in the session.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Restore defaults") {
                    withAnimation {
                        let p = NotchSizePreset.wide
                        expandedWidth = p.width
                        expandedHeight = p.height
                        cornerRadius = p.radius
                        appState.updateSettings { s in
                            s.notchTrigger = .hover
                            s.hoverDelayMs = 0
                            s.autoCollapseSeconds = 5
                            s.showBadgeCounter = true
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SizePresetRow: View {
    let preset: NotchSizePreset
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Mini visual indicator
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: relativeWidth, height: 18)
                    .overlay(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: relativeWidth * 0.45, height: 5)
                            .offset(y: -6.5)
                    )
                    .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.label).font(.system(size: 13, weight: .medium))
                    Text(preset.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08)
                          : (hover ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var relativeWidth: CGFloat {
        switch preset {
        case .compact:   return 32
        case .wide:      return 44
        case .extraWide: return 56
        }
    }
}

// MARK: - Capture

struct CaptureSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Capture", subtitle: "How screenshots are taken and saved.")

            SettingsSection_Card(title: "Defaults") {
                SettingsRow(title: "Default mode") {
                    Picker("", selection: settingsBinding(appState, \.defaultCaptureMode)) {
                        Text("Area").tag(CaptureMode.area)
                        Text("Window").tag(CaptureMode.window)
                        Text("Full screen").tag(CaptureMode.fullscreen)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider()
                Toggle(isOn: settingsBinding(appState, \.playSound)) {
                    rowText("Screenshot sound", "Play the standard system shutter sound.")
                }
                Divider()
                Toggle(isOn: settingsBinding(appState, \.windowShadow)) {
                    rowText("Window shadow", "Include the macOS drop shadow on window captures.")
                }
            }

            SettingsSection_Card(title: "Saving") {
                Toggle(isOn: settingsBinding(appState, \.autoSaveFile)) {
                    rowText("Auto-save to file", "Write each capture straight to disk.")
                }

                if appState.settings.autoSaveFile {
                    Divider()
                    SettingsRow(title: "Folder", subtitle: appState.settings.saveDirectory.path) {
                        Button("Choose\u{2026}") { chooseSaveDirectory() }
                    }
                }

                Divider()
                SettingsRow(title: "File format") {
                    Picker("", selection: settingsBinding(appState, \.fileFormat)) {
                        Text("PNG").tag(FileFormat.png)
                        Text("JPEG").tag(FileFormat.jpeg)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                if appState.settings.fileFormat == .jpeg {
                    Divider()
                    SettingsRow(
                        title: "JPEG quality",
                        subtitle: "\(Int(appState.settings.jpegQuality * 100))%"
                    ) {
                        Slider(value: settingsBinding(appState, \.jpegQuality), in: 0.1...1.0, step: 0.05)
                            .frame(width: 200)
                    }
                }
            }

            SettingsSection_Card(title: "Session") {
                SettingsRow(title: "Screenshots in memory") {
                    Picker("", selection: settingsBinding(appState, \.maxSessionScreenshots)) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("50").tag(50)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Divider()
                Toggle(isOn: settingsBinding(appState, \.clearSessionOnLaunch)) {
                    rowText("Clear session on launch", "Start fresh every time Otto opens.")
                }
            }
        }
    }

    @ViewBuilder
    private func rowText(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            appState.updateSettings { $0.saveDirectory = url }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Shortcuts", subtitle: "Global keyboard shortcuts available system-wide.")

            SettingsSection_Card(title: "Capture") {
                ShortcutRow(label: "Capture area", keys: "\u{2303}\u{21E7}4")
                Divider()
                ShortcutRow(label: "Capture window", keys: "\u{2303}\u{21E7}2")
                Divider()
                ShortcutRow(label: "Capture screen", keys: "\u{2303}\u{21E7}3")
                Divider()
                ShortcutRow(label: "Capture area + Editor", keys: "\u{2303}\u{21E7}5")
                Divider()
                ShortcutRow(label: "Repeat last capture", keys: "\u{2303}\u{21E7}Space")
            }

            SettingsSection_Card(title: "Notch") {
                ShortcutRow(label: "Open To-dos", keys: "\u{2303}\u{21E7}T")
                Divider()
                ShortcutRow(label: "New to-do (quick entry)", keys: "\u{2325}Space")
                Divider()
                ShortcutRow(label: "Open Notes", keys: "\u{2303}\u{21E7}N")
                Divider()
                ShortcutRow(label: "Open file Tray", keys: "\u{2303}\u{21E7}F")
                Divider()
                ShortcutRow(label: "Close notch", keys: "Esc")
            }

            SettingsSection_Card(title: "Application") {
                ShortcutRow(label: "Open Settings", keys: "\u{2318} ,")
                Divider()
                ShortcutRow(label: "Quit", keys: "\u{2318} Q")
            }

            Text("Shortcuts using \u{2303}\u{21E7} (Control+Shift) are global — they work from any app.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

struct ShortcutRow: View {
    let label: String
    let keys: String

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(keys)
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "About")

            SettingsSection_Card(title: "Otto") {
                HStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Otto").font(.system(size: 17, weight: .semibold))
                        Text("Version 1.0").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("Screenshot tool that lives in your Mac's notch.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Text("\u{00A9} 2026 Otto")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}
