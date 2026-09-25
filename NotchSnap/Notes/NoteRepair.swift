import Foundation

// MARK: - NoteRepair — what old notes need so they read the way they were written
//
// An audit of the notes on Marcello's Mac (2026-09-25) found three kinds of
// damage, all made by the app rather than by him:
//
// 1. ORPHAN EMPHASIS MARKERS. The serializer used to wrap every styled run in
//    its markers, whitespace included — a bold-italic space became
//    "mercoledi.*** ***rimandano". Markdown like that re-parses into markers
//    pairing across words, and after a few edits the file held stray "***"
//    in the middle of words ("du***e settimane"). The serializer no longer
//    does it (NoteMarkdown.inlineMarkdown); `stripOrphanEmphasis` removes the
//    markers old files still carry.
//
// 2. LINKS FOUND INSIDE A WORD. A to-do made from a note remembers its phrase
//    and was found again with a plain substring search — so "co: chiamare…"
//    matched inside "trasloco: chiamare…", the underline started mid-word and
//    the linked checkbox was drawn over the letters before it. `phraseRange`
//    finds whole words only, and snaps a phrase that can only be found
//    mid-word out to the word it is part of, so the link can be repaired.
//
// 3. RUNS OF EMPTY LINES that no one meant, eight or nine at a time. Two
//    newlines is a paragraph break; anything longer collapses to one.
//
// Repairs 1 and 3 run ONCE over every stored note (versioned, backed up
// first); repair 2 runs whenever a note is opened, and rewrites the link.

enum NoteRepair {

    /// Bump when a new one-time repair is added.
    static let version = 1

    static func repairMarkdown(_ markdown: String) -> String {
        collapseBlankRuns(stripOrphanEmphasis(markdown))
    }

    // MARK: 1 · Orphan emphasis

    /// Removes runs of two or more `*` that do not open or close a span on
    /// their line. A run opens when a non-space follows it and closes when a
    /// non-space precedes it; openers pair with the next closer of the same
    /// length. Escaped asterisks (`\*`) are the user's and are never touched.
    static func stripOrphanEmphasis(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").map(stripOrphans(inLine:)).joined(separator: "\n")
    }

    private static func stripOrphans(inLine line: String) -> String {
        let chars = Array(line)
        struct Run { let start: Int; let length: Int; let opens: Bool; let closes: Bool }
        var runs: [Run] = []
        var i = 0
        while i < chars.count {
            guard chars[i] == "*", i == 0 || chars[i - 1] != "\\" else { i += 1; continue }
            var j = i
            while j < chars.count, chars[j] == "*" { j += 1 }
            let length = j - i
            if length >= 2 {
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = j < chars.count ? chars[j] : nil
                runs.append(Run(start: i, length: length,
                                opens: after.map { !$0.isWhitespace } ?? false,
                                closes: before.map { !$0.isWhitespace } ?? false))
            }
            i = j
        }
        guard !runs.isEmpty else { return line }

        var keep = Set<Int>()
        var open: [Int] = []          // indices into `runs`
        for (index, run) in runs.enumerated() {
            if run.closes, let match = open.lastIndex(where: { runs[$0].length == run.length }) {
                keep.insert(open[match]); keep.insert(index)
                open.removeSubrange(match...)
            } else if run.opens {
                open.append(index)
            }
        }
        guard keep.count < runs.count else { return line }

        var out = chars
        for (index, run) in runs.enumerated().reversed() where !keep.contains(index) {
            out.removeSubrange(run.start..<(run.start + run.length))
        }
        return String(out)
    }

    // MARK: 3 · Blank-line runs

    static func collapseBlankRuns(_ markdown: String) -> String {
        var lines: [String] = []
        var blanks = 0
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                if blanks > 1 { continue }
            } else {
                blanks = 0
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 2 · Linked phrases

    /// Where `phrase` stands in `text` as WHOLE words. If it only occurs
    /// inside a word, the range is widened to that word's edges and
    /// `snapped` is true — the caller should store the widened phrase.
    static func phraseRange(of phrase: String, in text: NSString) -> (range: NSRange, snapped: Bool)? {
        guard !phrase.isEmpty else { return nil }
        var search = NSRange(location: 0, length: text.length)
        var firstPartial: NSRange?
        while search.length > 0 {
            let found = text.range(of: phrase, options: [], range: search)
            guard found.location != NSNotFound else { break }
            if startsWord(found, in: text) && endsWord(found, in: text) { return (found, false) }
            if firstPartial == nil { firstPartial = found }
            let next = found.location + 1
            search = NSRange(location: next, length: text.length - next)
        }
        guard let partial = firstPartial else { return nil }
        return (snapToWords(partial, in: text), true)
    }

    /// Widens a range so it neither starts nor ends in the middle of a word.
    static func snapToWords(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start > 0, isWordCharacter(text.character(at: start - 1)),
              isWordCharacter(text.character(at: start)) { start -= 1 }
        while end < text.length, end > 0, isWordCharacter(text.character(at: end - 1)),
              isWordCharacter(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func startsWord(_ range: NSRange, in text: NSString) -> Bool {
        range.location == 0 || !isWordCharacter(text.character(at: range.location - 1))
            || !isWordCharacter(text.character(at: range.location))
    }

    private static func endsWord(_ range: NSRange, in text: NSString) -> Bool {
        let end = NSMaxRange(range)
        return end >= text.length || !isWordCharacter(text.character(at: end))
            || !isWordCharacter(text.character(at: end - 1))
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }
}
