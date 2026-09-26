import AppKit
import SwiftUI

// MARK: - NoteBodyView — the NSTextView the note is written in
//
// The body is markdown on disk and attributed on screen. This bridges the two:
// it seeds the view from `NoteMarkdown.attributed`, and on every edit hands
// `NoteMarkdown.markdown` back to the store, which saves it exactly the way it
// saved a plain string before. No second writer, no new file, no migration —
// a note written before formatting existed is a note with no markers in it.

struct NoteBodyView: NSViewRepresentable {
    let noteID: UUID
    @Binding var markdown: String
    /// NSTextView otherwise inherits the hosting window's appearance, which
    /// can differ from the SwiftUI surface (the note panels draw their own
    /// dark/light treatment). Dynamic AppKit colors then resolve to the wrong
    /// ink when a user starts a fresh typing run.
    let colorScheme: ColorScheme
    /// A click landed on an underlined phrase — the picker's cue.
    var onActionTapped: ((NSRange, String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ActionTextView.scrollableTextView()
        guard let view = scroll.documentView as? ActionTextView else { return scroll }

        applyAppearance(to: view)

        view.delegate = context.coordinator
        view.isRichText = true
        view.allowsUndo = true
        view.drawsBackground = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        view.textContainerInset = NSSize(width: 28, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        // The user's own text is never reformatted — no smart quotes, no
        // dash substitution, no automatic capitalisation. Lowercase, missing
        // punctuation and typos are preserved exactly as typed.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.insertionPointColor = NSColor(LabMetrics.accent)
        view.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28)
        ]
        view.typingAttributes = [
            .font: NoteType.font(for: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NoteType.paragraphStyle(for: .body),
            .noteBlock: NoteBlock.body.rawValue,
        ]

        view.onActionClick = { point in
            guard let hit = NoteEditorController.shared.action(at: point) else { return false }
            onActionTapped?(hit.range, hit.phrase)
            return true
        }
        view.noteID = noteID
        view.onHeightChange = { height in
            DispatchQueue.main.async { NoteEditorController.shared.contentHeight = height }
        }

        context.coordinator.load(markdown, into: view)
        NoteEditorController.shared.textView = view
        // On OPEN, not only after typing: a note you come back to should show
        // what it found before you touch anything.
        context.coordinator.scheduleDetection(noteID: noteID, delay: 0)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? ActionTextView else { return }
        applyAppearance(to: view)
        context.coordinator.parent = self
        view.noteID = noteID
        NoteEditorController.shared.textView = view
        // Reload when the note changed underneath us — a note opened from the
        // stream — or when the text arrived from somewhere that is NOT this
        // view. Rewriting the storage on every keystroke would drop the caret
        // to the start of the document on every character typed, so the test
        // is against what this view last emitted rather than against the
        // storage: our own edit echoes back identical and is ignored, while a
        // genuine outside change is taken.
        if context.coordinator.shouldReload(noteID: noteID, markdown: markdown) {
            context.coordinator.load(markdown, into: view)
            context.coordinator.scheduleDetection(noteID: noteID, delay: 0)
        }
    }

    private func applyAppearance(to view: NSView) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelDetection()
        if NoteEditorController.shared.textView === scroll.documentView {
            NoteEditorController.shared.pickerTarget = nil
            NoteEditorController.shared.textView = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteBodyView
        private(set) var loadedNoteID: UUID?
        /// The last markdown this view either loaded or produced. Anything
        /// different arriving from outside is a change this view did not make.
        private var lastKnownMarkdown: String?
        /// True while we are seeding the view, so the delegate does not treat
        /// our own write as the user's edit and echo it back to the store.
        private var loading = false

        init(_ parent: NoteBodyView) { self.parent = parent }

        func shouldReload(noteID: UUID, markdown: String) -> Bool {
            loadedNoteID != noteID || lastKnownMarkdown != markdown
        }

        private var detectionWork: DispatchWorkItem?
        private var lastEdit = Date.distantPast
        func cancelDetection() { detectionWork?.cancel() }

        /// Re-detect after the user stops typing. Cancelling the previous item
        /// is what makes it a debounce rather than a queue of passes.
        @MainActor
        func scheduleDetection(noteID: UUID, delay: TimeInterval) {
            detectionWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    guard let view = NoteEditorController.shared.textView as? ActionTextView,
                          view.noteID == noteID else { return }
                    NoteEditorController.shared.refreshDetections(noteID: noteID,
                        excludingCaret: Date().timeIntervalSince(self.lastEdit) < 2)
                }
            }
            detectionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        func load(_ markdown: String, into view: NSTextView) {
            loading = true
            lastKnownMarkdown = markdown
            let attributed = NoteMarkdown.attributed(
                from: markdown,
                textColor: .labelColor,
                accent: .labelColor,
                mutedColor: .tertiaryLabelColor
            )
            view.textStorage?.setAttributedString(attributed)
            (view as? ActionTextView)?.applyCodeSpacing()
            loadedNoteID = parent.noteID
            loading = false
            MainActor.assumeIsolated { NoteEditorController.shared.refreshState() }
        }

        func textDidChange(_ notification: Notification) {
            guard !loading, let view = notification.object as? NSTextView,
                  let storage = view.textStorage else { return }
            MainActor.assumeIsolated {
                lastEdit = Date()
                NoteEditorController.shared.pickerTarget = nil
                NoteEditorController.shared.clearDetections()
                let written = NoteMarkdown.markdown(from: storage)
                lastKnownMarkdown = written
                parent.markdown = written
                NoteEditorController.shared.refreshState()
                // Debounced, and generously: detection that fires between
                // keystrokes would underline half-typed words and then take it
                // back, which is worse than not detecting at all.
                scheduleDetection(noteID: parent.noteID, delay: 1.5)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !loading else { return }
            MainActor.assumeIsolated {
                NoteEditorController.shared.refreshState()
                (notification.object as? ActionTextView)?.showSelectionControl()
                scheduleDetection(noteID: parent.noteID, delay: 1.5)
            }
        }

        /// Space and Return are the two keys markdown-as-you-type and the list
        /// behaviour need to see BEFORE the text system spends them.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            MainActor.assumeIsolated {
                if selector == #selector(NSResponder.deleteBackward(_:)) {
                    return NoteEditorController.shared.handleBackspace()
                }
                if selector == #selector(NSResponder.insertNewline(_:)) {
                    return NoteEditorController.shared.handleReturn()
                }
                return false
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString text: String?) -> Bool {
            guard text == " " else { return true }
            return MainActor.assumeIsolated { !NoteEditorController.shared.handleSpaceForMarkdown() }
        }

        func textDidBeginEditing(_ notification: Notification) {
            MainActor.assumeIsolated { NoteEditorController.shared.bodyFocused = true }
        }

        func textDidEndEditing(_ notification: Notification) {
            MainActor.assumeIsolated { NoteEditorController.shared.bodyFocused = false }
        }
    }
}

