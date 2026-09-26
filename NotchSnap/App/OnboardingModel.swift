import AppKit
import Combine
import EventKit
import ServiceManagement
import SwiftUI

// MARK: - Onboarding state (v3 SPEC §5)

/// Raw values are persisted in `onboarding.lastStep`. The v3 steps sit where
/// the Direction B ones did, so an interrupted B flow resumes sensibly with
/// no migration: focus (1) comes back as discover, notch (2) as style.
enum OnboardingStep: Int, CaseIterable {
    case welcome, discover, style, shortcut, permissions, done
}

/// The Discover tour's three stops. A tour, not a choice: nothing is saved.
enum DiscoverItem: Int, CaseIterable {
    case tasks, notes, meetings
}

/// Where Otto lives, chosen on the style step. Not a value of its own: it is
/// the same `notchLayout` setting Settings shows (v3 §4.3).
enum DisplayMode: String {
    case notch, floating

    var layout: NotchLayout { self == .notch ? .container : .panels }
    init(_ layout: NotchLayout) { self = layout == .container ? .notch : .floating }
}

/// The flow's one source of truth: where we are, what was chosen, and whether
/// the shortcut step has seen the shortcut. The window controller owns one.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep
    /// +1 going forward, −1 going back — which way the left column slides.
    @Published private(set) var direction: CGFloat = 1
    @Published private(set) var discoverItem: DiscoverItem = .tasks
    @Published private(set) var displayMode: DisplayMode

    // Shortcut step
    /// ⌃ and ⇧ physically down: their caps brighten while held.
    @Published private(set) var controlHeld = false
    @Published private(set) var shiftHeld = false
    /// The cap popping right now, in the 40-ms stagger after a detection.
    @Published private(set) var heldKey: Int?
    @Published private(set) var shortcutDetected = false

    let permissions = PermissionsModel()

    enum Keys {
        static let completed = "onboarding.completed"
        static let lastStep = "onboarding.lastStep"
        /// Direction B's focus choice. v3 has none; an old value is ignored.
        static let legacyFocus = "onboarding.focus"
    }

    private var bag = Set<AnyCancellable>()
    private var release: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.legacyFocus)
        // Resume where a quit left off — finishing resets this, so only an
        // interrupted flow ever comes back mid-way.
        step = OnboardingStep(rawValue: defaults.integer(forKey: Keys.lastStep)) ?? .welcome
        // The notch unless someone already picked a layout (a re-run from
        // Settings shows what is set, not the default).
        displayMode = defaults.string(forKey: "notchLayout") == nil
            ? .notch : DisplayMode(AppState.shared.notchLayout)

        // ⌃⇧N itself — the real global hotkey, so the step proves it works
        // from any app. Carbon swallows the key-down before any window sees
        // it; its notification is how the press is known.
        NotificationCenter.default.publisher(for: .quickEntryFired)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.shortcutFired() }
            .store(in: &bag)
    }

    // MARK: Navigation

    /// v3 §2: one third for all of Discover, then halves, thirds and sixths.
    var progress: CGFloat {
        switch step {
        case .welcome: return 0
        case .discover: return 0.33
        case .style: return 0.5
        case .shortcut: return 0.66
        case .permissions: return 0.83
        case .done: return 1
        }
    }

    /// Whether the primary action can run — false only while step 4 waits.
    var canAdvance: Bool { step != .shortcut || shortcutDetected }

    func advance() {
        guard canAdvance else { return }
        if step == .discover, let next = DiscoverItem(rawValue: discoverItem.rawValue + 1) {
            show(next); return
        }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        go(to: next, direction: 1)
    }

    /// The step-4 escape hatch: past the shortcut without pressing it, for a
    /// Mac where another app owns ⌃⇧N (v3 §4.4).
    func skipShortcut() {
        guard step == .shortcut else { return }
        go(to: .permissions, direction: 1)
    }

    func back() {
        if step == .discover, let previous = DiscoverItem(rawValue: discoverItem.rawValue - 1) {
            show(previous); return
        }
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        if previous == .discover { discoverItem = .meetings }
        go(to: previous, direction: -1)
    }

    private func go(to next: OnboardingStep, direction: CGFloat) {
        self.direction = direction
        if next == .discover, step == .welcome { discoverItem = .tasks }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = next }
        UserDefaults.standard.set(next.rawValue, forKey: Keys.lastStep)
        if next == .permissions { permissions.startWatching() } else { permissions.stopWatching() }
        if next != .shortcut { controlHeld = false; shiftHeld = false }
    }

    #if DEBUG
    func debugJump(to target: OnboardingStep, item: DiscoverItem = .tasks,
                   mode: DisplayMode? = nil, detected: Bool = false) {
        go(to: target, direction: 1)
        discoverItem = item
        if let mode { displayMode = mode }
        shortcutDetected = detected
    }
    #endif

    // MARK: Discover

    /// Next, Back and a click on the stepper all land here.
    func show(_ item: DiscoverItem) {
        guard step == .discover, item != discoverItem else { return }
        withAnimation(.easeInOut(duration: 0.25)) { discoverItem = item }
    }

    // MARK: Style

    /// Written straight through to the setting Settings shows, with the same
    /// reset a switch there does (`AppState.setNotchLayout`).
    func select(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        withAnimation(.easeInOut(duration: 0.2)) { displayMode = mode }
        AppState.shared.setNotchLayout(mode.layout)
    }

    // MARK: Shortcut

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let control = flags.contains(.control), shift = flags.contains(.shift)
        guard control != controlHeld || shift != shiftHeld else { return }
        withAnimation(.easeOut(duration: 0.12)) { controlHeld = control; shiftHeld = shift }
    }

    /// The hotkey, whichever path reported it.
    func shortcutFired() {
        guard step == .shortcut else { return }
        if !shortcutDetected {
            withAnimation(.easeInOut(duration: 0.4)) { shortcutDetected = true }
        }
        // Each key pops in turn, 40 ms apart (v3 §4.4); the key-up never
        // reaches us, so the highlight lets go on its own.
        release?.cancel()
        release = Task { @MainActor [weak self] in
            for index in 0..<3 {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { self?.heldKey = index }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.heldKey = nil }
        }
    }

    // MARK: Done

    /// `onboarding.completed` is written only here — quitting early resumes
    /// the flow next launch, it does not complete it.
    func finish() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Keys.completed)
        defaults.set(0, forKey: Keys.lastStep)
        // Whatever the style step showed is what opens, even if it was never
        // touched (the notch default is not written until then).
        AppState.shared.setNotchLayout(displayMode.layout)
        if let first = TodoStore.shared.firstUserCollection {
            TodoStore.shared.selectCollection(first.id)
        }
    }

    /// Whether ⌃⇧N should be left to this window instead of opening Otto —
    /// only while the shortcut step is on screen and this window has focus.
    var capturesQuickEntry: Bool { step == .shortcut }
}

