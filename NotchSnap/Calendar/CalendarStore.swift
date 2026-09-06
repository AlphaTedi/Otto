import AppKit
import Foundation
import SwiftUI

// MARK: - CalendarStore — meeting awareness (calendar PRD §§2-4)
//
// Owns: the connection, today's remaining meetings, and the two-stage alert
// schedule (ambient dot → self-opening alert). Everything calendar-derived
// hangs off `isConnected`, so disconnecting reverts the app to its
// pre-connection state in one move (SU-8).

@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    // MARK: Published state

    @Published private(set) var isConnected = false
    @Published private(set) var accountDescription: String?
    @Published private(set) var meetings: [DetectedMeeting] = []
    /// Non-nil while the interruptive alert is on screen (CA-3).
    @Published private(set) var activeAlert: DetectedMeeting?
    /// True from the moment an alert is sent away until the notch has
    /// finished closing behind it.
    ///
    /// Clearing `activeAlert` is what tells the column to draw the to-do panel
    /// again — so pressing Snooze swapped the meeting card for the whole to-do
    /// list and THEN played the close animation, opening a window on its way
    /// out that nobody asked for (Marcello, 2026-09-06). Held for the length
    /// of the collapse, the card just fades with the notch and nothing else is
    /// ever built.
    @Published private(set) var alertLeaving = false
    /// Seconds still to run on the alert's own countdown, and whether it is
    /// running. The Snooze button draws its fill from these; it does not own
    /// them.
    ///
    /// It used to own them, entirely: the clock lived in the button's
    /// `onAppear` and its `@State`. So an alert whose card was never drawn —
    /// and there is a real path to that, a refresh dropping the alerting
    /// meeting out of `meetings` between the alert firing and the card
    /// rendering — had no clock at all. It stayed "active" forever: the panel
    /// counted itself engaged, `evaluateAlerts` refused to raise any later
    /// alert because one was still live, and there was no Snooze button on
    /// screen to press (Marcello, 2026-09-06). A deadline that only exists
    /// while something is drawing it is not a deadline.
    @Published private(set) var autoSnoozeRemaining: Double = LabMetrics.autoSnoozeSeconds
    @Published private(set) var autoSnoozeRunning = false
    /// Non-nil while a meeting is inside the ambient window (CA-2).
    @Published private(set) var ambientMeeting: DetectedMeeting?
    @Published private(set) var lastError: String?

    /// Lead times, in minutes — configurable per the PRD's Settings mockup.
    @AppStorage("calAmbientLeadMinutes") var ambientLeadMinutes: Int = 15
    @AppStorage("calAlertLeadMinutes") var alertLeadMinutes: Int = 2
    @AppStorage("calSnoozeMinutes") var snoozeMinutes: Int = 5
    /// Set once the user connects, so we don't re-prompt on every launch.
    @AppStorage("calendarConnected") private var connectedPreference = false

    /// Which backend supplies meetings. Google exists because macOS's own
    /// Google sync can be broken (it was, on Marcello's Mac, for months) and
    /// because it needs no calendar permission at all — which matters on a
    /// machine where an unsigned build can't get one.
    enum Source: String, CaseIterable, Identifiable {
        case macOS, google
        var id: String { rawValue }
        var label: String {
            self == .macOS ? L10n.t("gcal.sourceMac") : L10n.t("gcal.sourceGoogle")
        }

        /// Sources this build can actually use.
        ///
        /// A build with no OAuth credential compiled in cannot sign in to
        /// Google, so offering it produces a dead end — a picker option whose
        /// only outcome is a setup form (Marcello, 2026-07-28). It reappears
        /// automatically once Config/GoogleOAuth.xcconfig is filled in, and
        /// stays visible for anyone already signed in so they are never
        /// stranded by a rebuild.
        @MainActor
        static var available: [Source] {
            if GoogleOAuth.hasBundledCredentials
                || GoogleOAuth.shared.isSignedIn
                || GoogleOAuth.shared.usesCustomCredentials {
                return allCases
            }
            return [.macOS]
        }
    }

    @AppStorage("calendarSource") private var storedSource: String = Source.macOS.rawValue
    var source: Source {
        get { Source(rawValue: storedSource) ?? .macOS }
        set {
            guard newValue != source else { return }
            // Switching backends invalidates everything derived from the old
            // one — never leave one provider's meetings on screen under the
            // other's name.
            disconnect()
            storedSource = newValue.rawValue
            provider = Self.makeProvider(newValue)
            objectWillChange.send()
        }
    }

    private static func makeProvider(_ source: Source) -> MeetingProvider {
        source == .google ? GoogleCalendarProvider() : EventKitCalendarProvider()
    }

    /// If a stored preference names a source this build cannot use — an old
    /// setting carried into a build without Google credentials — fall back to
    /// macOS rather than starting up with a provider that can never connect.
    private var effectiveSource: Source {
        Source.available.contains(source) ? source : .macOS
    }

    private lazy var provider: MeetingProvider = Self.makeProvider(effectiveSource)
    /// The concrete provider, for the EventKit-specific diagnostics shown in
    /// Settings. Nil while the Google provider is selected.
    private var eventKit: EventKitCalendarProvider? { provider as? EventKitCalendarProvider }

    /// Every calendar NotchSnap can see — shown in Settings so "Connected"
    /// is verifiable rather than a claim.
    var visibleCalendars: [EventKitCalendarProvider.CalendarSummary] {
        eventKit?.visibleCalendars ?? []
    }

    /// Today's events before filtering, each with the reason it is or isn't
    /// shown. Drives the Settings diagnostic and the `cal-debug` command.
    func diagnoseToday() -> [String] {
        eventKit?.diagnoseToday() ?? []
    }

    /// Newest write in the local calendar DB. Weeks old ⇒ macOS sync is dead.
    var lastSyncedAt: Date? { eventKit?.lastSyncedAt() }

    /// True when macOS clearly isn't syncing any more, so the UI can say so
    /// instead of silently showing an empty list.
    var syncLooksStale: Bool {
        guard isConnected, let last = lastSyncedAt else { return false }
        return Date().timeIntervalSince(last) > 7 * 86_400
    }

    /// Raw attendee data — diagnoses empty/letter-only avatars.
    func diagnoseAttendees() -> [String] { eventKit?.diagnoseAttendees() ?? [] }

    /// Wide-window probe — "is anything in the local calendar DB at all?"
    func probeWideWindow() -> [String] {
        eventKit?.probeWideWindow() ?? []
    }

    /// Per-calendar opt in/out (Marcello: "what if I only want one account?").
    func setCalendar(_ id: String, enabled: Bool) {
        eventKit?.setCalendar(id, enabled: enabled)
        objectWillChange.send()
        Task { await refresh() }
    }
    private var ticker: Timer?
    /// Meetings already alerted (or snoozed past) — keyed by meeting id.
    private var alertedIDs: Set<String> = []
    private var snoozedUntil: [String: Date] = [:]
    /// The alert auto-collapses if untouched (Marcello, 2026-07-25).
    private var autoCollapseTask: Task<Void, Never>?
    private var alertLeavingTask: Task<Void, Never>?
    private var autoSnoozeTask: Task<Void, Never>?
    private var autoSnoozeResumedAt: Date?

    private init() {
        if connectedPreference, provider.isConnected {
            isConnected = true
            accountDescription = provider.accountDescription
            startObserving()
            Task { await refresh() }
        }
    }

    // MARK: Connection (SU-5, SU-8)

    func connect() async {
        lastError = nil
        if let failure = await provider.connect() {
            lastError = failure
            isConnected = false
            connectedPreference = false
            return
        }
        isConnected = true
        connectedPreference = true
        accountDescription = provider.accountDescription
        startObserving()
        await refresh()
    }

    /// SU-8: stop every calendar-derived behavior immediately and revert to
    /// the pre-connection state (the nudge card comes back on its own,
    /// because it keys off `isConnected`).
    func disconnect() {
        provider.disconnect()
        isConnected = false
        connectedPreference = false
        accountDescription = nil
        meetings = []
        alertedIDs = []
        snoozedUntil = [:]
        lastError = nil
        alertLeavingTask?.cancel()
        alertLeaving = false
        withAnimation(NotchAnimation.contentHug) {
            activeAlert = nil
            ambientMeeting = nil
        }
        stopObserving()
    }

    // MARK: Data

    func refresh() async {
        guard isConnected else { return }
        #if DEBUG
        // An injected test meeting has to survive the 10s tick, or the harness
        // can never observe anything that takes longer than one tick to happen
        // — the countdown, most obviously.
        if debugHoldsInjectedMeetings { return }
        #endif
        let fetched = await provider.upcomingToday()
        withAnimation(NotchAnimation.contentHug) { meetings = fetched }
        evaluateAlerts()
    }

    /// Called when the panel opens — whatever is on screen should reflect
    /// the calendar as of this instant, not the last tick.
    func refreshNow() {
        Task { @MainActor in await refresh() }
    }

    /// CT-1/CT-4/CT-5: today's remaining events, soonest first.
    var upcomingToday: [DetectedMeeting] {
        let now = Date()
        return meetings.filter { $0.end > now }
    }

    var nextMeeting: DetectedMeeting? { upcomingToday.first }

    // MARK: Scheduling

    private func startObserving() {
        stopObserving()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: EventKitCalendarProvider.changeNotification, object: nil
        )
        // Opportunistic refreshes so the data is never stale at the exact
        // moments a person looks at it or comes back to the machine.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(storeChanged),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(storeChanged),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        // 10s, not 30s (Marcello wants near-instant, 2026-07-26). Each tick
        // re-reads the local database AND calls refreshSourcesIfNecessary(),
        // which asks macOS to poll Google — so a faster tick shortens the
        // whole chain, not just our end of it. The read is a local query;
        // running it every 10s is negligible.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        ticker?.invalidate()
        ticker = nil
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        stopAutoSnooze()
    }

    @objc private func storeChanged() {
        Task { @MainActor in await refresh() }
    }

    /// Returning to the app is the moment a permission change is most likely to
    /// have just happened — the user went to System Settings, flipped the
    /// switch, and came back. The EventKit store instance cannot see that
    /// change, so replace it and re-read.
    @objc private func appBecameActive() {
        Task { @MainActor in
            eventKit?.renewStore()
            await refresh()
        }
    }

    private func tick() {
        // ALWAYS re-fetch (Marcello, 2026-07-25). The previous version only
        // re-read the database when a loaded meeting had ended, so an event
        // created or RESCHEDULED in Google never appeared: with an empty
        // meetings list the "something ended" test is never true, and the app
        // would sit on stale data forever. A refresh is a local EventKit
        // query — cheap enough to run every 30s unconditionally.
        Task { @MainActor in await refresh() }
    }

    /// The two-stage logic: ambient dot first, self-opening alert second.
    private func evaluateAlerts() {
        guard isConnected else { return }
        let now = Date()

        // An alert whose meeting is no longer in the list has nothing left to
        // draw, and a card that is not drawn cannot be dismissed. Refreshes
        // replace `meetings` wholesale every 10 seconds, so this is a normal
        // occurrence — a rescheduled or deleted event — not an edge case.
        // Left alone it stranded the panel open around an empty column.
        if let live = activeAlert, !meetings.contains(where: { $0.id == live.id }) {
            clearAlert(whileCollapsing: NotchController.shared.dismissMeetingAlert())
        }

        // Stage 1 — ambient (CA-2)
        let ambientWindow = TimeInterval(ambientLeadMinutes * 60)
        let ambient = upcomingToday.first {
            $0.start > now && $0.start.timeIntervalSince(now) <= ambientWindow
        }
        if ambient?.id != ambientMeeting?.id {
            withAnimation(NotchAnimation.contentHug) { ambientMeeting = ambient }
        }

        // Stage 2 — active alert (CA-3). Skip anything already alerted, and
        // respect an outstanding snooze (CA-5).
        guard activeAlert == nil else { return }
        let alertWindow = TimeInterval(alertLeadMinutes * 60)
        let due = upcomingToday.first { meeting in
            guard !alertedIDs.contains(meeting.id) else { return false }
            if let until = snoozedUntil[meeting.id], now < until { return false }
            // Fire from the lead time right up to the start (and briefly
            // after, so a Mac waking from sleep still shows it).
            let delta = meeting.start.timeIntervalSince(now)
            return delta <= alertWindow && delta > -60
        }
        if let due { present(due) }
    }

    private func present(_ meeting: DetectedMeeting) {
        alertedIDs.insert(meeting.id)
        // A new alert inside the previous one's closing window would otherwise
        // inherit its "leaving" flag and hide the to-do panel for no reason.
        alertLeavingTask?.cancel()
        alertLeaving = false
        withAnimation(NotchAnimation.contentHug) { activeAlert = meeting }
        // CA-6: the SAME expand path every other panel-open uses, so the
        // self-triggered open feels identical to a clicked one.
        NotchController.shared.presentMeetingAlert()
        armAutoSnooze()
        scheduleAutoCollapse(for: meeting)
    }

    // MARK: The alert's own clock

    /// Start the countdown from full. Called when the alert is raised, not
    /// when a view appears.
    private func armAutoSnooze() {
        autoSnoozeRemaining = LabMetrics.autoSnoozeSeconds
        resumeAutoSnooze()
    }

    /// Hovering the button pauses it: someone whose pointer is on Snooze is
    /// deciding, and deciding must not be punished by having the thing decide
    /// for them.
    func pauseAutoSnooze() {
        autoSnoozeTask?.cancel()
        autoSnoozeTask = nil
        autoSnoozeRunning = false
        guard let started = autoSnoozeResumedAt else { return }
        autoSnoozeRemaining = max(0, autoSnoozeRemaining - Date().timeIntervalSince(started))
        autoSnoozeResumedAt = nil
    }

    func resumeAutoSnooze() {
        guard activeAlert != nil, autoSnoozeRemaining > 0, autoSnoozeResumedAt == nil else { return }
        autoSnoozeResumedAt = Date()
        autoSnoozeRunning = true
        let seconds = autoSnoozeRemaining
        autoSnoozeTask?.cancel()
        autoSnoozeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeAlert != nil else { return }
            self.snooze()
        }
    }

    private func stopAutoSnooze() {
        autoSnoozeTask?.cancel()
        autoSnoozeTask = nil
        autoSnoozeResumedAt = nil
        autoSnoozeRunning = false
        autoSnoozeRemaining = LabMetrics.autoSnoozeSeconds
    }

    /// Untouched alerts collapse shortly after the meeting starts, so the
    /// panel never sits open over the screen while the user is away.
    private func scheduleAutoCollapse(for meeting: DetectedMeeting) {
        autoCollapseTask?.cancel()
        let deadline = max(meeting.start.timeIntervalSinceNow + 120, 30)
        autoCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeAlert?.id == meeting.id else { return }
            self.dismissAlert()
        }
    }

    // MARK: Alert actions

    /// Hints Google Meet toward the account Otto is actually connected to,
    /// rather than whichever Google session the browser happens to have
    /// active. A browser signed into several Google accounts otherwise joins
    /// with the wrong one — not the identity that was actually invited to the
    /// meeting (Marcello, 2026-08-09). `authuser` is Google's own, documented
    /// mechanism for this across every one of its own properties (Meet,
    /// Calendar, Drive, Docs); it is meaningless outside google.com and left
    /// untouched there, so a Zoom or Teams link is never rewritten.
    ///
    /// Exact host match, not a suffix check: `"x.evil-google.com".hasSuffix(
    /// "google.com")` would also be true, which is the wrong kind of "close
    /// enough" for something that decides which account a browser signs
    /// requests as.
    static func urlForJoining(_ url: URL) -> URL {
        guard url.host == "meet.google.com",
              let account = GoogleOAuth.shared.account,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "authuser" }
        items.append(URLQueryItem(name: "authuser", value: account))
        components.queryItems = items
        return components.url ?? url
    }

    /// ⌘↩ from the panel: open the next meeting that actually has a link.
    /// Returns false when there is nothing to join, so the key handler can let
    /// the keystroke fall through instead of swallowing it.
    @discardableResult
    func joinNextMeeting() -> Bool {
        guard isConnected,
              let next = upcomingToday.first(where: { $0.videoURL != nil }),
              let url = next.videoURL else { return false }
        NSWorkspace.shared.open(Self.urlForJoining(url))
        NotchController.shared.attentionLeft()
        return true
    }

    /// CA-4 — open the detected call link.
    func join() {
        guard let url = activeAlert?.videoURL else { return }
        NSWorkspace.shared.open(Self.urlForJoining(url))
        dismissAlert()
        // Policy rule 7: the browser is taking over, so the notch is done.
        NotchController.shared.attentionLeft()
    }

    /// CA-5 — re-trigger after the snooze delay.
    /// Snooze a SPECIFIC meeting, whether or not it is the one alerting.
    ///
    /// Every card carries a Snooze now, including ones the user opened
    /// themselves from the stack — a meeting with no video link previously had
    /// no control at all and could not be dismissed. Snoozing one that is not
    /// alerting simply suppresses its alert; the panel stays put, because the
    /// user opened it and nothing has interrupted them.
    func snooze(_ meeting: DetectedMeeting) {
        HapticManager.shared.meetingSnoozed()
        suppress(meeting)
        guard activeAlert?.id == meeting.id else { return }
        // No `attentionLeft()` chaser. dismissAlert already closes the notch,
        // and the second call raced the first: it ran with the alert already
        // cleared, so it took the ordinary collapse path at the same moment
        // the alert path was taking it, and the to-do panel got a frame to
        // appear in between.
        dismissAlert()
    }

    func snooze() {
        guard let meeting = activeAlert else { return }
        suppress(meeting)
        // Snooze means "not now" — so the panel goes away, the same as Join
        // does. It used to fall back to the to-do list, leaving a panel open
        // that the user never asked to open: the notch had opened ITSELF for
        // the meeting, so dismissing the meeting should return the screen to
        // exactly where it was (Marcello, 2026-08-10).
        dismissAlert()
    }

    /// The notch is closing for a reason that has nothing to do with the
    /// meeting — an outside click, Escape, another app coming forward.
    ///
    /// That has to be a snooze, not a silent drop. `forceCollapse` used to
    /// close the notch and leave `activeAlert` set, which had two costs: the
    /// panel counted itself as engaged forever after, and `updateAlerts`
    /// refuses to raise a new alert while one is live — so one outside click
    /// during a meeting alert quietly turned every later alert off for the
    /// rest of the session.
    ///
    /// Walking away is "not now": the meeting comes back after the snooze
    /// interval rather than being lost.
    func alertLostAttention() {
        guard let meeting = activeAlert else { return }
        suppress(meeting)
        clearAlert(whileCollapsing: true)
    }

    func dismissAlert() {
        guard activeAlert != nil else { return }
        // Close FIRST, then clear — the order is the whole fix. Asked to
        // collapse before the card is taken away, the panel has nothing to
        // swap in and the meeting simply leaves with the notch.
        clearAlert(whileCollapsing: NotchController.shared.dismissMeetingAlert())
    }

    /// Stop this meeting alerting for a while, without touching what is drawn.
    private func suppress(_ meeting: DetectedMeeting) {
        snoozedUntil[meeting.id] = Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        alertedIDs.remove(meeting.id)
    }

    private func clearAlert(whileCollapsing: Bool) {
        stopAutoSnooze()
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        alertLeavingTask?.cancel()
        alertLeaving = whileCollapsing
        withAnimation(NotchAnimation.contentHug) { activeAlert = nil }
        guard whileCollapsing else { return }
        // Long enough to cover the close, short enough that a panel reopened
        // straight afterwards is a normal to-do panel again.
        alertLeavingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.alertLeaving = false
        }
    }

    // MARK: Testing seam

    #if DEBUG
    /// Inject a synthetic meeting so the alert stages can be exercised
    /// without waiting for a real one (see DebugDriver).
    /// Set by `injectTestMeeting`, so a real provider refresh cannot replace
    /// the fixture out from under a test.
    private(set) var debugHoldsInjectedMeetings = false

    func debugReleaseInjectedMeetings() { debugHoldsInjectedMeetings = false }

    func injectTestMeeting(minutesFromNow: Int, withLink: Bool) {
        debugHoldsInjectedMeetings = true
        let start = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        let meeting = DetectedMeeting(
            id: "test-\(UUID().uuidString.prefix(6))",
            title: "Design sync",
            start: start,
            end: start.addingTimeInterval(1800),
            attendees: ["Rose", "Wessel"],
            organizer: "Rose",
            attendeeEmails: ["rose@example.com", "wessel@example.com"],
            participantNames: ["Rose", "Wessel", "You"],
            participantEmails: ["rose@example.com", "wessel@example.com", ""],
            location: nil,
            videoURL: withLink ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
            platform: withLink ? "Google Meet" : nil,
            isAllDay: false
        )
        isConnected = true
        withAnimation(NotchAnimation.contentHug) { meetings = [meeting] }
        evaluateAlerts()
    }
    #endif
}
