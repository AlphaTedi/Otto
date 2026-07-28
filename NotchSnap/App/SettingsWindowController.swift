import AppKit
import SwiftUI

// MARK: - SettingsWindowController
//
// Custom NSWindow that hosts SettingsView. The whole window is a single
// frosted-glass surface with rounded corners — traffic-light buttons sit
// at the standard top-left of THIS window, so they're inside the glass,
// not floating in nowhere.

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
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Strip every bit of native title-bar chrome — the traffic lights
        // remain visible at their default top-left position, but everything
        // else (title, separator, toolbar) is gone.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none

        // Transparent so our SwiftUI FrostedGlassBackground IS the window.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Kill the system's titlebar blur so the glass is uniform top-to-bottom.
        if let closeButton = window.standardWindowButton(.closeButton),
           let titlebarContainer = closeButton.superview?.superview {
            titlebarContainer.wantsLayer = true
            titlebarContainer.layer?.backgroundColor = NSColor.clear.cgColor
            for sibling in titlebarContainer.subviews {
                sibling.wantsLayer = true
                if String(describing: type(of: sibling)).contains("VisualEffect") {
                    sibling.isHidden = true
                }
            }
        }

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false

        self.init(window: window)
        window.delegate = self

        // Host SettingsView and apply the SINGLE rounded-corner mask of the
        // whole window. The glass background, sidebar tint, and content all
        // live inside this one shape.
        let host = NSHostingView(
            rootView: SettingsView().environmentObject(AppState.shared)
        )
        host.frame = NSRect(x: 0, y: 0, width: 880, height: 620)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        // Match the standard macOS window corner radius for the running OS.
        // Tahoe (macOS 26+) uses larger continuous curves; earlier systems
        // use the classic ~10pt radius.
        host.layer?.cornerRadius = Self.systemWindowCornerRadius()
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true

        window.contentView = host
    }

    // MARK: - NSWindowDelegate

    /// Standard macOS window corner radius for the current OS version.
    /// Tahoe (macOS 26+) → 12pt; earlier systems → 10pt.
    private static func systemWindowCornerRadius() -> CGFloat {
        if #available(macOS 26.0, *) { return 12 }
        return 10
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
            SettingsWindowController.sharedController = nil
        }
    }
}
