import Foundation
import AppKit
import SwiftUI

// MARK: - NotchPanel — NSPanel subclass
//
// canBecomeKey is dynamic:
// - true when expanded (needed for drag-and-drop & context menu)
// - false when idle/hovering (prevents stealing focus from other apps)

/// The invisible drop target over the notch while a press is held
/// (NotchController.armDragCatcher). Accepts only drags carrying an image,
/// and calls `onHeld` once one has rested on it for `dwell` seconds.
final class DragCatcherPanel: NSPanel {
    var onHeld: (() -> Void)?
    var dwell: TimeInterval = 0.3

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        // Not clear: a window ignores the pointer, drags included, wherever
        // it draws nothing.
        backgroundColor = NSColor(white: 0, alpha: 0.001)
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let target = DropView()
        target.owner = self
        contentView = target
    }

    override var canBecomeKey: Bool { false }

    func disarm() {
        (contentView as? DropView)?.cancel()
        orderOut(nil)
    }

    private final class DropView: NSView {
        weak var owner: DragCatcherPanel?
        private var anchor = NSPoint.zero
        private var restingSince: Date?
        private var timer: Timer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL, .png, .tiff])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let isImage = MainActor.assumeIsolated { AttachmentStore.hasImage(sender.draggingPasteboard) }
            guard isImage else { return [] }
            anchor = NSEvent.mouseLocation
            restingSince = Date()
            // Polls rather than waits on draggingUpdated: a hand held still
            // sends nothing, and still is the one thing to confirm.
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            restingSince == nil ? [] : .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { cancel() }

        /// Nothing is dropped here: by the time a drop could land, the notch
        /// is open and this window is gone.
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { cancel(); return false }

        func cancel() {
            timer?.invalidate()
            timer = nil
            restingSince = nil
        }

        private func tick() {
            guard let since = restingSince else { return }
            let now = NSEvent.mouseLocation
            if hypot(now.x - anchor.x, now.y - anchor.y) > 24 {
                // Still travelling — a drag crossing the notch never opens it.
                anchor = now
                restingSince = Date()
            } else if Date().timeIntervalSince(since) >= owner?.dwell ?? 0.3 {
                cancel()
                owner?.onHeld?()
            }
        }
    }
}

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
