import Foundation
import AppKit
import SwiftUI

// MARK: - NotchController — Alcove-style animated notch with 3 states

@MainActor
class NotchController: ObservableObject {
    static let shared = NotchController()

    /// Container layout: where the gear / Notes · Meetings triggers sit, in
    /// NotchRootView's space, so their menus can be drawn above the
    /// silhouette instead of clipped inside it.
    @Published var containerMenuAnchors: [MenuAnchor: CGRect] = [:]
    /// The open container menu's frame on screen — it may hang past the
    /// silhouette, and that part still counts as the panel for clicks and
    /// for the pointer-left close.
    private(set) var overflowMenuRect: NSRect?

    /// Container layout: the detached meeting card under the silhouette, on
    /// screen. Like the overflow menu, it counts as the panel.
    private(set) var containerCardRect: NSRect?

    func setContainerCardFrame(_ frame: CGRect?) {
        guard let frame, let panel else { containerCardRect = nil; return }
        containerCardRect = NSRect(x: panel.frame.minX + frame.minX,
                                   y: panel.frame.maxY - frame.maxY,
                                   width: frame.width, height: frame.height)
    }

    /// The container silhouette's BODY width: the shape's frame is
    /// `expandedSize.width` including its two 12pt top fillets (NotchShapeView,
    /// expanded state), so the straight sides stand 12pt in from each edge.
    var containerBodyWidth: CGFloat { expandedSize.width - 2 * 12 }

    /// The silhouette's bottom corner radius while expanded (same formula as
    /// NotchShapeView.bottomCornerRadius).
    var containerBottomRadius: CGFloat {
        max(CGFloat(cornerRadius), min(28, expandedSize.height * 0.13)) + 4
    }

    /// The container silhouette's height while expanded — where the meeting
    /// card hangs from.
    var containerSilhouetteHeight: CGFloat { expandedSize.height + AppState.shared.notchExtraHeight }

    /// Extra live areas outside the silhouette (container layout).
    func isInExtraPanelArea(_ point: NSPoint, padding: CGFloat = 0) -> Bool {
        guard state == .expanded else { return false }
        return [overflowMenuRect, containerCardRect].contains { rect in
            rect.map { $0.insetBy(dx: -padding, dy: -padding).contains(point) } ?? false
        }
    }

    func setOverflowMenuFrame(_ frame: CGRect?) {
        guard let frame, let panel else { overflowMenuRect = nil; return }
        overflowMenuRect = NSRect(x: panel.frame.minX + frame.minX,
                                  y: panel.frame.maxY - frame.maxY,
                                  width: frame.width, height: frame.height)
    }

    @Published var state: NotchState = .idle {
        // An image chip's hover preview is its own window, so nothing closes
        // it when the notch does — a desktop swipe mid-hover left it floating
        // on screen (Marcello, 2026-10-01). Leaving `.expanded` closes it.
        didSet { if oldValue == .expanded, state != .expanded { ImagePreviewPanel.shared.dismiss() } }
    }
    /// Visibility follows presentation; cancelled tasks cannot strand an empty panel.
    var contentVisible: Bool { state == .expanded }

    private var panel: NSPanel?
    /// The drawn floating cards in the hosting view's top-left coordinate space.
    /// The gaps and shadow margins are deliberately absent.
    private var panelContentFrames: [CGRect] = []
    #if DEBUG
    /// Read-only, for the runtime probes in DebugDriver. Never in Release.
    var panelForDebug: NSPanel? { panel }
    var panelContentFramesForDebug: [CGRect] { panelContentFrames }
    #endif
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var keyMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
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
    /// How long a drag must be HELD over the notch before it opens.
    /// Long enough that crossing the top of the screen never triggers it,
    /// short enough that aiming at the notch still feels immediate.
    private let dragDwellNanos: UInt64 = 300_000_000

    // Tuned parameters — hoverDebounce is read from settings (0-500ms, configurable)
    private var hoverDebounceNanos: UInt64 {
        UInt64(AppState.shared.settings.hoverDelayMs) * 1_000_000
    }
    private let maxTriggerSpeed: CGFloat = 300  // px/sec — ignore fast mouse transits

    // Geometry — @AppStorage for live Settings preview propagation
    @AppStorage("notchCornerRadius")   var cornerRadius: Double = 10
    @AppStorage("notchExpandedWidth")  var expandedWidth: Double = 620
    @AppStorage("notchExpandedHeight") var expandedHeight: Double = 200

    private(set) var notchSize: CGSize = .zero
    private(set) var hasPhysicalNotch: Bool = false

