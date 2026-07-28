import Foundation
import AppKit
import SwiftUI

// MARK: - Capture Action (result of inline editing phase)

enum CaptureAction {
    case copy
    case save
    case cancel
}

// MARK: - KeyableBorderlessWindow
//
// Borderless NSWindow return `canBecomeKey = false` by default, which prevents
// any embedded NSTextField (e.g. the text annotation field) from receiving
// keyboard focus. Override so our inline capture window becomes key on demand.
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Area Selector Window (fullscreen overlay for area selection + inline annotation)
//
// Phase 1: crosshair + drag to select area (existing flow)
// Phase 2: selection stays visible, radial menu + action bar + annotation canvas appear

@MainActor
class AreaSelectorWindow {
    private var window: NSWindow?

    /// Simple completion: returns just the rect (for silent capture, Ctrl+Shift+4)
    private var simpleCompletion: (@MainActor (CGRect?) -> Void)?
    /// Inline completion: returns rect + annotations + action (for edit-before-capture, Ctrl+Shift+5)
    private var inlineCompletion: (@MainActor (CGRect?, [AnnotationModel], CaptureAction, Bool) -> Void)?

    private var isInlineMode: Bool

    // Simple mode (backwards compatible)
    init(completion: @escaping @MainActor (CGRect?) -> Void) {
        self.simpleCompletion = completion
        self.inlineCompletion = nil
        self.isInlineMode = false
    }

    // Inline annotation mode. The trailing Bool indicates whether the selection
    // was produced by snapping to a detected window (→ apply rounded-corner mask).
    init(inlineCompletion: @escaping @MainActor (CGRect?, [AnnotationModel], CaptureAction, Bool) -> Void) {
        self.simpleCompletion = nil
        self.inlineCompletion = inlineCompletion
        self.isInlineMode = true
    }

    func show() {
        // Use the screen where the cursor is, not NSScreen.main —
        // on multi-desktop (Spaces) setups, .main is always the primary
        // physical display, which may be on a different Space.
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else {
            simpleCompletion?(nil)
            inlineCompletion?(nil, [], .cancel, false)
            return
        }

        let window = KeyableBorderlessWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let selectorView = AreaSelectorNSView(isInlineMode: isInlineMode) { [weak self] rect, annotations, action, isWindowSnap in
            window.orderOut(nil)
            self?.window = nil
            if let simple = self?.simpleCompletion {
                simple(rect)
            } else {
                self?.inlineCompletion?(rect, annotations, action, isWindowSnap)
            }
        }
        window.contentView = selectorView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectorView)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()

        self.window = window
    }
}

// MARK: - Area Selector NSView — Two-phase selection + inline annotation

class AreaSelectorNSView: NSView {

    // MARK: - Phase tracking

    enum Phase {
        case selecting   // Phase 1: crosshair + drag
        case editing     // Phase 2: tools visible, annotation mode
    }

    private var phase: Phase = .selecting
    private let isInlineMode: Bool
    private let completion: @MainActor (CGRect?, [AnnotationModel], CaptureAction, Bool) -> Void
    private var isWindowSnap: Bool = false

    // Phase 1 state
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var trackingArea: NSTrackingArea?

    // Window-snap (Phase 1): auto-detect windows and snap selection to their bounds
    // when the user clicks without dragging.
    private struct DetectedWindow {
        let rect: CGRect       // view coordinates (unflipped, like selectionRect)
        let windowNumber: Int
        let ownerName: String
    }
    private var detectedWindows: [DetectedWindow] = []
    private var hoveredWindow: DetectedWindow?
    private var didDrag: Bool = false
    private let dragThreshold: CGFloat = 5

    // Phase 2 state
    private(set) var selectionRect: CGRect = .zero // view coordinates (flipped=false)
    private var annotationCanvas: InlineAnnotationCanvas?
    private var toolbarHost: NSHostingView<AnyView>?
    private var actionBarHost: NSHostingView<CaptureActionBar>?

