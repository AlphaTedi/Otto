import Foundation
import AppKit
import SwiftUI

// MARK: - NotchController — Alcove-style animated notch with 3 states

@MainActor
class NotchController: ObservableObject {
    static let shared = NotchController()

    @Published var state: NotchState = .idle
    @Published var contentVisible: Bool = false
    @Published var screenshotJustArrived: Bool = false

    // Notification state (Dynamic Island style)
    @Published var notificationContentVisible: Bool = false
    @Published var notificationThumbnail: NSImage? = nil
    @Published var notificationIcon: String? = nil
    @Published var notificationIconColor: Color = .white
    @Published var notificationIconFill: Color? = nil
    @Published var notificationRightText: String? = nil
    @Published var notificationShowCheckmark: Bool = false
    @Published var notificationWide: Bool = false

    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var keyMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var autoCollapseTimer: Timer?

    // Mouse velocity tracking
    private var lastMousePoint: NSPoint = .zero
    private var lastMouseTime: TimeInterval = 0
    private var lastMouseSpeed: CGFloat = 0

    // Drag-and-drop awareness: true while the user is dragging something
    // (files, text, images) anywhere on screen. While a drag is in flight
    // the notch NEVER auto-collapses, and touching the notch zone with a
    // drag expands it straight onto the file tray.
    private var isDragSessionActive = false {
        didSet {
            // Whatever ended the drag — drop, mouse-up, a stray move — a
            // pending "open the tray" must not survive it.
            if !isDragSessionActive {
                dragDwellTask?.cancel()
                dragDwellTask = nil
            }
        }
    }
    private var dragDwellTask: Task<Void, Never>?
    /// How long a drag must be HELD over the notch before the tray opens.
    /// Long enough that crossing the top of the screen never triggers it,
    /// short enough that aiming at the notch still feels immediate.
    private let dragDwellNanos: UInt64 = 450_000_000

    // Tuned parameters — hoverDebounce is read from settings (0-500ms, configurable)
    private var hoverDebounceNanos: UInt64 {
        UInt64(AppState.shared.settings.hoverDelayMs) * 1_000_000
    }
    private let collapseDelayNanos: UInt64 = 300_000_000  // 300ms delay before collapse
    private let maxTriggerSpeed: CGFloat = 300  // px/sec — ignore fast mouse transits

    // Geometry — @AppStorage for live Settings preview propagation
    @AppStorage("notchCornerRadius")   var cornerRadius: Double = 10
    @AppStorage("notchExpandedWidth")  var expandedWidth: Double = 680
    @AppStorage("notchExpandedHeight") var expandedHeight: Double = 200

    private(set) var notchSize: CGSize = .zero
    private(set) var hasPhysicalNotch: Bool = false

