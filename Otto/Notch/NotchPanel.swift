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
///
/// Then it ROUTES: spread over the open panel, it takes the drop itself and
/// hands it to `onDrop`, which puts it in the text under the pointer. The
/// panel's own text views never saw a drag — the trace showed the notch
/// open, under the dragged file, and not one draggingEntered reaching the
/// to-do field — so the drop no longer depends on the panel's hosting view
/// passing it down.
final class DragCatcherPanel: NSPanel {
    var onHeld: (() -> Void)?
    var dwell: TimeInterval = 0.3
    /// Routing mode: whether a drop at this screen point has a place to go,
    /// and putting it there.
    var canDrop: ((NSPoint) -> Bool)?
    var onDrop: ((NSPasteboard, NSPoint) -> Bool)?
    fileprivate(set) var isRouting = false

    /// Spread over `frame` (the open panel) and take the drop.
    func route(over frame: NSRect) {
        (contentView as? DropView)?.cancel()
        isRouting = true
        level = NSWindow.Level(rawValue: Self.dragLevel.rawValue + 1)
        setFrame(frame, display: false)
        orderFrontRegardless()
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        // A window lets the pointer — drags included — through wherever its
        // pixels are fully transparent. 0.001 alpha rounds to 0 in an 8-bit
        // backing store, which is exactly that: the first version of this
        // panel never saw a single drag. Opt in to the pointer explicitly,
        // and keep a fill that survives the rounding (3/255, unseen).
        ignoresMouseEvents = false
        backgroundColor = NSColor(white: 0, alpha: 0.012)
        hasShadow = false
        // Above the menu bar, but nowhere near the notch's own shielding
        // level: at shielding level + 1 the panel was up, in place, and not
        // one drag was offered to it (otto-drag trace, 2026-10-04) — the
        // drag system does not look for destinations that high. The idle
        // notch ignores the pointer, so it does not stand in the way.
        level = Self.dragLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let target = DropView()
        target.owner = self
        contentView = target
    }

    override var canBecomeKey: Bool { false }

    /// Over the menu bar, under the drag image: where drops are offered.
    static let dragLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)

    #if DEBUG
    /// /tmp/otto-drag.txt — what the catcher saw, for a drag only a person
    /// can make.
    static func trace(_ line: String) {
        let url = URL(fileURLWithPath: "/tmp/otto-drag.txt")
        let entry = Data("[\(Date())] \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(entry); try? handle.close()
        } else {
            try? entry.write(to: url)
        }
    }
    #endif

    func disarm() {
        (contentView as? DropView)?.cancel()
        orderOut(nil)
        isRouting = false
        level = Self.dragLevel
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
            #if DEBUG
            DragCatcherPanel.trace("entered: image=\(isImage) types=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? [])")
            #endif
            guard isImage else { return [] }
            if owner?.isRouting == true { return routeOperation() }
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
            if owner?.isRouting == true { return routeOperation() }
            return restingSince == nil ? [] : .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { cancel() }

        /// The plus cursor only over a place that takes the image.
        private func routeOperation() -> NSDragOperation {
            owner?.canDrop?(NSEvent.mouseLocation) == true ? .copy : []
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            cancel()
            guard owner?.isRouting == true else { return false }
            let done = owner?.onDrop?(sender.draggingPasteboard, NSEvent.mouseLocation) ?? false
            #if DEBUG
            DragCatcherPanel.trace("routed drop: inserted=\(done)")
            #endif
            return done
        }

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
                #if DEBUG
                DragCatcherPanel.trace("held: opening the notch")
                #endif
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
