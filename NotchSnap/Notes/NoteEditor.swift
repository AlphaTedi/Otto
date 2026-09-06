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

    /// Return on an EMPTY list row leaves the list rather than making another
    /// one — the only way out that does not involve reaching for the mouse.
    /// Returns true when it handled the key.
    func handleReturn() -> Bool {
        guard let view = textView, let storage = view.textStorage, activeBlock.isList else { return false }
        let caret = view.selectedRange().location
        let string = storage.string as NSString
        let line = string.lineRange(for: NSRange(location: min(caret, string.length), length: 0))
        var content = line
        if content.length > 0,
           string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
            content.length -= 1
        }
        let glyph = NoteMarkdown.listGlyph(activeBlock, index: 1)
        let text = string.substring(with: content)
        // Empty means "marker and nothing else".
        let stripped = text.replacingOccurrences(of: "^(\\d+\\.|•|☐|☑)\\s+", with: "",
                                                 options: .regularExpression)
        guard stripped.trimmingCharacters(in: .whitespaces).isEmpty, glyph.count <= content.length + 1 else {
            return false
        }
        setBlock(.body)
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
    /// marker.
    private func retype(_ storage: NSTextStorage, paragraph: NSRange, to block: NoteBlock) {
        let string = storage.string as NSString
        var content = paragraph
        if content.length > 0,
           string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
            content.length -= 1
        }
        let old = (storage.attribute(.noteBlock, at: content.location, effectiveRange: nil) as? String)
            .flatMap(NoteBlock.init(rawValue:)) ?? .body

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
            .paragraphStyle: NoteType.paragraphStyle(for: block),
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
            let marker = NSAttributedString(string: NoteMarkdown.listGlyph(block, index: 1), attributes: [
                .font: NoteType.font(for: .body),
                .foregroundColor: NSColor.controlAccentColor,
                .paragraphStyle: NoteType.paragraphStyle(for: block),
                .noteBlock: block.rawValue,
            ])
            storage.insert(marker, at: full.location)
        }
    }

    /// Numbered lists count from the top of their own run, so deleting a row
    /// does not leave 1, 2, 4.
    private func renumber(_ storage: NSTextStorage) {
        let string = storage.string as NSString
        var index = 0
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
            if block == .numbered {
                index += 1
                let text = string.substring(with: content)
                if let match = text.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                    let drawn = text.distance(from: text.startIndex, to: match.upperBound)
                    let wanted = NoteMarkdown.listGlyph(.numbered, index: index)
                    if String(text[text.startIndex..<match.upperBound]) != wanted {
                        storage.replaceCharacters(
                            in: NSRange(location: content.location, length: drawn),
                            with: NSAttributedString(string: wanted, attributes: [
                                .font: NoteType.font(for: .body),
                                .foregroundColor: NSColor.controlAccentColor,
                                .paragraphStyle: NoteType.paragraphStyle(for: .numbered),
                                .noteBlock: NoteBlock.numbered.rawValue,
                            ]))
                        return renumber(storage)   // lengths moved; start again
                    }
                }
            } else {
                index = 0
            }
            location = NSMaxRange(line)
        }
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