    var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: expandedHeight)
    }

    // MARK: - Setup

    func setup() {
        guard let screen = NSScreen.main else { return }

        // Calculate notch geometry
        hasPhysicalNotch = screen.safeAreaInsets.top > 0
        notchSize = calculateNotchSize(screen: screen)
        // Hugging height needs the strip height to size the to-do panel.
        AppState.shared.notchBarHeight = notchSize.height

        // Panel is ALWAYS at max expanded size — we animate the shape inside, not the window
        let panelFrame = calculateMaxPanelFrame(screen: screen)

        let panel = NotchPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true  // Starts true — only false when expanded (prevents stealing clicks from other apps)
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true

        // SwiftUI content — NotchRootView with the animated shape
        // NotchHostingView, not NSHostingView: the panel is far bigger than the
        // shape drawn inside it, and the transparent remainder must not eat
        // clicks meant for the app underneath.
        let hostingView = NotchHostingView(rootView: AnyView(
            NotchRootView(controller: self)
                .environmentObject(AppState.shared)
        ))
        hostingView.controller = self
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.orderFront(nil)
        self.panel = panel

        // Start mouse tracking
        startMouseTracking()

        // Observe screen parameter changes (resolution change, display (dis)connect,
        // fullscreen toggles that alter the menu bar) so the panel stays glued to the top.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Space changes (e.g. switching to a fullscreen app's Space) can also leave
        // the panel anchored to stale geometry — re-anchor on activation too.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange() {
        // Hop to the next runloop tick so NSScreen reports the new geometry.
        DispatchQueue.main.async { [weak self] in
            self?.repositionForCurrentScreen()
        }
    }

    private func repositionForCurrentScreen() {
        guard let panel, let screen = NSScreen.main else { return }
        hasPhysicalNotch = screen.safeAreaInsets.top > 0
        notchSize = calculateNotchSize(screen: screen)
        AppState.shared.notchBarHeight = notchSize.height
        let newFrame = calculateMaxPanelFrame(screen: screen)
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    // MARK: - State Transitions (with velocity preservation and interruptibility)

    func triggerHover() {
        guard state == .idle else { return }
        hoverTask?.cancel()

        let delay = hoverDebounceNanos
        if delay == 0 {
            // Accept mouse events so the local monitor can receive clicks to expand
            panel?.ignoresMouseEvents = false
            HapticManager.shared.hoverTap()
            withAnimation(NotchAnimation.hover) {
                state = .hovering
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                panel?.ignoresMouseEvents = false
                HapticManager.shared.hoverTap()
                withAnimation(NotchAnimation.hover) {
                    state = .hovering
                }
            }
        }
    }

    func triggerExpand() {
        // Cancel any collapse in progress
        collapseTask?.cancel()
        collapseTask = nil
        hoverTask?.cancel()
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        guard state != .expanded else { return }

        HapticManager.shared.expandTap()

        // Opening the panel is the moment the data must be current.
        CalendarStore.shared.refreshNow()

        expandTask = Task { @MainActor in
            // Allow key + accept mouse events so drag-and-drop works in expanded state
            (panel as? NotchPanel)?.allowKey = true
            panel?.ignoresMouseEvents = false

            // Step 1: animate the SHAPE (immediate)
            withAnimation(NotchAnimation.expand) {
                state = .expanded
            }
            AppState.shared.isNotchExpanded = true

            // Step 2: content fades in with delay (stagger) — the delay is in NotchAnimation.contentIn
            withAnimation(NotchAnimation.contentIn) {
                contentVisible = true
            }

            // Start auto-collapse timer
            startAutoCollapseTimer()
        }
    }

    /// Policy rule 2: a real click outside the panel closes it no matter
    /// which mode is up. Unpins first so the collapse guards can't veto it.
    private func handleOutsideClick(_ location: NSPoint) {
        guard state == .expanded, let screen = NSScreen.main else { return }
        guard !expandedPanelRect(screen: screen).insetBy(dx: -8, dy: -8).contains(location) else { return }
        forceCollapse()
    }

    /// Collapse that overrides the modal pin — the one guaranteed exit.
    func forceCollapse() {
        TodoStore.shared.setMode(.browsing)
        TodoStore.shared.showShortcuts = false
        panel?.resignKey()
        triggerCollapse()
    }

    func triggerCollapse() {
        // Guard against re-entry: mouse-move events call this continuously
        // while the cursor is outside the panel. Without the guard, every
        // event spawned a new collapse task and fired sound + haptic —
        // the "machine-gun" glitch. One collapse at a time, only from
        // the expanded state. Never collapse while a drag is in flight —
        // the user may be carrying a file to or from the tray — or while
        // the user is engaged (typing in the composer, date popover open).
        guard state == .expanded, collapseTask == nil,
              !isDragSessionActive, !isUserEngaged else { return }

        expandTask?.cancel()
        expandTask = nil
        hoverTask?.cancel()

        collapseTask = Task { @MainActor in
            // Step 1: hide content FIRST (immediate)
            withAnimation(NotchAnimation.contentOut) {
                contentVisible = false
            }

            // Step 2: after 80ms close the shape
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
            if Task.isCancelled {
                // The collapse was called off inside this 80ms window — the
                // cursor came back, or something cancelled it.
                //
                // Step 1 already hid the content. Returning here used to leave
                // the panel EXPANDED with contentVisible == false: an open,
                // black, empty notch that stayed that way until Escape
                // (Marcello, 2026-08-04). Put the content back, since we are
                // no longer collapsing, and release the task so a later
                // collapse is not blocked by the `collapseTask == nil` guard.
                withAnimation(NotchAnimation.contentIn) { contentVisible = true }
                collapseTask = nil
                return
            }

            // Feedback only when the collapse actually happens — a collapse
            // cancelled by hovering back in must stay silent.
            HapticManager.shared.notchCollapsed()

            withAnimation(NotchAnimation.collapse) {
                state = .idle
            }
            AppState.shared.isNotchExpanded = false
            autoCollapseTimer?.invalidate()
            autoCollapseTimer = nil

            // Tear down any open Quick Look + clear hover state.
            QuickLookPreviewController.shared.close()
            AppState.shared.hoveredQuickLookItem = nil

            // Revoke key status + stop intercepting mouse events
            (panel as? NotchPanel)?.allowKey = false
            panel?.resignKey()
            panel?.ignoresMouseEvents = true

            collapseTask = nil
        }
    }

    /// Give the notch panel keyboard focus so typing works immediately
    /// (used by the ⌃⇧N hotkey — the panel is non-activating, so making it
    /// key doesn't steal the whole app's activation).
    func makeKeyForTyping() {
        Task { @MainActor in
            // Let the expand animation put the panel into its key-able state.
            try? await Task.sleep(nanoseconds: 80_000_000)
            (panel as? NotchPanel)?.allowKey = true
            panel?.makeKey()
        }
    }

    func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    // MARK: - Show New Screenshot (Dynamic Island notification instead of full expand)

    func showNewScreenshot() {
        guard let lastItem = AppState.shared.screenshots.first else { return }
        triggerCaptureNotification(screenshot: lastItem)
    }

    // MARK: - Capture Notification (thumbnail + checkmark)

    func triggerCaptureNotification(screenshot: ScreenshotItem) {
        // If already in notification, cancel and restart
        notificationTask?.cancel()
        resetNotificationContent()

        // If expanded, don't interrupt
        guard state != .expanded else { return }

        // Set notification content
        notificationThumbnail = screenshot.cachedThumbnail
        notificationIcon = nil
        notificationRightText = nil
        notificationShowCheckmark = true
        notificationWide = false

        startNotificationSequence()
    }

    // MARK: - Clipboard Notification (icon + contextual text)

    func triggerClipboardNotification(item: ClipboardItem) {
        notificationTask?.cancel()
        resetNotificationContent()
        guard state != .expanded else { return }

        notificationThumbnail = nil
        notificationIcon = item.notchIcon
        notificationIconColor = item.notchIconColor
        notificationIconFill = nil

        // URL: show text snippet, no checkmark; everything else: checkmark only
        if item.type == .url {
            notificationRightText = item.notchRightLabel
            notificationShowCheckmark = false
            notificationWide = true
        } else {
            notificationRightText = nil
            notificationShowCheckmark = true
            notificationWide = false
        }

        startNotificationSequence()
    }

    private func resetNotificationContent() {
        notificationContentVisible = false
        notificationThumbnail = nil
        notificationIcon = nil
        notificationRightText = nil
        notificationShowCheckmark = false
        notificationWide = false
        notificationIconColor = .white
        notificationIconFill = nil
    }

    // MARK: - Notification Timing Sequence

    private func startNotificationSequence() {
        hoverTask?.cancel()
        collapseTask?.cancel()

        notificationTask = Task { @MainActor in
            // t=0ms: expand the pill
            HapticManager.shared.hoverTap()
            withAnimation(NotchAnimation.notificationExpand) {
                state = .captureNotification
            }

            // t=80ms: content fades in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(NotchAnimation.notificationContentIn) {
                notificationContentVisible = true
            }

            // t=2080ms: content fades out
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(NotchAnimation.notificationContentOut) {
                notificationContentVisible = false
            }

            // t=2130ms: contract the pill while the content is still mid-fade —
            // the two motions overlap so the close reads as one continuous
            // gesture instead of fade… pause… shrink.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(NotchAnimation.notificationContract) {
                state = .idle
            }

            // Clean up
            notificationThumbnail = nil
            notificationIcon = nil
            notificationRightText = nil
        }
    }

    // Legacy compatibility
    func expand() {
        triggerExpand()
    }

    func collapse() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        expandTask?.cancel()
        withAnimation(NotchAnimation.collapse) {
            state = .idle
            contentVisible = false
        }
        AppState.shared.isNotchExpanded = false
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        // Revoke key status + stop intercepting mouse events
        (panel as? NotchPanel)?.allowKey = false
        panel?.resignKey()
        panel?.ignoresMouseEvents = true
    }

    // MARK: - Right-Click Context Menu

    func showContextMenu(at location: NSPoint) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(
            title: "Otto Settings\u{2026}",
            action: #selector(AppDelegate.openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = NSApp.delegate
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Otto",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        // Ensure key status for context menu
        guard let notchPanel = panel as? NotchPanel,
              let contentView = notchPanel.contentView else { return }

        let wasAllowed = notchPanel.allowKey
        notchPanel.allowKey = true
        notchPanel.makeKeyAndOrderFront(nil)

        NSMenu.popUpContextMenu(menu, with: NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: notchPanel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!, for: contentView)

        // Restore previous key status after menu closes
        notchPanel.allowKey = wasAllowed
        if !wasAllowed { notchPanel.resignKey() }
    }

    // MARK: - Mouse Tracking

    private func startMouseTracking() {
        // ── CLOSE POLICY (Marcello, 2026-07-15) ─────────────────────
        // 1. Pointer LEAVING the panel: closes while browsing; never closes
        //    while a modal surface is up (create/find/category/overlay) —
        //    typing must not be yanked away by a stray mouse move.
        // 2. An explicit CLICK outside the panel ALWAYS closes, every mode —
        //    the creation draft survives (KB-11), nothing is lost.
        // 3. Esc backs out one level: modal surface → browsing → closed.
        // There is always a way out: one outside click, or Esc (twice at most).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]) { [weak self] event in
            let isDrag = event.type == .leftMouseDragged
            let isUp = event.type == .leftMouseUp
            let isDown = event.type == .leftMouseDown
            Task { @MainActor in
                guard let self else { return }
                if isDown {
                    // Global monitor = the click landed in ANOTHER app or the
                    // desktop (our own panel's clicks arrive via the local
                    // monitor) → policy rule 2.
                    self.handleOutsideClick(NSEvent.mouseLocation)
                    return
                }
                if isUp {
                    // Drag session over — normal hover/collapse rules resume.
                    self.isDragSessionActive = false
                    return
                }
                if isDrag {
                    // A leftMouseDragged with a populated drag pasteboard means
                    // the user is carrying something (file, image, text).
                    if NSPasteboard(name: .drag).pasteboardItems?.isEmpty == false {
                        self.isDragSessionActive = true
                    }
                } else {
                    // A plain mouse-move means the button is up — any drag is
                    // over (drag sessions can swallow the final mouse-up).
                    self.isDragSessionActive = false
                }
                self.handleMouseMoved(NSEvent.mouseLocation, timestamp: event.timestamp)
            }
        }

        // Spacebar Quick Look — works while the expanded notch is showing and
        // a tile is hovered. Mirrors Finder's spacebar preview.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49 { // spacebar
                // NSEvent local monitors fire on the main thread; this class
                // is @MainActor, so we can call into it directly.
                let handled = MainActor.assumeIsolated { self.handleSpacebar() }
                if handled { return nil }
            }
            if event.keyCode == 53 { // escape — close the notch even while
                                     // engaged (engagement blocks auto-collapse)
                let handled = MainActor.assumeIsolated { () -> Bool in
                    // A modal to-do surface owns Escape (backs out one level
                    // via TodoBrowsingKeyHandler); only a plain browsing
                    // panel closes outright.
                    guard !TodoStore.shared.isPanelPinnedOpen else { return false }
                    guard self.state == .expanded else { return false }
                    self.panel?.resignKey()
                    self.triggerCollapse()
                    return true
                }
                if handled { return nil }
            }
            return event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .leftMouseDown:
                    self.handleClick()
                case .rightMouseDown:
                    self.handleRightClick(event)
                case .leftMouseDragged:
                    // Drag-out from a tray card: our own app's drag events are
                    // local-only, so track them here to keep the notch open
                    // for the whole journey to the drop target.
                    if NSPasteboard(name: .drag).pasteboardItems?.isEmpty == false {
                        self.isDragSessionActive = true
                    }
                case .leftMouseUp:
                    self.isDragSessionActive = false
                default:
                    self.handleMouseMoved(NSEvent.mouseLocation, timestamp: event.timestamp)
                }
            }
            return event
        }
    }

    private func handleMouseMoved(_ location: NSPoint, timestamp: TimeInterval) {
        guard let screen = NSScreen.main else { return }
        let settings = AppState.shared.settings
        // Drag-to-tray works regardless of the notch trigger setting —
        // only plain hover behavior is gated by it.
        guard settings.notchTrigger == .hover || isDragSessionActive else { return }

        // Calculate mouse velocity
        let distance = hypot(location.x - lastMousePoint.x, location.y - lastMousePoint.y)
        let elapsed = timestamp - lastMouseTime
        lastMouseSpeed = elapsed > 0 ? distance / elapsed : 0
        lastMousePoint = location
        lastMouseTime = timestamp

        let inZone = isInTriggerZone(location, screen: screen)

        // ── Drag in flight ─────────────────────────────────────────────
        // Carrying a file/text/image changes the rules entirely:
        //   • HOLDING the drag over the notch opens it straight onto the Tray
        //   • the notch NEVER collapses mid-drag, so the user can wander
        //     to another window and back, or drag a tray item out.
        //
        // This used to fire the instant a drag touched a zone 120pt wider than
        // the notch and 2.5x its height, reasoning that while carrying
        // something the intent is obvious. It isn't. Dragging a browser or
        // Figma tab across the screen fills the drag pasteboard and passes
        // straight through the top centre, so the notch flew open mid-drag
        // (Marcello, 2026-08-05). Passing over a thing is not aiming at it:
        // the target is now the notch itself plus a small forgiveness margin,
        // and it has to be held there.
        if isDragSessionActive {
            if state != .expanded && dragTargetRect().contains(location) {
                if dragDwellTask == nil {
                    // Polls its own clock rather than waiting on mouse events.
                    // A hand held still emits NO events, so an event-driven
                    // timer can never confirm the one thing it needs to know —
                    // that the pointer stopped.
                    dragDwellTask = Task { @MainActor in
                        defer { self.dragDwellTask = nil }
                        var anchor = NSEvent.mouseLocation
                        var settled: UInt64 = 0
                        let tick: UInt64 = 50_000_000
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: tick)
                            guard !Task.isCancelled, self.isDragSessionActive,
                                  self.state != .expanded else { return }
                            let now = NSEvent.mouseLocation
                            guard self.dragTargetRect().contains(now) else { return }
                            if hypot(now.x - anchor.x, now.y - anchor.y) > 24 {
                                // Still travelling — a drag crossing the top of
                                // the screen never accumulates settled time, no
                                // matter how slowly it passes through.
                                anchor = now
                                settled = 0
                            } else {
                                settled += tick
                                if settled >= self.dragDwellNanos {
                                    AppState.shared.pendingNotchFilter = .tray
                                    self.triggerExpand()
                                    return
                                }
                            }
                        }
                    }
                }
            } else {
                dragDwellTask?.cancel()
                dragDwellTask = nil
            }
            cancelCollapse()
            return
        }

        if inZone && lastMouseSpeed < maxTriggerSpeed {
            if state == .idle {
                triggerHover()
            } else if state == .captureNotification {
                // Mouse approached during notification — interrupt and expand
                notificationTask?.cancel()
                notificationContentVisible = false
                triggerExpand()
            }
            cancelCollapse()
        } else if !inZone && state == .expanded {
            scheduleCollapseIfOutsidePanel(location, screen: screen)
        } else if !inZone && state == .hovering {
            hoverTask?.cancel()
            withAnimation(NotchAnimation.collapse) {
                state = .idle
            }
            panel?.ignoresMouseEvents = true
        } else if !inZone && state == .idle {
            hoverTask?.cancel()
        }
    }

    /// Spacebar Quick Look. Returns true if the event was consumed.
    private func handleSpacebar() -> Bool {
        // If a Quick Look panel is already up, close it regardless of state.
        if QuickLookPreviewController.shared.isVisible {
            QuickLookPreviewController.shared.close()
            return true
        }
        // Otherwise only react when the notch is actually expanded AND a
        // tile is currently being hovered.
        guard state == .expanded,
              let item = AppState.shared.hoveredQuickLookItem else {
            return false
        }
        QuickLookPreviewController.shared.show(item)
        return true
    }

    private func handleClick() {
        // Tested against the DRAWN shape, not the trigger zone: the trigger
        // zone is a deliberately forgiving hover target, and "I was near it"
        // must not mean "I clicked it". Opening the notch requires landing on
        // the notch (Marcello, 2026-08-05).
        let onNotch = visibleShapeScreenRect().contains(NSEvent.mouseLocation)
        switch state {
        case .idle, .hovering:
            if onNotch { triggerExpand() }
        case .captureNotification:
            if onNotch {
                // Interrupt notification → expand to full gallery
                notificationTask?.cancel()
                notificationContentVisible = false
                triggerExpand()
            }
        case .expanded:
            break
        }
    }

    private func handleRightClick(_ event: NSEvent) {
        guard visibleShapeScreenRect().contains(NSEvent.mouseLocation) else { return }
        showContextMenu(at: event.locationInWindow)
    }

    private func scheduleCollapseIfOutsidePanel(_ point: NSPoint, screen: NSScreen) {
        let panelRect = expandedPanelRect(screen: screen)
        let paddedRect = panelRect.insetBy(dx: -30, dy: -30)
        if !paddedRect.contains(point) {
            triggerCollapse()
        }
    }

    // MARK: - Hit Region

    /// A band of live area just BELOW the drawn notch — the one place the hit
    /// region is deliberately allowed to exceed the shape.
    ///
    /// On a MacBook with a real notch the collapsed pill occupies exactly the
    /// hardware cutout, so triggering it meant parking the pointer inside the
    /// cutout, where the display physically ends and the cursor is chopped in
    /// half. It looked like NotchSnap was clipping the cursor; nothing in
    /// software was, there are simply no pixels there (Marcello, 2026-08-05).
    ///
    /// The apron gives the pointer somewhere to rest a few points lower, on
    /// real display, while still counting as "on the notch". It is small
    /// enough that a click aimed at a browser tab still passes through — the
    /// tab bar sits far below this.
    ///
    /// The system cursor is NOT hidden. Doing that reliably means
    /// CGDisplayHideCursor, which is process-global and survives a crash: a
    /// bug there leaves the user with no pointer at all until they log out.
    /// Not a trade worth making for a cosmetic clip.
    private static let cursorApron: CGFloat = 8

    /// The rectangle the notch is ACTUALLY drawing right now, in screen
    /// coordinates — mirroring NotchShapeView's per-state geometry exactly.
    ///
    /// The panel window is deliberately huge (`calculateMaxPanelFrame`: the
    /// full expanded width by the tallest possible height) so the shape can
    /// animate without clipping. That leaves the great majority of the window
    /// transparent at any given moment. Anything that decides "did the user
    /// mean the notch?" has to test against THIS rect, never the window frame:
    /// a 680×580 invisible rectangle sitting over the top of the screen was
    /// swallowing clicks aimed at whatever was underneath — Figma's tab bar,
    /// a browser's tabs (Marcello, 2026-08-05).
    ///
    /// Same single geometry source as the renderer, so the hit region and the
    /// visible shape cannot drift apart.
    func visibleShapeScreenRect() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let notchRect = calculateNotchRect(screen: screen)

        // Matches NotchShapeView.currentFilletRadius.
        let fillet: CGFloat = (state == .hovering) ? 14 : 12
        let width: CGFloat
        let height: CGFloat
        switch state {
        case .idle:
            width = notchSize.width + fillet * 2
            height = notchSize.height + Self.cursorApron
        case .hovering:
            width = notchSize.width + 28 + fillet * 2
            height = notchSize.height + 6 + Self.cursorApron
        case .captureNotification:
            width = notificationWide ? 320 : notchSize.width + 80 + fillet * 2
            height = notchSize.height
        case .expanded:
            width = expandedSize.width
            height = expandedSize.height + currentExtraExpandedHeight
        }
        return NSRect(x: notchRect.midX - width / 2,
                      y: screen.frame.maxY - height,
                      width: width,
                      height: height)
    }

    /// Where a drag has to be HELD to open the tray: the drawn notch plus a
    /// small forgiveness margin. Big enough to hit while carrying something,
    /// nowhere near big enough to catch a drag crossing the top of the screen.
    private func dragTargetRect() -> NSRect {
        visibleShapeScreenRect().insetBy(dx: -16, dy: -8)
    }

    // MARK: - Trigger Zone

    private func isInTriggerZone(_ point: NSPoint, screen: NSScreen) -> Bool {
        // PF-12/PF-13: tight containment against the SAME rect used to
        // render the collapsed notch, with a deliberate 8px side buffer —
        // no broad proximity band. The hit zone and the visual zone can't
        // drift apart because they share one geometry source.
        let notchRect = calculateNotchRect(screen: screen)
        let zone = NSRect(
            x: notchRect.minX - 8,
            y: notchRect.minY,
            width: notchRect.width + 16,
            height: notchRect.height + (screen.frame.maxY - notchRect.maxY)
        )
        return zone.contains(point)
    }

    // MARK: - Auto-Collapse Timer

    private func startAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        guard let seconds = AppState.shared.settings.autoCollapseSeconds else { return }

        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Staged close (content fades, then shape) — same path as
                // hover-out, so the timer close feels identical.
                self?.triggerCollapse()
            }
        }
    }

    // MARK: - Geometry Calculations

    private func calculateNotchSize(screen: NSScreen) -> CGSize {
        // Clamp to a sane menu-bar range: frame-vs-visibleFrame math can
        // report wildly large values around Space/display transitions, which
        // silently inflated the notch height AND its hover zone (the
        // "triggers from 100px away" bug).
        let computedMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let raw = computedMenuBarHeight > 10 ? computedMenuBarHeight : NSStatusBar.system.thickness
        let menuBarHeight = min(raw, 44)
        print("[NotchController] menuBarHeight=\(menuBarHeight), NSStatusBar=\(NSStatusBar.system.thickness), computed=\(computedMenuBarHeight)")

        if screen.safeAreaInsets.top > 0 {
            let leftArea = screen.auxiliaryTopLeftArea ?? .zero
            let rightArea = screen.auxiliaryTopRightArea ?? .zero
            let width = screen.frame.width - leftArea.width - rightArea.width
            return CGSize(width: width, height: menuBarHeight)
        } else {
            return CGSize(width: 180, height: menuBarHeight)
        }
    }

    private func calculateNotchRect(screen: NSScreen) -> NSRect {
        if hasPhysicalNotch {
            let leftArea = screen.auxiliaryTopLeftArea ?? .zero
            let notchX = screen.frame.origin.x + leftArea.width
            let notchY = screen.frame.maxY - notchSize.height
            return NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
        } else {
            let x = screen.frame.midX - notchSize.width / 2
            let y = screen.frame.maxY - notchSize.height
            return NSRect(x: x, y: y, width: notchSize.width, height: notchSize.height)
        }
    }

    /// The expanded shape can be taller than the base size (filter bar,
    /// Notes tab). The hover/collapse geometry MUST match, or the lower
    /// part of the UI counts as "outside" and hovering it closes the notch.
    /// Same single source the shape uses — hover/collapse geometry can never
    /// drift from what's rendered.
    private var currentExtraExpandedHeight: CGFloat {
        AppState.shared.notchExtraHeight
    }

    private func expandedPanelRect(screen: NSScreen) -> NSRect {
        let notchRect = calculateNotchRect(screen: screen)
        let height = expandedSize.height + currentExtraExpandedHeight
        return NSRect(
            x: notchRect.midX - expandedSize.width / 2,
            y: notchRect.maxY - height,
            width: expandedSize.width,
            height: height
        )
    }

    /// True while the user is actively working inside the notch — the panel
    /// is key (typing in the Notes composer) or one of its popovers (date
    /// picker) is key. Collapse is suspended so interaction can't be
    /// yanked away mid-click; it resumes once focus moves elsewhere.
    private var isUserEngaged: Bool {
        // A modal to-do surface (creation "+" tab, Quick Find, category
        // form, shortcuts overlay) pins the panel open — auto-collapse
        // mid-typing would destroy the draft.
        if TodoStore.shared.isPanelPinnedOpen { return true }
        // A live meeting alert holds the panel too: it opened itself, so a
        // stray mouse-out must not yank it away before it's been read. It
        // still auto-collapses on its own timer (CalendarStore).
        if CalendarStore.shared.activeAlert != nil { return true }
        guard let panel else { return false }
        if panel.isKeyWindow { return true }
        if let key = NSApp.keyWindow, key.parent === panel { return true }
        return false
    }

    // MARK: - To-do creation entry points (design PRD §3)

    /// KB-3: ⌘N / ⌥Space land on the in-panel "+" tab — one creation
    /// surface, no floating window.
    func openCreate() {
        TodoStore.shared.setMode(.create)
        triggerExpand()
        makeKeyForTyping()
    }

    /// FB8: a GLOBAL "new to-do" shortcut (⌃⇧N / ⌥⌘N from anywhere) — opens
    /// straight into the creation page on the user's default category, never
    /// on whatever was last browsed.
    func openCreateFresh() {
        TodoStore.shared.prepareGlobalCreateDraft()
        openCreate()
    }

    /// ⌥Space toggles: already on the "+" tab → dismiss; otherwise open it.
    func toggleCreate() {
        if state == .expanded && TodoStore.shared.panelMode == .create {
            TodoStore.shared.setMode(.browsing)
            panel?.resignKey()
            triggerCollapse()
        } else {
            openCreate()
        }
    }

    // MARK: - Meeting alerts (calendar PRD §3)

    /// CA-3/CA-6: the notch opens ITSELF before a meeting. Deliberately routed
    /// through the same `triggerExpand()` every click uses, so the
    /// self-triggered open is indistinguishable in feel from a manual one —
    /// same spring, same sequencing, no special "alert" animation.
    func presentMeetingAlert() {
        AppState.shared.pendingNotchFilter = .todos
        triggerExpand()
    }

    /// Collapse after an alert unless the user is doing something else in the
    /// panel (typing a to-do, mid-voice capture) — their work wins.
    func dismissMeetingAlert() {
        guard state == .expanded, !TodoStore.shared.isPanelPinnedOpen else { return }
        triggerCollapse()
    }

    /// Give the panel key status immediately (mode switches from inside the
    /// already-expanded panel, e.g. tapping the "+" tab).
    func focusPanel() {
        (panel as? NotchPanel)?.allowKey = true
        panel?.makeKey()
    }

    private func calculateMaxPanelFrame(screen: NSScreen) -> NSRect {
        let notchRect = calculateNotchRect(screen: screen)
        // VW-1: fixed width. Height headroom covers the tallest tab (Notes
        // with a full to-do list) so the shape can grow without clipping.
        // Taken from the SAME value the hugging height clamps against, plus a
        // small margin — a window smaller than the shape's own ceiling would
        // silently clip the bottom of the panel.
        let height = expandedSize.height + AppState.maxExtraHeight + 24
        return NSRect(
            x: notchRect.midX - expandedSize.width / 2,
            y: screen.frame.maxY - height,
            width: expandedSize.width,
            height: height
        )
    }
}