// MARK: - ActionTextView — the note's text view, plus the click on an underline
//
// Subclassed rather than handled with a gesture recognizer: a click inside a
// text view is the text view's to place the caret with, and the only honest
// place to decide "this one was on an underlined phrase instead" is before
// `super.mouseDown` runs. A recognizer on top would fight the caret for every
// click in the note.

final class ActionTextView: NSTextView {
    /// Returns true when the click was consumed by an underlined phrase.
    var onActionClick: ((NSPoint) -> Bool)?
    var noteID: UUID?
    var onHeightChange: ((CGFloat) -> Void)?
    private var measuredHeight: CGFloat = 0

    override func layout() {
        super.layout()
        guard let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height + layout.extraLineFragmentRect.height + 12)
        if abs(height - measuredHeight) > 1 { measuredHeight = height; onHeightChange?(height) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, NotesStore.shared.openNote?.meetingContext != nil { NotesStore.shared.meetingFocus = 0 }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = linkedControls().first(where: { $0.rect.contains(point) }), let noteID,
           let linked = TodoStore.shared.todo(forNote: noteID, phrase: hit.phrase) {
            TodoStore.shared.toggleComplete(linked.id)
            NoteEditorController.shared.refreshDetections(noteID: noteID)
            return
        }
        if let hit = controlTarget, controlRect.contains(point) {
            MainActor.assumeIsolated {
                if let noteID, let linked = TodoStore.shared.todo(forNote: noteID, phrase: hit.phrase) {
                    TodoStore.shared.toggleComplete(linked.id)
                    NoteEditorController.shared.refreshDetections(noteID: noteID)
                } else { NoteEditorController.shared.pickerTarget = hit }
            }
            return
        }
        if MainActor.assumeIsolated({ NoteEditorController.shared.pickerTarget != nil }) {
            MainActor.assumeIsolated { NoteEditorController.shared.pickerTarget = nil }
            return
        }
        super.mouseDown(with: event)
    }

