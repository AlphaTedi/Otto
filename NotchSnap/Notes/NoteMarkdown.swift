import AppKit
import SwiftUI

// MARK: - Note formatting — nine formats, all of them markdown
//
// The governing rule comes from the handoff and it is the reason this file is
// short: IF IT CANNOT BE WRITTEN INTO Notes.md AS MARKDOWN, IT DOES NOT ENTER
// THE EDITOR. No colour, no highlight, no tables, no code blocks, no quotes,
// no images, no font size. Nine formats, each with an exact markdown
// equivalent, and a closed set is what makes the round-trip safe: a note is
// still a `String` of markdown in notes.json, the mirror still has one writer,
// and nothing about persistence changes.
//
// Underline is the single exception and writes `<u>…</u>`, which markdown
// passes through as HTML. The handoff sanctioned that explicitly and offered
// the alternative of dropping underline instead; it is kept, and it is the one
// thing in the file a strict markdown reader will show as a tag.

/// What a whole paragraph is. One per line, mutually exclusive.
enum NoteBlock: String, Equatable {
    case h1, h2, body, bullet, numbered, checklistOpen, checklistDone

    var isList: Bool {
        switch self {
        case .bullet, .numbered, .checklistOpen, .checklistDone: return true
        default: return false
        }
    }

    var isChecklist: Bool { self == .checklistOpen || self == .checklistDone }

    /// What the line starts with in the file, nesting included.
    func marker(index: Int, indent: Int = 0) -> String {
        String(repeating: NoteIndent.unit, count: isList ? max(indent, 0) : 0) + bareMarker(index: index)
    }

    private func bareMarker(index: Int) -> String {
        switch self {
        case .h1:            return "# "
        case .h2:            return "## "
        case .body:          return ""
        case .bullet:        return "- "
        case .numbered:      return "\(index). "
        case .checklistOpen: return "- [ ] "
        case .checklistDone: return "- [x] "
        }
    }
}

extension NSAttributedString.Key {
    /// The paragraph's block type, carried on its characters so a selection
    /// anywhere in the line can be asked what it is.
    static let noteBlock = NSAttributedString.Key("ottoNoteBlock")
    /// How deeply the paragraph is nested, 0 for the outer level. Carried the
    /// same way and for the same reason as `noteBlock`.
    ///
    /// It is markdown's own nesting and nothing new: two spaces per level in
    /// front of the marker, which is what every reader already understands.
    /// Only LIST rows carry it — a heading has no sub-heading in this format,
    /// and inventing one would be a tenth format with no markdown to write it
    /// into, which is the line this file does not cross.
    static let noteIndent = NSAttributedString.Key("ottoNoteIndent")
}

/// The nesting the editor allows. Four is Apple Notes' own limit and it is
/// well past the point where a note is still a note.
enum NoteIndent {
    static let max = 4
    /// One level in the file. Two spaces, the CommonMark convention for
    /// nesting under a `- ` marker.
    static let unit = "  "
    /// One level on screen.
    static let step: CGFloat = 22
}

// MARK: - Type scale

enum NoteType {
    /// The body matches the to-do list's own title size rather than the
    /// handoff's 15.5.
    ///
    /// Marcello's standing correction: Notes was reading as a separate product
    /// because it was drawn to a scale of its own. The headings keep the
    /// design's PROPORTIONS against it (1.35 and 1.14) rather than its
    /// absolute numbers, so the hierarchy is the one that was designed and the
    /// base is the one the app already uses.
    static let bodySize = DSFont.todoTitleSize          // 14
    static let h1Size: CGFloat = 19
    static let h2Size: CGFloat = 16

    static func font(for block: NoteBlock, traits: NSFontTraitMask = []) -> NSFont {
        let manager = NSFontManager.shared
        let base: NSFont
        switch block {
        case .h1:   base = .systemFont(ofSize: h1Size, weight: .semibold)
        case .h2:   base = .systemFont(ofSize: h2Size, weight: .semibold)
        default:    base = .systemFont(ofSize: bodySize, weight: .regular)
        }
        guard !traits.isEmpty else { return base }
        return manager.convert(base, toHaveTrait: traits)
    }

