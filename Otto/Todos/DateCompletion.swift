import AppKit

// MARK: - Completing a date as you type it (Marcello, 2026-10-19)
//
// Typing "do this on fri" used to show the date it understood on a line BELOW
// the field ("→ Fri, Oct 23"), and ⇥ — the key that feels like "finish this
// word" — switched space instead. Now the rest of the word appears AFTER the
// caret, in the placeholder grey, the way the notes editor completes words
// (macOS inline prediction): "fri" + "day", and ⇥ writes it. Once the date is
// whole, the day it means follows it in the same grey — "friday  Oct 23" — so
// the line below is gone and nothing moves.
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

    /// What follows the caret in grey: the rest of the word, then the day it
    /// means. Nil when there is nothing to offer.
    static func ghost(in text: String, caret: Int) -> String? {
        guard caret == (text as NSString).length, !text.isEmpty else { return nil }
        let rest = remainder(in: text, caret: caret) ?? ""
        // The date only when the date phrase is what was just typed — at
        // the end — not for one earlier in the title.
        guard let match = NLDateParser.parse(text + rest),
              NSMaxRange(match.nsRange) == (text as NSString).length + (rest as NSString).length
        else { return rest.isEmpty ? nil : rest }
        return rest + "  " + match.display
    }
}
