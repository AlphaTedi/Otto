import EventKit
import Foundation

// MARK: - EventKitCalendarProvider — reads macOS Calendar (v1 source)
//
// Marcello chose this over Google OAuth (2026-07-25): a Google account added
// in System Settings › Internet Accounts surfaces through EventKit with no
// OAuth client registration, no token storage or refresh, and it picks up
// iCloud/Exchange calendars for free. The app already uses EventKit for
// Reminders, so this adds no new dependency.
//
// Read-only by contract — the equivalent of the PRD's `calendar.readonly`
// scope (SU-4): this type never creates, edits, or removes an event.

@MainActor
final class EventKitCalendarProvider: MeetingProvider {

    private let store = EKEventStore()

    var isConnected: Bool {
        Self.authorized(EKEventStore.authorizationStatus(for: .event))
    }

    private static func authorized(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    var accountDescription: String? {
        guard isConnected else { return nil }
        let sources = Set(store.calendars(for: .event)
            .filter { !$0.title.isEmpty }
            .map { $0.source.title })
        guard !sources.isEmpty else { return nil }
        return sources.sorted().joined(separator: ", ")
    }

    /// What NotchSnap can actually see, per calendar — surfaced in Settings.
    ///
    /// "Connected" alone proved misleading (Marcello, 2026-07-25): EventKit
    /// reported his account emails as sources, which reads like "your Google
    /// Calendar is connected", while the calendar holding the meeting wasn't
    /// synced to this Mac at all. Naming every visible calendar makes the
    /// difference obvious instead of silent.
    struct CalendarSummary: Identifiable {
        let id: String
        let title: String
        let source: String
        let sourceType: String
        var isEnabled: Bool
    }

    var visibleCalendars: [CalendarSummary] {
        guard isConnected else { return [] }
        return store.calendars(for: .event).map { cal in
            CalendarSummary(
                id: cal.calendarIdentifier,
                title: cal.title,
                source: cal.source.title,
                sourceType: Self.describe(cal.source.sourceType),
                isEnabled: isCalendarEnabled(cal.calendarIdentifier)
            )
        }
        .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    private static func describe(_ type: EKSourceType) -> String {
        switch type {
        case .local:      return "On this Mac"
        case .exchange:   return "Exchange"
        case .calDAV:     return "CalDAV/Google"
        case .mobileMe:   return "iCloud"
        case .subscribed: return "Subscribed"
        case .birthdays:  return "Birthdays"
        @unknown default: return "Other"
        }
    }

    /// Wide-window probe: is the local EventKit database populated at all?
    /// Distinguishes "nothing scheduled today" from "this store is stale or
    /// the account isn't syncing to this Mac".
    func probeWideWindow() -> [String] {
        guard isConnected else { return ["not connected"] }
        syncSources()
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return ["no calendars visible"] }

        let now = Date()
        let from = now.addingTimeInterval(-7 * 86_400)
        let to = now.addingTimeInterval(30 * 86_400)
        var lines: [String] = []
        var grandTotal = 0
        for cal in calendars.sorted(by: { $0.title < $1.title }) {
            let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [cal])
            let count = store.events(matching: predicate).count
            grandTotal += count
            lines.append("  \(cal.title) [\(cal.source.title)] → \(count) events in -7d..+30d")
        }
        lines.insert("TOTAL events in -7d..+30d: \(grandTotal)", at: 0)

        // EVERY event in the window with its creation/modification stamps.
        // The newest stamp is the real answer to "when did this Mac last
        // receive data from Google?" — if it's days old while the account
        // clearly has newer events, the account's sync is dead (expired
        // token / needs re-auth), not slow.
        let all = store.events(matching: store.predicateForEvents(withStart: from, end: to,
                                                                  calendars: calendars))
            .sorted { $0.startDate < $1.startDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        let stamp = DateFormatter()
        stamp.dateFormat = "MMM d HH:mm"
        lines.append("ALL \(all.count) events in window (start | created | modified):")
        for event in all {
            let created = event.creationDate.map { stamp.string(from: $0) } ?? "?"
            let modified = event.lastModifiedDate.map { stamp.string(from: $0) } ?? "?"
            lines.append("  \(formatter.string(from: event.startDate)) '\(event.title ?? "?")'"
                + " [\(event.calendar.title)] created=\(created) mod=\(modified)")
        }
        // Newest sync stamp anywhere — the freshness of the whole database.
        let newest = all.compactMap { $0.lastModifiedDate ?? $0.creationDate }.max()
        lines.append("NEWEST record on this Mac: \(newest.map { stamp.string(from: $0) } ?? "none")")
        lines.append("now: \(stamp.string(from: now))")
        return lines
    }

    /// What attendee data EventKit really hands over for today's events —
    /// names, emails, roles. Answers "why is that avatar just a letter?".
    func diagnoseAttendees() -> [String] {
        guard isConnected else { return ["not connected"] }
        syncSources()
        let calendars = activeCalendars
        guard !calendars.isEmpty else { return ["no calendars"] }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: Calendar.current.startOfDay(for: now),
                                                 end: Self.windowEnd(from: now),
                                                 calendars: calendars)
        var lines: [String] = []
        for event in store.events(matching: predicate) {
            lines.append("EVENT '\(event.title ?? "?")'")
            lines.append("  organizer: name=\(event.organizer?.name ?? "nil") "
                         + "url=\(event.organizer?.url.absoluteString ?? "nil")")
            let attendees = event.attendees ?? []
            lines.append("  attendees: \(attendees.count)")
            for a in attendees {
                lines.append("    • name=\(a.name ?? "nil") url=\(a.url.absoluteString) "
                             + "isMe=\(a.isCurrentUser) status=\(a.participantStatus.rawValue)")
            }
        }
        return lines.isEmpty ? ["no events in window"] : lines
    }

