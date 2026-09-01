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
                    case .storage:    StorageSettingsView()
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
    case general, appearance, notch, storage, calendar, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .notch:      return "Notch"
        case .storage:    return "Storage"
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
        case .storage:    return "folder"
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
        // NOT the onboarding's GlassTile: that one is a fixed 30% black,
        // correct on the onboarding's own dark purple and wrong in every
        // Light window. See DSColor.cardSurface.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DSColor.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DSColor.hairlineOnPanel, lineWidth: 1)
        )
        .shadow(color: DSColor.shadowSoft, radius: 16, y: 6)
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
                Toggle(isOn: $soundEffectsEnabled) {
                    rowText("Interface sound effects", "Subtle clicks for the notch and clipboard tiles.")
                }
                Divider()
                Toggle(isOn: $hapticFeedback) {
                    rowText("Haptic feedback", "Trackpad taps when the notch expands or you copy.")
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
    @AppStorage("showNotchPresence") private var showNotchPresence: Bool = true
    @EnvironmentObject var appState: AppState
    @AppStorage("notchCornerRadius")   private var cornerRadius: Double = 10
    @AppStorage("notchExpandedWidth")  private var expandedWidth: Double = 680
    @AppStorage("notchExpandedHeight") private var expandedHeight: Double = 200
    @AppStorage("notchLayout")         private var notchLayout: NotchLayout = .panels

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
                title: "Layout",
                subtitle: "Two designs for the open notch. Switching closes it so it reopens in the new shape."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: Binding(
                        get: { notchLayout },
                        set: { newValue in
                            guard newValue != notchLayout else { return }
                            notchLayout = newValue
                            // The two layouts measure themselves differently,
                            // and the height one of them published is
                            // meaningless to the other. Close first, drop the
                            // stale measurement, and let the new layout
                            // measure itself on the next open — otherwise the
                            // silhouette animates to a size nothing on screen
                            // asked for.
                            NotchController.shared.forceCollapse()
                            NotchController.shared.applyNotchAppearance()
                            appState.labColumnHeight = 0
                            // Both measurements, not just the column's: a
                            // panels-era todoContentHeight surviving into the
                            // container sized the silhouette to a panel that
                            // was no longer on screen.
                            appState.todoContentHeight = 0
                            appState.objectWillChange.send()
                        }
                    )) {
                        ForEach(NotchLayout.allCases, id: \.self) { layout in
                            Text(layout.label).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(notchLayout.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSection_Card(
                title: "Size",
                subtitle: "Choose a preset. Width, height and curvature adapt together. The presets size the notch container; the floating panels keep their own width."
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

            SettingsSection_Card(
                title: "Presence",
                subtitle: "A small always-on indicator in the notch: Otto is running, and what is coming up."
            ) {
                SettingsRow(
                    title: "Show in the notch",
                    subtitle: "Widens the collapsed notch slightly, which covers a little of the menu bar beside it."
                ) {
                    Toggle("", isOn: $showNotchPresence)
                        .toggleStyle(.switch)
                        .labelsHidden()
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

// MARK: - Storage

/// Where the Markdown copy of everything lives. The panel is the daily
/// interface; this folder is the guarantee behind it — every to-do and note,
/// always on disk as plain .md, findable without the app. See MarkdownVault.
struct StorageSettingsView: View {
    @EnvironmentObject var appState: AppState

    private var vaultPath: String {
        appState.settings.vaultDirectory.path
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path,
                                  with: "~")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                title: "Storage",
                subtitle: "Everything you write is also saved as plain Markdown, so it is always yours to find."
            )

            SettingsSection_Card(
                title: "Markdown folder",
                subtitle: "One .md file per section, a Notes.md for quick notes, and an Archive folder holding completed to-dos by day. Open it in Finder, grep it, or point Obsidian at it."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text(vaultPath)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DSColor.fieldBackground)
                    )

                    HStack(spacing: 10) {
                        Button("Choose Folder…") { chooseFolder() }
                        Button("Show in Finder") {
                            let dir = appState.settings.vaultDirectory
                            try? FileManager.default.createDirectory(
                                at: dir, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                        Spacer()
                        Button("Use Default") {
                            setDirectory(MarkdownVault.defaultDirectory)
                        }
                        .disabled(appState.settings.vaultDirectory == MarkdownVault.defaultDirectory)
                    }
                }
            }

            SettingsSection_Card(
                title: "How it works",
                subtitle: nil
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("The app keeps its own database and mirrors it here after every change — nothing extra to manage.")
                    bullet("Completed to-dos older than a day move to Archive/<date>.md and leave the panel's Completed list.")
                    bullet("Files here are the app's copy: edits made in another editor are overwritten on the next change. Your own files in the folder are never touched.")
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Shortcuts", subtitle: "Global keyboard shortcuts available system-wide.")

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
    /// "Version 1.8.0 (72)" — marketing version plus build, both straight from
    /// the bundle so a screenshot of this row identifies the exact build.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "About")

            SettingsSection_Card(title: "Otto") {
                HStack(spacing: 16) {
                    // The app's real icon, so About cannot drift from the
                    // artwork the way a hardcoded SF Symbol did — it was still
                    // showing a screenshot camera after the pivot.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Otto").font(.system(size: 17, weight: .semibold))
                        // Read from the bundle. This said "Version 1.0" through
                        // twenty releases, which made every bug report ambiguous
                        // about which build it came from.
                        Text(Self.versionText)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("Your to-dos and today's meetings, in the notch.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Onboarding is the only part of the app a user cannot get
                // back to on their own — it runs once and never again. Being
                // able to replay it is how the flow gets reviewed without
                // reinstalling or editing defaults by hand.
                SettingsRow(title: "Onboarding",
                            subtitle: "Walk through the welcome flow again.") {
                    Button("Show again") {
                        UserDefaults.standard.set(0, forKey: "onboardingVersion")
                        OnboardingWindowController.show()
                    }
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
