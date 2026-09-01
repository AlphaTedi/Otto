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
            case .browsing:
                return handleBrowsing(store, cmd: cmd, shift: shift, option: option,
                                      control: control, chars: chars, keyCode: keyCode, lower: lower)
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
                store.cycleCollection(by: shift ? -1 : 1)
                return true
            }

            // The draft row owns ⏎ / Esc whenever it holds the caret.
            if handleDraft(store, keyCode: keyCode) { return true }

            // While a text control has focus (note field, add-step), don't
            // steal keys; Esc hands focus back to the list.
            if isEditingText() {
                if cmd, lower == "n" {
                    NotchController.shared.openCreate()
                    return true
                }
                if keyCode == 53 {
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
                guard let focused = store.focusedItemID else { return false }
                withAnimation(NotchAnimation.contentHug) {
                    store.expandedItemID = focused
                }
                return true
            case 123:                           // ← collapse details
                guard store.expandedItemID != nil else { return false }
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
