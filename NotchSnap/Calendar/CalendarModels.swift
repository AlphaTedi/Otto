import Foundation

// MARK: - Calendar awareness models (calendar PRD §3.1)
//
// `DetectedMeeting` is the single shape the rest of the app consumes, so the
// data SOURCE stays swappable: EventKit today, a Google OAuth provider later,
// without the alert logic or any view knowing the difference.

struct DetectedMeeting: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    /// Display names, excluding the user themselves.
    var attendees: [String]
    /// Organizer display name — the single avatar shown on a Today row (AV-5).
    var organizer: String?
    /// Attendee emails, parallel to `attendees` — used to resolve photos.
    var attendeeEmails: [String]
    /// EVERYONE on the invite including you, in display order. The avatar
    /// composite uses this so a 1:1 shows two faces, not one (Marcello,
    /// 2026-07-26); the text line still lists only the others.
    var participantNames: [String] = []
    var participantEmails: [String] = []
    /// Where it happens, when there's no video link (room, address).
    var location: String?
    /// Detected video-call link, if any — drives the Join button (CA-4).
    var videoURL: URL?
    /// "Google Meet" / "Zoom" / "Teams", shown next to the attendees.
    var platform: String?
    var isAllDay: Bool

    var minutesUntilStart: Int {
        Int((start.timeIntervalSinceNow / 60).rounded(.down))
    }

    var hasStarted: Bool { Date() >= start }

    /// "10:00" — the compact time shown in the Today list.
    var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: start)
    }

    /// Who to show an avatar for: attendees if there are any, else the
    /// organizer, else the meeting title (so a solo event still gets a disc
    /// rather than a blank space).
    var avatarNames: [String] {
        if !participantNames.isEmpty { return participantNames }
        if !attendees.isEmpty { return attendees }
        if let organizer, !organizer.isEmpty { return [organizer] }
        return [title]
    }

    var avatarEmails: [String] {
        if !participantEmails.isEmpty { return participantEmails }
        return attendeeEmails
    }

    /// "3 guests" — the count label beside the composite.
    var participantCountLabel: String? {
        let total = max(participantNames.count, attendees.count + 1)
        guard total > 1 else { return nil }
        return String(format: L10n.t("cal.guests"), total)
    }

    /// "10:00 – 10:30" — the full span, so a row says how long it runs.
    var timeRangeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return "\(formatter.string(from: start)) \u{2013} \(formatter.string(from: end))"
    }

    /// "Rose, Wessel" / "Rose, Wessel +2" / the location when nobody is
    /// listed — the second line of a row, so it always carries context.
    var contextLabel: String {
        if !attendees.isEmpty {
            let names = attendees.prefix(2).joined(separator: ", ")
            let extra = attendees.count - min(2, attendees.count)
            return extra > 0 ? "\(names) +\(extra)" : names
        }
        if let location, !location.isEmpty { return location }
        return ""
    }

    /// "with Rose, Wessel · Google Meet"
    var subtitle: String {
        var parts: [String] = []
        if !attendees.isEmpty {
            let names = attendees.prefix(3).joined(separator: ", ")
            let extra = attendees.count > 3 ? " +\(attendees.count - 3)" : ""
            parts.append(L10n.t("cal.with") + " " + names + extra)
        }
        if let platform { parts.append(platform) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Provider seam

/// Anything that can supply today's meetings. Deliberately narrow: connect,
/// disconnect, fetch. A Google OAuth provider can conform later without any
/// change to CalendarStore or the views (Marcello chose EventKit for v1,
/// 2026-07-25).
@MainActor
protocol MeetingProvider {
    /// Human-readable account/source description for the Settings screen —
    /// e.g. the Google account email, or the macOS calendar source names.
    var accountDescription: String? { get }
    /// True once the provider can actually read events.
    var isConnected: Bool { get }
    /// Ask for access. Returns the failure reason on refusal, nil on success.
    func connect() async -> String?
    func disconnect()
    /// Today's events that haven't ended yet, soonest first.
    func upcomingToday() async -> [DetectedMeeting]
}

// MARK: - Video-call link detection

enum VideoCallDetector {
    private static let patterns: [(host: String, name: String)] = [
        ("meet.google.com", "Google Meet"),
        ("zoom.us", "Zoom"),
        ("teams.microsoft.com", "Microsoft Teams"),
        ("teams.live.com", "Microsoft Teams"),
        ("webex.com", "Webex"),
        ("whereby.com", "Whereby"),
        ("meet.jit.si", "Jitsi"),
        ("around.co", "Around"),
        ("gather.town", "Gather"),
    ]

    /// Scan the fields where meeting links actually live — the event's URL,
    /// its location, and the body of the invite.
    static func detect(in candidates: [String?]) -> (url: URL, platform: String)? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for candidate in candidates.compactMap({ $0 }) where !candidate.isEmpty {
            let range = NSRange(candidate.startIndex..., in: candidate)
            let matches = detector?.matches(in: candidate, range: range) ?? []
            for match in matches {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if let hit = patterns.first(where: { host.contains($0.host) }) {
                    return (url, hit.name)
                }
            }
        }
        return nil
    }
}
