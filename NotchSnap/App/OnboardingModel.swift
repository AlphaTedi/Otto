import AppKit
import Combine
import EventKit
import ServiceManagement
import SwiftUI

// MARK: - Onboarding state (SPEC §10)

enum OnboardingStep: Int, CaseIterable {
    case welcome, focus, notch, shortcut, permissions, done
}

enum OnboardingFocus: String, CaseIterable {
    case tasks, meetings, both
}

/// The flow's one source of truth: where we are, what was chosen, and what the
/// practice steps have seen happen. The window controller owns one per window.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep
    /// +1 going forward, −1 going back — which way the left column slides.
    @Published private(set) var direction: CGFloat = 1
    @Published var focus: OnboardingFocus {
        didSet { UserDefaults.standard.set(focus.rawValue, forKey: Keys.focus) }
    }

    // Notch step
    @Published private(set) var notchArmed = false
    @Published private(set) var notchTried = false

    // Shortcut step
    @Published private(set) var controlHeld = false
    @Published private(set) var shiftHeld = false
    @Published private(set) var nHeld = false
    @Published private(set) var shortcutDetected = false
    /// Bumped whenever the field should take the caret.
    @Published var fieldFocusRequest = 0
    /// Bumped once per saved to-do — the Continue button pulses on it.
    @Published private(set) var continuePulse = 0

    let permissions = PermissionsModel()

    enum Keys {
        static let completed = "onboarding.completed"
        static let focus = "onboarding.focus"
        static let lastStep = "onboarding.lastStep"
    }

    private var bag = Set<AnyCancellable>()
    private var nRelease: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        focus = OnboardingFocus(rawValue: defaults.string(forKey: Keys.focus) ?? "") ?? .both
        // Resume where a quit left off — closing the window resets this, so
        // only an interrupted flow ever comes back mid-way.
        step = OnboardingStep(rawValue: defaults.integer(forKey: Keys.lastStep)) ?? .welcome

        // The real notch, hovered or opened while the listener is armed.
        NotchController.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.notchArmed, !self.notchTried else { return }
                if state == .hovering || state == .expanded {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.notchTried = true }
                }
            }
            .store(in: &bag)

        // ⌃⇧N itself. Carbon swallows the key-down before any window sees it,
        // so the hotkey's own notification is how N is known to be pressed.
        NotificationCenter.default.publisher(for: .quickEntryFired)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.shortcutFired() }
            .store(in: &bag)
    }

    // MARK: Navigation

    var progress: CGFloat { CGFloat(step.rawValue + 1) / CGFloat(OnboardingStep.allCases.count) }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        go(to: next, direction: 1)
    }

    func back() {
        guard step.rawValue > OnboardingStep.focus.rawValue,
              let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous, direction: -1)
    }

    private func go(to next: OnboardingStep, direction: CGFloat) {
        self.direction = direction
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = next }
        UserDefaults.standard.set(next.rawValue, forKey: Keys.lastStep)
        if next == .permissions { permissions.startWatching() } else { permissions.stopWatching() }
        if next != .shortcut { releaseKeys() }
    }

    #if DEBUG
    func debugJump(to target: OnboardingStep) {
        go(to: target, direction: 1)
    }
    #endif

    // MARK: Focus step

    func selectFocus(_ choice: OnboardingFocus) {
        withAnimation(.easeInOut(duration: 0.25)) { focus = choice }
    }

    func moveFocus(by delta: Int) {
        let all = OnboardingFocus.allCases
        let index = all.firstIndex(of: focus) ?? 0
        selectFocus(all[max(0, min(all.count - 1, index + delta))])
    }

    // MARK: Notch step

    func armNotch() {
        withAnimation(.easeOut(duration: 0.2)) { notchArmed = true }
    }

    // MARK: Shortcut step

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let control = flags.contains(.control), shift = flags.contains(.shift)
        guard control != controlHeld || shift != shiftHeld else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            controlHeld = control
            shiftHeld = shift
            if !control || !shift { nHeld = false }
        }
    }

    private func shortcutFired() {
        guard step == .shortcut else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            controlHeld = true; shiftHeld = true; nHeld = true
        }
        if !shortcutDetected {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { shortcutDetected = true }
        }
        fieldFocusRequest += 1
        // The key-up never reaches us either, so N lets go on its own; ⌃ and
        // ⇧ follow the real modifier state through flagsChanged.
        nRelease?.cancel()
        nRelease = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.nHeld = false }
        }
    }

    private func releaseKeys() {
        controlHeld = false; shiftHeld = false; nHeld = false
    }

    /// ↵ in the practice field: a real to-do, filed where the focus choice
    /// says the day starts.
    @discardableResult
    func saveFirstTodo(_ title: String) -> Bool {
        let store = TodoStore.shared
        guard let target = store.firstUserCollection?.id ?? store.collections.first?.id,
              store.addItem(title: title, collectionID: target) != nil else { return false }
        continuePulse += 1
        return true
    }

    // MARK: Done

    /// `onboarding.completed` is written only here — closing the window early
    /// counts as seen (the launch gate), not as completed (SPEC §2).
    func finish() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Keys.completed)
        defaults.set(0, forKey: Keys.lastStep)
        // Focus decides which list is selected first (SPEC §2).
        let store = TodoStore.shared
        if focus == .meetings, let today = store.collections.first(where: { $0.isSystemToday }) {
            store.selectCollection(today.id)
        } else if let first = store.firstUserCollection {
            store.selectCollection(first.id)
        }
    }

    /// Whether ⌃⇧N should be left to this window instead of opening the notch
    /// — only while the shortcut step is on screen and this window has focus.
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
