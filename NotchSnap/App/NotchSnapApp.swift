import SwiftUI
import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply user-selected theme (system / light / dark)
        AppState.shared.applyTheme()

        // Hide from Dock if configured
        if !AppState.shared.settings.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }

        // Initialize defaults
        if UserDefaults.standard.object(forKey: "hapticFeedback") == nil {
            UserDefaults.standard.set(true, forKey: "hapticFeedback")
        }
        if UserDefaults.standard.object(forKey: "soundEffectsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "soundEffectsEnabled")
        }

        // Show onboarding if not completed
        let onboardingVersion = UserDefaults.standard.integer(forKey: "onboardingVersion")
        if onboardingVersion < 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.show()
            }
        }

        // Setup hotkey manager
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.start()

        // A user can revoke Otto from their Apple ID's own settings without
        // telling this app — check once per launch so a stale sign-in never
        // lingers in the tab-row avatar or Settings.
        AppleSignIn.shared.refreshCredentialState()

        #if DEBUG
        // Scriptable side door for agent/CI verification (see DebugDriver).
        DebugDriver.install()
        #endif

        // Setup Caps Lock hotkey observers
        CaptureManager.shared.setupHotkeyObservers()

        // Pre-warm SCShareableContent cache — eliminates 1-3s delay on first capture

        // Setup notch controller
        notchController = NotchController.shared
        notchController?.setup()

        // Start clipboard monitoring
        ClipboardMonitor.shared.startMonitoring()

        // Restore pinned clipboard items + snippets
        AppState.shared.loadClipboardArchive()

        // Clear session on launch if configured
        if AppState.shared.settings.clearSessionOnLaunch {
            AppState.shared.clearSession()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        ClipboardMonitor.shared.stopMonitoring()
        TempFileManager.shared.cleanupAll()
        // Flush the debounced stores. Every save path waits 500 ms to batch
        // keystrokes, so without this a quit inside that window silently
        // dropped the last edit — the one bug a to-do app must not have.
        MainActor.assumeIsolated {
            TodoStore.shared.saveNow()
            NotesStore.shared.saveNow()
        }
    }

    // MARK: - Settings & Quit actions (called from menu and notifications)

    @objc func openSettingsAction() {
        NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main App

@main
struct NotchSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // Hidden window — needed to give context to openSettings() in accessory apps
        Window("Hidden", id: "hidden") {
            HiddenContextView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topLeading)
        .windowStyle(.hiddenTitleBar)

        // Menu bar icon removed — actions are available via keyboard shortcuts
        // and the notch UI, so the status-bar badge was redundant.

        // NOTE: We intentionally do NOT use SwiftUI's `Settings { }` scene
        // here. That scene wraps our SettingsView in an AppKit-managed window
        // with its own title bar and outer corner mask — which fought our
        // custom chrome and caused visible "double rounded corners".
        // SettingsWindowController hosts SettingsView in a fully custom
        // NSWindow instead.
    }
}

// MARK: - HiddenContextView — Receives notification and opens Settings

struct HiddenContextView: View {
    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    SettingsWindowController.show()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowClosed)) { _ in
                // Deferred to the next turn of the runloop, and skipped when
                // the policy already matches.
                //
                // This fires from `windowWillClose` — the window is still on
                // screen. Changing the activation policy there makes AppKit
                // re-order the app's windows mid-teardown, which is when
                // anything else still alive gets a frame of visibility. Let the
                // close finish first; then there is nothing to re-order.
                guard !AppState.shared.settings.showInDock else { return }
                DispatchQueue.main.async {
                    if NSApp.activationPolicy() != .accessory {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            Text("Otto")
                .font(.headline)

            Divider()

            Button("Capture Area ⌃⇧4") {
                Task { await CaptureManager.shared.startCapture(mode: .area) }
            }

            Button("Capture Window ⌃⇧2") {
                Task { await CaptureManager.shared.startCapture(mode: .window) }
            }

            Button("Capture Screen ⌃⇧3") {
                Task { await CaptureManager.shared.startCapture(mode: .fullscreen) }
            }

            Button("Area + Editor ⌃⇧5") {
                NotificationCenter.default.post(name: .captureAreaWithEditor, object: nil)
            }

            Divider()

            Text("\(appState.screenshots.count) screenshots in session")
                .font(.caption)
                .foregroundColor(.secondary)

            if !appState.screenshots.isEmpty {
                Button("Clear session") {
                    appState.clearSession()
                }
            }

            Divider()

            Button("Settings…") {
                NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Esci da Otto") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
    }
}

// MARK: - Menu Bar Icon with Badge

struct MenuBarIconView: View {
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "camera.viewfinder")

            if count > 0 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.58, blue: 0.0)) // Orange #FF9500
                    )
                    .offset(x: 6, y: -4)
            }
        }
    }
}