// MARK: - PermissionsModel — live, never cached (SPEC §10)

@MainActor
final class PermissionsModel: ObservableObject {
    enum Status: Equatable { case notDetermined, granted, denied }

    @Published private(set) var calendar: Status = .notDetermined
    @Published private(set) var calendarBusy = false
    @Published private(set) var loginEnabled = false
    /// "Found N calendars · next up: …", or nil when there is nothing true to say.
    @Published private(set) var calendarSummary: String?

    private var observers: [NSObjectProtocol] = []

    init() { refresh() }

    func startWatching() {
        refresh()
        guard observers.isEmpty else { return }
        // Coming back from System Settings is the moment a denial may have
        // become a grant (SPEC §7.5: re-check when the window is key again).
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } })
    }

    func stopWatching() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let next: Status
        switch status {
        case .notDetermined: next = .notDetermined
        case .denied, .restricted: next = .denied
        default:
            // .authorized / .fullAccess. Write-only cannot read a meeting, so
            // it is a denial as far as this row is concerned.
            if #available(macOS 14.0, *), status == .writeOnly { next = .denied } else { next = .granted }
        }
        if next != calendar {
            withAnimation(.easeInOut(duration: 0.3)) { calendar = next }
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
        updateSummary()
    }

    /// Through CalendarStore — the same connect the Settings page uses, so a
    /// grant here is a connected calendar everywhere, not a second path.
    func grantCalendar() {
        guard calendar != .granted, !calendarBusy else { return }
        if calendar == .denied { openSettings(); return }
        calendarBusy = true
        Task { @MainActor in
            await CalendarStore.shared.connect()
            calendarBusy = false
            refresh()
        }
    }

    func setLogin(_ on: Bool) {
        AppState.shared.updateSettings { $0.launchAtLogin = on }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            print("[Onboarding] Login item error: \(error)")
        }
        withAnimation(.easeInOut(duration: 0.2)) { refresh() }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateSummary() {
        guard calendar == .granted else { calendarSummary = nil; return }
        let count = EKEventStore().calendars(for: .event).count
        guard count > 0 else { calendarSummary = nil; return }
        var line = String(format: L10n.t(count == 1 ? "ob.perm.found1" : "ob.perm.foundN"), count)
        if let next = CalendarStore.shared.nextMeeting {
            let time = next.start.formatted(date: .omitted, time: .shortened)
            line += " · " + String(format: L10n.t("ob.perm.nextUp"), next.title, time)
        }
        calendarSummary = line
    }
}
