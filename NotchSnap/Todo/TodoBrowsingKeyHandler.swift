import AppKit
import SwiftUI

// MARK: - TodoBrowsingKeyHandler — mode-aware keyboard routing
//
// A local key monitor rather than SwiftUI .keyboardShortcut: the notch is a
// non-activating panel whose rows aren't in the responder chain, and ⌘⇥ /
// bare arrow keys never reach SwiftUI shortcut handlers reliably. Installed
// while the to-do panel is on screen; routing depends on TodoPanelMode:
//
//   browsing     arrows/space/return operate on rows; → ← expand/collapse
//                details; a printable character seeds Quick Find (QF-2:
//                "type anywhere, no shortcut needed"); ? opens the overlay.
//                ⇥ switches section whether or not the draft row has the
//                caret; when it does, ⏎ files the draft and Esc steps out of
//                it keeping the text.
//   find         all typing is routed manually into the query (the field
//                is deliberately not a focused NSTextField — see
//                QuickFindView); ↑↓ move the selection, ⏎ jumps, Esc backs out.
//   newCategory  Esc backs out; typing flows to the name field.

struct TodoBrowsingKeyHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Only the notch's own keys. A local monitor hears every key
                // the APP receives, so with Settings or the Move picker key
                // this router was still answering — the picker's first Esc
                // was consumed here (resigning its field) and the second one
                // fell through to the notch-close monitor, collapsing the
                // notch while the picker stayed up. Keys addressed to another
                // window are that window's business.
                if let window = event.window, !(window is NotchPanel) {
                    return event
                }
                // NSEvent isn't Sendable — snapshot fields before hopping
                // onto the actor.
                let cmd = event.modifierFlags.contains(.command)
                let shift = event.modifierFlags.contains(.shift)
                let option = event.modifierFlags.contains(.option)
                let control = event.modifierFlags.contains(.control)
                let chars = event.charactersIgnoringModifiers ?? ""
                let keyCode = event.keyCode
                let consumed = MainActor.assumeIsolated {
                    Self.handle(cmd: cmd, shift: shift, option: option, control: control,
                                chars: chars, keyCode: keyCode)
                }
                return consumed ? nil : event
            }
        }

        /// Returns true if the event was consumed.
        @MainActor
        private static func handle(cmd: Bool, shift: Bool, option: Bool, control: Bool,
                                   chars: String, keyCode: UInt16) -> Bool {
            let store = TodoStore.shared
            let lower = chars.lowercased()

            // §2.3: the overlay is a temporary sheet — ? / Esc dismiss it,
            // everything else is inert while it's up.
            if store.showShortcuts {
                if chars == "?" || keyCode == 53 || (cmd && lower == "/") {
                    withAnimation(NotchAnimation.hintFade) { store.showShortcuts = false }
                }
                return true
            }

            switch store.panelMode {
            case .voice:
                return handleVoice(store, keyCode: keyCode)
            case .find:
                return handleFind(store, cmd: cmd, option: option, control: control,
                                  chars: chars, keyCode: keyCode)
            case .newCategory:
                if keyCode == 53 { store.setMode(.browsing); return true }
                return false
            case .notes:
                return handleNotes(cmd: cmd, shift: shift, option: option,
                                   control: control, chars: chars, keyCode: keyCode, lower: lower)
            case .browsing:
                return handleBrowsing(store, cmd: cmd, shift: shift, option: option,
                                      control: control, chars: chars, keyCode: keyCode, lower: lower)
            }
        }

        // MARK: Notes space
        //
        // The composer holds the caret almost all the time here, so this
        // branch is deliberately narrow: it claims the modified keys and the
        // navigation keys and lets every printable character through to the
        // field. Anything cleverer would be a key router competing with a text
        // field for the alphabet, which is how you lose someone's typing.

        @MainActor
        private static func handleNotes(cmd: Bool, shift: Bool, option: Bool,
                                        control: Bool, chars: String,
                                        keyCode: UInt16, lower: String) -> Bool {
            let notes = NotesStore.shared

            // Esc backs out ONE level, the same rule as everywhere else:
            // search → note → stream → the list you came from.
            if keyCode == 53, !cmd, !option, !control {
                if notes.searchActive { notes.toggleSearch(); return true }
                if notes.openNoteID != nil { notes.closeNote(); return true }
                notes.leaveSpace()
                return true
            }

            if cmd, !shift, !option {
                switch lower {
                case "s":
                    // NOT "persist" — the draft has been on disk since the
                    // first keystroke. It closes the entry.
                    if notes.openNoteID != nil { notes.closeNote() }
                    else { notes.commitDraft(); notes.focusComposer() }
                    return true
                case "n":
                    // A new empty composer. Nothing is discarded: whatever was
                    // there is either already an entry or was already empty.
                    notes.commitDraft()
                    notes.focusComposer()
                    return true
                case "f":
                    notes.toggleSearch()
                    return true
                case "z":
                    if notes.pendingDelete != nil { notes.undoDelete(); return true }
                    return false
                case "[":
                    if notes.openNoteID != nil { notes.closeNote(); return true }
                    return false
                default:
                    break
                }
                // ⌘⌫ — the row goes now, the file goes in five seconds.
                if keyCode == 51 {
                    let target = notes.openNoteID ?? notes.selectedNoteID
                    if let target { notes.delete(target); return true }
                    return false
                }
            }

            if cmd, shift, !option {
                switch lower {
                case "r":
                    // Only ever on a title the model proposed. A hand-typed one
                    // is final and the store refuses.
                    if let target = notes.openNoteID ?? notes.selectedNoteID {
                        notes.requestTitle(for: target)
                        return true
                    }
                    return false
                case "s":
                    if notes.openNoteID != nil { notes.exportOpenNote(); return true }
                    return false
                default:
                    return false
                }
            }

            // ⇥ and ←/→ leave the space, whether or not the composer holds
            // the caret.
            //
            // The composer is focused essentially all the time here — that is
            // the point of the surface — so a rule of "only when not editing"
            // would have meant "never", which is exactly what ⇥ did: it went
            // to the field and inserted a tab (Marcello, 2026-09-06). These
            // three keys are navigation between spaces and the field has no
            // use for any of them.
            if keyCode == 48, !cmd, !option, !control {          // ⇥
                TodoStore.shared.cycleSpace(by: shift ? -1 : 1)
                return true
            }
            if keyCode == 123 || keyCode == 124, !cmd, !option, !control,
               notes.draft.isEmpty {
                TodoStore.shared.cycleSpace(by: keyCode == 124 ? 1 : -1)
                return true
            }

            // ↑↓ walk the stream and ⏎ opens the selection — but only while
            // the composer is EMPTY.
            //
            // "Only when not editing" fails here for the same reason: the
            // caret lives in the composer, so the guard was permanently true
            // and the arrows did nothing at all. Emptiness is the honest test
            // instead — with a draft in the field those keys belong to the
            // text being written, and with nothing in it they belong to the
            // stream, which is the state you are in the moment after ⌘S.
            let composerEmpty = notes.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard composerEmpty || !isEditingText() else { return false }
            switch keyCode {
            case 126: notes.moveSelection(-1); return true
            case 125: notes.moveSelection(1);  return true
            case 36:
                if let selected = notes.selectedNoteID { notes.open(selected); return true }
                return false
            default:
                return false
            }
        }

        // MARK: Voice mode (VC-1)

        @MainActor
        private static func handleVoice(_ store: TodoStore, keyCode: UInt16) -> Bool {
            let voice = VoiceCaptureController.shared
            switch keyCode {
            case 53:                            // Esc — abandon the capture
                voice.cancel()
                store.setMode(.browsing)
                return true
            case 36:                            // Return
                switch voice.phase {
                case .listening: voice.finishListening()   // stop + parse
                case .review:    voice.confirm()           // VC-6: create all
                                 store.setMode(.browsing)
                default:         break
                }
                return true
            case 126:                           // ↑ move between drafts
                voice.moveFocus(-1); return true
            case 125:                           // ↓
                voice.moveFocus(1); return true
            default:
                // Everything else flows to the focused draft's text field.
                return false
            }
        }

        // MARK: The inline draft row
        //
        // Scoped by FIRST RESPONDER, not by a store flag. A draft can be open
        // while the caret sits somewhere else entirely — a note field, a step
        // field, the row you clicked into below — and ⏎/⇥/Esc mean different
        // things in each. Asking who actually has the caret is the only way
        // those three keys can't be stolen out from under another field.

        /// The window this panel lives in, asked directly.
        ///
        /// Everything here used to go through `NSApp.keyWindow`, which is only
        /// our panel while it actually holds focus. On a hover-open it did
        /// not, so `isEditingText()` came back false and the first printable
        /// character seeded Quick Find instead of reaching the field the user
        /// was looking at (Marcello, 2026-08-22). Asking the panel itself is
        /// true regardless of who holds focus.
        @MainActor
        private static var notchWindow: NSWindow? {
            NSApp.keyWindow ?? NSApp.windows.first { $0 is NotchPanel }
        }

        @MainActor
        private static var notchResponder: NSResponder? {
            notchWindow?.firstResponder
        }

        @MainActor
        private static func draftHasCaret() -> Bool {
            guard let responder = notchResponder as? NSView else { return false }
            return responder.identifier == HighlightingTitleField.fieldIdentifier
        }

        @MainActor
        private static func handleDraft(_ store: TodoStore, keyCode: UInt16) -> Bool {
            guard draftHasCaret() else { return false }
            switch keyCode {
            case 36:                            // ⏎ — file it, caret stays put
                store.commitDraft()
                return true
            case 125:                           // ↓ — walk from the field into the list
                // The draft is row zero of the list, not a separate mode:
                // ↓ hands the caret back and lands focus on the first to-do,
                // so Space/⏎/→ mean what they always mean there, and ↑ from
                // that first row returns to the field (see handleBrowsing).
                // One key, one direction, the whole panel drivable from the
                // place every open lands you (Thomas, 2026-09-01).
                guard let collection = store.activeCollection,
                      !store.openItems(in: collection).isEmpty else { return true }
                notchWindow?.makeFirstResponder(nil)
                store.blurDraft()
                store.moveFocus(1)              // nil → first row
                return true
            case 126:                           // ↑ — nothing above the field
                return true
            case 53:                            // Esc — step out, keep the text
                notchWindow?.makeFirstResponder(nil)
                store.blurDraft()
                // Nothing typed → nothing to keep, so one Esc closes the
                // notch outright. The two-step exit (leave the field, then
                // close) exists to protect a half-written to-do; with an
                // empty field it was only a second keypress for nothing
                // (Thomas, 2026-09-01). Every explicit open now lands the
                // caret here, so this IS the common close.
                if store.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NotchController.shared.forceCollapse()
                }
                return true
            default:
                // ⇥ is NOT handled here: it means the same thing in the field
                // and out of it, so it is handled once, below.
                return false                    // typing flows to the field
            }
        }

        /// True when the caret is in any text control — the draft row, a
        /// note, a step. Typing must reach it untouched.
        @MainActor
        private static func isEditingText() -> Bool {
            let responder = notchResponder
            return responder is NSTextView || responder is NSTextField
        }

        // MARK: Find mode (manual query editing)

        @MainActor
        private static func handleFind(_ store: TodoStore, cmd: Bool, option: Bool,
                                       control: Bool, chars: String, keyCode: UInt16) -> Bool {
            switch keyCode {
            case 53:                            // Esc
                store.setMode(.browsing)
                return true
            case 36:                            // Return — jump to match
                store.jumpToFindSelection()
                return true
            case 126:                           // ↑
                store.findSelection = max(0, store.findSelection - 1)
                return true
            case 125:                           // ↓
                store.findSelection = min(max(0, store.findMatches.count - 1),
                                          store.findSelection + 1)
                return true
            case 51:                            // ⌫
                if store.findQuery.isEmpty {
                    store.setMode(.browsing)
                } else {
                    store.findQuery.removeLast()
                    store.findSelection = 0
                }
                return true
            default:
                // Printable only: exclude control characters AND the
                // 0xF700-0xF8FF private-use range macOS uses for function/
                // arrow keys — those would otherwise append garbage glyphs.
                guard !cmd && !option && !control,
                      let scalar = chars.unicodeScalars.first,
                      chars.count == 1,
                      !CharacterSet.controlCharacters.contains(scalar),
                      !(0xF700...0xF8FF).contains(scalar.value) else { return false }
                store.findQuery.append(chars)
                store.findSelection = 0
                return true
            }
        }

        // MARK: Browsing mode

        @MainActor
        private static func handleBrowsing(_ store: TodoStore, cmd: Bool, shift: Bool,
                                           option: Bool, control: Bool, chars: String,
                                           keyCode: UInt16, lower: String) -> Bool {
            // ⇥ switches sections, full stop — while typing a draft (where it
            // re-aims the destination) and while just reading a list (where it
            // is plain tab switching). Those are the same act now that the
            // draft row is always on screen, so they are one key with one
            // meaning (Marcello, 2026-08-16). ⇧⇥ goes back.
            //
            // It has to be caught here: left alone, AppKit spends Tab on
            // focus-ring traversal and it never reaches us at all. The one
            // exception is a note or step field, where the caret is inside a
            // to-do rather than in the panel, and stealing ⇥ would be reaching
            // over the user's shoulder.
            if keyCode == 48, !cmd, !option, !control,
               draftHasCaret() || !isEditingText() {
                // The whole bar, Notes included: ⇥ walks past the last list
                // into Notes and round again, because they are one row on
                // screen and one row is what the key should feel like.
                store.cycleSpace(by: shift ? -1 : 1)
                return true
            }

            // ←/→ walk the space bar, INCLUDING while the caret sits in the
            // creation field — which is where it is the moment the notch
            // opens, and therefore the only state that matters for this key
            // (Marcello, 2026-09-06: "doesn't matter se l'input field è
            // selezionato oppure no").
            //
            // The one thing that stops them is text already typed. With
            // characters in the field ←/→ have to be the caret, or a to-do
            // cannot be corrected while it is being written — you would be
            // able to reach every section and not the letter you mistyped.
            // Empty field, no text to move through: the arrows belong to the
            // bar. That is the same test the Notes composer uses for ↑↓, and
            // it covers his case exactly, since the field is empty every time
            // the panel opens.
            if keyCode == 123 || keyCode == 124, !cmd, !option, !control, !shift,
               store.draftTitle.isEmpty,
               draftHasCaret() || !isEditingText() {
                store.cycleSpace(by: keyCode == 124 ? 1 : -1)
                return true
            }

            // The draft row owns ⏎ / Esc whenever it holds the caret.
            if handleDraft(store, keyCode: keyCode) { return true }

            // While a text control has focus (note field, add-step), don't
            // steal keys; Esc hands focus back to the list.
            if isEditingText() {
                // ↑/↓ walk the checklist while a step field has the caret.
                //
                // This has to sit INSIDE the editing branch and before it
                // returns: a step field is an NSTextField, so `isEditingText`
                // is true and every arrow used to fall straight through to the
                // field editor — where moveUp:/moveDown: on a single line just
                // park the caret at either end. Nothing moved, which is why
                // there was no way to walk a checklist from the keyboard
                // (Marcello, 2026-09-05).
                //
                // Past the last step is the draft slot; above the first, the
                // caret leaves the block and the row's title takes it back.
                if let focus = store.focusedDetail, keyCode == 126 || keyCode == 125,
                   !cmd, !option, !control {
                    let down = keyCode == 125
                    if !store.moveDetailFocus(down ? 1 : -1, in: focus.item) {
                        // Off the end of this to-do's form: carry on into the
                        // neighbouring one rather than stopping. Writing a list
                        // is one continuous act, and having to open each to-do
                        // by hand to keep typing breaks it.
                        if !store.moveDetailToAdjacentItem(down ? 1 : -1, from: focus.item) {
                            // Genuinely the end of the section: hand the caret
                            // back to the list, which the same two keys walk.
                            store.clearDetailFocus()
                            notchWindow?.makeFirstResponder(nil)
                            store.focusedItemID = focus.item
                        }
                    }
                    return true
                }
                // ⌘⏎ ticks off whatever the caret is in.
                if cmd, keyCode == 36, let focus = store.focusedDetail {
                    switch focus.target {
                    case .step(let stepID):
                        store.toggleChecklistItem(stepID, in: focus.item)
                    default:
                        store.toggleComplete(focus.item)
                    }
                    return true
                }
                if cmd, lower == "n" {
                    NotchController.shared.openCreate()
                    return true
                }
                if keyCode == 53 {
                    store.clearDetailFocus()
                    // Escape means DISCARD in a row's title or step editor —
                    // their .onExitCommand says so — but this monitor consumes
                    // the key before AppKit can deliver it (letting it through
                    // would hand it to the notch-close monitor instead, which
                    // closes the whole panel mid-edit). So the discard is
                    // announced explicitly, synchronously, BEFORE the blur:
                    // the editors listen and drop their draft, and the
                    // commit-on-blur that follows finds nothing to commit.
                    NotificationCenter.default.post(name: .todoEditorEscape, object: nil)
                    notchWindow?.makeFirstResponder(nil)
                    return true
                }
                return false
            }

            // KB-3: ⌘N drops a draft row on top of the section being browsed.
            if cmd, !shift, lower == "n" {
                NotchController.shared.openCreate()
                return true
            }

            // VC-1: ⇧⌘V starts the voice brain-dump (panel-only, per
            // Marcello — no global audio trigger).
            if cmd, shift, lower == "v", VoiceFeature.isEnabled {
                store.setMode(.voice)
                NotchController.shared.focusPanel()
                VoiceCaptureController.shared.start()
                return true
            }

            // ⌘↩ joins the next meeting that has a link. Plain Return is
            // already "complete the focused to-do", so the meeting action
            // takes the modifier — the card advertises ⌘↩ on its Join button.
            // Falls through when there is nothing to join.
            // ⌘⏎ completes the focused to-do.
            //
            // ⏎ used to complete; it now opens the row and hands over the
            // caret, which is the right default — but it left completing with
            // only Space, and Space is unreachable the moment any field has
            // focus. ⌘⏎ is the modifier form of "finish this one" and works
            // from the list and from inside the form alike (Marcello,
            // 2026-09-05).
            //
            // Before the meeting-join, deliberately: a selected to-do is what
            // the panel is about, and joining still answers ⌘⏎ whenever
            // nothing is selected.
            if cmd, !shift, keyCode == 36, let focused = store.focusedItemID {
                store.toggleComplete(focused)
                return true
            }
            if cmd, !shift, keyCode == 36, CalendarStore.shared.joinNextMeeting() {
                return true
            }

            // KB-5: ⇧⌘M moves the focused to-do.
            if cmd, shift, lower == "m" {
                TodoMovePicker.shared.showForFocusedItem()
                return true
            }

            // §7.3: ? toggles the reference (⌘/ kept as an alias).
            if chars == "?" || (cmd && lower == "/") {
                withAnimation(NotchAnimation.hintFade) { store.showShortcuts = true }
                return true
            }

            // KB-4: ⌘1…⌘9 direct-jump.
            if cmd, let digit = Int(lower), (1...9).contains(digit) {
                store.selectCollection(atIndex: digit - 1)
                return true
            }

            // TD-5 (keyboard): ⌥↑/⌥↓ reorder.
            if option, keyCode == 126 || keyCode == 125,
               let focused = store.focusedItemID {
                store.moveItem(focused, by: keyCode == 126 ? -1 : 1)
                return true
            }

            switch keyCode {
            case 126:                           // ↑
                // From the first row, ↑ goes back UP into the draft field —
                // the field is row zero (see handleDraft's ↓).
                if let focused = store.focusedItemID,
                   store.visibleFocusIndex(of: focused) == 0 {
                    store.focusDraft(fromGlobalShortcut: false)
                    return true
                }
                store.moveFocus(-1); return true
            case 125:                           // ↓
                store.moveFocus(1); return true
            case 124:                           // → expand details (NC-1)
                // With a row focused these still open and close its details:
                // that is the nearer meaning when the keyboard is ON something.
                // With nothing focused there is nothing to expand, and the
                // arrow walks the space bar (handled above for the common
                // case, here for a list with no caret anywhere).
                guard let focused = store.focusedItemID else {
                    store.cycleSpace(by: 1)
                    return true
                }
                withAnimation(NotchAnimation.contentHug) {
                    store.expandedItemID = focused
                }
                return true
            case 123:                           // ← collapse details
                guard store.expandedItemID != nil else {
                    guard store.focusedItemID == nil else { return false }
                    store.cycleSpace(by: -1)
                    return true
                }
                withAnimation(NotchAnimation.contentHug) {
                    store.expandedItemID = nil
                }
                return true
            case 49:                            // Space — complete
                guard let focused = store.focusedItemID else { return false }
                store.toggleComplete(focused)
                return true
            case 36:                            // ⏎ — open the row and edit it
                // The keyboard mirror of clicking a row (activateRow): the
                // details open and the caret lands in the title. Finder's ⏎
                // renames for the same reason — Return on a selected thing
                // means "work on this one", and completing stays on Space,
                // one key with one meaning each. Before this, editing a
                // to-do was the only daily act that REQUIRED the mouse
                // (a user of Marcello's, then Thomas, 2026-09-01).
                guard let focused = store.focusedItemID else { return false }
                store.requestTitleEdit(focused)
                return true
            default:
                // QF-2: any printable character starts Quick Find, seeded
                // with the character itself — no shortcut needed.
                guard !cmd && !option && !control,
                      chars.count == 1,
                      let ch = chars.first,
                      ch.isLetter || ch.isNumber else { return false }
                store.setMode(.find)
                store.findQuery = chars
                return true
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { remove() }
    }
}
