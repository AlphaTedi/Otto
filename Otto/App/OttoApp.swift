import SwiftUI
import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var hotkeyManager: HotkeyManager?
    /// Read in willFinishLaunching: by didFinish the launch event is gone.
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ONE Otto. A second copy — the app opened from the mounted DMG while
        // the installed one runs, or the binary started from Terminal — used
        // to run in full: two notch panels on top of each other, the second
        // one's hot keys failing, two writers on the same files (seen on a
        // colleague's Mac, 2026-10-02: `pgrep` listed two Ottos). The newcomer
        // hands over — "open the notch" to the running copy — and quits.
        // Release only: a Debug build from Xcode runs beside the installed app.
        #if !DEBUG
        if let running = Self.otherInstance() {
            DistributedNotificationCenter.default().postNotificationName(
                .ottoShowRequest, object: nil, userInfo: nil, deliverImmediately: true)
            running.activate()
            NSApp.terminate(nil)
            return
        }
        #endif
        DistributedNotificationCenter.default().addObserver(
            forName: .ottoShowRequest, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.showOtto() }
        }

        // Apply user-selected theme (system / light / dark)
        AppState.shared.applyTheme()

        // Hide from Dock if configured
        if !AppState.shared.settings.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }

        // Initialize defaults
        if UserDefaults.standard.object(forKey: "hapticFeedback") == nil {
            UserDefaults.standard.set(true, forKey: "hapticFeedback")
        }
        if UserDefaults.standard.object(forKey: "soundEffectsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "soundEffectsEnabled")
        }
        // The screenshot, shelf and clipboard product was retired. Clear the
        // old opt-in so an installation upgraded from an older build cannot
        // bring those surfaces back.
        UserDefaults.standard.set(false, forKey: "showLegacyPanels")

        // Wide became 620 (was 680, 2026-10-03). A Mac still on the old
        // Wide moves with it; any other width was chosen and is kept.
        if UserDefaults.standard.double(forKey: "notchExpandedWidth") == 680 {
            UserDefaults.standard.set(620.0, forKey: "notchExpandedWidth")
        }

        // Show onboarding if not completed
        let showsOnboarding = Self.needsOnboarding()
        if showsOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.show()
            }
        }

        // Setup hotkey manager
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.start()

        #if DEBUG
        // Scriptable side door for agent/CI verification (see DebugDriver).
        DebugDriver.install()
        #endif

        // Anonymous usage counts — a no-op without the user's yes.
        Analytics.appDidLaunch()

        // Setup notch controller
        notchController = NotchController.shared
        notchController?.setup()

        // Opened by hand (not at login) and past the onboarding: show the
        // notch. Otto has no window and no Dock icon, so a launch that drew
        // nothing read as "the app does not open" — clicking the icon again
        // and again did, in fact, nothing visible.
        if !showsOnboarding && !launchedAsLoginItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Self.showOtto() }
        }
    }

    /// Clicking Otto in Finder, Launchpad or the Dock while it already runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { Self.showOtto() }
        return false
    }

    /// The notch, open on the to-dos with the caret in the draft — what a
    /// user who just opened the app is asking for.
    @MainActor
    static func showOtto() {
        guard !OnboardingWindowController.isShowing else {
            OnboardingWindowController.show()
            return
        }
        NotchController.shared.triggerExpand(trigger: .appIcon)
        NotchController.shared.makeKeyForTyping()
    }

    /// Another running copy of this same app, if any.
    private static func otherInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// The onboarding runs until it is finished — and once more for a Mac
    /// whose "finished" flag is a leftover.
    ///
    /// Preferences outlive the app: dragging Otto to the Trash leaves
    /// ~/Library/Preferences/com.notchsnap.app.plist behind. A colleague who
    /// tried a pre-Otto build months ago and deleted it got
    /// `onboardingVersion = 1` back on reinstall, so Otto started straight
    /// into an empty notch with no window at all (2026-10-02). That leftover
    /// is recognisable: done, yet never answered the usage question this
    /// onboarding asks, and not one to-do or note written.
    @MainActor
    static func needsOnboarding() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: "onboardingVersion") < 1 { return true }
        let neverAsked = AppState.shared.settings.analyticsConsent == nil
        let nothingWritten = TodoStore.shared.items.isEmpty && NotesStore.shared.notes.isEmpty
        if neverAsked && nothingWritten {
            defaults.set(0, forKey: "onboardingVersion")
            return true
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        // Flush the debounced stores. Every save path waits 500 ms to batch
        // keystrokes, so without this a quit inside that window silently
        // dropped the last edit — the one bug a to-do app must not have.
        MainActor.assumeIsolated {
            TodoStore.shared.saveNow()
            NotesStore.shared.saveNow()
            Analytics.flush()
        }
    }

    // MARK: - Settings & Quit actions (called from menu and notifications)

    @objc func openSettingsAction() {
        NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension Notification.Name {
    /// A second Otto asking the running one to show itself (distributed).
    static let ottoShowRequest = Notification.Name("otto.show")
    static let openSettingsRequest = Notification.Name("otto.openSettings")
    static let settingsWindowClosed = Notification.Name("otto.settingsClosed")
    /// Posted whenever the global quick-entry hotkey actually fires. Onboarding
    /// listens for this so its practice step advances on the REAL keypress
    /// rather than a "Next" button — the user performs the app's core action
    /// for real before onboarding ends.
    static let quickEntryFired = Notification.Name("otto.quickEntryFired")
    /// Posted when a to-do is actually committed. Onboarding uses it to know
    /// the user finished the job, not just opened the panel.
    static let todoCreated = Notification.Name("otto.todoCreated")
    /// Posted by the key router when Escape lands while a row's title or
    /// step editor holds the caret. The editors listen and DISCARD their
    /// draft — the router must consume Esc itself (letting it through would
    /// close the notch), so "Escape means cancel" has to travel this way.
    static let todoEditorEscape = Notification.Name("otto.todoEditorEscape")
}

// MARK: - Main App

@main
struct OttoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // Hidden window — needed to give context to openSettings() in accessory apps
        Window("Hidden", id: "hidden") {
            HiddenContextView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topLeading)
        .windowStyle(.hiddenTitleBar)

        // Menu bar icon removed — actions are available via keyboard shortcuts
        // and the notch UI, so the status-bar badge was redundant.

        // NOTE: We intentionally do NOT use SwiftUI's `Settings { }` scene
        // here. That scene wraps our SettingsView in an AppKit-managed window
        // with its own title bar and outer corner mask — which fought our
        // custom chrome and caused visible "double rounded corners".
        // SettingsWindowController hosts SettingsView in a fully custom
        // NSWindow instead.
    }
}

// MARK: - HiddenContextView — Receives notification and opens Settings

struct HiddenContextView: View {
    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    SettingsWindowController.show()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowClosed)) { _ in
                // Deferred to the next turn of the runloop, and skipped when
                // the policy already matches.
                //
                // This fires from `windowWillClose` — the window is still on
                // screen. Changing the activation policy there makes AppKit
                // re-order the app's windows mid-teardown, which is when
                // anything else still alive gets a frame of visibility. Let the
                // close finish first; then there is nothing to re-order.
                guard !AppState.shared.settings.showInDock else { return }
                DispatchQueue.main.async {
                    if NSApp.activationPolicy() != .accessory {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
    }
}
