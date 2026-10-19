import AppKit

// MARK: - Completing a date as you type it (Marcello, 2026-10-19)
//
// Typing "do this on fri" used to show the date it understood on a line BELOW
// the field ("→ Fri, Oct 23"), and ⇥ — the key that feels like "finish this
// word" — switched space instead. Now the rest of the word appears AFTER the
// caret, in the placeholder grey, the way the notes editor completes words
// (macOS inline prediction): "fri" + "day  Fri, Oct 23". ⇥ then writes the
// DATE in place of the day word — "nice Oct 23" — which ⏎ files as the to-do's
// due date. The line below is gone and nothing moves.
//
// Only at the END of the text, only for a word of three letters or more that
// begins one of the parser's own day words, and only when the completed text
// really parses as a date. Anything else and ⇥ is what it always was.

enum DateCompletion {
    /// The words NLDateParser resolves on their own, spelled out in full.
    private static let words = ["monday", "tuesday", "wednesday", "thursday", "friday",
                                "saturday", "sunday", "today", "tomorrow"]

    /// The letters still to type, if the word being typed is the start of a
    /// day word ("thu" → "rsday").
    static func remainder(in text: String, caret: Int) -> String? {
        let ns = text as NSString
        guard caret == ns.length else { return nil }
        var start = caret
        while start > 0, let scalar = UnicodeScalar(ns.character(at: start - 1)),
              CharacterSet.letters.contains(scalar) { start -= 1 }
        let typed = ns.substring(with: NSRange(location: start, length: caret - start))
        guard typed.count >= 3 else { return nil }
        let lower = typed.lowercased()
        guard let word = words.first(where: { $0.hasPrefix(lower) && $0 != lower }) else { return nil }
        let rest = String(word.dropFirst(lower.count))
        // The whole thing must then BE a date: "on friday", not a stray "sun".
        guard NLDateParser.parse(text + rest) != nil else { return nil }
        // In the case the word was begun in: "THU" → "RSDAY".
        return typed == typed.uppercased() && typed.count > 1 ? rest.uppercased() : rest
    }

    /// ⇥ fills the DATE, not just the word (Marcello, 2026-10-20): "nice fri"
    /// becomes "nice Oct 23" — the day it means, written as a date the parser
    /// reads back exactly, so ⏎ files the to-do with that due date. The range
    /// to replace in `text`, and what goes there; nil when the phrase at the
    /// end is already a written date or there is none.
    static func fill(in text: String, caret: Int) -> (range: NSRange, replacement: String)? {
        let length = (text as NSString).length
        guard caret == length, !text.isEmpty else { return nil }
        let rest = remainder(in: text, caret: caret) ?? ""
        let full = text + rest
        let fullLength = (full as NSString).length
        guard let match = NLDateParser.parse(full), NSMaxRange(match.nsRange) == fullLength else { return nil }
        let phrase = (full as NSString).substring(with: match.nsRange)
        let replacement = monthDay.string(from: match.date)
        guard phrase.lowercased() != replacement.lowercased() else { return nil }
        let range = NSRange(location: match.nsRange.location,
                            length: match.nsRange.length - (rest as NSString).length)
        return (range, replacement)
    }

    /// "Oct 23" — in English, the only month names NLDateParser knows.
    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// What follows the caret in grey: the rest of the word, then the day it
    /// means — only while ⇥ has something to fill. Once the date is written
    /// out ("Oct 23") it is coloured as a date and needs no echo.
    static func ghost(in text: String, caret: Int) -> String? {
        guard fill(in: text, caret: caret) != nil else { return nil }
        let rest = remainder(in: text, caret: caret) ?? ""
        guard let match = NLDateParser.parse(text + rest) else { return rest.isEmpty ? nil : rest }
        return rest + "  " + match.display
    }
}
