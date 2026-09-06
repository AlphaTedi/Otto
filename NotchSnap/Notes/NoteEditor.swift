import AppKit
import SwiftUI

// MARK: - NoteEditorController — the note body, and the commands that act on it
//
// An NSTextView rather than a SwiftUI TextField, because rich text needs
// attributed storage and a selection the app can ask questions of. The text is
// still markdown on disk: the view holds the attributed rendering, and every
// edit serializes straight back through NoteMarkdown (see that file for why
// the format set is closed).
//
// Commands live HERE and not in the view, so the formatting bar, the key
// router and markdown-as-you-type all reach the same implementation. A second
// path for the same verb is how two of them end up disagreeing.

@MainActor
final class NoteEditorController: ObservableObject {
    static let shared = NoteEditorController()

    weak var textView: NSTextView?

    /// Derived from the caret on every selection change; drives the lit
    /// controls. Not persisted.
    @Published private(set) var activeBlock: NoteBlock = .body
    @Published private(set) var bold = false
    @Published private(set) var italic = false
    @Published private(set) var underline = false
    @Published var bodyFocused = false

    // MARK: Reading the caret

    func refreshState() {
        guard let view = textView else { return }
        let selection = view.selectedRange()
        let storage = view.textStorage
        guard let storage, storage.length > 0 else {
            activeBlock = .body; bold = false; italic = false; underline = false
            return
        }
        // One before the caret when it sits at the very end of a run, so the
        // lit state answers for the text you are about to extend rather than
        // for nothing.
        let probe = min(max(selection.location, 0), storage.length - 1)
        let attributes = storage.attributes(at: probe, effectiveRange: nil)
        activeBlock = (attributes[.noteBlock] as? String).flatMap(NoteBlock.init(rawValue:)) ?? .body
        let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
        bold = traits.contains(.boldFontMask)
        italic = traits.contains(.italicFontMask)
        underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
    }

    // MARK: Inline style

    func toggleBold()      { toggleTrait(.boldFontMask, isOn: bold) }
    func toggleItalic()    { toggleTrait(.italicFontMask, isOn: italic) }

    func toggleUnderline() {
        guard let view = textView, let storage = view.textStorage else { return }
        let range = view.selectedRange()
        guard range.length > 0 else {
            // No selection: remember it for what is typed next, the way every
            // Mac editor does.
            underline.toggle()
            view.typingAttributes[.underlineStyle] = underline ? NSUnderlineStyle.single.rawValue : 0
            return
        }
        let turningOn = !underline
        edit(view) {
            storage.addAttribute(.underlineStyle,
                                 value: turningOn ? NSUnderlineStyle.single.rawValue : 0,
                                 range: range)
        }
    }