    static func paragraphStyle(for block: NoteBlock, indent: Int = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch block {
        case .h1:
            style.lineHeightMultiple = 1.15
            style.paragraphSpacingBefore = 16
            style.paragraphSpacing = 4
        case .h2:
            style.lineHeightMultiple = 1.2
            style.paragraphSpacingBefore = 14
            style.paragraphSpacing = 3
        case .body:
            style.lineHeightMultiple = 1.35
            style.paragraphSpacing = 8
        case .bullet, .numbered, .checklistOpen, .checklistDone:
            style.lineHeightMultiple = 1.3
            style.paragraphSpacing = 3
            // The marker is drawn by the text itself, so the wrap has to be
            // indented or a second line starts under the bullet. A nested row
            // moves BOTH edges by the same step, so its marker lines up under
            // the text of its parent — the shape that makes a sub-level read
            // as one.
            let offset = CGFloat(max(indent, 0)) * NoteIndent.step
            style.headIndent = 20 + offset
            style.firstLineHeadIndent = offset
        }
        return style
    }
}

// MARK: - Parse: markdown → attributed

enum NoteMarkdown {

    /// Inline syntax, in the order it must be scanned.
    private static let inlinePatterns: [(NSRegularExpression, NSFontTraitMask, Bool)] = {
        func re(_ p: String) -> NSRegularExpression {
            // Force-try: these are literals, compiled once, and a failure here
            // is a programming error rather than anything a note can cause.
            try! NSRegularExpression(pattern: p, options: [])
        }
        return [
            (re("\\*\\*(.+?)\\*\\*"), .boldFontMask, false),
            (re("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"), .italicFontMask, false),
            (re("<u>(.+?)</u>"), [], true),
        ]
    }()