// MARK: - NotchPanel — NSPanel subclass
//
// canBecomeKey is dynamic:
// - true when expanded (needed for drag-and-drop & context menu)
// - false when idle/hovering (prevents stealing focus from other apps)

class NotchPanel: NSPanel {
    var allowKey = false

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
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
// there. Only points inside the drawn shape reach SwiftUI.
final class NotchHostingView: NSHostingView<AnyView> {
    weak var controller: NotchController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller, let window else { return super.hitTest(point) }
        // For a window's contentView the incoming point is in window
        // coordinates, which share the window's bottom-left origin.
        let screenPoint = NSPoint(x: window.frame.minX + point.x,
                                  y: window.frame.minY + point.y)
        let shape = MainActor.assumeIsolated { controller.visibleShapeScreenRect() }
        guard shape.contains(screenPoint) else { return nil }
        return super.hitTest(point)
    }
}
// MARK: - QuickLookPreviewController
// (QuickLookItem is defined in AppState.swift so it's always in scope.)
//
// Mimics Finder's spacebar Quick Look. While the expanded notch is up and
// the user hovers a thumbnail or clipboard tile, pressing the spacebar
// surfaces a centered, borderless NSPanel with a large preview. Spacebar /
// Escape / outside click dismisses it.

@MainActor
final class QuickLookPreviewController {
    static let shared = QuickLookPreviewController()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    var isVisible: Bool { panel != nil }