    // Resize handles
    private var activeHandle: ResizeHandle?
    private var handleDragStart: CGPoint = .zero
    private var rectBeforeDrag: CGRect = .zero

    // Shared annotation state (bridged to SwiftUI via ObservableObject)
    private let toolState = InlineToolState()

    // OCR state
    private var ocrHost: NSHostingView<AnyView>?

    // Local key monitor — intercepts keys at window level, bypasses first responder issues
    private var localKeyMonitor: Any?

    init(isInlineMode: Bool, completion: @escaping @MainActor (CGRect?, [AnnotationModel], CaptureAction, Bool) -> Void) {
        self.isInlineMode = isInlineMode
        self.completion = completion
        super.init(frame: .zero)
        // Layer-backed: without this every mouse move re-rasterizes the whole
        // screen-sized view on the CPU (very laggy on Retina). With a layer,
        // draw(_:) renders into a GPU-composited backing store instead.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setupTrackingArea()
        setupLocalKeyMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Hit testing
    //
    // The annotation canvas is a fullscreen subview and would otherwise steal clicks
    // that are meant for the resize handles on the selection border. Intercept those
    // first so handles remain draggable during the editing phase.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if phase == .editing, !toolState.isOCRMode {
            let local = convert(point, from: superview)
            if hitTestHandle(at: local) != nil {
                return self
            }
        }
        return super.hitTest(point)
    }

    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        if phase == .selecting {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            currentPoint = convert(mouseInWindow, from: nil)
            captureDetectedWindows()
            needsDisplay = true
        }
    }

    // MARK: - Window detection (for snap-to-window)

    /// Enumerate on-screen windows (excluding our own overlay + desktop/menubar chrome)
    /// and cache their bounds in view coordinates for hover hit-testing.
    private func captureDetectedWindows() {
        detectedWindows.removeAll()
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }

        // Our own overlay window number — never snap to ourselves.
        let ownWindowNumber = window?.windowNumber ?? -1

        // CG global coords have (0,0) at top-left of the *primary* display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height

        for entry in info {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let windowNumber = (entry[kCGWindowNumber as String] as? Int) ?? -1
            if windowNumber == ownWindowNumber { continue }
            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? ""
            // Skip trivially small windows (often helper panels)
            if cgRect.width < 40 || cgRect.height < 40 { continue }

            // CG (top-left origin, primary height) → AppKit screen coords (bottom-left origin)
            let screenY = primaryHeight - cgRect.origin.y - cgRect.height
            // Screen coords → view coords (this view's frame == its screen's frame)
            let viewRect = CGRect(
                x: cgRect.origin.x - screen.frame.origin.x,
                y: screenY - screen.frame.origin.y,
                width: cgRect.width,
                height: cgRect.height
            )
            // Only keep windows that are at least partially on this screen.
            if !viewRect.intersects(bounds) { continue }
            // Clip to screen bounds so the highlight never extends off-screen.
            let clipped = viewRect.intersection(bounds)
            detectedWindows.append(DetectedWindow(
                rect: clipped,
                windowNumber: windowNumber,
                ownerName: ownerName
            ))
        }
    }

    /// Topmost window under the given point. `detectedWindows` is in z-order
    /// (frontmost first) as returned by CGWindowListCopyWindowInfo.
    private func windowAt(_ point: CGPoint) -> DetectedWindow? {
        detectedWindows.first { $0.rect.contains(point) }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        if toolState.isOCRMode { return } // SwiftUI handles taps
        let point = convert(event.locationInWindow, from: nil)

        switch phase {
        case .selecting:
            startPoint = point
            currentPoint = point
            didDrag = false
            needsDisplay = true

        case .editing:
            // Check resize handles first
            if let handle = hitTestHandle(at: point) {
                activeHandle = handle
                handleDragStart = point
                rectBeforeDrag = selectionRect
                return
            }

            // Forward to annotation canvas if a tool is active
            if toolState.selectedTool != nil {
                annotationCanvas?.mouseDown(with: event)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch phase {
        case .selecting:
            currentPoint = point
            if let start = startPoint, hypot(point.x - start.x, point.y - start.y) > dragThreshold {
                didDrag = true
                hoveredWindow = nil
            }
            needsDisplay = true

        case .editing:
            if let handle = activeHandle {
                // Resize the selection
                let dx = point.x - handleDragStart.x
                let dy = point.y - handleDragStart.y
                selectionRect = resizedRect(original: rectBeforeDrag, handle: handle, dx: dx, dy: dy)
                updatePhase2Layout()
                needsDisplay = true
            } else if toolState.selectedTool != nil {
                annotationCanvas?.mouseDragged(with: event)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch phase {
        case .selecting:
            guard let start = startPoint, let end = currentPoint else {
                finish(rect: nil, annotations: [], action: .cancel)
                return
            }

            // Click without drag on a detected window → snap to its bounds.
            var rect = normalizedRect(from: start, to: end)
            if !didDrag, let snap = hoveredWindow ?? windowAt(end) {
                rect = snap.rect
                isWindowSnap = true
            } else {
                isWindowSnap = false
            }
            startPoint = nil
            didDrag = false
            guard rect.width >= 10, rect.height >= 10 else {
                finish(rect: nil, annotations: [], action: .cancel)
                return
            }

            if isInlineMode {
                // Transition to Phase 2
                selectionRect = rect
                enterPhase2()
            } else {
                // Simple mode — return rect immediately
                NSCursor.pop()
                let mousePos = NSEvent.mouseLocation
                guard let screen = NSScreen.screens.first(where: {
                    NSMouseInRect(mousePos, $0.frame, false)
                }) ?? NSScreen.main else {
                    finish(rect: nil, annotations: [], action: .cancel)
                    return
                }
                let screenRect = CGRect(
                    x: rect.origin.x,
                    y: screen.frame.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                finish(rect: screenRect, annotations: [], action: .copy)
            }

        case .editing:
            if activeHandle != nil {
                activeHandle = nil
            } else if toolState.selectedTool != nil {
                annotationCanvas?.mouseUp(with: event)
                refreshUndoState()
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if phase == .selecting {
            let p = convert(event.locationInWindow, from: nil)
            currentPoint = p
            // Only update hovered window when not actively dragging.
            if startPoint == nil {
                hoveredWindow = windowAt(p)
            }
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        // Handled by local key monitor — prevent system beep
    }

    // MARK: - Local Key Monitor (bypasses first responder chain)

    private func setupLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    /// Returns true if the event was handled (consumed).
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let hasCmd = flags.contains(.command)
        let hasShift = flags.contains(.shift)

        // If a text field (text annotation) is actively editing, let keystrokes
        // flow through to the field editor — otherwise typing would be swallowed.
        // Enter/Return (36) commits via the field's action, Esc (53) cancels it.
        if let responder = window?.firstResponder, responder is NSText {
            return false
        }

        // OCR mode
        if toolState.isOCRMode {
            if event.keyCode == 53 { exitOCRMode(); return true }
            if hasCmd && event.charactersIgnoringModifiers == "c" { ocrCopySelectedText(); return true }
            if hasCmd && event.charactersIgnoringModifiers == "a" { ocrSelectAll(); return true }
            return true // consume all keys in OCR mode
        }

        // ESC — cancel at any phase
        if event.keyCode == 53 {
            NSCursor.pop()
            finish(rect: nil, annotations: [], action: .cancel)
            return true
        }

        guard phase == .editing else { return false }

        // ⌘C → Copy
        if hasCmd && event.charactersIgnoringModifiers == "c" { performAction(.copy); return true }
        // ⌘S → Save
        if hasCmd && event.charactersIgnoringModifiers == "s" { performAction(.save); return true }
        // ⌘Z / ⌘⇧Z → Undo / Redo
        if hasCmd && event.charactersIgnoringModifiers == "z" {
            if hasShift { doRedo() } else { doUndo() }
            return true
        }

        // Tool shortcuts (no modifiers)
        if !hasCmd {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "p": toolState.selectedTool = .pen
            case "a": toolState.selectedTool = .arrow
            case "r": toolState.selectedTool = .rectangle
            case "t": toolState.selectedTool = .text
            case "b": toolState.selectedTool = .blur
            case "x": enterOCRMode(); return true
            default: break
            }

            // Color shortcuts 1-6
            if event.keyCode >= 18 && event.keyCode <= 23 {
                let index = Int(event.keyCode) - 18
                if index >= 0 && index < AnnotationToolbar.paletteColors.count {
                    toolState.selectedColor = AnnotationToolbar.paletteColors[index]
                }
            }

            // Brush size [ / ]
            if event.keyCode == 33 { toolState.lineWeight = max(2, toolState.lineWeight - 2) }
            else if event.keyCode == 30 { toolState.lineWeight = min(20, toolState.lineWeight + 2) }

            syncToolState()
            return true
        }

        return false
    }

    // MARK: - Phase 2 Setup

    private func enterPhase2() {
        phase = .editing
        NSCursor.pop() // Remove crosshair
        window?.invalidateCursorRects(for: self)

        // Create annotation canvas (fullscreen, clips to selectionRect)
        let canvas = InlineAnnotationCanvas(frame: bounds)
        canvas.clipRect = selectionRect
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        annotationCanvas = canvas

        // Create unified toolbar (SwiftUI hosted) inside an observing container so
        // canUndo/canRedo update reactively when the canvas changes.
        let toolbarView = InlineToolbarContainer(
            toolState: toolState,
            onUndo: { [weak self] in self?.doUndo() },
            onRedo: { [weak self] in self?.doRedo() },
            onOCR:  { [weak self] in self?.enterOCRMode() },
            onCancel: { [weak self] in self?.performAction(.cancel) },
            onCopy:   { [weak self] in self?.performAction(.copy) },
            onSave:   { [weak self] in self?.performAction(.save) },
            syncTools: { [weak self] in self?.syncToolState() }
        )
        let host = NSHostingView(rootView: AnyView(toolbarView))
        // Let SwiftUI compute the natural size so text never gets truncated.
        let fitting = host.fittingSize
        host.frame = toolbarFrame(preferredSize: fitting)
        addSubview(host)
        toolbarHost = host

        needsDisplay = true
    }

    private func updatePhase2Layout() {
        annotationCanvas?.clipRect = selectionRect
        if let host = toolbarHost {
            toolbarHost?.frame = toolbarFrame(preferredSize: host.fittingSize)
        }
        annotationCanvas?.needsDisplay = true
    }

    /// Returns the unified toolbar frame, clamped inside the screen so it never
    /// gets cropped at the edges (e.g. when the selection hugs left/right/bottom).
    private func toolbarFrame(preferredSize: CGSize) -> CGRect {
        let barWidth: CGFloat  = max(preferredSize.width,  320)
        let barHeight: CGFloat = max(preferredSize.height, 44)
        let spacing: CGFloat = 10
        let margin: CGFloat = 16
        let minX: CGFloat = margin
        let maxX: CGFloat = bounds.width - barWidth - margin
        let minY: CGFloat = margin
        let maxY: CGFloat = bounds.height - barHeight - margin

        // Prefer: centered below selection.
        var y = selectionRect.minY - barHeight - spacing
        // If no room below, put above.
        if y < minY {
            y = selectionRect.maxY + spacing
        }
        // If still overflowing, tuck it against the nearest vertical edge.
        y = max(minY, min(maxY, y))

        var x = selectionRect.midX - barWidth / 2
        x = max(minX, min(maxX, x))

        return CGRect(x: x, y: y, width: barWidth, height: barHeight)
    }

    // MARK: - OCR Mode

    private func enterOCRMode() {
        guard let screen = window?.screen ?? NSScreen.main,
              let overlayWindow = window else { return }

        // Convert selectionRect (NSView, bottom-left origin) to CG display coords (top-left origin)
        // For CGWindowListCreateImage: global coords with (0,0) at top-left of primary display
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgRect = CGRect(
            x: screen.frame.origin.x + selectionRect.origin.x,
            y: primaryHeight - (screen.frame.origin.y + selectionRect.origin.y + selectionRect.height),
            width: selectionRect.width,
            height: selectionRect.height
        )

        // Briefly hide our overlay so we capture clean screen content
        overlayWindow.orderOut(nil)

        // Small delay to let the window manager update
        usleep(50_000) // 50ms

        let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )

        // Restore overlay immediately
        overlayWindow.orderFront(nil)
        overlayWindow.makeKeyAndOrderFront(nil)
        overlayWindow.makeFirstResponder(self)

        guard let cgImage else {
            print("[OCR] CGWindowListCreateImage returned nil for rect: \(cgRect)")
            return
        }

        print("[OCR] Captured image: \(cgImage.width)×\(cgImage.height) for CG rect: \(cgRect)")

        toolState.isOCRMode = true

        // Hide annotation tools
        annotationCanvas?.isHidden = true
        toolbarHost?.isHidden = true
        actionBarHost?.isHidden = true

        // Display size = selectionRect size (not pixel size from Retina)
        let displaySize = selectionRect.size

        let extractionView = TextExtractionView(
            image: cgImage,
            imageSize: displaySize,
            onExit: { [weak self] in self?.exitOCRMode() }
        )

        let host = NSHostingView(rootView: AnyView(extractionView))
        host.frame = selectionRect
        addSubview(host)
        ocrHost = host

        // Ensure we keep receiving keyboard events
        window?.makeFirstResponder(self)
    }

    private func ocrCopySelectedText() {
        NotificationCenter.default.post(name: .ocrCopySelected, object: nil)
    }

    private func ocrSelectAll() {
        NotificationCenter.default.post(name: .ocrSelectAll, object: nil)
    }

    private func exitOCRMode() {
        toolState.isOCRMode = false
        ocrHost?.removeFromSuperview()
        ocrHost = nil

        // Restore annotation tools
        annotationCanvas?.isHidden = false
        toolbarHost?.isHidden = false
        actionBarHost?.isHidden = false

        // Restore keyboard focus
        window?.makeFirstResponder(self)
    }

    // MARK: - Undo / Redo bridge (updates observable state for toolbar)

    fileprivate func doUndo() {
        annotationCanvas?.undo()
        refreshUndoState()
    }

    fileprivate func doRedo() {
        annotationCanvas?.redo()
        refreshUndoState()
    }

    fileprivate func refreshUndoState() {
        guard let canvas = annotationCanvas else {
            toolState.canUndo = false
            toolState.canRedo = false
            return
        }
        toolState.canUndo = !canvas.annotations.isEmpty
        toolState.canRedo = !canvas.redoStack.isEmpty
    }

    // MARK: - Sync tool state to canvas

    private func syncToolState() {
        guard let canvas = annotationCanvas else { return }
        canvas.currentToolType = toolState.selectedTool ?? .pen
        canvas.currentColor = toolState.selectedColor
        canvas.lineWeight = toolState.lineWeight
    }

    // MARK: - Perform Action

    private func performAction(_ action: CaptureAction) {
        NSCursor.pop()

        let mousePos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mousePos, $0.frame, false)
        }) ?? NSScreen.main else {
            finish(rect: nil, annotations: [], action: .cancel)
            return
        }

        let annotations = annotationCanvas?.annotations ?? []

        // Convert selectionRect from view coords to screen coords (flip Y)
        let screenRect = CGRect(
            x: selectionRect.origin.x,
            y: screen.frame.height - selectionRect.origin.y - selectionRect.height,
            width: selectionRect.width,
            height: selectionRect.height
        )

        finish(rect: screenRect, annotations: annotations, action: action)
    }

    private func finish(rect: CGRect?, annotations: [AnnotationModel], action: CaptureAction) {
        finish(rect: rect, annotations: annotations, action: action, isWindowSnap: self.isWindowSnap)
    }

    private func finish(rect: CGRect?, annotations: [AnnotationModel], action: CaptureAction, isWindowSnap: Bool) {
        // Remove key monitor
        removeLocalKeyMonitor()

        // Clean up OCR views
        ocrHost?.removeFromSuperview()
        ocrHost = nil

        // Clean up Phase 2 views
        annotationCanvas?.removeFromSuperview()
        toolbarHost?.removeFromSuperview()
        actionBarHost?.removeFromSuperview()  // legacy, no longer used
        annotationCanvas = nil
        toolbarHost = nil
        actionBarHost = nil

        Task { @MainActor in
            completion(rect, annotations, action, isWindowSnap)
        }
    }

    // MARK: - Drawing (Phase 1 visuals + Phase 2 selection rect + handles)

    override func draw(_ dirtyRect: NSRect) {
        switch phase {
        case .selecting:
            drawSelectionPhase(dirtyRect)
        case .editing:
            drawEditingPhase(dirtyRect)
        }
    }

    private func drawSelectionPhase(_ dirtyRect: NSRect) {
        if let start = startPoint, let current = currentPoint {
            let rect = normalizedRect(from: start, to: current)

            // Subtle dim outside
            NSColor.black.withAlphaComponent(0.15).setFill()
            dirtyRect.fill()
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            // Selection border
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1.5
            border.stroke()

            // Dashed inner border
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let dashed = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            dashed.lineWidth = 0.5
            dashed.setLineDash([4, 4], count: 2, phase: 0)
            dashed.stroke()

            drawCoordinateLabel(at: current, size: rect.size)
        } else if let pos = currentPoint {
            // Window-snap highlight (shown only when a detected window is under the cursor
            // and the user hasn't started dragging).
            if let hovered = hoveredWindow {
                NSColor.black.withAlphaComponent(0.15).setFill()
                dirtyRect.fill()
                NSColor.clear.setFill()
                hovered.rect.fill(using: .copy)

                NSColor.systemBlue.withAlphaComponent(0.18).setFill()
                hovered.rect.fill()

                NSColor.systemBlue.setStroke()
                let border = NSBezierPath(rect: hovered.rect)
                border.lineWidth = 2
                border.stroke()

                drawCoordinateLabel(at: pos, size: hovered.rect.size)
            } else {
                drawCrosshair(at: pos)
                drawCoordinateLabel(at: pos, size: nil)
            }
        }
    }

    private func drawEditingPhase(_ dirtyRect: NSRect) {
        // Dim outside selection
        NSColor.black.withAlphaComponent(0.25).setFill()
        dirtyRect.fill()
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        // Selection border — blue
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 2.0
        border.stroke()

        // Dimension badge
        drawDimensionBadge()

        // Resize handles
        drawResizeHandles()
    }

    private func drawDimensionBadge() {
        let text = "\(Int(selectionRect.width)) \u{00D7} \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()

        let badgeRect = CGRect(
            x: selectionRect.minX,
            y: selectionRect.maxY + 6,
            width: textSize.width + 16,
            height: textSize.height + 8
        )

        let pill = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        pill.fill()
        str.draw(at: NSPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 4))
    }

    // MARK: - Resize Handles

    enum ResizeHandle: CaseIterable {
        case topLeft, topCenter, topRight
        case middleLeft, middleRight
        case bottomLeft, bottomCenter, bottomRight
    }

    private func handlePosition(_ handle: ResizeHandle) -> CGPoint {
        let r = selectionRect
        switch handle {
        case .topLeft:      return CGPoint(x: r.minX, y: r.maxY)
        case .topCenter:    return CGPoint(x: r.midX, y: r.maxY)
        case .topRight:     return CGPoint(x: r.maxX, y: r.maxY)
        case .middleLeft:   return CGPoint(x: r.minX, y: r.midY)
        case .middleRight:  return CGPoint(x: r.maxX, y: r.midY)
        case .bottomLeft:   return CGPoint(x: r.minX, y: r.minY)
        case .bottomCenter: return CGPoint(x: r.midX, y: r.minY)
        case .bottomRight:  return CGPoint(x: r.maxX, y: r.minY)
        }
    }

    private func drawResizeHandles() {
        for handle in ResizeHandle.allCases {
            let pos = handlePosition(handle)
            let handleRect = CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)

            // White filled circle with blue border
            NSColor.white.setFill()
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            NSColor.systemBlue.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func hitTestHandle(at point: CGPoint) -> ResizeHandle? {
        for handle in ResizeHandle.allCases {
            let pos = handlePosition(handle)
            if hypot(point.x - pos.x, point.y - pos.y) < 12 {
                return handle
            }
        }
        return nil
    }

    private func resizedRect(original: CGRect, handle: ResizeHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY

        switch handle {
        case .topLeft:      minX += dx; maxY += dy
        case .topCenter:    maxY += dy
        case .topRight:     maxX += dx; maxY += dy
        case .middleLeft:   minX += dx
        case .middleRight:  maxX += dx
        case .bottomLeft:   minX += dx; minY += dy
        case .bottomCenter: minY += dy
        case .bottomRight:  maxX += dx; minY += dy
        }

        // Minimum size
        if maxX - minX < 50 { minX = original.minX; maxX = original.maxX }
        if maxY - minY < 50 { minY = original.minY; maxY = original.maxY }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Phase 1 Drawing Helpers

    private func drawCrosshair(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let vLine = NSBezierPath()
        vLine.move(to: NSPoint(x: point.x, y: bounds.minY))
        vLine.line(to: NSPoint(x: point.x, y: bounds.maxY))
        vLine.lineWidth = 0.5
        vLine.stroke()

        let hLine = NSBezierPath()
        hLine.move(to: NSPoint(x: bounds.minX, y: point.y))
        hLine.line(to: NSPoint(x: bounds.maxX, y: point.y))
        hLine.lineWidth = 0.5
        hLine.stroke()
    }

    private func drawCoordinateLabel(at point: NSPoint, size: NSSize?) {
        let text: String = size != nil
            ? "\(Int(size!.width)) \u{00D7} \(Int(size!.height))px"
            : "\(Int(point.x)), \(Int(point.y))"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let labelRect = CGRect(x: point.x + 15, y: point.y - textSize.height - 10,
                               width: textSize.width + 12, height: textSize.height + 6)

        let pill = NSBezierPath(roundedRect: labelRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.75).setFill()
        pill.fill()
        str.draw(at: NSPoint(x: labelRect.origin.x + 6, y: labelRect.origin.y + 3))
    }

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }
}

// MARK: - InlineToolState — bridges NSView ↔ SwiftUI

class InlineToolState: ObservableObject {
    @Published var selectedTool: AnnotationToolType?
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWeight: CGFloat = 4.0
    @Published var isOCRMode: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
}

// MARK: - InlineToolbarContainer — observes InlineToolState so undo/redo refresh reactively

struct InlineToolbarContainer: View {
    @ObservedObject var toolState: InlineToolState
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onOCR:  () -> Void
    var onCancel: () -> Void
    var onCopy: () -> Void
    var onSave: () -> Void
    var syncTools: () -> Void

    var body: some View {
        AnnotationToolbar(
            activeTool: Binding(
                get: { toolState.selectedTool ?? .pen },
                set: { toolState.selectedTool = $0; syncTools() }
            ),
            activeColor: Binding(
                get: { toolState.selectedColor },
                set: { toolState.selectedColor = $0; syncTools() }
            ),
            brushSize: Binding(
                get: { toolState.lineWeight },
                set: { toolState.lineWeight = $0; syncTools() }
            ),
            canUndo: toolState.canUndo,
            canRedo: toolState.canRedo,
            onUndo: onUndo,
            onRedo: onRedo,
            onOCR:  onOCR,
            onCancel: onCancel,
            onCopy: onCopy,
            onSave: onSave
        )
    }
}
