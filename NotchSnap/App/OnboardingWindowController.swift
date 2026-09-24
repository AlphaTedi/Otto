import AppKit
import SwiftUI

// MARK: - OnboardingWindowController — the one regular window Otto shows (SPEC §3)
//
// 860×460, fixed, 36-pt continuous corners, transparent titlebar with only the
// close button. `.normal` level: it must never float above the macOS
// permission prompts the permissions step raises.

class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private static var sharedController: OnboardingWindowController?

    private let model = OnboardingModel()
    private var keyMonitor: Any?

    /// ⌃⇧N is being practised: while the shortcut step is on screen and this
    /// window has focus, the hotkey lights the keycaps instead of opening the
    /// notch over the lesson.
    @MainActor
    static var capturesQuickEntry: Bool {
        guard let controller = sharedController, controller.window?.isKeyWindow == true else { return false }
        return controller.model.capturesQuickEntry
    }

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
            self.removeKeyMonitor()
            self.model.permissions.stopWatching()
            OnboardingWindowController.sharedController = nil
            // The launch gate is `onboardingVersion < 1`. The window has no
            // close button and ⌘W does nothing (Marcello, 2026-09-24: finish
            // it or quit, the way Dia's onboarding works), so the one route
            // here is "Open Otto" at the end — this is completion.
            //
            // Quitting mid-flow never reaches this: the gate stays at 0 and
            // the next launch resumes at `onboarding.lastStep`.
            //
            // Settings can still bring it back: that path sets the key to 0
            // deliberately, and this only ever moves it forward.
            UserDefaults.standard.set(1, forKey: "onboardingVersion")
            UserDefaults.standard.set(0, forKey: OnboardingModel.Keys.lastStep)
            if !AppState.shared.settings.showInDock {
                NSApp.setActivationPolicy(.accessory)
            }
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
        guard let window = sharedController?.window else { return }
        sharedController?.showWindow(nil)
        center(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // The shadow follows the content's alpha — compute it once the rounded
        // content has actually been drawn.
        DispatchQueue.main.async { window.invalidateShadow() }
    }

    static func dismiss() {
        sharedController?.window?.close()
    }

    /// Centred on the screen with the notch (the built-in display), else the
    /// main screen (SPEC §3).
    private static func center(_ window: NSWindow) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        let size = OBMetric.windowSize
        let visible = screen?.visibleFrame ?? window.frame
        // Size and place in one call. Showing the window re-derives its frame
        // from the content rect (plus a titlebar the full-size content view
        // already covers), so the size is restated here, after that.
        window.setFrame(NSRect(x: visible.midX - size.width / 2,
                               y: visible.midY - size.height / 2,
                               width: size.width, height: size.height), display: true)
    }

    convenience init() {
        let size = OBMetric.windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            // Titled for key-window behaviour and the system shadow, but not
            // closable: no traffic lights at all. Finishing is the way out.
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Otto"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        // Plain .normal — same as Settings. .floating pins a window above every
        // other app's windows, which covered the browser the calendar consent
        // opened in (Marcello, 2026-08-09) and would cover the macOS permission
        // prompts now (SPEC §3).
        window.level = .normal
        window.isMovableByWindowBackground = true
        // Fixed size by omission: no `.resizable` in the style mask. Not by
        // minSize/maxSize — with a full-size content view AppKit turned a
        // 460-pt minimum into a 460-pt CONTENT minimum and added the titlebar,
        // and the window came out 492 tall.

        // No traffic lights (Marcello, 2026-09-24 — departs from SPEC §3,
        // which kept the close button).
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // ARC owns it through this controller. Left at its default `true`,
        // AppKit would free the window under the controller and the static
        // would be left pointing at freed memory.
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self

        let model = self.model
        let hostingView = NSHostingView(
            rootView: OnboardingFlowView(model: model) { [weak self] in self?.primaryAction() }
        )
        // The SwiftUI content is exactly the window; it must not negotiate the
        // window's size. As the content view itself, the hosting view kept
        // growing the window by the titlebar's height (a 32-pt safe area it
        // insisted on keeping) — inside a plain container it has no say.
        hostingView.sizingOptions = []
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        window.contentView = container
        // With a full-size content view the FRAME is the window — a content
        // rect of 860×460 would add the titlebar on top and make it 492.
        window.setFrame(NSRect(origin: .zero, size: size), display: false)

        if model.step == .permissions { model.permissions.startWatching() }
        installKeyMonitor()
    }

    // MARK: Actions

    private func primaryAction() {
        if model.step == .done {
            complete()
        } else {
            model.advance()
        }
    }

    /// `Open Otto ↵`: completed, closed, and the notch opened once so the
    /// user sees where Otto lives (SPEC §7.6).
    private func complete() {
        model.finish()
        window?.close()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            NotchController.shared.triggerExpand()
            NotchController.shared.focusPanel()
        }
    }

    #if DEBUG
    /// Every step, dark and light, written as PNGs — the only way to look at
    /// this window on a machine where screen capture is not permitted.
    static func debugSnapshots(to directory: URL, steps: [OnboardingStep] = OnboardingStep.allCases) async {
        show()
        guard let controller = sharedController, let window = controller.window,
              let view = window.contentView else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            window.appearance = NSAppearance(named: appearance)
            for step in steps {
                controller.model.debugJump(to: step)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                DebugDriver.note("onboarding window frame=\(window.frame) content=\(view.frame) "
                    + "closeHidden=\(window.standardWindowButton(.closeButton)?.isHidden ?? true) "
                    + "closable=\(window.styleMask.contains(.closable))")
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = directory.appendingPathComponent(
                    String(format: "%@-%02d-%@.png", name, step.rawValue + 1, "\(step)"))
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        window.appearance = nil
    }
    #endif

    // MARK: Keyboard (SPEC §8)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// True when the event was consumed.
    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        if event.type == .flagsChanged {
            if model.step == .shortcut { model.modifiersChanged(event.modifierFlags) }
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let typing = window.firstResponder is NSTextView

        // ⌘W is swallowed rather than passed on: the window is not closable,
        // and letting it through would only beep.
        if command && chars == "w" { return true }
        if command && chars == "[" { model.back(); return true }
        // A focused text field keeps its own keys — ↵ saves the to-do there.
        if typing { return false }
        if command || flags.contains(.control) || flags.contains(.option) { return false }

        switch event.keyCode {
        case 36, 76:                       // ↵, keypad enter
            primaryAction(); return true
        case 123:                          // ←
            model.back(); return true
        case 126 where model.step == .focus:   // ↑
            model.moveFocus(by: -1); return true
        case 125 where model.step == .focus:   // ↓
            model.moveFocus(by: 1); return true
        default:
            break
        }

        switch (model.step, chars) {
        case (.focus, "1"): model.selectFocus(.tasks); return true
        case (.focus, "2"): model.selectFocus(.meetings); return true
        case (.focus, "3"): model.selectFocus(.both); return true
        case (.permissions, "c"): model.permissions.grantCalendar(); return true
        case (.permissions, "l"): model.permissions.setLogin(!model.permissions.loginEnabled); return true
        default: return false
        }
    }
}