    static func attributed(from markdown: String, textColor: NSColor,
                           accent: NSColor, mutedColor: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        // `components` and not `enumerateLines`: a trailing newline has to
        // survive, or the caret cannot sit on the empty last line the user
        // just made.
        let lines = markdown.isEmpty ? [""] : markdown.components(separatedBy: "\n")
        var counters = NumberCounters()

        for (i, raw) in lines.enumerated() {
            let (block, indent, content) = split(raw)
            let numberedIndex = counters.advance(block: block, indent: indent)

            let paragraph = NSMutableAttributedString(string: content, attributes: [
                .font: NoteType.font(for: block),
                .foregroundColor: block == .checklistDone ? mutedColor : textColor,
                .paragraphStyle: NoteType.paragraphStyle(for: block, indent: indent),
                .noteBlock: block.rawValue,
                .noteIndent: indent,
            ])
            if block == .checklistDone {
                paragraph.addAttribute(.strikethroughStyle,
                                       value: NSUnderlineStyle.single.rawValue,
                                       range: NSRange(location: 0, length: paragraph.length))
            }
            applyInline(to: paragraph, block: block, textColor: textColor)

            // The marker is drawn, not stored as part of the user's text: it
            // is prepended here and stripped again on the way out, so the
            // words in the file are only ever the words that were typed.
            if block.isList {
                let marker = NSAttributedString(string: listGlyph(block, index: numberedIndex), attributes: [
                    .font: NoteType.font(for: .body),
                    .foregroundColor: accent,
                    .paragraphStyle: NoteType.paragraphStyle(for: block, indent: indent),
                    .noteBlock: block.rawValue,
                    .noteIndent: indent,
                ])
                paragraph.insert(marker, at: 0)
            }

            out.append(paragraph)
            if i < lines.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [
                    .font: NoteType.font(for: block),
                    .paragraphStyle: NoteType.paragraphStyle(for: block, indent: indent),
                    .noteBlock: block.rawValue,
                    .noteIndent: indent,
                ]))
            }
        }
        return out
    }

    /// What the reader sees in front of a list row. Not in the file.
    static func listGlyph(_ block: NoteBlock, index: Int) -> String {
        switch block {
        case .bullet:        return "•  "
        case .numbered:      return "\(max(index, 1)).  "
        case .checklistOpen: return "☐  "
        case .checklistDone: return "☑  "
        default:             return ""
        }
    }

    /// Split a raw markdown line into its block type, its nesting level and
    /// the text after the marker.
    ///
    /// Leading spaces are read as nesting ONLY in front of a list marker. In
    /// front of anything else they are the user's own indentation and are left
    /// in the text, because a paragraph that begins with a space is a
    /// paragraph that begins with a space — reinterpreting it would silently
    /// edit a file the user may also be writing by hand.
    static func split(_ line: String) -> (NoteBlock, Int, String) {
        let spaces = line.prefix { $0 == " " }.count
        let body = String(line.dropFirst(spaces))
        // Two spaces to the level, and an odd space is rounded down rather
        // than rejected: a hand-written file using four is read as two levels,
        // and one using three still lands somewhere sensible.
        let indent = min(spaces / NoteIndent.unit.count, NoteIndent.max)

        if body.hasPrefix("- [x] ")   { return (.checklistDone, indent, String(body.dropFirst(6))) }
        if body.hasPrefix("- [X] ")   { return (.checklistDone, indent, String(body.dropFirst(6))) }
        if body.hasPrefix("- [ ] ")   { return (.checklistOpen, indent, String(body.dropFirst(6))) }
        if body.hasPrefix("- ")       { return (.bullet, indent, String(body.dropFirst(2))) }
        if let match = body.range(of: "^\\d+\\. ", options: .regularExpression) {
            return (.numbered, indent, String(body[match.upperBound...]))
        }
        // Not a list: the spaces were never nesting, so the line is handed
        // back whole.
        if line.hasPrefix("## ")      { return (.h2, 0, String(line.dropFirst(3))) }
        if line.hasPrefix("# ")       { return (.h1, 0, String(line.dropFirst(2))) }
        return (.body, 0, line)
    }

    /// Numbered lists count PER LEVEL, and a level restarts whenever something
    /// else interrupts it.
    ///
    /// Without this a nested list carried on from its parent's count — 1, 2,
    /// then 3 indented under 2 — which is not what any markdown reader will
    /// render it as, so the file and the screen would disagree the moment the
    /// note left the app.
    struct NumberCounters {
        private var counts = [Int](repeating: 0, count: NoteIndent.max + 1)

        /// Advance to the given line and return the number it should wear.
        mutating func advance(block: NoteBlock, indent: Int) -> Int {
            let level = min(max(indent, 0), NoteIndent.max)
            if block == .numbered {
                counts[level] += 1
                // Anything nested UNDER this row starts again from one.
                // Half-open, not `...`: at the deepest level `(max + 1)...max`
                // is not an empty range, it is a crash.
                for deeper in (level + 1)..<counts.count { counts[deeper] = 0 }
                return counts[level]
            }
            for cleared in level...NoteIndent.max { counts[cleared] = 0 }
            return 0
        }
    }

    private static func applyInline(to paragraph: NSMutableAttributedString,
                                    block: NoteBlock, textColor: NSColor) {
        for (regex, traits, isUnderline) in inlinePatterns {
            // Backwards, so replacing one match cannot shift the ranges of the
            // ones not yet handled.
            let matches = regex.matches(in: paragraph.string, options: [],
                                        range: NSRange(location: 0, length: paragraph.length))
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let inner = match.range(at: 1)
                let whole = match.range(at: 0)
                let text = (paragraph.string as NSString).substring(with: inner)
                let replacement = NSMutableAttributedString(
                    attributedString: paragraph.attributedSubstring(from: inner)
                )
                replacement.mutableString.setString(text)
                let existing = paragraph.attributes(at: whole.location, effectiveRange: nil)
                var attributes = existing
                let currentTraits = (existing[.font] as? NSFont).map {
                    NSFontManager.shared.traits(of: $0)
                } ?? []
                if !traits.isEmpty {
                    attributes[.font] = NoteType.font(for: block, traits: currentTraits.union(traits))
                }
                if isUnderline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                replacement.setAttributes(attributes,
                                          range: NSRange(location: 0, length: replacement.length))
                paragraph.replaceCharacters(in: whole, with: replacement)
            }
        }
    }

    // MARK: - Serialize: attributed → markdown

    /// Back to the file. Every attribute that survives here is one of the
    /// nine; anything else the text system may have picked up (a pasted
    /// colour, a pasted size) is dropped on purpose rather than invented a
    /// syntax for.
    static func markdown(from attributed: NSAttributedString) -> String {
        let string = attributed.string as NSString
        var lines: [String] = []
        var counters = NumberCounters()
        var start = 0

        while start <= string.length {
            let lineRange = string.lineRange(for: NSRange(location: min(start, string.length), length: 0))
            // The paragraph without its newline.
            var contentRange = lineRange
            if contentRange.length > 0,
               string.substring(with: NSRange(location: NSMaxRange(contentRange) - 1, length: 1)) == "\n" {
                contentRange.length -= 1
            }

            let block: NoteBlock = contentRange.length > 0
                ? (attributed.attribute(.noteBlock, at: contentRange.location, effectiveRange: nil)
                    as? String).flatMap(NoteBlock.init(rawValue:)) ?? .body
                : .body
            let indent: Int = contentRange.length > 0
                ? (attributed.attribute(.noteIndent, at: contentRange.location, effectiveRange: nil)
                    as? Int) ?? 0
                : 0

            // The number this row wears is worked out the SAME way the parser
            // works it out, from the same counters — so what is written into
            // the file is what reading the file back would produce.
            let numberedIndex = counters.advance(block: block, indent: indent)

            // Strip the drawn marker back off.
            var textRange = contentRange
            if block.isList {
                let glyph = listGlyph(block, index: numberedIndex)
                let prefix = string.substring(with: NSRange(
                    location: contentRange.location,
                    length: min(glyph.count, contentRange.length)))
                if prefix == glyph {
                    textRange.location += glyph.count
                    textRange.length -= glyph.count
                } else if let drawn = drawnMarkerLength(in: string, at: contentRange, block: block) {
                    textRange.location += drawn
                    textRange.length -= drawn
                }
            }

            lines.append(block.marker(index: numberedIndex, indent: indent)
                         + inlineMarkdown(attributed, in: textRange, block: block))

            if NSMaxRange(lineRange) >= string.length { break }
            start = NSMaxRange(lineRange)
        }
        // The EMPTY LAST LINE, which the loop above cannot see.
        //
        // `lineRange` hands back the final newline as part of the line before
        // it, so a document ending in "\n" breaks out of the loop having
        // emitted one line fewer than it has. The parser deliberately keeps
        // that line — the caret has to be able to sit on the blank line you
        // just made — so dropping it here meant the two halves disagreed and
        // a note ending in a blank line did not survive its own save. Press ⏎
        // to step out of a list, save, reopen: the line you made was gone.
        if string.length > 0,
           string.substring(with: NSRange(location: string.length - 1, length: 1)) == "\n" {
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// A numbered marker the user has renumbered by editing: match on the
    /// shape rather than the exact string.
    private static func drawnMarkerLength(in string: NSString, at range: NSRange,
                                          block: NoteBlock) -> Int? {
        guard block == .numbered else { return nil }
        let text = string.substring(with: range)
        guard let match = text.range(of: "^\\d+\\.  ", options: .regularExpression) else { return nil }
        return text.distance(from: text.startIndex, to: match.upperBound)
    }

    private static func inlineMarkdown(_ attributed: NSAttributedString, in range: NSRange,
                                       block: NoteBlock) -> String {
        guard range.length > 0 else { return "" }
        var out = ""
        // What the BLOCK is already, so its own weight is not mistaken for
        // emphasis. A heading is drawn semibold, and NSFontManager reports
        // semibold as `.boldFontMask` — so serializing naively turned
        // "# Scadenze" into "# **Scadenze**" on the first save, and every save
        // after that added nothing but noise to the file. Caught by the
        // round-trip test, which is the only place a fault like this shows:
        // on screen the heading looked exactly right.
        let baseTraits = NSFontManager.shared.traits(of: NoteType.font(for: block))
        attributed.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
            let text = (attributed.string as NSString).substring(with: runRange)
            guard !text.isEmpty else { return }
            let raw = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let traits = raw.subtracting(baseTraits)
            let underlined = (attributes[.underlineStyle] as? Int).map { $0 != 0 } ?? false
            var wrapped = text
            // Innermost first, so `**_x_**` nests the way markdown expects.
            if traits.contains(.italicFontMask) { wrapped = "*\(wrapped)*" }
            if traits.contains(.boldFontMask)   { wrapped = "**\(wrapped)**" }
            if underlined                       { wrapped = "<u>\(wrapped)</u>" }
            out += wrapped
        }
        return out
    }

    /// Plain text, for the stream's preview line and the word count — the
    /// markers are not words.
    static func plainText(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").map { split($0).2 }
            .joined(separator: "\n")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
    }
}
