import Foundation
import AppKit
import SwiftUI

// MARK: - NotchPanel — NSPanel subclass
//
// canBecomeKey is dynamic:
// - true when expanded (needed for drag-and-drop & context menu)
// - false when idle/hovering (prevents stealing focus from other apps)

class NotchPanel: NSPanel {
    var allowKey = false

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }

    /// The only frame this panel may take: NotchController computes it from
    /// the screen and the notch. Any other request — SwiftUI propagating its
    /// content size from inside the display cycle, above all — is dropped:
    /// resizing the window there re-enters layout and AppKit aborts the app
    /// (see the hosting-view setup in NotchController). nil until the
    /// controller has pinned one.
    var pinnedFrame: NSRect?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if let pinnedFrame, frameRect != pinnedFrame { return }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        if let pinnedFrame, frameRect != pinnedFrame { return }
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }

    override func setContentSize(_ size: NSSize) {
        if let pinnedFrame, size != pinnedFrame.size { return }
        super.setContentSize(size)
    }
}

/// The notch panel's contentView: a plain holder for NotchHostingView, so the
/// hosting view is not the window's contentView and cannot size the window.
/// Transparent to clicks of its own — where NotchHostingView answers "not
/// mine" the event must still fall through to the app underneath, not stop
/// here.
final class NotchContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

// MARK: - NotchHostingView — clicks land on the notch, or on nothing at all
//
// `ignoresMouseEvents` is all-or-nothing per window, and the window is far
// larger than the shape inside it (see visibleShapeScreenRect). The moment the
// notch went from idle to hovering the whole 680×580 rectangle started
// accepting clicks, so pressing a Figma tab or a browser tab near the top of
// the screen hit an invisible panel instead of the app that was visibly there.
//
// Returning nil from hitTest is the AppKit way to say "not mine" — the event
// falls through to whatever is underneath, exactly as if the panel were not
// there. In the floating layout only the measured cards reach SwiftUI; the
// air between the notch and cards is no longer part of their hit region.
final class NotchHostingView: NSHostingView<AnyView> {
    weak var controller: NotchController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller, let window else { return super.hitTest(point) }
        // The incoming point is in NotchContainerView's coordinates, which —
        // the container being the window's contentView at the origin — are
        // window coordinates, sharing the window's bottom-left origin.
        let screenPoint = NSPoint(x: window.frame.minX + point.x,
                                  y: window.frame.minY + point.y)
        let acceptsClick = MainActor.assumeIsolated { () -> Bool in
            if controller.state == .expanded && AppState.shared.notchLayout == .panels {
                return controller.isInsidePanelContent(screenPoint)
            }
            return controller.visibleShapeScreenRect().contains(screenPoint)
                || controller.isInExtraPanelArea(screenPoint)
        }
        guard acceptsClick else { return nil }
        return super.hitTest(point)
    }
}
