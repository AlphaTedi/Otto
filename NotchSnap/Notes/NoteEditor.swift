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
    /// Inline code at the caret / selection.
    @Published private(set) var code = false
    @Published var bodyFocused = false
    /// How many phrases the current note has underlined — the header's
    /// "3 impegni trovati". Zero means the header shows only the date, never
    /// "0 impegni trovati", which would advertise a failure nobody asked about.
    @Published var contentHeight: CGFloat = 160
    @Published var detectedCount = 0
    /// The span whose picker is open, if one is.
    @Published var pickerExpanded = false
    @Published var pickerIndex = 0
    @Published var pickerTarget: (range: NSRange, phrase: String)? {
        didSet { pickerExpanded = false; pickerIndex = 0 }
    }

    // MARK: Reading the caret

    func refreshState() {
        guard let view = textView else { return }
        let selection = view.selectedRange()
        let storage = view.textStorage
        guard let storage, storage.length > 0 else {
            activeBlock = .body; bold = false; italic = false; underline = false; code = false
            return
        }
        // One before the caret when it sits at the very end of a run, so the
        // lit state answers for the text you are about to extend rather than
        // for nothing.
        let probe = min(max(selection.location, 0), storage.length - 1)
        let attributes = selection.length == 0 ? view.typingAttributes : storage.attributes(at: probe, effectiveRange: nil)
        activeBlock = (attributes[.noteBlock] as? String).flatMap(NoteBlock.init(rawValue:)) ?? .body
        let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
        bold = traits.contains(.boldFontMask)
        italic = traits.contains(.italicFontMask)
        underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
        code = attributes[.noteCode] != nil
    }

    // MARK: Code

    /// Inline code on the selection — monospace, a faint ground, and nothing
    /// else: bold, italic and underline come off, because code does not
    /// carry them. With no selection it applies to what is typed next.
    func toggleInlineCode() {
        guard let view = textView, let storage = view.textStorage else { return }
        guard activeBlock != .code else { return }
        let range = view.selectedRange()
        let turningOn = !code
        let plain = NoteType.font(for: activeBlock)
        guard range.length > 0 else {
            if turningOn {
                view.typingAttributes[.font] = NoteType.codeFont
                view.typingAttributes[.noteCode] = true
                view.typingAttributes[.backgroundColor] = NoteType.codeBackground
                view.typingAttributes[.underlineStyle] = 0
            } else {
                view.typingAttributes[.font] = plain
                view.typingAttributes.removeValue(forKey: .noteCode)
                view.typingAttributes.removeValue(forKey: .backgroundColor)
            }
            code = turningOn
            return
        }
        edit(view) {
            if turningOn {
                storage.addAttributes([.font: NoteType.codeFont, .noteCode: true,
                                       .backgroundColor: NoteType.codeBackground,
                                       .underlineStyle: 0], range: range)
            } else {
                storage.removeAttribute(.noteCode, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.font, value: plain, range: range)
            }
        }
        refreshState()
    }

    /// The paragraph(s) at the caret become a code block, or stop being one.
    func toggleCodeBlock() {
        guard let view = textView, let storage = view.textStorage else { return }
        let leaving = activeBlock == .code
        setBlock(leaving ? .body : .code)
        // A block is code through and through: inline code, bold and italic
        // inside it are dropped (their font is already the block's).
        for range in paragraphRanges(in: storage, covering: view.selectedRange()) {
            storage.removeAttribute(.noteCode, range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            if !leaving { storage.addAttribute(.underlineStyle, value: 0, range: range) }
        }
        view.needsDisplay = true
        refreshState()
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
        // Underlining a selected phrase is also an explicit request to turn
        // that phrase into an action. Keep the user's underline as formatting,
        // then reveal the same section picker used by detected commitments.
        if turningOn, (view as? ActionTextView)?.noteID != nil {
            let raw = (storage.string as NSString).substring(with: range)
            let phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { return }
            let leading = (raw as NSString).rangeOfCharacter(from: .whitespacesAndNewlines.inverted).location
            let trailing = (raw as NSString).rangeOfCharacter(from: .whitespacesAndNewlines.inverted,
                                                               options: .backwards).location
            guard leading != NSNotFound, trailing != NSNotFound else { return }
            let actionRange = NSRange(location: range.location + leading,
                                      length: trailing - leading + 1)
            storage.addAttribute(.noteAction, value: phrase, range: actionRange)
            view.layoutManager?.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor(LabMetrics.accent).withAlphaComponent(0.85)
            ], forCharacterRange: actionRange)
            if actionRange.length > 0 {
                view.layoutManager?.addTemporaryAttribute(.kern, value: 27,
                    forCharacterRange: NSRange(location: NSMaxRange(actionRange) - 1, length: 1))
            }
            pickerTarget = (actionRange, phrase)
            detectedCount = max(1, detectedCount)
            (view as? ActionTextView)?.showSelectionControl()
        } else if !turningOn {
            pickerTarget = nil
        }
    }

    private func toggleTrait(_ trait: NSFontTraitMask, isOn: Bool) {
        guard let view = textView, let storage = view.textStorage else { return }
        // Code never takes bold or italic (spec: no unintended inheritance).
        guard activeBlock != .code, !code else { return }
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

        var adjusted = selection
        edit(view) {
            // Back to front: retyping a marker changes the length of every
            // paragraph after it.
            for range in paragraphs.reversed() {
                let before = storage.length
                retype(storage, paragraph: range, to: block)
                let delta = storage.length - before
                if range.location <= adjusted.location { adjusted.location = max(range.location, adjusted.location + delta) }
                else { adjusted.length = max(0, adjusted.length + delta) }
            }
            renumber(storage)
        }
        // The caret does not move. Applying a format must never take focus or
        // the selection away from where the user left it.
        view.setSelectedRange(NSRange(location: min(adjusted.location, storage.length), length: min(adjusted.length, storage.length - min(adjusted.location, storage.length))))
        // What is typed NEXT belongs to the paragraph, never to the marker.
        //
        // The caret ends up immediately after a drawn marker, and an NSTextView
        // inherits its typing attributes from the character behind it — so
        // everything written after "- " came out wearing the marker's own
        // colour. Setting them explicitly is what makes the marker punctuation
        // rather than a mode you have entered.
        resetTypingAttributes(view, to: block)
        refreshState()
    }

    /// The attributes a freshly typed character should have in this block.
    private func resetTypingAttributes(_ view: NSTextView, to block: NoteBlock, indent: Int = 0) {
        view.typingAttributes = [
            .font: NoteType.font(for: block),
            .foregroundColor: block == .checklistDone ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            .paragraphStyle: NoteType.paragraphStyle(for: block, indent: indent),
            .noteBlock: block.rawValue,
            .noteIndent: indent,
        ]
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
        guard view.selectedRange().length == 0, !view.hasMarkedText() else { return false }
        let string = storage.string as NSString
        let line = string.paragraphRange(for: NSRange(location: min(caret, string.length), length: 0))
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
            storage.deleteCharacters(in: NSRange(location: line.location, length: (typed as NSString).length))
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
        guard let view = textView, let storage = view.textStorage else { return false }
        if activeBlock == .h1 || activeBlock == .h2 {
            let selection = view.selectedRange()
            edit(view) {
                storage.replaceCharacters(in: selection, with: NSAttributedString(string: "\n", attributes: view.typingAttributes))
            }
            view.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            setBlock(.body)
            return true
        }
        guard activeBlock.isList else { return false }
        let selection = view.selectedRange()
        let string = storage.string as NSString
        let line = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0))
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

        var caret = selection.location + insertion.length
        edit(view) {
            storage.replaceCharacters(in: selection, with: insertion)
            caret = renumber(storage, caret: caret) ?? caret
        }
        caret = min(caret, storage.length)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        // What is typed NEXT belongs to the new row, not to the marker.
        resetTypingAttributes(view, to: continuing, indent: level)
        refreshState()
        return true
    }

    func handleBackspace() -> Bool {
        guard let view = textView, let storage = view.textStorage, activeBlock.isList,
              view.selectedRange().length == 0 else { return false }
        let caret = view.selectedRange().location
        let text = storage.string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: caret, length: 0))
        let prefix = text.substring(with: NSRange(location: paragraph.location, length: caret - paragraph.location))
        guard prefix.range(of: "^(\\d+\\.|•|☐|☑)\\s+$", options: .regularExpression) != nil else { return false }
        setBlock(.body)
        return true
    }

    // MARK: Internals

    private func paragraphRanges(in storage: NSTextStorage, covering selection: NSRange) -> [NSRange] {
        let string = storage.string as NSString
        guard string.length > 0 else { return [NSRange(location: 0, length: 0)] }
        var ranges: [NSRange] = []
        var location = min(selection.location, string.length)
        let end = min(NSMaxRange(selection), string.length)
        repeat {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
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
            var traits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            if old == .h1 || old == .h2 { traits.remove(.boldFontMask) }
            // Leaving code: the monospace face's own traits must not follow.
            if old == .code { traits = [] }
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
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NoteType.paragraphStyle(for: block, indent: indent),
            .noteBlock: block.rawValue,
            .noteIndent: indent,
        ])
    }

    /// Numbered lists count from the top of their own run AND their own level,
    /// so deleting a row does not leave 1, 2, 4 — and a sub-list starts at 1
    /// rather than carrying on from its parent.
    @discardableResult
    private func renumber(_ storage: NSTextStorage, caret: Int? = nil) -> Int? {
        let string = storage.string as NSString
        var counters = NoteMarkdown.NumberCounters()
        var location = 0
        while location < string.length {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
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
                        let adjusted = caret.map { value in
                            content.location < value ? max(content.location, value + (wanted as NSString).length - drawn) : value
                        }
                        return renumber(storage, caret: adjusted)
                    }
                }
            }
            location = NSMaxRange(line)
        }
        return caret
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
        let previous = NSAttributedString(attributedString: storage)
        let selection = view.selectedRange()
        let typing = view.typingAttributes
        view.undoManager?.registerUndo(withTarget: self) { controller in
            controller.restore(previous, selection: selection, typing: typing, in: view)
        }
        storage.beginEditing()
        work()
        storage.endEditing()
        view.didChangeText()
    }

    private func restore(_ text: NSAttributedString, selection: NSRange,
                         typing: [NSAttributedString.Key: Any], in view: NSTextView) {
        edit(view) { view.textStorage?.setAttributedString(text) }
        view.setSelectedRange(selection)
        view.typingAttributes = typing
        refreshState()
    }
}