    /// When the local calendar database was last written to, across every
    /// calendar. If this is weeks old, macOS has stopped syncing and NO new
    /// event will ever appear — the failure that cost hours on 2026-07-25,
    /// where the newest record was May 12 while the user kept creating
    /// events in Google. Surfaced in Settings so it can never look like a
    /// NotchSnap bug again.
    func lastSyncedAt() -> Date? {
        guard isConnected else { return nil }
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return nil }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-120 * 86_400),
                                                 end: now.addingTimeInterval(120 * 86_400),
                                                 calendars: calendars)
        return store.events(matching: predicate)
            .compactMap { $0.lastModifiedDate ?? $0.creationDate }
            .max()
    }

    /// Every event in today's window BEFORE filtering, with the reason each
    /// one was hidden. This is the diagnostic that answers "why isn't my
    /// meeting showing?" without guesswork.
    func diagnoseToday() -> [String] {
        guard isConnected else { return ["not connected"] }
        syncSources()
        let calendars = activeCalendars
        guard !calendars.isEmpty else { return ["no calendars visible"] }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: Calendar.current.startOfDay(for: now),
                                                 end: Self.windowEnd(from: now),
                                                 calendars: calendars)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return store.events(matching: predicate).map { event in
            let reason: String
            if event.isAllDay { reason = "hidden: all-day" }
            else if let end = event.endDate, end <= now { reason = "hidden: already ended" }
            else if event.status == .canceled { reason = "hidden: cancelled" }
            else if let me = event.attendees?.first(where: { $0.isCurrentUser }),
                    me.participantStatus == .declined { reason = "hidden: you declined" }
            else { reason = "SHOWN" }
            return "\(formatter.string(from: event.startDate))-\(formatter.string(from: event.endDate)) "
                + "'\(event.title ?? "?")' [\(event.calendar.title)] → \(reason)"
        }
    }

    /// Triggers the system permission prompt. Returns nil on success, or a
    /// human-readable reason on failure.
    func connect() async -> String? {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Self.authorized(status) { return nil }
        if status == .denied || status == .restricted {
            return L10n.t("cal.err.denied")
        }
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            guard granted else { return L10n.t("cal.err.denied") }
            if store.calendars(for: .event).isEmpty {
                // Access granted but nothing to read — the most likely real
                // situation on a fresh Mac, so say what to do about it.
                return L10n.t("cal.err.noCalendars")
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// EventKit access is a system-level grant, so "disconnect" can't revoke
    /// it from here — CalendarStore stops using the data and points the user
    /// at System Settings for the permission itself (SU-8).
    func disconnect() {}

    // MARK: Calendar selection
    //
    // EventKit permission is all-or-nothing at the SYSTEM level — macOS grants
    // access to the calendar database, not to one account, so there's no way
    // to "connect just one account" (Marcello, 2026-07-25). What NotchSnap can
    // do is let you choose which calendars it actually uses, which is the part
    // that matters: holidays and birthdays shouldn't open your notch.

    /// Persisted calendar identifiers. Empty = every calendar (the default).
    private static let enabledIDsKey = "calEnabledCalendarIDs"

    var enabledCalendarIDs: Set<String> {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.enabledIDsKey) ?? ""
            return Set(raw.split(separator: ",").map(String.init))
        }
        set {
            UserDefaults.standard.set(newValue.sorted().joined(separator: ","),
                                      forKey: Self.enabledIDsKey)
        }
    }

    func setCalendar(_ id: String, enabled: Bool) {
        var ids = enabledCalendarIDs
        // First explicit choice materializes the current "all" set so the
        // toggle the user just flipped is the only one that changes.
        if ids.isEmpty {
            ids = Set(store.calendars(for: .event).map(\.calendarIdentifier))
        }
        if enabled { ids.insert(id) } else { ids.remove(id) }
        enabledCalendarIDs = ids
    }

    func isCalendarEnabled(_ id: String) -> Bool {
        let ids = enabledCalendarIDs
        return ids.isEmpty || ids.contains(id)
    }

    /// The calendars actually queried: the user's selection, or all of them.
    private var activeCalendars: [EKCalendar] {
        let all = store.calendars(for: .event)
        let ids = enabledCalendarIDs
        guard !ids.isEmpty else { return all }
        let selected = all.filter { ids.contains($0.calendarIdentifier) }
        return selected.isEmpty ? all : selected
    }

    /// How far ahead to look.
    ///
    /// "The rest of the calendar day" breaks late at night: at 22:20 a meeting
    /// at 03:15 the next morning is the genuine NEXT event, yet it fell
    /// outside the window entirely — so it never showed in Up next and never
    /// alerted (Marcello, 2026-07-25). The window is now the rest of today OR
    /// the next 12 hours, whichever reaches further. During normal hours that
    /// is identical to "today"; near midnight it rolls over correctly.
    static func windowEnd(from now: Date) -> Date {
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        return max(endOfToday, now.addingTimeInterval(12 * 3600))
    }

    /// Pull remote changes down before reading.
    ///
    /// EventKit only ever sees what macOS Calendar has already synced, and
    /// Google/CalDAV accounts refresh on their own slow schedule — a meeting
    /// created in Google Calendar minutes ago simply isn't in the local
    /// database yet (verified 2026-07-25: EventKit had events from these very
    /// accounts, but nothing created that day). This asks the sources to
    /// fetch, which is the difference between "my meeting never shows up" and
    /// "it shows up within a minute".
    private func syncSources() {
        store.refreshSourcesIfNecessary()
        // Re-read the database. A store created before the DB was ready can
        // otherwise keep serving stale results.
        store.reset()
    }

    /// Today's events that haven't ended yet, soonest first.
    func upcomingToday() async -> [DetectedMeeting] {
        guard isConnected else { return [] }
        syncSources()
        let calendars = activeCalendars
        guard !calendars.isEmpty else { return [] }

        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                 end: Self.windowEnd(from: now),
                                                 calendars: calendars)

        return store.events(matching: predicate)
            .filter { Self.shouldSurface($0, now: now) }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.meeting(from:))
    }

    // MARK: Filtering

    private static func shouldSurface(_ event: EKEvent, now: Date) -> Bool {
        // CT-5: only what's still ahead.
        guard let end = event.endDate, end > now else { return false }
        // All-day entries are context, not meetings to alert on.
        guard !event.isAllDay else { return false }
        guard event.status != .canceled else { return false }
        // CA-7: never alert on something the user declined.
        if let me = event.attendees?.first(where: { $0.isCurrentUser }),
           me.participantStatus == .declined {
            return false
        }
        return true
    }

    private static func meeting(from event: EKEvent) -> DetectedMeeting {
        let detected = VideoCallDetector.detect(in: [
            event.url?.absoluteString, event.location, event.notes,
        ])
        let others = (event.attendees ?? []).filter { !$0.isCurrentUser }
        let attendees = others.compactMap {
            $0.name ?? $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        }
        let emails = others.map {
            $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        }
        // Everyone, you last — so a two-person meeting renders two discs.
        let everyone = others + (event.attendees ?? []).filter(\.isCurrentUser)
        let participantNames = everyone.compactMap {
            $0.name ?? $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        }
        let participantEmails = everyone.map {
            $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        }

        return DetectedMeeting(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? L10n.t("cal.untitled"),
            start: event.startDate,
            end: event.endDate,
            attendees: attendees,
            organizer: event.organizer?.name
                ?? event.organizer?.url.absoluteString
                    .replacingOccurrences(of: "mailto:", with: ""),
            attendeeEmails: emails,
            participantNames: participantNames,
            participantEmails: participantEmails,
            location: event.location,
            videoURL: detected?.url,
            platform: detected?.platform,
            isAllDay: event.isAllDay
        )
    }

    /// EventKit posts this when anything in the calendar database changes.
    static var changeNotification: Notification.Name { .EKEventStoreChanged }
}
