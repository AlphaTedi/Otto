import Foundation

// MARK: - NLDateParser — Things-style natural-language dates (design PRD §8)
//
// Recognizes a date phrase typed INSIDE the to-do title ("Confirm dinner
// spot tom") and resolves it live. NL-1..4 as inferred from the mockups:
//   • recognized substring is highlighted inline, never removed while typing
//   • a caption below shows what the parser concluded ("→ Tomorrow, Jul 14")
//   • the phrase is stripped from the title only on Create, becoming dueDate
//   • the LAST recognized phrase wins — people append dates at the end
//
// Deliberately small vocabulary (today/tom/tomorrow, weekdays with optional
// "next", "next week", month-day) — a full NLP date engine is out of scope.

struct NLDateMatch: Equatable {
    /// UTF-16 range of the recognized phrase within the original title.
    let nsRange: NSRange
    let date: Date
    /// e.g. "Tomorrow, Jul 14" / "Mon, Jul 20"
    let display: String
    /// Title with the phrase stripped and whitespace collapsed.
    let cleanedTitle: String
}

enum NLDateParser {
    private static let weekdays: [String: Int] = [
        // Calendar weekday numbers: 1 = Sunday … 7 = Saturday
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tues": 3, "tue": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thurs": 5, "thur": 5, "thu": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    // Longest alternatives first so "tomorrow" wins over "tom", "thurs" over "thu".
    private static let pattern: String = {
        let weekdayAlts = weekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let monthAlts = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let pieces = [
            "next\\s+week",
            "(?:next\\s+)?(?:\(weekdayAlts))",
            "tomorrow|tom",
            "today|tod",
            "(?:\(monthAlts))\\s+\\d{1,2}",
            "\\d{1,2}\\s+(?:\(monthAlts))",
        ]
        return "\\b(?:" + pieces.joined(separator: "|") + ")\\b"
    }()

    private static let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    /// Image tokens (`![…](Attachments/…)`) are never read as dates: a
    /// pasted image is named with its timestamp, and "2026-09-27" inside
    /// the token became a due date and was cut out of it (2026-09-27). The
    /// title is parsed with each token as one placeholder, then mapped back.
    static func parse(_ title: String, now: Date = Date()) -> NLDateMatch? {
        let ns = title as NSString
        let tokens = AttachmentStore.tokenPattern.matches(in: title, range: NSRange(location: 0, length: ns.length))
        guard !tokens.isEmpty else { return parseUnmasked(title, now: now) }
        let placeholder = "\u{FFFC}"
        var masked = title as NSString
        for token in tokens.reversed() { masked = masked.replacingCharacters(in: token.range, with: placeholder) as NSString }
        guard let match = parseUnmasked(masked as String, now: now) else { return nil }
        // Back to the title's coordinates: each earlier token is longer than
        // its placeholder by (length − 1).
        let shift = tokens.filter { $0.range.location < match.nsRange.location }.reduce(0) { $0 + $1.range.length - 1 }
        var cleaned = match.cleanedTitle
        for token in tokens {
            if let slot = cleaned.range(of: placeholder) {
                cleaned.replaceSubrange(slot, with: ns.substring(with: token.range))
            }
        }
        return NLDateMatch(nsRange: NSRange(location: match.nsRange.location + shift, length: match.nsRange.length),
                           date: match.date, display: match.display, cleanedTitle: cleaned)
    }

    private static func parseUnmasked(_ title: String, now: Date = Date()) -> NLDateMatch? {
        guard let regex else { return nil }
        let full = NSRange(title.startIndex..., in: title)
        // NL: the LAST phrase wins.
        guard let match = regex.matches(in: title, options: [], range: full).last,
              let range = Range(match.range, in: title) else { return nil }

        let phrase = title[range].lowercased()
        guard let date = resolve(phrase: phrase, now: now) else { return nil }

        var cleaned = title
        cleaned.removeSubrange(range)
        cleaned = cleaned
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return NLDateMatch(nsRange: match.range, date: date,
                           display: display(for: date, now: now), cleanedTitle: cleaned)
    }

    // MARK: - Resolution

    private static func resolve(phrase: String, now: Date) -> Date? {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)

        switch phrase {
        case "today", "tod":
            return todayStart
        case "tomorrow", "tom":
            return cal.date(byAdding: .day, value: 1, to: todayStart)
        case "next week":
            return cal.date(byAdding: .day, value: 7, to: todayStart)
        default:
            break
        }

        let isNext = phrase.hasPrefix("next ")
        let word = isNext ? String(phrase.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                          : phrase

        if let weekday = weekdays[word] {
            // Next occurrence strictly after today; "next X" pushes one week out.
            let current = cal.component(.weekday, from: todayStart)
            var ahead = (weekday - current + 7) % 7
            if ahead == 0 { ahead = 7 }
            if isNext { ahead += 7 }
            return cal.date(byAdding: .day, value: ahead, to: todayStart)
        }

        // "jul 14" / "14 jul" — this year, or next if already past.
        let parts = phrase.split(separator: " ").map(String.init)
        if parts.count == 2 {
            let month = months[parts[0]] ?? months[parts[1]]
            let day = Int(parts[0]) ?? Int(parts[1])
            if let month, let day, (1...31).contains(day) {
                var comps = cal.dateComponents([.year], from: todayStart)
                comps.month = month
                comps.day = day
                guard let candidate = cal.date(from: comps) else { return nil }
                if candidate < todayStart {
                    return cal.date(byAdding: .year, value: 1, to: candidate)
                }
                return candidate
            }
        }
        return nil
    }

    // MARK: - Display ("→ Tomorrow, Jul 14")

    private static func display(for date: Date, now: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = "MMM d"
        let monthDay = formatter.string(from: date)

        if cal.isDate(date, inSameDayAs: now) {
            return "\(L10n.t("date.today")), \(monthDay)"
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
           cal.isDate(date, inSameDayAs: tomorrow) {
            return "\(L10n.t("date.tomorrow")), \(monthDay)"
        }
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
