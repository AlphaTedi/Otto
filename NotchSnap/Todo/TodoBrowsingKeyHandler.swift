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
//                While the inline draft row holds the caret, ⇥ re-aims it at
//                the next section, ⏎ files it, Esc throws it away.
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

        @MainActor
        private static func handleDraft(_ store: TodoStore, keyCode: UInt16) -> Bool {
            guard store.isCreatingDraft,
                  let responder = NSApp.keyWindow?.firstResponder as? NSView,
                  responder.identifier == HighlightingTitleField.fieldIdentifier else { return false }
            switch keyCode {
            case 36:                            // ⏎ — file it where we are
                store.commitDraft()
                return true
            case 48:                            // ⇥ — re-aim at the next section
                // Must be caught here: left alone, AppKit spends Tab on
                // focus-ring traversal and the key never reaches us at all.
                store.cycleDraftDestination()
                return true
            case 53:                            // Esc — discard
                NSApp.keyWindow?.makeFirstResponder(nil)
                store.cancelDraft()
                return true
            default:
                return false                    // typing flows to the field
            }
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
            // The draft row owns ⏎ / ⇥ / Esc whenever it holds the caret.
            if handleDraft(store, keyCode: keyCode) { return true }

            // While a text control has focus (note field, add-step), don't
            // steal keys; Esc hands focus back to the list.
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                if cmd, lower == "n" {
                    NotchController.shared.openCreate()
                    return true
                }
                if keyCode == 53 {
                    NSApp.keyWindow?.makeFirstResponder(nil)
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
            case 49, 36:                        // Space / Return — complete
                guard let focused = store.focusedItemID else { return false }
                store.toggleComplete(focused)
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
