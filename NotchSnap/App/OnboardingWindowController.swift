import AppKit
import SwiftUI

// MARK: - OnboardingWindowController — NSWindow (not NSPanel) for stable onboarding

class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private static var sharedController: OnboardingWindowController?

    /// Dropped on close by ANY route, not just `dismiss()`.
    ///
    /// It used to be cleared in `dismiss()` alone, so a window closed any other
    /// way stayed alive behind the static — closed, invisible, and still one of
    /// the app's windows. That is what AppKit re-orders when the activation
    /// policy flips, which it does every time Settings opens and closes, and
    /// the stale onboarding window flashed for a frame on the way past
    /// (Marcello, 2026-08-22).
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            OnboardingWindowController.sharedController = nil
        }
    }

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
        let vis = screen.visibleFrame
        // The design is drawn at 1200x800, but a window may not be larger than
        // the screen it is on — clamped with a margin so the redesign does not
        // become unusable on a smaller display than the one it was drawn for.
        let full = NSSize(width: min(OnbMetric.windowWidth, vis.width - 80),
                          height: min(OnbMetric.windowHeight, vis.height - 80))
        let size = compact ? NSSize(width: 520, height: 300) : full
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
            contentRect: NSRect(x: 0, y: 0,
                                width: OnbMetric.windowWidth,
                                height: OnbMetric.windowHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        // Plain .normal — same as Settings, which never had this problem.
        // .floating pins a window ABOVE every other app's windows regardless
        // of which app is active, not just above Otto's own; the calendar
        // step opens a real browser tab for Google's consent screen, and a
        // floating onboarding window sat permanently on top of it with no way
        // to bring the browser forward (Marcello, 2026-08-09: "you cannot
        // move it behind another window"). NSApp.activate + makeKeyAndOrderFront
        // in show() already bring this window to the front on its own when it
        // opens; nothing here needed .floating to begin with.
        window.level = .normal
        window.isMovableByWindowBackground = true
        // A hard safety envelope around setCompact's two real target sizes
        // (520x300 / 600x560). macOS enforces minSize/maxSize on EVERY
        // setFrame call, programmatic or not — so no computation error here,
        // in setCompact, or in the hosting view's own layout can ever again
        // produce a window that swallows the screen the way it did on
        // 2026-08-09 (Marcello: "I cannot go through the onboarding").
        window.minSize = NSSize(width: 480, height: 260)
        window.maxSize = NSSize(width: OnbMetric.windowWidth, height: OnbMetric.windowHeight)
        window.center()

        // Hide traffic lights
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // ARC owns it through this controller. Left at its default `true`,
        // AppKit would free the window under the controller and the static
        // would be left pointing at freed memory.
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self

        // The export's 26pt corner. The window frame keeps the system radius,
        // but the frame is transparent — the rounded rect the content clips
        // itself to IS the visible window edge, which gets the design's corner
        // without going borderless and losing key-window and drag behaviour.
        let hostingView = NSHostingView(
            rootView: OnboardingFlowView()
                .clipShape(RoundedRectangle(cornerRadius: OnbMetric.windowRadius,
                                            style: .continuous))
        )
        window.contentView = hostingView
    }
}
