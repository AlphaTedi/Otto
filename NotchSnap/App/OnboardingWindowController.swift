import AppKit
import SwiftUI

// MARK: - OnboardingWindowController — NSWindow (not NSPanel) for stable onboarding

class OnboardingWindowController: NSWindowController {

    private static var sharedController: OnboardingWindowController?

    static func show() {
        if sharedController == nil {
            sharedController = OnboardingWindowController()
        }
        // The app may be running as an accessory (no Dock icon) — become a
        // regular app first, or the window can silently stay behind others
        // on a fresh install.
        NotchController.shared.attentionLeft()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        sharedController?.showWindow(nil)
        sharedController?.window?.center()
        sharedController?.window?.makeKeyAndOrderFront(nil)
        sharedController?.window?.orderFrontRegardless()
    }

    /// Shrink and drop the window to the lower part of the screen for the
    /// practice steps.
    ///
    /// Those two steps ask the user to open the notch — and the notch expands
    /// DOWNWARD from the top of the screen, straight over a window centred in
    /// the middle of it. The instructions were being covered by the very thing
    /// they were instructing about, and it got worse the moment a to-do was
    /// added and the panel grew (Marcello, 2026-08-06).
    ///
    /// So the window gets out of the way instead: shorter, and parked near the
    /// bottom edge where the notch cannot reach it. Every other step keeps the
    /// full-size centred window.
    static func setCompact(_ compact: Bool) {
        guard let window = sharedController?.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let size = compact ? NSSize(width: 520, height: 300)
                           : NSSize(width: 600, height: 560)
        let vis = screen.visibleFrame
        let origin: NSPoint
        if compact {
            // Sit just above the Dock, well clear of anything the notch can
            // grow into.
            origin = NSPoint(x: vis.midX - size.width / 2, y: vis.minY + 48)
        } else {
            origin = NSPoint(x: vis.midX - size.width / 2,
                             y: vis.midY - size.height / 2)
        }
        window.setFrame(NSRect(origin: origin, size: size),
                        display: true, animate: true)
    }

    static func dismiss() {
        sharedController?.window?.close()
        sharedController = nil
        // Return to menu-bar-only mode if the user keeps the Dock icon off.
        Task { @MainActor in
            if !AppState.shared.settings.showInDock {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        // A hard safety envelope around setCompact's two real target sizes
        // (520x300 / 600x560). macOS enforces minSize/maxSize on EVERY
        // setFrame call, programmatic or not — so no computation error here,
        // in setCompact, or in the hosting view's own layout can ever again
        // produce a window that swallows the screen the way it did on
        // 2026-08-09 (Marcello: "I cannot go through the onboarding").
        window.minSize = NSSize(width: 480, height: 260)
        window.maxSize = NSSize(width: 640, height: 620)
        window.center()

        // Hide traffic lights
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.init(window: window)

        let hostingView = NSHostingView(rootView: OnboardingFlowView())
        window.contentView = hostingView
    }
}