    private var actionTracking: NSTrackingArea?
    private var controlTarget: (range: NSRange, phrase: String)?
    private var controlRect = NSRect.zero

    func clearActionControl() {
        if let old = controlTarget {
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: old.range)
            layoutManager?.addTemporaryAttribute(.underlineColor,
                value: NSColor(LabMetrics.accent).withAlphaComponent(0.55),
                forCharacterRange: old.range)
        }
        controlTarget = nil
        controlRect = .zero
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let actionTracking { removeTrackingArea(actionTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        actionTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if controlTarget != nil, controlRect.insetBy(dx: -7, dy: -4).contains(point) { return }
        guard let hit = MainActor.assumeIsolated({ NoteEditorController.shared.action(at: point) }),
              let layout = layoutManager, let container = textContainer else {
            clearActionControl(); return
        }
        let glyphs = layout.glyphRange(forCharacterRange: hit.range, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        guard rect.insetBy(dx: 4, dy: 3).contains(point) else { clearActionControl(); return }
        if controlTarget?.phrase != hit.phrase { clearActionControl() }
        controlTarget = hit
        layout.addTemporaryAttributes([
            .backgroundColor: NSColor(LabMetrics.accent).withAlphaComponent(0.10),
            .underlineColor: NSColor(LabMetrics.accent).withAlphaComponent(0.85)
        ], forCharacterRange: hit.range)
        // Keep the control beside the phrase in temporary layout space: never
        // obscure text or inject attachment characters into Markdown.
        controlRect = inlineControlRect(after: hit.range, size: 20)
        needsDisplay = true
    }

    func showSelectionControl() {
        guard selectedRange().length > 0,
              let target = NoteEditorController.shared.actionAtCaret() else { return }
        controlTarget = target
        controlRect = inlineControlRect(after: target.range, size: 20)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) { clearActionControl() }

    private func linkedControls() -> [(rect: NSRect, phrase: String, done: Bool)] {
        guard let storage = textStorage else { return [] }
        var controls: [(rect: NSRect, phrase: String, done: Bool)] = []
        storage.enumerateAttribute(.noteActionDone, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let done = value as? Bool,
                  let phrase = storage.attribute(.noteAction, at: range.location, effectiveRange: nil) as? String else { return }
            controls.append((inlineControlRect(before: range, size: 16), phrase, done))
        }
        return controls
    }

    /// Draw controls beside the phrase itself. The text container has a 28pt
    /// inset, which reserves enough leading room for linked checkboxes.
    private func inlineControlRect(after range: NSRange, size: CGFloat) -> NSRect {
        guard let layout = layoutManager, let container = textContainer else { return .zero }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return .zero }
        let last = NSRange(location: NSMaxRange(glyphs) - 1, length: 1)
        let rect = layout.boundingRect(forGlyphRange: last, in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return NSRect(x: min(rect.maxX + 7, bounds.width - size - 4),
                      y: rect.midY - size / 2, width: size, height: size)
    }

    private func inlineControlRect(before range: NSRange, size: CGFloat) -> NSRect {
        guard let layout = layoutManager, let container = textContainer else { return .zero }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return .zero }
        let first = NSRange(location: glyphs.location, length: 1)
        let rect = layout.boundingRect(forGlyphRange: first, in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return NSRect(x: max(4, rect.minX - size - 6),
                      y: rect.midY - size / 2, width: size, height: size)
    }

    /// The block grounds and marks, all drawn behind the glyphs and none of
    /// them stored: a code block's full-width ground and hairline (a
    /// per-glyph background would stop at each line's last word), a quote's
    /// leading rule, and inline code's chip.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let layout = layoutManager,
              let container = textContainer else { return }
        let origin = textContainerOrigin
        let full = NSRange(location: 0, length: storage.length)

        // One rect per run of code or quote lines. The empty line the caret
        // sits on at the very end has no character to carry the block, so its
        // type is the typing attributes' and its rect the extra fragment.
        var runs: [(block: NoteBlock, rect: NSRect, endsDocument: Bool)] = []
        storage.enumerateAttribute(.noteBlock, in: full) { value, range, _ in
            guard let block = (value as? String).flatMap(NoteBlock.init(rawValue:)),
                  block == .code || block == .quote else { return }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            // Used rects, not line fragments: the fragments include the
            // paragraph spacing around the block, which is air, not block.
            var used = NSRect.null
            layout.enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, _, _ in
                used = used.union(usedRect)
            }
            runs.append((block, used, NSMaxRange(range) == storage.length))
        }
        let extra = layout.extraLineFragmentUsedRect
        if !extra.isEmpty, selectedRange().location == storage.length,
           let block = (typingAttributes[.noteBlock] as? String).flatMap(NoteBlock.init(rawValue:)),
           block == .code || block == .quote {
            if let last = runs.last, last.block == block, last.endsDocument {
                runs[runs.count - 1].rect = last.rect.union(extra)
            } else {
                runs.append((block, extra, true))
            }
        }
        for run in runs {
            let bounds = run.rect.offsetBy(dx: origin.x, dy: origin.y)
            if run.block == .code {
                let ground = NSRect(x: origin.x, y: bounds.minY - 6,
                                    width: container.size.width, height: bounds.height + 12)
                let path = NSBezierPath(roundedRect: ground.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
                NoteType.codeBackground.setFill()
                path.fill()
                NoteType.codeBorder.setStroke()
                path.lineWidth = 1
                path.stroke()
            } else {
                let rule = NSRect(x: origin.x + 1, y: bounds.minY + 2, width: 3,
                                  height: max(bounds.height - 2, 8))
                NoteType.quoteRule.setFill()
                NSBezierPath(roundedRect: rule, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        // Inline code: a compact chip per line the span wraps across, sized
        // from the code face's own ascender and descender — the line fragment
        // is 1.35 lines tall and a chip that tall read as a selection.
        let font = NoteType.codeFont
        storage.enumerateAttribute(.noteCode, in: full) { value, range, _ in
            guard value != nil else { return }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            layout.enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
                let piece = NSIntersectionRange(glyphs, lineGlyphs)
                guard piece.length > 0 else { return }
                let box = layout.boundingRect(forGlyphRange: piece, in: container)
                let baseline = line.minY + layout.location(forGlyphAt: piece.location).y
                // The span's last glyph carries the padding as kerning
                // (applyCodeSpacing), and the glyph box already includes it.
                let right = NSMaxRange(piece) == NSMaxRange(glyphs)
                    ? box.maxX : box.maxX + Self.codePadding
                let chip = NSRect(x: box.minX - Self.codePadding,
                                  y: baseline - font.ascender - 2,
                                  width: right - box.minX + Self.codePadding,
                                  height: font.ascender - font.descender + 4)
                    .offsetBy(dx: origin.x, dy: origin.y)
                let path = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                NoteType.codeBackground.setFill()
                path.fill()
                NoteType.codeBorder.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    /// The air inside an inline-code chip, each side.
    static let codePadding: CGFloat = 4
    /// The air above and below a code block, outside its ground.
    static let codeBlockMargin: CGFloat = 10

    /// Layout the code formats need and the markdown never sees, re-derived
    /// from the text after every edit:
    ///  - kerning that makes room for each inline chip's padding, on the
    ///    character in front of the span and on its last character. REAL
    ///    kerning, in the storage: a layout manager's temporary `.kern` only
    ///    draws, it does not move a glyph, and the chip cut into the letters.
    ///    The serializer ignores `.kern`, and every run is rebuilt here, so a
    ///    character typed after a chip cannot carry its spacing along.
    ///  - space above a code block's first line and below its last. Per line
    ///    would open gaps inside the block, so it follows the lines' position.
    func applyCodeSpacing() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: storage.length)
        var wanted: [(NSRange, CGFloat)] = []
        storage.enumerateAttribute(.noteCode, in: full) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            if range.location > 0, text.character(at: range.location - 1) != 0x0A {
                wanted.append((NSRange(location: range.location - 1, length: 1), Self.codePadding))
            }
            wanted.append((NSRange(location: NSMaxRange(range) - 1, length: 1), Self.codePadding))
        }
        var stale: [NSRange] = []
        storage.enumerateAttribute(.kern, in: full) { value, range, _ in
            if value != nil { stale.append(range) }
        }
        let blocks = paragraphBlocks(in: storage)
        storage.beginEditing()
        for range in stale { storage.removeAttribute(.kern, range: range) }
        for (range, kern) in wanted { storage.addAttribute(.kern, value: kern, range: range) }
        for (index, line) in blocks.enumerated() where line.block == .code && line.range.length > 0 {
            let before: CGFloat = index > 0 && blocks[index - 1].block == .code ? 0 : Self.codeBlockMargin
            let after: CGFloat = index + 1 < blocks.count && blocks[index + 1].block == .code ? 0 : Self.codeBlockMargin
            let current = storage.attribute(.paragraphStyle, at: line.range.location, effectiveRange: nil) as? NSParagraphStyle
            guard current?.paragraphSpacingBefore != before || current?.paragraphSpacing != after,
                  let style = (current ?? NoteType.paragraphStyle(for: .code)).mutableCopy() as? NSMutableParagraphStyle
            else { continue }
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            storage.addAttribute(.paragraphStyle, value: style, range: line.range)
        }
        storage.endEditing()
    }

    /// Each paragraph with its type, line break included in its range.
    private func paragraphBlocks(in storage: NSTextStorage) -> [(range: NSRange, block: NoteBlock)] {
        let text = storage.string as NSString
        var lines: [(range: NSRange, block: NoteBlock)] = []
        var location = 0
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            let block = (storage.attribute(.noteBlock, at: range.location, effectiveRange: nil) as? String)
                .flatMap(NoteBlock.init(rawValue:)) ?? .body
            lines.append((range, block))
            location = NSMaxRange(range)
        }
        return lines
    }

    // MARK: Copy and paste keep the note's formatting (NoteEditorController.paste)

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [NoteEditorController.markdownPasteboardType] + super.writablePasteboardTypes
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == NoteEditorController.markdownPasteboardType else {
            return super.writeSelection(to: pboard, type: type)
        }
        guard let storage = textStorage, selectedRange().length > 0 else { return false }
        let markdown = NoteMarkdown.markdown(from: storage.attributedSubstring(from: selectedRange()))
        return pboard.setString(markdown, forType: type)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [NoteEditorController.markdownPasteboardType] + super.readablePasteboardTypes
    }

    /// Drags keep the text system's own path: our paste inserts at the
    /// selection, which is not where a drop lands.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter { $0 != NoteEditorController.markdownPasteboardType }
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == NoteEditorController.markdownPasteboardType,
              let markdown = pboard.string(forType: type) else {
            return super.readSelection(from: pboard, type: type)
        }
        MainActor.assumeIsolated { NoteEditorController.shared.paste(markdown: markdown) }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for control in linkedControls() {
            NSColor(LabMetrics.accent).setStroke()
            let path = NSBezierPath(roundedRect: control.rect, xRadius: 5, yRadius: 5)
            path.lineWidth = 1.5
            path.stroke()
            if control.done {
                ("✓" as NSString).draw(in: control.rect.offsetBy(dx: 2, dy: -1), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(LabMetrics.accent)
                ])
            }
        }
        guard let target = controlTarget else { return }
        NSColor(LabMetrics.accent).setFill()
        NSBezierPath(ovalIn: controlRect).fill()
        let linked = noteID.flatMap { TodoStore.shared.todo(forNote: $0, phrase: target.phrase) }
        let glyph = linked.map { $0.isCompleted ? "✓" : "○" } ?? "+"
        (glyph as NSString).draw(in: controlRect.offsetBy(dx: 4, dy: 0), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black
        ])
    }

    /// Right-click on an underlined phrase offers the two verbs the spec asks
    /// for; anywhere else the ordinary text menu is untouched.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard noteID != nil,
              let hit = MainActor.assumeIsolated({ NoteEditorController.shared.action(at: point) })
        else { return super.menu(for: event) }

        let menu = NSMenu()
        let add = NSMenuItem(title: L10n.t("notes.action.add"),
                             action: #selector(addAsTodo(_:)), keyEquivalent: "")
        add.target = self
        add.representedObject = hit.phrase
        menu.addItem(add)
        let reject = NSMenuItem(title: L10n.t("notes.action.notATask"),
                                action: #selector(notATask(_:)), keyEquivalent: "")
        reject.target = self
        reject.representedObject = hit.phrase
        menu.addItem(reject)
        return menu
    }

    @objc private func addAsTodo(_ sender: NSMenuItem) {
        guard let phrase = sender.representedObject as? String else { return }
        MainActor.assumeIsolated {
            guard let storage = textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            var target: NSRange?
            storage.enumerateAttribute(.noteAction, in: full, options: []) { value, range, stop in
                if value as? String == phrase { target = range; stop.pointee = true }
            }
            guard let target else { return }
            NoteEditorController.shared.pickerTarget = (target, phrase)
        }
    }

    @objc private func notATask(_ sender: NSMenuItem) {
        guard let phrase = sender.representedObject as? String, let noteID else { return }
        MainActor.assumeIsolated {
            NotesStore.shared.dismissAction(phrase, in: noteID)
            NoteEditorController.shared.refreshDetections(noteID: noteID)
        }
    }
}