    func toggle(for item: QuickLookItem) {
        if isVisible {
            close()
        } else {
            show(item)
        }
    }

    func show(_ item: QuickLookItem) {
        close()

        guard let screen = NSScreen.main else { return }

        // Size: cap at 80% of the screen, with a comfortable minimum.
        let maxW = screen.visibleFrame.width  * 0.8
        let maxH = screen.visibleFrame.height * 0.8
        let size = NSSize(width: min(900, maxW), height: min(640, maxH))

        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let host = NSHostingView(rootView: QuickLookPreviewView(item: item))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()

        self.panel = panel
        installMonitors()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        if let m = keyMonitor   { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    // MARK: - Monitors (key + click-outside)

    private func installMonitors() {
        // Spacebar / Escape close — global so it works even though the panel
        // is non-activating and our app may not be frontmost.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 49 || event.keyCode == 53 { // space / escape
                Task { @MainActor in self.close() }
            }
        }
        // Local fallback (when our own panel happens to be key, e.g. after a
        // click): same keys, but consume the event.
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49 || event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
        // Stash the local monitor on top of the global one — close() removes both.
        if keyMonitor == nil { keyMonitor = local } else { clickMonitor = local }
    }
}

// MARK: - QuickLookPreviewView — SwiftUI body of the Quick Look panel

