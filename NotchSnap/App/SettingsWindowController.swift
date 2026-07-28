import AppKit
import SwiftUI

// MARK: - SettingsWindowController
//
// A standard macOS window hosting SettingsView.
//
// It used to fight the system for control of its own chrome: transparent
// background, hidden title, the titlebar's visual-effect view reached into and
// hidden, and a corner radius drawn by hand onto the hosting view. All of that
// existed to make a hand-built frosted surface look like a window. It also
// meant the window could never look like whatever macOS looks like next.
//
// Now it asks for the ordinary thing and gets the ordinary result — including
// the material behind a `.sidebar` List, and Liquid Glass on macOS 26 — with
// exactly two deviations, both standard practice for a sidebar app:
// a transparent titlebar and full-size content, so the sidebar's material runs
// up behind the traffic lights instead of stopping below them.

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var sharedController: SettingsWindowController?

    /// SU-6: the Today-tab nudge card opens Settings straight to Calendar,
    /// so discovery is one click rather than "go find it in Settings".
    static func showCalendarTab() {
        AppState.shared.pendingSettingsSection = .calendar
        show()
    }

    static func show() {
        if sharedController == nil {
            sharedController = SettingsWindowController()
        }
        guard let controller = sharedController else { return }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.center()
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        // The two deviations: let the sidebar's material continue up behind the
        // traffic lights, the way Finder and System Settings do.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Unified so the toolbar area belongs to the split view rather than
        // sitting on a separate strip above it.
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 520)

        self.init(window: window)
        window.delegate = self

        // A plain hosting view. No transparency, no hand-drawn corner radius —
        // the window draws its own background and its own corners, correctly,
        // on every OS version.
        window.contentView = NSHostingView(
            rootView: SettingsView().environmentObject(AppState.shared)
        )
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
            SettingsWindowController.sharedController = nil
        }
    }
}