    private func toggleTrait(_ trait: NSFontTraitMask, isOn: Bool) {
        guard let view = textView, let storage = view.textStorage else { return }
        let range = view.selectedRange()
        let manager = NSFontManager.shared
        guard range.length > 0 else {
            let current = (view.typingAttributes[.font] as? NSFont) ?? NoteType.font(for: activeBlock)
            view.typingAttributes[.font] = isOn
                ? manager.convert(current, toNotHaveTrait: trait)
                : manager.convert(current, toHaveTrait: trait)
            if trait == .boldFontMask { bold.toggle() } else { italic.toggle() }
            return
        }
        edit(view) {
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? NoteType.font(for: activeBlock)
                storage.addAttribute(.font,
                                     value: isOn ? manager.convert(font, toNotHaveTrait: trait)
                                                 : manager.convert(font, toHaveTrait: trait),
                                     range: subrange)
            }
        }
    }

    // MARK: Block type

    func setBlock(_ block: NoteBlock) {
        guard let view = textView, let storage = view.textStorage else { return }
        let paragraphs = paragraphRanges(in: storage, covering: view.selectedRange())
        guard !paragraphs.isEmpty else { return }
        let selection = view.selectedRange()

        edit(view) {
            // Back to front: retyping a marker changes the length of every
            // paragraph after it.
            for range in paragraphs.reversed() {
                retype(storage, paragraph: range, to: block)
            }
        }
        renumber(storage)
        // The caret does not move. Applying a format must never take focus or
        // the selection away from where the user left it.
        view.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        refreshState()
    }

    /// Toggle: pressing the list you are already in returns to body.
    func toggleBlock(_ block: NoteBlock) {
        setBlock(activeBlock == block ? .body : block)
    }

    /// Tick the checklist row the caret is on.
    func toggleCheck() {
        guard activeBlock.isChecklist else { return }
        setBlock(activeBlock == .checklistDone ? .checklistOpen : .checklistDone)
    }

    // MARK: Markdown as you type
    //
    // `# `, `## `, `- `, `1. `, `[] ` at the head of a line become the block
    // the moment the space lands. Free once the formats map to markdown, and
    // it is how anyone who types fast will actually use this — the bar is for
    // everyone else.
    //
    // Returns true when it consumed the space.
    func handleSpaceForMarkdown() -> Bool {
        guard let view = textView, let storage = view.textStorage else { return false }
        let caret = view.selectedRange().location
        let string = storage.string as NSString
        let line = string.lineRange(for: NSRange(location: min(caret, string.length), length: 0))
        let typed = string.substring(with: NSRange(location: line.location,
                                                   length: max(0, caret - line.location)))
        let block: NoteBlock?
        switch typed {
        case "#":    block = .h1
        case "##":   block = .h2
        case "-", "*": block = .bullet
        case "[]", "[ ]": block = .checklistOpen
        default:
            block = typed.range(of: "^\\d+\\.$", options: .regularExpression) != nil ? .numbered : nil
        }
        guard let block else { return false }
        edit(view) {
            storage.deleteCharacters(in: NSRange(location: line.location, length: typed.count))
        }
        setBlock(block)
        return true
    }

    /// Return inside a list. Returns true when it handled the key; false lets
    /// the text system break the line the ordinary way.
    ///
    /// Two behaviours, and they are the two Apple Notes has:
    ///
    ///  - on a row with text, ⏎ CONTINUES the list — a new row at the same
    ///    level, with its marker already drawn. Left to the text system it
    ///    inserted a line that carried the bullet's attributes but no bullet,
    ///    so the list looked as though it had ended and the file said it had
    ///    not.
    ///  - on an EMPTY row it leaves: one level out if the row is nested, and
    ///    out of the list entirely at the margin. That is the only way out
    ///    that does not involve reaching for the mouse.
    func handleReturn() -> Bool {
        guard let view = textView, let storage = view.textStorage, activeBlock.isList else { return false }
        let selection = view.selectedRange()
        let string = storage.string as NSString
        let line = string.lineRange(for: NSRange(location: min(selection.location, string.length), length: 0))
        var content = line
        if content.length > 0,
           string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
            content.length -= 1
        }
        let level = content.location < storage.length
            ? (storage.attribute(.noteIndent, at: content.location, effectiveRange: nil) as? Int) ?? 0
            : 0

        // Empty means "marker and nothing else".
        let text = string.substring(with: content)
        let stripped = text.replacingOccurrences(of: "^(\\d+\\.|•|☐|☑)\\s+", with: "",
                                                 options: .regularExpression)
        if stripped.trimmingCharacters(in: .whitespaces).isEmpty {
            if level > 0 { return shiftIndent(by: -1) }
            setBlock(.body)
            return true
        }

        // A checked row does not breed more checked rows: the next thing you
        // write is something still to do.
        let continuing: NoteBlock = activeBlock == .checklistDone ? .checklistOpen : activeBlock
        let insertion = NSMutableAttributedString(string: "\n", attributes: [
            .font: NoteType.font(for: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NoteType.paragraphStyle(for: continuing, indent: level),
            .noteBlock: continuing.rawValue,
            .noteIndent: level,
        ])
        // Index 1 is a placeholder — renumber() below settles what the row
        // actually wears, from the same counters the parser uses.
        insertion.append(Self.marker(continuing, index: 1, indent: level))

        edit(view) { storage.replaceCharacters(in: selection, with: insertion) }
        let caret = min(selection.location + insertion.length, storage.length)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        renumber(storage)
        // What is typed NEXT belongs to the new row, not to the marker's own
        // accent colour.
        view.typingAttributes = [
            .font: NoteType.font(for: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NoteType.paragraphStyle(for: continuing, indent: level),
            .noteBlock: continuing.rawValue,
            .noteIndent: level,
        ]
        refreshState()
        return true
    }

    // MARK: Internals

    private func paragraphRanges(in storage: NSTextStorage, covering selection: NSRange) -> [NSRange] {
        let string = storage.string as NSString
        guard string.length > 0 else { return [NSRange(location: 0, length: 0)] }
        var ranges: [NSRange] = []
        var location = min(selection.location, string.length - 1)
        let end = min(NSMaxRange(selection), string.length)
        repeat {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(line)
            location = NSMaxRange(line)
        } while location < end
        return ranges
    }

    /// Swap one paragraph's block type: retype its attributes and redraw its
    /// marker. `indent` nil means "keep whatever level the row already had".
    private func retype(_ storage: NSTextStorage, paragraph: NSRange,
                        to block: NoteBlock, indent: Int? = nil) {
        let string = storage.string as NSString
        var content = paragraph
        if content.length > 0,
           string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
            content.length -= 1
        }
        // An EMPTY document is a real state — ⌘⇧8 on a note you have not
        // typed into yet — and `attribute(at:)` on it is out of bounds, not
        // nil. Reading only when there is a character to read is what keeps
        // "make this a bullet" from being a crash on the first keystroke.
        let hasText = content.location < storage.length
        let old = hasText
            ? (storage.attribute(.noteBlock, at: content.location, effectiveRange: nil) as? String)
                .flatMap(NoteBlock.init(rawValue:)) ?? .body
            : .body
        let existingIndent = hasText
            ? (storage.attribute(.noteIndent, at: content.location, effectiveRange: nil) as? Int) ?? 0
            : 0
        // Only a list is nested. Turning a sub-bullet into a paragraph brings
        // it back to the margin rather than leaving a body line hanging at
        // level two with no marker to explain why.
        let level = block.isList ? min(max(indent ?? existingIndent, 0), NoteIndent.max) : 0

        // Take the old marker off first, so markers cannot stack.
        var textRange = content
        if old.isList {
            let text = string.substring(with: content)
            if let match = text.range(of: "^(\\d+\\.|•|☐|☑)\\s+", options: .regularExpression) {
                let drawn = text.distance(from: text.startIndex, to: match.upperBound)
                storage.deleteCharacters(in: NSRange(location: content.location, length: drawn))
                textRange.length -= drawn
            }
        }

        let full = NSRange(location: textRange.location, length: max(textRange.length, 0))
        storage.addAttributes([
            .noteBlock: block.rawValue,
            .noteIndent: level,
            .paragraphStyle: NoteType.paragraphStyle(for: block, indent: level),
        ], range: NSRange(location: full.location, length: min(full.length + 1, storage.length - full.location)))
        // Keep whatever inline traits the run already had; only the base size
        // and weight follow the block.
        storage.enumerateAttribute(.font, in: full, options: []) { value, subrange, _ in
            let traits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            storage.addAttribute(.font, value: NoteType.font(for: block, traits: traits), range: subrange)
        }
        storage.addAttribute(.foregroundColor,
                             value: block == .checklistDone ? NSColor.tertiaryLabelColor
                                                            : NSColor.labelColor,
                             range: full)
        if block == .checklistDone {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: full)
        }

        if block.isList {
            storage.insert(Self.marker(block, index: 1, indent: level), at: full.location)
        }
    }

    /// The drawn marker for a list row. One place, because it is inserted from
    /// three — retyping a block, renumbering, and continuing a list on ⏎.
    private static func marker(_ block: NoteBlock, index: Int, indent: Int) -> NSAttributedString {
        NSAttributedString(string: NoteMarkdown.listGlyph(block, index: index), attributes: [
            .font: NoteType.font(for: .body),
            .foregroundColor: NSColor.controlAccentColor,
            .paragraphStyle: NoteType.paragraphStyle(for: block, indent: indent),
            .noteBlock: block.rawValue,
            .noteIndent: indent,
        ])
    }

    /// Numbered lists count from the top of their own run AND their own level,
    /// so deleting a row does not leave 1, 2, 4 — and a sub-list starts at 1
    /// rather than carrying on from its parent.
    private func renumber(_ storage: NSTextStorage) {
        let string = storage.string as NSString
        var counters = NoteMarkdown.NumberCounters()
        var location = 0
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            var content = line
            if content.length > 0,
               string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
                content.length -= 1
            }
            let block = content.length > 0
                ? (storage.attribute(.noteBlock, at: content.location, effectiveRange: nil) as? String)
                    .flatMap(NoteBlock.init(rawValue:)) ?? .body
                : .body
            let indent = content.length > 0
                ? (storage.attribute(.noteIndent, at: content.location, effectiveRange: nil) as? Int) ?? 0
                : 0
            let index = counters.advance(block: block, indent: indent)
            if block == .numbered {
                let text = string.substring(with: content)
                if let match = text.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                    let drawn = text.distance(from: text.startIndex, to: match.upperBound)
                    let wanted = NoteMarkdown.listGlyph(.numbered, index: index)
                    if String(text[text.startIndex..<match.upperBound]) != wanted {
                        storage.replaceCharacters(
                            in: NSRange(location: content.location, length: drawn),
                            with: Self.marker(.numbered, index: index, indent: indent))
                        return renumber(storage)   // lengths moved; start again
                    }
                }
            }
            location = NSMaxRange(line)
        }
    }

    // MARK: Nesting

    /// ⇥ / ⇧⇥ on a list row. Returns true when it moved something.
    ///
    /// Only lists nest. On a paragraph or a heading this answers false and the
    /// key goes back to the text view, which is the honest outcome: this
    /// format has no sub-heading to promote anything into.
    func shiftIndent(by delta: Int) -> Bool {
        guard let view = textView, let storage = view.textStorage, storage.length > 0 else { return false }
        // The BODY has to be the thing holding the keyboard. A note's title is
        // an NSTextField above the same text view, and without this ⇥ pressed
        // while renaming would have quietly re-indented a list row somewhere
        // below, out of sight of the caret that asked for it.
        guard view.window?.firstResponder === view else { return false }
        let selection = view.selectedRange()
        let paragraphs = paragraphRanges(in: storage, covering: selection)
        guard !paragraphs.isEmpty else { return false }

        // Every selected row has to be a list row, and the whole run has to be
        // able to move. Nothing partial: a ⇥ that indented three rows out of
        // four would be a worse answer than a ⇥ that did nothing.
        var moves: [(NSRange, NoteBlock, Int)] = []
        for range in paragraphs {
            var content = range
            let string = storage.string as NSString
            if content.length > 0,
               string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
                content.length -= 1
            }
            guard content.location < storage.length else { return false }
            let block = (storage.attribute(.noteBlock, at: content.location, effectiveRange: nil) as? String)
                .flatMap(NoteBlock.init(rawValue:)) ?? .body
            guard block.isList else { return false }
            let current = (storage.attribute(.noteIndent, at: content.location, effectiveRange: nil) as? Int) ?? 0
            let wanted = current + delta
            guard wanted >= 0, wanted <= NoteIndent.max else { return false }
            moves.append((range, block, wanted))
        }

        edit(view) {
            // Back to front, like setBlock: a redrawn marker changes the
            // length of every paragraph after it.
            for (range, block, level) in moves.reversed() {
                retype(storage, paragraph: range, to: block, indent: level)
            }
        }
        renumber(storage)
        view.setSelectedRange(NSRange(location: min(selection.location, storage.length),
                                      length: min(selection.length, storage.length - min(selection.location, storage.length))))
        refreshState()
        return true
    }

    /// One undo group, one change notification. Without the begin/end pair a
    /// block change lands as a dozen separate edits and ⌘Z unpicks it one
    /// attribute at a time.
    private func edit(_ view: NSTextView, _ work: () -> Void) {
        guard let storage = view.textStorage else { return }
        storage.beginEditing()
        work()
        storage.endEditing()
        view.didChangeText()
    }
}
