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
    /// A click landed on an underlined phrase — the picker's cue.
    var onActionTapped: ((NSRange, String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ActionTextView.scrollableTextView()
        guard let view = scroll.documentView as? ActionTextView else { return scroll }

        view.delegate = context.coordinator
        view.isRichText = true
        view.allowsUndo = true
        view.drawsBackground = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        view.textContainerInset = NSSize(width: 0, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        // The user's own text is never reformatted — no smart quotes, no
        // dash substitution, no automatic capitalisation. Lowercase, missing
        // punctuation and typos are preserved exactly as typed.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.insertionPointColor = NSColor.controlAccentColor
        view.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28)
        ]
        view.typingAttributes = [
            .font: NoteType.font(for: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NoteType.paragraphStyle(for: .body),
            .noteBlock: NoteBlock.body.rawValue,
        ]

        view.onActionClick = { [weak view] point in
            guard let view else { return false }
            guard let hit = NoteEditorController.shared.action(at: point) else { return false }
            onActionTapped?(hit.range, hit.phrase)
            return true
        }
        view.noteID = noteID

        context.coordinator.load(markdown, into: view)
        NoteEditorController.shared.textView = view
        // On OPEN, not only after typing: a note you come back to should show
        // what it found before you touch anything.
        context.coordinator.scheduleDetection(noteID: noteID, delay: 0)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
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
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: NoteBodyView
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

        /// Re-detect after the user stops typing. Cancelling the previous item
        /// is what makes it a debounce rather than a queue of passes.
        @MainActor
        func scheduleDetection(noteID: UUID, delay: TimeInterval) {
            detectionWork?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated {
                    NoteEditorController.shared.refreshDetections(noteID: noteID)
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
            loadedNoteID = parent.noteID
            loading = false
            MainActor.assumeIsolated { NoteEditorController.shared.refreshState() }
        }

        func textDidChange(_ notification: Notification) {
            guard !loading, let view = notification.object as? NSTextView,
                  let storage = view.textStorage else { return }
            MainActor.assumeIsolated {
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
            MainActor.assumeIsolated { NoteEditorController.shared.refreshState() }
        }

        /// Space and Return are the two keys markdown-as-you-type and the list
        /// behaviour need to see BEFORE the text system spends them.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            MainActor.assumeIsolated {
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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onActionClick?(point) == true { return }
        super.mouseDown(with: event)
    }

    /// Right-click on an underlined phrase offers the two verbs the spec asks
    /// for; anywhere else the ordinary text menu is untouched.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let noteID,
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