struct QuickLookPreviewView: View {
    let item: QuickLookItem

    var body: some View {
        ZStack {
            // Soft, blurred backdrop with a subtle stroke to feel like macOS Quick Look.
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            content
                .padding(24)
        }
        .shadow(color: .black.opacity(0.45), radius: 28, y: 10)
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .screenshot(let s):
            ScreenshotPreview(item: s)
        case .clipboard(let c):
            ClipboardPreview(item: c)
        }
    }
}

// MARK: - Screenshot preview body

private struct ScreenshotPreview: View {
    let item: ScreenshotItem

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: item.flattenedImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                Text(item.dimensions)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(item.relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Press Space to close")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Clipboard preview body

private struct ClipboardPreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(item.relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Press Space to close")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Group {
                switch item.type {
                case .screenshot, .image:
                    if let img = item.previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                case .color:
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colorFromItem)
                            .frame(width: 160, height: 160)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                        Text(item.previewText ?? "")
                            .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        Spacer()
                    }
                default:
                    ScrollView {
                        Text(item.previewText ?? "")
                            .font(.system(size: 14, design: item.type == .code ? .monospaced : .default))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var colorFromItem: Color {
        if let nsColor = item.previewColor { return Color(nsColor) }
        if let hex = item.previewText, let c = NSColor.fromHex(hex) { return Color(nsColor: c) }
        return .gray
    }
}