// MARK: - Detected action items
//
// The underlines, and everything that acts on them. It lives on the controller
// because the text view, the key router and the picker all need to ask the same
// questions of the same selection — a second copy of "which span is the caret
// in" is a second answer waiting to disagree.

extension NoteEditorController {

    /// Re-run detection over the note and mark what it finds.
    ///
    /// NEVER WHILE THE CARET IS INSIDE THE SPAN BEING EVALUATED. An underline
    /// appearing under the words you are still typing is the single most
    /// disruptive thing this feature could do, so a candidate containing the
    /// insertion point is skipped this pass and picked up on the next one,
    /// after the caret has moved on.
    func refreshDetections(noteID: UUID, excludingCaret: Bool = false) {
        guard let view = textView, let storage = view.textStorage else { return }
        guard !view.hasMarkedText() else { return }

        var found = ActionItemDetector.detect(
            in: storage.string,
            ignoring: NotesStore.shared.dismissed(in: noteID))
        // A user-applied underline is an explicit action cue. Reconstruct it
        // on every open/refresh so its + action does not disappear after the
        // first debounce or after reopening the note.
        storage.enumerateAttribute(.underlineStyle,
            in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard (value as? Int ?? 0) != 0 else { return }
            let phrase = (storage.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty,
                  !found.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return }
            found.append(DetectedAction(range: range, phrase: phrase,
                                        dueDate: ActionItemDetector.dueDate(in: phrase)))
        }
        for item in TodoStore.shared.items where item.sourceNoteID == noteID {
            guard let stored = item.sourcePhrase,
                  let match = NoteRepair.phraseRange(of: stored, in: storage.string as NSString) else { continue }
            // WHOLE WORDS only. A plain substring search found "co: chiamare…"
            // inside "trasloco: chiamare…" and drew the link mid-word. A link
            // that can only be found inside a word is widened to that word and
            // stored that way — old notes heal the first time they are opened.
            var phrase = stored
            if match.snapped {
                phrase = (storage.string as NSString).substring(with: match.range)
                TodoStore.shared.relinkNotePhrase(itemID: item.id, to: phrase)
            }
            let range = match.range
            guard !found.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { continue }
            found.append(DetectedAction(range: range, phrase: phrase, dueDate: item.dueDate))
        }

        let typing = view.typingAttributes
        clearDetections()
        var count = 0
        for action in found {
            if excludingCaret, view.selectedRange().location >= action.range.location,
               view.selectedRange().location <= NSMaxRange(action.range) { continue }
            let linked = TodoStore.shared.todo(forNote: noteID, phrase: action.phrase)
            storage.addAttribute(.noteAction, value: action.phrase, range: action.range)
            view.layoutManager?.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor(LabMetrics.accent).withAlphaComponent(0.55)
            ], forCharacterRange: action.range)
            // Reserve the inline chip's width even before hover. Temporary
            // kerning changes layout only; it never reaches Markdown.
            if action.range.length > 0 {
                view.layoutManager?.addTemporaryAttribute(.kern, value: 27,
                    forCharacterRange: NSRange(location: NSMaxRange(action.range) - 1, length: 1))
            }
            if let linked {
                storage.addAttribute(.noteActionDone, value: linked.isCompleted, range: action.range)
                // The linked checkbox is drawn just BEFORE the phrase. At the
                // start of a line the container's inset holds it; mid-line it
                // landed on the letters in front (the audit's "checkbox over
                // the text"). Make the room with layout-only kerning on the
                // preceding character — it never reaches the Markdown.
                let text = storage.string as NSString
                if action.range.location > 0,
                   text.character(at: action.range.location - 1) != 0x0A {
                    view.layoutManager?.addTemporaryAttribute(.kern, value: 24,
                        forCharacterRange: NSRange(location: action.range.location - 1, length: 1))
                }
                if linked.isCompleted {
                    view.layoutManager?.addTemporaryAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ], forCharacterRange: action.range)
                }
            }
            count += 1
        }
        view.typingAttributes = typing.filter { $0.key != .noteAction && $0.key != .noteActionDone }
        detectedCount = count
        (view as? ActionTextView)?.needsDisplay = true
        (view as? ActionTextView)?.showSelectionControl()
    }

    func clearDetections() {
        guard let view = textView, let storage = view.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        for key: NSAttributedString.Key in [.underlineStyle, .underlineColor, .strikethroughStyle,
                                            .foregroundColor, .backgroundColor, .kern] {
            view.layoutManager?.removeTemporaryAttribute(key, forCharacterRange: full)
        }
        storage.removeAttribute(.noteAction, range: full)
        storage.removeAttribute(.noteActionDone, range: full)
        view.typingAttributes.removeValue(forKey: .noteAction)
        view.typingAttributes.removeValue(forKey: .noteActionDone)
        (view as? ActionTextView)?.clearActionControl()
    }

    /// The detected span the caret is in, if any — what ⌥↩ acts on.
    func actionAtCaret() -> (range: NSRange, phrase: String)? {
        guard let view = textView, let storage = view.textStorage, storage.length > 0 else {
            return nil
        }
        let selection = view.selectedRange()
        if selection.length > 0 {
            // Whole words: a selection dragged from mid-word made a to-do
            // titled "Co: chiamare…" out of "trasloco: chiamare…".
            let snapped = NoteRepair.snapToWords(selection, in: storage.string as NSString)
            let phrase = (storage.string as NSString).substring(with: snapped).trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty { return (snapped, phrase) }
        }
        let caret = min(selection.location, storage.length - 1)
        var range = NSRange(location: 0, length: 0)
        guard let phrase = storage.attribute(.noteAction, at: caret,
                                             effectiveRange: &range) as? String else {
            return nil
        }
        return (range, phrase)
    }

    /// The detected span at a point in the view — what a click acts on.
    func action(at point: NSPoint) -> (range: NSRange, phrase: String)? {
        guard let view = textView, let storage = view.textStorage, storage.length > 0,
              let container = view.textContainer, let layout = view.layoutManager else {
            return nil
        }
        let inset = NSPoint(x: point.x - view.textContainerOrigin.x,
                            y: point.y - view.textContainerOrigin.y)
        let index = layout.characterIndex(for: inset, in: container,
                                          fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length else { return nil }
        var range = NSRange(location: 0, length: 0)
        guard let phrase = storage.attribute(.noteAction, at: index,
                                             effectiveRange: &range) as? String else {
            return nil
        }
        return (range, phrase)
    }
}

extension NSAttributedString.Key {
    /// Marks an underline as OTTO'S, so clearing detections cannot take the
    /// user's own ⌘U underlines with it.
    static let ottoUnderlineMark = NSAttributedString.Key("ottoUnderlineMark")
}
