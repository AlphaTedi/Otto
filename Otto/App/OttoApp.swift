import SwiftUI
import AppKit

// MARK: - Main App

@main
struct OttoApp: App {
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
