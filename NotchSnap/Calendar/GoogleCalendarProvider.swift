import Foundation

// MARK: - GoogleCalendarProvider — talks to Google directly
//
// Exists because reading the macOS Calendar app is only as good as macOS's own
// Google sync, and on Marcello's Mac that sync has been dead since May 2026:
// the notch showed nothing while Google's web UI showed a full day. Going
// straight to the API removes macOS from the path entirely — and with it the
// calendar permission prompt, which an ad-hoc-signed build cannot reliably get
// on a second machine anyway.
//
// Read-only, by scope as well as by behaviour.

// Main-actor isolated to match MeetingProvider (and EventKitCalendarProvider).
// That is fine for a network client: every request is `await`ed, so the main
// thread suspends rather than blocks.
@MainActor
final class GoogleCalendarProvider: MeetingProvider {
    nonisolated private static let base = "https://www.googleapis.com/calendar/v3"

    private var cachedAccount: String?
    private var lastError: String?

    // MARK: MeetingProvider

    var accountDescription: String? { GoogleOAuth.shared.account }

    var isConnected: Bool { GoogleOAuth.shared.isSignedIn }

    func connect() async -> String? {
        do {
            try await GoogleOAuth.shared.signIn()
            // Prove the grant actually works before reporting success —
            // consent can be given and still yield nothing readable.
            _ = try await fetchEvents()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func disconnect() { GoogleOAuth.shared.signOut() }

    func upcomingToday() async -> [DetectedMeeting] {
        do {
            let events = try await fetchEvents()
            let now = Date()
            return events
                .filter { $0.end > now }
                .sorted { $0.start < $1.start }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func lastErrorText() -> String? { lastError }

    // MARK: Fetch

    /// Same window as the EventKit provider: the rest of today, extended to at
    /// least 12 hours so an event just after midnight doesn't vanish.
    private func fetchEvents() async throws -> [DetectedMeeting] {
        let token = try await GoogleOAuth.shared.validAccessToken()
        let now = Date()
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let windowEnd = max(endOfToday, now.addingTimeInterval(12 * 3600))

        var components = URLComponents(string: "\(Self.base)/calendars/primary/events")!
        components.queryItems = [
            .init(name: "timeMin", value: ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))),
            .init(name: "timeMax", value: ISO8601DateFormatter().string(from: windowEnd)),
            // Expands recurring events into concrete instances; without it a
            // weekly standup arrives as one master row with a rule to apply.
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "50"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            throw GoogleOAuth.AuthError.tokenExchange(detail ?? "HTTP \(http.statusCode)")
        }
        return Self.parse(data)
    }

    // MARK: Parsing
    //
    // Split out and given internal visibility so it can be tested against
    // recorded payloads — the live path needs a client ID that only Marcello
    // can create.

    nonisolated static func parse(_ data: Data) -> [DetectedMeeting] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap(meeting(from:))
    }

    nonisolated static func meeting(from item: [String: Any]) -> DetectedMeeting? {
        guard let id = item["id"] as? String else { return nil }
        // Cancelled instances of a recurring series still come back.
        if (item["status"] as? String) == "cancelled" { return nil }

        let startInfo = item["start"] as? [String: Any] ?? [:]
        let endInfo = item["end"] as? [String: Any] ?? [:]
        let isAllDay = startInfo["date"] != nil
        guard let start = date(from: startInfo), let end = date(from: endInfo) else { return nil }
        // All-day events are not meetings; they'd otherwise sit at the top of
        // the list all day claiming to start "now".
        if isAllDay { return nil }

        let attendeeList = item["attendees"] as? [[String: Any]] ?? []
        // "self" marks the signed-in user. They belong in the avatar composite
        // but not in the "with …" text line.
        let others = attendeeList.filter { !(($0["self"] as? Bool) ?? false) }
        let name: ([String: Any]) -> String = { a in
            (a["displayName"] as? String) ?? (a["email"] as? String) ?? "?"
        }

        let organizerInfo = item["organizer"] as? [String: Any]
        let conference = conferenceLink(item)

        return DetectedMeeting(
            id: id,
            title: (item["summary"] as? String) ?? L10n.t("cal.untitled"),
            start: start,
            end: end,
            attendees: others.map(name),
            organizer: organizerInfo.map(name),
            attendeeEmails: others.compactMap { $0["email"] as? String },
            participantNames: attendeeList.map(name),
            participantEmails: attendeeList.compactMap { $0["email"] as? String },
            location: item["location"] as? String,
            videoURL: conference.url,
            platform: conference.platform,
            isAllDay: false
        )
    }

    /// Prefer Google's structured conferenceData; fall back to scanning the
    /// location and description the way the EventKit provider does, because
    /// Zoom/Teams invites often only put the link in the body.
    nonisolated private static func conferenceLink(_ item: [String: Any]) -> (url: URL?, platform: String?) {
        if let data = item["conferenceData"] as? [String: Any],
           let entryPoints = data["entryPoints"] as? [[String: Any]],
           let video = entryPoints.first(where: { ($0["entryPointType"] as? String) == "video" }),
           let uri = video["uri"] as? String, let url = URL(string: uri) {
            // Google names the solution ("Google Meet", "Zoom Meeting"); fall
            // back to host matching if it doesn't.
            let solution = (data["conferenceSolution"] as? [String: Any])?["name"] as? String
            let detected = VideoCallDetector.detect(in: [uri])
            return (url, solution ?? detected?.platform)
        }
        // Zoom and Teams invites frequently put the link only in the body.
        if let found = VideoCallDetector.detect(in: [
            item["hangoutLink"] as? String,
            item["location"] as? String,
            item["description"] as? String,
        ]) {
            return (found.url, found.platform)
        }
        return (nil, nil)
    }

    nonisolated private static func date(from info: [String: Any]) -> Date? {
        if let dateTime = info["dateTime"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: dateTime) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateTime)
        }
        if let day = info["date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            return formatter.date(from: day)
        }
        return nil
    }
}