    var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: expandedHeight)
    }

    // MARK: - Setup

    func setup() {
        guard let screen = notchScreen else { return }

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
        // A status-bar-level panel still belongs to the desktop compositor
        // during a horizontal Spaces gesture, so it travels with the desktop
        // even with `.stationary`. This is a tiny, transparent, click-through
        // overlay outside its visible silhouette, so the public screen-saver
        // overlay level is appropriate here: it stays at the hardware notch
        // while the desktops slide underneath.
        // The public half of the same recipe. `.screenSaver` (1000) is still
        // inside the range the Spaces transition composites; the shielding
        // level is the documented "above everything" constant, and Alcove
        // imports it alongside the private calls for exactly this reason.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // WHO OWNS SPACE MEMBERSHIP decides whether the notch slides.
        //
        // `.canJoinAllSpaces` asks AppKit to present the window on every
        // space, and AppKit carries it across during a swipe — that carrying
        // IS the bug. When SpaceAnchor is available the window server is told
        // directly instead, and the flag is dropped so the two cannot both
        // claim the job; `.stationary` stays either way, as the instruction
        // not to animate.
        //
        // If the private symbols are gone, this falls back to exactly the
        // behaviour Otto shipped before: the flag goes back on and the notch
        // travels, which is a visible annoyance rather than a broken app.
        // START with the AppKit behaviour, always.
        //
        // This used to be decided by `SpaceAnchor.isAvailable` — whether the
        // SYMBOLS resolved — and that is the wrong question. The symbols
        // resolved and the pin then failed (`CGSSpaceCreate` returned 0), so
        // the window had neither the private space nor `.canJoinAllSpaces`:
        // strictly worse than before the feature existed. The flag is only
        // dropped once a pin has actually SUCCEEDED, which is a fact rather
        // than a capability.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
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
        // NOTHING here may resize the window. This one line is the crash fix.
        //
        // An NSHostingView acting as a window's contentView propagates its
        // content's ideal size to the WINDOW, through
        // `updateAnimatedWindowSize` on every layout pass. That is fine for an
        // ordinary window and wrong for this one: NotchController computes the
        // panel's frame itself, from the screen and the notch, and SwiftUI
        // fighting it produced all three of the symptoms reported together
        // (Marcello, macOS 26.6.1, crash log 2026-08-22):
        //
        //   * The notch JUMPED RIGHT on click — the window was being resized
        //     while its origin stayed put, so the shape slid sideways.
        //   * It CRASHED a second later — resizing a window from inside the
        //     display cycle re-entered layout
        //     (setFrameSize -> setNeedsLayout -> _postWindowNeedsLayout),
        //     which throws, and an uncaught ObjC exception aborts.
        //   * Clicking outside STOPPED CLOSING it — `handleOutsideClick` tests
        //     against the frame the controller computed, but the real window
        //     had been grown past it, so "outside" was still inside.
        //
        // `sizingOptions = []` opts out of that propagation entirely. The
        // hosting view then only ever fills the frame it is given.
        hostingView.sizingOptions = []
        // …and it was not enough (crash log 2026-09-28, macOS 26.6.2, v1.67.0:
        // the same NSHostingView.updateAnimatedWindowSize -> setFrameSize ->
        // _postWindowNeedsLayout abort the moment the notch opened). Two
        // further guards, either of which breaks the loop on its own:
        //
        //   * The hosting view is no longer the window's contentView but sits
        //     inside a plain container, where it has no say over the window's
        //     size at all (the onboarding window learned the same lesson).
        //   * NotchPanel refuses any frame but `pinnedFrame`, the one this
        //     controller computed — whoever asks.
        let container = NotchContainerView(frame: panel.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        panel.pinnedFrame = panel.frame

        panel.orderFront(nil)
        // Only AFTER the window exists on screen: the window number is 0
        // until it is ordered in, and the window server has nothing to pin.
        //
        // AppKit's flag comes off only if this worked. A failed pin leaves the
        // window exactly as it behaved before any of this existed.
        self.panel = panel
        pinToOwnSpace()
        // Once more when the login rush is over, in case the window server
        // refused the first one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.pinToOwnSpace() }
        applyNotchAppearance()

        // Start mouse tracking
        startMouseTracking()
        installAutoCollapsePolicy()

        // Observe screen parameter changes (resolution change, display (dis)connect,
        // fullscreen toggles that alter the menu bar) so the panel stays glued to the top.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Do not set the frame during a Space swipe. Re-anchoring the frame
        // mid-transition is itself a way to make the panel visibly travel
        // with the desktop underneath it.
        //
        // Re-pin when the set of spaces CHANGES, though. A window is added to
        // the spaces that existed at the time; make a new desktop afterwards
        // and the notch is simply absent from it. Mission Control posts this
        // when spaces are added or removed.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pinToOwnSpace() }
        }
    }

    /// Put the panel in Otto's own space, and only once that has WORKED drop
    /// AppKit's `.canJoinAllSpaces` (which is what carries the notch along a
    /// desktop swipe). Every re-pin goes through here: re-pinning used to
    /// leave the flag on, so a pin that failed at launch — the window server
    /// is not always ready at login — and succeeded later still had AppKit
    /// dragging the notch across with the desktop, the "two notches" of
    /// Marcello's report (2026-09-30).
    private func pinToOwnSpace() {
        guard let panel else { return }
        if SpaceAnchor.pin(panel) {
            panel.collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
        } else {
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .fullScreenAuxiliary, .ignoresCycle]
        }
    }

    /// The display the notch belongs to.
    ///
    /// Deliberately NOT `NSScreen.main`, which means "the screen with the key
    /// window" — so on a two-display setup it becomes the external monitor the
    /// moment you click something over there, and the panel followed it. You
    /// then had Otto's simulated notch drawn on the external display AND the
    /// real hardware notch on the laptop: the notch, twice, one of them in the
    /// wrong place (Marcello, 2026-08-17).
    ///
    /// A notch is a property of one specific piece of hardware, so the panel is
    /// pinned to the display that actually has one (`safeAreaInsets.top > 0`).
    ///
    /// On a Mac where NO display has a notch — Marcello's own 2018 machine
    /// included, where the entire black silhouette is Otto's drawing — the
    /// panel still has to stop wandering. It falls back to the PRIMARY display
    /// (frame origin at zero, the one macOS hangs the menu bar off), not to
    /// `.main`, so it stays on one screen for the whole session instead of
    /// hopping to whichever display you last clicked on.
    var notchScreen: NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    @objc private func screenParametersDidChange() {
        // Hop to the next runloop tick so NSScreen reports the new geometry.
        DispatchQueue.main.async { [weak self] in
            self?.repositionForCurrentScreen()
        }
    }

    private func repositionForCurrentScreen() {
        guard let panel, let screen = notchScreen else { return }
        hasPhysicalNotch = screen.safeAreaInsets.top > 0
        notchSize = calculateNotchSize(screen: screen)
        AppState.shared.notchBarHeight = notchSize.height
        let newFrame = calculateMaxPanelFrame(screen: screen)
        // Pin first, and always: the panel refuses any other frame.
        (panel as? NotchPanel)?.pinnedFrame = newFrame
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true, animate: false)
        }
        pinToOwnSpace()
    }

    // MARK: - State Transitions (with velocity preservation and interruptibility)

    func triggerHover() {
        guard state == .idle else { return }
        hoverTask?.cancel()

        let delay = hoverDebounceNanos
        if delay == 0 {
            // Accept mouse events so the local monitor can receive clicks to expand
            panel?.ignoresMouseEvents = false
            HapticManager.shared.notchHoverEntered()
            withAnimation(NotchAnimation.hover) {
                state = .hovering
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                panel?.ignoresMouseEvents = false
                HapticManager.shared.notchHoverEntered()
                withAnimation(NotchAnimation.hover) {
                    state = .hovering
                }
            }
        }
    }

    /// `trigger` is only reported (anonymous usage counts): which way people
    /// open Otto is the keyboard-first question the numbers exist to answer.
    func triggerExpand(trigger: AnalyticsEvent.OpenTrigger = .other) {
        // Cancel any collapse in progress
        collapseTask?.cancel()
        collapseTask = nil
        hoverTask?.cancel()
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        guard state != .expanded else { return }

        Analytics.track(.notchOpened(trigger, layout: AppState.shared.notchLayout))
        HapticManager.shared.notchExpanded()

        // Opening the panel is the moment the data must be current.
        CalendarStore.shared.refreshNow()

        // Opening is the other moment the material comes back stale: the
        // second open rendered flat and desaturated where the first was right.
        GlassRefresh.shared.bump()

        // Allow key + accept mouse events so drag-and-drop works in expanded state
        (panel as? NotchPanel)?.allowKey = true
        panel?.ignoresMouseEvents = false
        // Take key on EVERY open, not only the keyboard ones.
        //
        // `allowKey` was set and then nothing ever asked for it on a
        // hover-open, so the panel sat unfocused: on macOS 26 the glass
        // draws its INACTIVE variant when its window is not key — lighter
        // and desaturated, which is the washed-out notch — and
        // `NSApp.keyWindow` was never ours, so typing went to Quick Find
        // instead of the field. `makeKey` on a nonactivating panel does
        // NOT bring the app forward; that is what the style mask is for.
        panel?.makeKey()

        // The caret is ready in EVERY space, not just Notes and Calendar.
        //
        // Those two focus their own field in `onAppear`, so they were ready to
        // type the moment they were drawn. A to-do section's draft row waits
        // for `draftWantsFocus`, which only the ⌃⇧N hotkey ever set — so
        // opening on Grocery, Work or Personal left you with a field you had
        // to click before you could write (Marcello, 2026-09-20). Same
        // contract, now asked for from the same place.
        //
        // HERE and not in `triggerHover`: a panel that opened because the
        // pointer crossed it must never take the caret away from whatever the
        // user was actually typing in.
        //
        // After `makeKey()` above, deliberately — the field's
        // `makeFirstResponder` on a window that is not key yet is thrown away
        // when the window later becomes key and resets to its initial
        // responder. That ordering is the same one `makeKeyForTyping` had to
        // learn.
        if TodoStore.shared.panelMode == .browsing {
            TodoStore.shared.draftWantsFocus = true
        }

        // Step 1: animate the SHAPE (immediate)
        withAnimation(NotchAnimation.expand) {
            state = .expanded
        }
        AppState.shared.isNotchExpanded = true

        // Start auto-collapse timer
        startAutoCollapseTimer()
    }

    /// Policy rule 2: a real click outside the panel closes it no matter
    /// which mode is up. Unpins first so the collapse guards can't veto it.
    private func handleOutsideClick(_ location: NSPoint) {
        guard state == .expanded else { return }
        guard !isInsidePanelContent(location) else { return }
        forceCollapse()
    }

    func setPanelContentFrames(_ frames: [CGRect]) {
        panelContentFrames = frames.filter { !$0.isEmpty }
    }

    /// Convert each measured card from the hosting view's top-left origin to
    /// screen coordinates. The detached cards are separate hit regions: the
    /// area above them, the meeting gap, and the shadow all count as outside.
    func isInsidePanelContent(_ location: NSPoint) -> Bool {
        guard state == .expanded, AppState.shared.notchLayout == .panels else {
            return visibleShapeScreenRect().contains(location) || isInExtraPanelArea(location)
        }
        guard let panel else { return false }
        return panelContentFrames.contains { frame in
            let screenFrame = NSRect(x: panel.frame.minX + frame.minX,
                                     y: panel.frame.maxY - frame.maxY,
                                     width: frame.width, height: frame.height)
            return screenFrame.contains(location)
        }
    }

    /// Pins the panel window to the dark appearance in the container layout.
    ///
    /// `darkGroundSurface()` states the same thing for SwiftUI, and for the
    /// panels layout that is enough — the only thing on black there is the
    /// notch strip itself. The container layout draws the WHOLE to-do panel
    /// inside the black silhouette, and two things in there do not read
    /// SwiftUI's environment at all: NSVisualEffectView materials, and the
    /// NSTextViews behind the draft row and the title field, which colour
    /// themselves from their window's `effectiveAppearance`. On a Light
    /// system that put near-black text on the black notch.
    ///
    /// nil, not `.aqua`, for the panels layout: the glass has to follow the
    /// system, which is what an unset appearance means.
    func applyNotchAppearance() {
        panel?.appearance = AppState.shared.notchLayout == .container
            ? NSAppearance(named: .darkAqua)
            : nil
    }

    /// Collapse that overrides the modal pin — the one guaranteed exit.
    func forceCollapse() {
        // An alert on screen when the notch is forced shut has to be told, or
        // it stays "active" with nothing drawing it: the panel then counts
        // itself engaged forever and CalendarStore refuses to raise any later
        // alert, because it believes one is still up.
        CalendarStore.shared.alertLostAttention()
        // Keep the place, drop only the passing state: the notch reopens where
        // it was closed — the note being written, the section being filled
        // (Marcello, 2026-09-24). This used to reset to the lists, and it is
        // the close that runs when you click away to copy something, so every
        // trip out for a paste landed you back on Work.
        TodoStore.shared.settleForClose()
        TodoStore.shared.showShortcuts = false
        // Actually relinquish key status, don't just announce it. resignKey()
        // is what AppKit CALLS on a window to tell it the status is gone; it
        // does not give the status up, so `panel.isKeyWindow` stayed true and
        // isUserEngaged kept vetoing the collapse underneath. allowKey backs
        // canBecomeKey, so dropping it first is what makes the resign stick.
        (panel as? NotchPanel)?.allowKey = false
        panel?.resignKey()
        // force: this is the guaranteed exit. Re-applying isUserEngaged here
        // is what made "force" a misnomer — clicking a button inside the panel
        // makes it key, and a key panel counted as "engaged", so the one path
        // that exists to always work was blocked by the user having clicked
        // something (Marcello, 2026-08-10).
        triggerCollapse(force: true)
    }

    /// - Parameter force: skip the "user is engaged" veto. Used by
    ///   `forceCollapse` for the paths that must always work — an explicit
    ///   outside click, Escape, dismissing a meeting alert. A drag in flight
    ///   still blocks even a forced collapse: the user may be carrying a file
    ///   to the tray, and yanking the target away mid-drag loses the drop.
    func triggerCollapse(force: Bool = false) {
        // Guard against re-entry: mouse-move events call this continuously
        // while the cursor is outside the panel. Without the guard, every
        // event spawned a new collapse task and fired sound + haptic —
        // the "machine-gun" glitch. One collapse at a time, only from
        // the expanded state. Never collapse while a drag is in flight —
        // the user may be carrying a file to or from the tray — or while
        // the user is engaged (typing in the composer, date popover open).
        guard state == .expanded, collapseTask == nil,
              !isDragSessionActive, force || !isUserEngaged else { return }

        hoverTask?.cancel()

        collapseTask = Task { @MainActor in
            // Keep the content visible until the panel actually closes. A cancelled
            // task must neither hide content nor clear a newer collapse task.
            do { try await Task.sleep(nanoseconds: 80_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }

            // Feedback only when the collapse actually happens — a collapse
            // cancelled by hovering back in must stay silent.
            HapticManager.shared.notchCollapsed()

            withAnimation(NotchAnimation.collapse) {
                state = .idle
            }
            AppState.shared.isNotchExpanded = false
            // The caret went with the panel; the text did not — policy rule 2.
            TodoStore.shared.releaseDraftFocus()
            autoCollapseTimer?.invalidate()
            autoCollapseTimer = nil

            // Revoke key status + stop intercepting mouse events
            (panel as? NotchPanel)?.allowKey = false
            panel?.resignKey()
            panel?.ignoresMouseEvents = true

            // Day-old completions move to the Markdown archive on the way
            // OUT, never while the panel is open — rows silently vanishing
            // from a Completed section the user is looking at would read as
            // data loss. Once per day; the call is a no-op otherwise.
            TodoStore.shared.archiveOldCompletedIfNeeded()

            collapseTask = nil
        }
    }

    /// Give the notch panel keyboard focus so typing works immediately
    /// (used by the ⌃⇧N hotkey — the panel is non-activating, so making it
    /// key doesn't steal the whole app's activation).
    /// The global-hotkey path into typing. Same contract as `focusPanel()`,
    /// just deferred until the expand animation has the panel in a key-able
    /// state — and it MUST activate the app for the same reason: a
    /// nonactivating panel never takes focus from the frontmost application on
    /// its own, so ⌥⌘N used to open the creation field with a focus ring while
    /// every keystroke continued on into Chrome (Marcello's testers,
    /// 2026-08-06).
    func makeKeyForTyping() {
        Task { @MainActor in
            // Let the expand animation put the panel into its key-able state.
            try? await Task.sleep(nanoseconds: 80_000_000)
            focusPanel()
            // Ask for the caret AFTER the window is key — the ordering IS the
            // fix. The field's `makeFirstResponder` ran the moment
            // `draftWantsFocus` was set, before this sleep, on a window that
            // was not key yet; `makeKeyAndOrderFront` then resets the
            // responder to the window's initial one. The request was made and
            // thrown away, so the first character typed seeded Quick Find.
            //
            // And into the field of the space that is ON SCREEN: the notch
            // reopens where it was closed, so a note left open gets its caret
            // back rather than the to-do draft row it is not showing.
            TodoStore.shared.requestCaretForCurrentSpace()
        }
    }

    func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    /// Straight to idle, skipping the collapse policy (engagement, pinned
    /// surfaces). DebugDriver's `collapse` command only.
    func collapse() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        collapseTask = nil
        withAnimation(NotchAnimation.collapse) {
            state = .idle
        }
        AppState.shared.isNotchExpanded = false
        TodoStore.shared.releaseDraftFocus()
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

    // MARK: - Auto-collapse policy
    //
    // The panel floats at .statusBar + 1, above every other window on the
    // machine. Left open it sits on top of whatever the user moved on to, and
    // an open notch during a screen share or a call is worse than useless
    // (Marcello, 2026-08-06).
    //
    // The governing idea: THE NOTCH IS A GLANCE, NOT A WINDOW. It should be
    // open only while it is the thing being looked at. Everything below follows
    // from that, and each rule answers "has the user's attention demonstrably
    // gone somewhere else?"
    //
    // CLOSE IMMEDIATELY — attention has moved; overrides the typing/modal pin,
    // because a draft is preserved anyway and a panel stuck over another app is
    // the worse failure:
    //   1. Another application becomes frontmost.
    //   2. Otto itself resigns active.
    //   3. One of Otto's own windows takes over — Settings, onboarding.
    //   4. The Space changes, or a fullscreen app takes the screen.
    //   5. The Mac sleeps, the screens sleep, or the session is locked.
    //   6. The display arrangement changes (the panel's geometry is now stale).
    //   7. A link is opened out of the notch — joining a meeting hands over to
    //      the browser, so the notch has finished its job.
    //   8. WITHDRAWN 2026-08-16. A to-do captured through the GLOBAL shortcut
    //      used to close the notch — "note it and get back to work", the way
    //      Things and Alfred do. Marcello asked for it to stay open: with the
    //      draft row permanent and ⏎ now handing the caret back, the panel
    //      that remains is a list showing the thing you just made, at the top
    //      where you can see it. Closing it hid the confirmation. One Escape
    //      still closes.
    //
    // CLOSE POLITELY — existing rules, which respect a drag in flight and an
    // active typing surface: pointer leaves while browsing, an explicit outside
    // click, Escape, the auto-collapse timer.
    //
    // NEVER CLOSE, even for rules 1-8:
    //   * while a drag is in flight — the user may be carrying a file to the
    //     tray, and switching apps mid-drag is normal.
    //   * while a meeting alert is up. It opened itself because something is
    //     about to start and it already has its own dismissal timer; killing it
    //     on an app switch would silently drop the one notification that
    //     matters most.
    private func installAutoCollapsePolicy() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(anotherAppTookOver(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        for name: NSNotification.Name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            ws.addObserver(self, selector: #selector(attentionLeft), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(attentionLeft),
            name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(attentionLeft),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func anotherAppTookOver(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        // Otto activating itself — which focusPanel does on purpose so the user
        // can type — must not close the panel it just opened.
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        attentionLeft()
    }

    /// Rule 1-8's single implementation.
    @objc func attentionLeft() {
        Task { @MainActor in
            guard self.state == .expanded else { return }
            guard !self.isDragSessionActive else { return }
            // A live meeting alert used to return here, which is what made an
            // interruption into a modal: clicking another app did nothing,
            // the notch stayed over whatever was underneath, and the only way
            // back to the screen was to deal with the alert first (Marcello,
            // 2026-09-06: "blocca l'interfaccia"). An interruption you cannot
            // walk away from is not a notification.
            //
            // forceCollapse snoozes it on the way out, so walking away costs
            // nothing — the meeting comes back after the snooze interval.
            self.forceCollapse()
        }
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
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let isDrag = event.type == .leftMouseDragged
            let isUp = event.type == .leftMouseUp
            let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown
            let isLeftDown = event.type == .leftMouseDown
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }
                if isDown {
                    if isLeftDown { self.armDragCatcher() }
                    // Global monitor = the click landed in ANOTHER app or the
                    // desktop. Even if that window overlaps the card's screen
                    // coordinates, the click did not land in Otto's panel.
                    if self.state == .expanded { self.forceCollapse() }
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
                self.handleMouseMoved(location, timestamp: event.timestamp)
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // escape — close the notch even while
                                     // engaged (engagement blocks auto-collapse)
                let handled = MainActor.assumeIsolated { () -> Bool in
                    // A modal to-do surface owns Escape (backs out one level
                    // via TodoBrowsingKeyHandler); only a plain browsing
                    // panel closes outright.
                    guard !TodoStore.shared.isPanelPinnedOpen else { return false }
                    guard self.state == .expanded else { return false }
                    // forceCollapse, not resignKey + triggerCollapse: the
                    // panel being key counts as "engaged", resignKey alone
                    // does not give key status up (allowKey has to drop
                    // first — see forceCollapse), and an unforced collapse
                    // is vetoed by the very engagement pressing Esc created.
                    // The event was consumed and nothing closed: the exact
                    // "Esc doesn't work while the notch is open" report
                    // (Thomas, 2026-09-01).
                    self.forceCollapse()
                    return true
                }
                if handled { return nil }
            }
            return event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            // Snapshot before hopping actors — NSEvent isn't Sendable.
            let inNotchWindow = event.window is NotchPanel
            let location = NSEvent.mouseLocation
            let eventLocation = event.locationInWindow
            let timestamp = event.timestamp
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .leftMouseDown:
                    self.handleClick(at: location, inNotchWindow: inNotchWindow)
                case .rightMouseDown:
                    self.handleRightClick(at: location, eventLocation: eventLocation,
                                          inNotchWindow: inNotchWindow)
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
                    self.handleMouseMoved(location, timestamp: timestamp)
                }
            }
            return event
        }
    }

    private func handleMouseMoved(_ location: NSPoint, timestamp: TimeInterval) {
        guard let screen = notchScreen else { return }
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
            cancelCollapse()
            return
        }

        if inZone && lastMouseSpeed < maxTriggerSpeed {
            if state == .idle {
                triggerHover()
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

    private func handleClick(at location: NSPoint, inNotchWindow: Bool) {
        // Tested against the DRAWN shape, not the trigger zone: the trigger
        // zone is a deliberately forgiving hover target, and "I was near it"
        // must not mean "I clicked it". Opening the notch requires landing on
        // the notch (Marcello, 2026-08-05).
        let onNotch = visibleShapeScreenRect().contains(location)
        // Our own window is far larger than what it draws, and not every
        // click outside the drawn content falls through to the app beneath:
        // where the glass shadow leaves the pixels faintly non-transparent
        // the window server hands the click to US, hitTest says "not mine",
        // and the event died here — a click just beside the panel did
        // nothing, while the same click a little further out (reaching the
        // global monitor) closed it. A click outside the content is outside,
        // whichever window it arrived through; it means what Escape means
        // (Thomas, 2026-09-01). The save dialog remains attached to its note.
        if state == .expanded {
            // The save dialog is a separate Otto window that belongs to the
            // open note. Its clicks must not dismiss the note behind it.
            if isPresentingDialog && !inNotchWindow { return }
            if !inNotchWindow {
                forceCollapse()
                return
            }
            handleOutsideClick(location)
            return
        }
        switch state {
        case .idle, .hovering:
            if onNotch {
                triggerExpand(trigger: .click)
                // A click is an explicit open, and opening is the intent to
                // interact: the caret lands in the draft row immediately
                // (keyboard-first, Thomas 2026-09-01). This also activates
                // the app, which is what lets Esc, arrows and Quick Find
                // reach the panel at all — a nonactivating panel opened by
                // click otherwise keeps sending every key to the app the
                // user came from. Hover-opens deliberately do NOT do this:
                // stealing keyboard focus on a mouse pass-over would yank
                // typing out of whatever the user is writing in.
                makeKeyForTyping()
            }
        case .expanded:
            break
        }
    }

    private func handleRightClick(at location: NSPoint, eventLocation: NSPoint,
                                  inNotchWindow: Bool) {
        if state == .expanded {
            if isPresentingDialog && !inNotchWindow { return }
            if !inNotchWindow {
                forceCollapse()
                return
            }
            handleOutsideClick(location)
            guard isInsidePanelContent(location) else { return }
        } else {
            guard visibleShapeScreenRect().contains(location) else { return }
        }
        showContextMenu(at: eventLocation)
    }

    private func scheduleCollapseIfOutsidePanel(_ point: NSPoint, screen: NSScreen) {
        let panelRect = expandedPanelRect(screen: screen)
        let paddedRect = panelRect.insetBy(dx: -30, dy: -30)
        if isInExtraPanelArea(point, padding: 12) { return }
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
    /// half. It looked like Otto was clipping the cursor; nothing in
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
        guard let screen = notchScreen else { return .zero }
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
        case .expanded:
            switch AppState.shared.notchLayout {
            case .panels:
                // The column is centred and the notch sits above it, so the
                // live region is the wider of the two, from the screen top
                // down past the last panel. Without this the "pointer left"
                // test fires the moment you move off the notch and onto the
                // panel you opened.
                width = max(expandedSize.width,
                            PanelMetrics.blockWidth + PanelMetrics.shadowMargin * 2)
                height = notchSize.height + AppState.shared.panelColumnHeight + 24
            case .container:
                // The silhouette itself is the whole of what is drawn, so the
                // live region is the grown shape — the same geometry the
                // renderer uses, hugging height included.
                width = expandedSize.width
                height = expandedSize.height + currentExtraExpandedHeight
            }
        }
        return NSRect(x: notchRect.midX - width / 2,
                      y: screen.frame.maxY - height,
                      width: width,
                      height: height)
    }

    // ── Opening for an image drag (Marcello, 2026-10-04) ─────────────
    // Drag a picture from the Finder onto the notch and hold it there: the
    // notch opens on the page it was left on, so the image can be dropped
    // into a note or the to-do field. Only an image opens it — a browser tab
    // crossing the top of the screen never does (2026-09-30).
    //
    // Nothing outside a drop target can see a drag: the system drag
    // session's pasteboard is its own, not the shared `.drag` one the old
    // tray code read (that stayed empty through every Finder drag), and the
    // global monitor hears no events while it runs. So while the button is
    // held after a press elsewhere, a small invisible drop target sits over
    // the notch. Mouse events go to the window that was pressed, so it costs
    // a click or a window drag nothing; a drag passing over it is offered to
    // it, and it says yes only to images. Held there (`dragDwellNanos`), it
    // opens the notch and steps aside so the drop lands in the text below.
    private var dragCatcher: DragCatcherPanel?
    private var dragCatcherWatch: Timer?
    private var dragCatcherPress = NSPoint.zero

    /// A press elsewhere: watch it until release. The target goes up only
    /// once the pointer travels with the button down — a plain click never
    /// puts a window over the menu bar, so a quick second click can't land
    /// on it.
    private func armDragCatcher() {
        guard state != .expanded else { return }
        dragCatcherPress = NSEvent.mouseLocation
        dragCatcherWatch?.invalidate()
        dragCatcherWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragCatcherTick() }
        }
    }

    private func dragCatcherTick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            // Released — dropped, or let go. The global mouse-up never
            // arrives after a system drag, so the drag ends here.
            dragCatcherWatch?.invalidate()
            dragCatcherWatch = nil
            dragCatcher?.disarm()
            isDragSessionActive = false
            return
        }
        guard state != .expanded, dragCatcher?.isVisible != true, let screen = notchScreen else { return }
        let now = NSEvent.mouseLocation
        guard hypot(now.x - dragCatcherPress.x, now.y - dragCatcherPress.y) > 6 else { return }
        let catcher = dragCatcher ?? DragCatcherPanel()
        dragCatcher = catcher
        catcher.dwell = TimeInterval(dragDwellNanos) / 1_000_000_000
        catcher.onHeld = { [weak self] in
            guard let self, self.state != .expanded else { return }
            self.dragCatcher?.disarm()
            // Through the release that ends the drag, nothing may close it.
            self.isDragSessionActive = true
            self.triggerExpand(trigger: .drag)
        }
        let target = dragTargetRect()
        // Up to the screen's top edge: the pointer pins there when the drag
        // is pushed into the menu bar.
        catcher.setFrame(NSRect(x: target.minX, y: target.minY,
                                width: target.width, height: screen.frame.maxY - target.minY), display: false)
        catcher.orderFrontRegardless()
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
        // Wide enough for the panel AND the room its shadow needs on each
        // side. At the old width the window was ~11pt clear of a 657pt column,
        // so a 24pt shadow was cut off vertically down both edges.
        let width = max(expandedSize.width,
                        PanelMetrics.blockWidth + PanelMetrics.shadowMargin * 2)
        return NSRect(
            x: notchRect.midX - width / 2,
            y: notchRect.maxY - height,
            width: width,
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
        // A live meeting alert holds the panel against POINTER movement
        // only: it opened itself, and the pointer is rarely near the notch, so
        // a stray mouse-move must not yank it away before it has been read.
        //
        // This is not what made it blocking. Every deliberate action — an
        // outside click, Escape, another app coming forward — goes through
        // forceCollapse, which bypasses this and snoozes the alert. And the
        // Snooze button itself now forces the collapse rather than being
        // vetoed by this very line.
        if CalendarStore.shared.activeAlert != nil { return true }
        // A dialog Otto opened (Download .md) keeps the panel it belongs to.
        if isPresentingDialog { return true }
        guard let panel else { return false }
        if panel.isKeyWindow { return true }
        if let key = NSApp.keyWindow, key.parent === panel { return true }
        return false
    }

    // MARK: - To-do creation entry points (design PRD §3)

    /// KB-3: ⌘N / ⌥Space put the caret in the draft row at the top of the
    /// section already on screen. No card, no modal — and no conjuring
    /// either: the row is always there, this just aims at it.
    func openCreate() {
        TodoStore.shared.focusDraft(fromGlobalShortcut: false)
        triggerExpand()
        makeKeyForTyping()
    }

    /// FB8: a GLOBAL "new to-do" shortcut (⌃⇧N / ⌥⌘N from anywhere) starts the
    /// draft on the user's default category, never on whatever was last
    /// browsed — someone summoning the notch from another app has no idea
    /// which tab it was left on.
    func openCreateFresh() {
        TodoStore.shared.focusDraft(fromGlobalShortcut: true)
        triggerExpand(trigger: .hotkey)
        makeKeyForTyping()
    }

    /// ⌥Space toggles: already typing → step out and close; otherwise take
    /// the caret.
    func toggleCreate() {
        if state == .expanded && TodoStore.shared.draftFocused {
            TodoStore.shared.blurDraft()
            // forceCollapse for the same reason Escape uses it: resignKey
            // alone does not surrender key status, and a still-key panel
            // counts as "engaged", so the unforced collapse this used to
            // call was vetoed by the very state it was trying to leave.
            forceCollapse()
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
        triggerExpand(trigger: .meetingAlert)
    }

    /// Collapse after an alert unless the user is doing something else in the
    /// panel (typing a to-do, mid-voice capture) — their work wins.
    /// - Returns: true if the panel is now closing, so the caller knows to
    ///   hold the meeting card in place until it has.
    @discardableResult
    func dismissMeetingAlert() -> Bool {
        guard state == .expanded, !TodoStore.shared.isPanelPinnedOpen else { return false }
        // force: the alert pins the panel open against a stray mouse-out (see
        // isUserEngaged), and that same pin was vetoing the collapse the
        // alert itself asked for — so Snooze worked or did nothing depending
        // on where the pointer happened to be.
        triggerCollapse(force: true)
        return true
    }

    /// Give the panel key status immediately (mode switches from inside the
    /// already-expanded panel, e.g. tapping the "+" tab).
    /// Give the panel real keyboard focus — not just "key within our process".
    ///
    /// The panel is a `.nonactivatingPanel` in an LSUIElement app, which by
    /// design does NOT bring the app forward. So `makeKey()` alone marked the
    /// panel key inside Otto while macOS kept delivering keystrokes to whatever
    /// was actually frontmost: the creation field drew its focus ring, and
    /// every character went to Chrome. Clicking the field appeared to "fix" it
    /// only because clicking is what activated the app.
    ///
    /// That one omission also swallowed Escape and every other shortcut routed
    /// through `addLocalMonitorForEvents`, which only fires while the app is
    /// active — so "Esc doesn't close it" and "the interactions are broken" had
    /// the same cause (Marcello's testers, 2026-08-06).
    ///
    /// Pressing a global creation hotkey is an unambiguous request to type
    /// here, so taking focus is correct. Nothing calls this on plain hover.
    /// True while a dialog opened from the panel is on screen.
    var isPresentingDialog = false

    /// The window a dialog opened from the panel must stand in front of.
    var dialogHostWindow: NSWindow? { panel }

    func focusPanel() {
        (panel as? NotchPanel)?.allowKey = true
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func calculateMaxPanelFrame(screen: NSScreen) -> NSRect {
        let notchRect = calculateNotchRect(screen: screen)
        // VW-1: fixed width. Height headroom covers the tallest tab (Notes
        // with a full to-do list) so the shape can grow without clipping.
        // Taken from the SAME value the hugging height clamps against, plus a
        // small margin — a window smaller than the shape's own ceiling would
        // silently clip the bottom of the panel.
        // + room under the container's silhouette for its detached meeting
        // card (2026-10-04).
        let height = expandedSize.height + AppState.maxExtraHeight + 24 + 190
        // Wide enough for the panels AND their shadows.
        //
        // This is the window everything is drawn into, and it was still
        // `expandedSize.width` — 600 on this setup — while the column asks for
        // 657 plus 62 of shadow margin on each side. The content was simply
        // wider than its own window, so the panels were clipped down both
        // edges and the shadow was sliced. `expandedPanelRect` had already
        // been widened for the same reason; this is the one that actually
        // sizes the window, and it had been left behind.
        let width = max(expandedSize.width,
                        PanelMetrics.blockWidth + PanelMetrics.shadowMargin * 2)
        return NSRect(
            x: notchRect.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}
