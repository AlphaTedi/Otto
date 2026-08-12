import Foundation

// MARK: - EntityParser — inline entities in to-do titles (urgency/entity PRD §2)
//
// Splits a title into plain-text runs and recognized entities so the row can
// render Slack-style inline chips. Detection per §2.1:
//   code     `backtick spans` — explicit marker only, no heuristics (EH-4)
//   link     NSDataDetector .link, display shortened to the host (EH-1)
//   mention  @name prefix pattern, purely visual in v1 — no contacts model
//            behind it (EH-3, confirmed with Marcello)
//   date     NSDataDetector .date + the NLDateParser shorthand vocabulary
//            ("Fri", "tomorrow") (EH-2)
//
// Overlaps resolve by precedence code > link > mention > date — a backticked
// URL is code, an @ inside a URL is not a mention, a date inside a code span
// stays code.

enum TitleSegment: Equatable {
    case text(String)
    case entity(kind: EntityKind, display: String, url: URL?)
}

enum EntityParser {

    private struct Candidate {
        let range: NSRange
        let kind: EntityKind
        let display: String
        let url: URL?
        let priority: Int   // lower wins
    }

    private static let codeRegex = try? NSRegularExpression(pattern: "`([^`]+)`")
    // Lookbehind keeps the @ from matching inside an email address
    // ("me@julian.dev" is not a mention of @julian.dev).
    private static let mentionRegex = try? NSRegularExpression(pattern: "(?<![\\w.])@([\\p{L}\\w.-]+)")
    /// #channel / #tag. Same shape as a mention but requires a leading letter,
    /// so "#1" and a hex colour like "#3A3A3A" stay plain text rather than
    /// becoming chips — the common false positives for this pattern.
    private static let channelRegex = try? NSRegularExpression(
        pattern: "(?<![\\w#])#([\\p{L}][\\p{L}\\w-]*)")
    private static let dataDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
             | NSTextCheckingResult.CheckingType.date.rawValue
    )

    static func parse(_ title: String) -> [TitleSegment] {
        let ns = title as NSString
        let full = NSRange(location: 0, length: ns.length)
        var candidates: [Candidate] = []

        // 1. Code spans (explicit backtick marker; backticks stripped, EH-4).
        codeRegex?.enumerateMatches(in: title, range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            candidates.append(Candidate(
                range: match.range,
                kind: .code,
                display: ns.substring(with: match.range(at: 1)),
                url: nil, priority: 0
            ))
        }

        // 2. Links + explicit dates via the system detector.
        dataDetector?.enumerateMatches(in: title, range: full) { match, _, _ in
            guard let match else { return }
            if match.resultType == .link, let url = match.url {
                // Bare emails also come back as .link (mailto) — leave those
                // to the mention/plain treatment unless typed as a URL.
                guard url.scheme != "mailto" else { return }
                candidates.append(Candidate(
                    range: match.range,
                    kind: .link,
                    display: Self.shortHost(for: url, typed: ns.substring(with: match.range)),
                    url: url, priority: 1
                ))
            } else if match.resultType == .date {
                candidates.append(Candidate(
                    range: match.range,
                    kind: .date,
                    display: ns.substring(with: match.range),
                    url: nil, priority: 3
                ))
            }
        }

        // 3. Mentions.
        mentionRegex?.enumerateMatches(in: title, range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            candidates.append(Candidate(
                range: match.range,
                kind: .mention,
                display: ns.substring(with: match.range(at: 1)),
                url: nil, priority: 2
            ))
        }

        // 3b. Channels / tags.
        channelRegex?.enumerateMatches(in: title, range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            candidates.append(Candidate(
                range: match.range,
                kind: .channel,
                display: ns.substring(with: match.range(at: 1)),
                url: nil, priority: 2
            ))
        }

        // 4. Shorthand dates the system detector misses ("tom", "next mon").
        if let nl = NLDateParser.parse(title) {
            candidates.append(Candidate(
                range: nl.nsRange,
                kind: .date,
                display: ns.substring(with: nl.nsRange),
                url: nil, priority: 3
            ))
        }

        // Resolve overlaps: stable order by (priority, position), keep
        // whatever doesn't intersect an already-accepted range.
        var accepted: [Candidate] = []
        for candidate in candidates.sorted(by: {
            ($0.priority, $0.range.location) < ($1.priority, $1.range.location)
        }) {
            let overlaps = accepted.contains {
                NSIntersectionRange($0.range, candidate.range).length > 0
            }
            if !overlaps { accepted.append(candidate) }
        }
        accepted.sort { $0.range.location < $1.range.location }

        // Interleave plain runs and entities.
        var segments: [TitleSegment] = []
        var cursor = 0
        for candidate in accepted {
            if candidate.range.location > cursor {
                let run = ns.substring(with: NSRange(location: cursor,
                                                     length: candidate.range.location - cursor))
                segments.append(.text(run))
            }
            segments.append(.entity(kind: candidate.kind,
                                    display: candidate.display,
                                    url: candidate.url))
            cursor = NSMaxRange(candidate.range)
        }
        if cursor < ns.length {
            segments.append(.text(ns.substring(from: cursor)))
        }
        if segments.isEmpty { segments = [.text(title)] }
        return segments
    }

    /// EH-1: chips display `youtube.com`, never the full URL — the full URL
    /// is still what opens on click.
    private static func shortHost(for url: URL, typed: String) -> String {
        if let host = url.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return typed
    }
}
