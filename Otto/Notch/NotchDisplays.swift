import AppKit
import SwiftUI

// MARK: - The notch on every display (Marcello, 2026-10-19)
//
// With an external monitor attached the notch lived only on the MacBook, and
// with the lid closed it was nowhere you could see. Alcove offers "Display on:
// Built-in / Main / All displays / Selected" and draws a simulated notch where
// the hardware has none — one notch controller per display.
//
// Otto keeps ONE controller and ONE panel (the controller is woven through
// the whole app) and gets the same result differently: every display shows a
// notch, and the panel goes where you open it.
//
//   • The display the panel is on draws the real thing.
//   • Every OTHER display without a hardware notch gets a stub: the collapsed
//     silhouette, drawn by a tiny click-through window (`NotchStubs`).
//   • Pointing at a stub's notch (hover, or click) moves the panel to that
//     display, and it opens there as it would anywhere. A keyboard open goes
//     to the display with the pointer.
//
// The MacBook's own notch never goes away — it is hardware, and pointing at
// it brings the panel home. With the lid closed the built-in display is gone
// and the panel lives on the external one.

enum NotchDisplays: String, CaseIterable {
    /// The display with the hardware notch (or the main one without).
    case builtIn
    /// Every display.
    case all

    static let key = "notchDisplays"
    static var current: NotchDisplays {
        NotchDisplays(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .all
    }
}

extension NSScreen {
    /// The display's stable id for this session.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// The collapsed silhouette, on displays the panel is not on.
@MainActor
final class NotchStubs {
    static let shared = NotchStubs()
    private var windows: [CGDirectDisplayID: NSPanel] = [:]

    /// One stub per display that needs one; the rest taken down.
    func update(activeDisplay: CGDirectDisplayID?, size: (NSScreen) -> CGSize, cornerRadius: CGFloat) {
        let wanted = NotchDisplays.current == .all
            ? NSScreen.screens.filter { $0.displayID != activeDisplay && $0.safeAreaInsets.top == 0 }
            : []
        let ids = Set(wanted.compactMap(\.displayID))
        for (id, window) in windows where !ids.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
        for screen in wanted {
            guard let id = screen.displayID else { continue }
            let notch = size(screen)
            let fillet: CGFloat = 12
            let frame = NSRect(x: screen.frame.midX - notch.width / 2 - fillet,
                               y: screen.frame.maxY - notch.height,
                               width: notch.width + fillet * 2, height: notch.height)
            let window = windows[id] ?? Self.makeWindow()
            window.contentView = NSHostingView(rootView:
                NotchShape(bottomRadius: cornerRadius, filletRadius: fillet)
                    .fill(Color.black)
                    .frame(width: frame.width, height: frame.height))
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows[id] = window
        }
    }

    func hideAll() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private static func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Pure drawing: the controller's mouse monitor does the hit-testing.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}
