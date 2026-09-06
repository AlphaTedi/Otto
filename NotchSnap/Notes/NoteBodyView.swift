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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }

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

        context.coordinator.load(markdown, into: view)
        NoteEditorController.shared.textView = view
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

        func load(_ markdown: String, into view: NSTextView) {
            loading = true
            lastKnownMarkdown = markdown
            let attributed = NoteMarkdown.attributed(
                from: markdown,
                textColor: .labelColor,
                accent: .controlAccentColor,
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
