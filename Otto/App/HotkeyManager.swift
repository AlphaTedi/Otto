import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - HotkeyManager — Global shortcuts via Carbon RegisterEventHotKey
//
// Carbon Hot Keys work ALWAYS:
// ✅ No Accessibility permission needed
// ✅ Works when app is active OR background
// ✅ Works with accessory apps (no dock icon)
// ✅ Survives app activation/deactivation
//
// Shortcuts are intentionally limited to Otto's to-do and notes flows. The
// former screenshot-capture bindings were retired with the product pivot.

@MainActor
class HotkeyManager {
    static let shared = HotkeyManager()

    /// The global new-to-do shortcut as it is shown to people. One source for
    /// every place that prints it — the onboarding once showed ⌥⌘N, which was
    /// never the binding.
    static let quickEntryDisplay = "\u{2303}\u{21E7}N"

    /// False when another app already owns ⌃⇧N and the registration failed —
    /// the onboarding then offers a way past its shortcut step (v3 §4.4).
    private(set) var quickEntryRegistered = false

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    // Signature for our hot keys (ASCII "OTTO")
    private let signature: FourCharCode = {
        let chars: [UInt8] = [0x4F, 0x54, 0x54, 0x4F] // "OTTO"
        return FourCharCode(chars[0]) << 24 | FourCharCode(chars[1]) << 16 | FourCharCode(chars[2]) << 8 | FourCharCode(chars[3])
    }()

    // Hot key IDs
    private enum HotKeyID: UInt32 {
        case openNotes = 6        // ⌃⇧N — expand notch on the Notes tab
        case quickEntry = 8       // ⌥Space — global to-do quick entry (KB-1)
        case openTodos = 9        // ⌃⇧T — expand notch on the To-do tab
        case openNotesSpace = 10  // ⌃⇧E — expand notch on the Notes space
        case joinMeeting = 11     // ⌘↩ — only while a meeting alert is up
    }

    private var joinHotKeyRef: EventHotKeyRef?
    /// The last registration's result, for diagnostics (noErr = 0).
    private(set) var joinHotKeyStatus: OSStatus = 0
    var joinHotKeyActive: Bool { joinHotKeyRef != nil }

    /// ⌘↩ joins the alerting meeting from any app. Registered only for the
    /// alert's lifetime, so ⌘↩ belongs to every other app the rest of the time.
    func setJoinHotKey(_ active: Bool) {
        if active, joinHotKeyRef == nil, eventHandler != nil {
            let id = EventHotKeyID(signature: signature, id: HotKeyID.joinMeeting.rawValue)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr { joinHotKeyRef = ref }
            joinHotKeyStatus = status
        } else if !active, let ref = joinHotKeyRef {
            UnregisterEventHotKey(ref)
            joinHotKeyRef = nil
        }
    }

    func start() {
        guard eventHandler == nil else { return }

        // Install Carbon event handler for hot key events
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }

            Task { @MainActor in
                HotkeyManager.shared.handleHotKey(id: hotKeyID.id)
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        // Ctrl+Shift modifier mask for Otto's own navigation shortcuts.
        let ctrlShift = UInt32(controlKey | shiftKey)

        registerHotKey(id: .openNotes, keyCode: UInt32(kVK_ANSI_N), modifiers: ctrlShift)
        // KB-1: global quick entry, independent of whether the notch is open.
        // ⌥⌘N, not ⌥Space: launcher apps (Raycast, Alfred) claim ⌥Space by
        // default, so it silently never reached us on machines running one.
        registerHotKey(id: .quickEntry, keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey | cmdKey))
        registerHotKey(id: .openTodos, keyCode: UInt32(kVK_ANSI_T), modifiers: ctrlShift)
        // E, not N. ⌃⇧N is registered above and reassigned to quick capture,
        // and it is the one onboarding teaches — taking it back for Notes
        // would break the only shortcut every user has been shown.
        registerHotKey(id: .openNotesSpace, keyCode: UInt32(kVK_ANSI_E), modifiers: ctrlShift)

        print("[HotkeyManager] Carbon hot keys registered. No Accessibility permission needed.")
    }

    func stop() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        setJoinHotKey(false)

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Register a single hot key

    private func registerHotKey(id: HotKeyID, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
            if id == .openNotes { quickEntryRegistered = true }
        } else {
            print("[HotkeyManager] Failed to register hotkey \(id): \(status)")
        }
    }

    // MARK: - Handle hot key press

    private func handleHotKey(id: UInt32) {
        guard let hotKey = HotKeyID(rawValue: id) else { return }

        switch hotKey {
        case .openNotes:
            print("[HotkeyManager] ⌃⇧N → new to-do (creation)")
            Task { @MainActor in
                // The onboarding's shortcut step is practising this very key:
                // there it lights the keycaps, and opening the notch on top of
                // the lesson would bury it.
                if !OnboardingWindowController.capturesQuickEntry {
                    NotchController.shared.openCreateFresh()
                }
                NotificationCenter.default.post(name: .quickEntryFired, object: nil)
            }

        case .openNotesSpace:
            print("[HotkeyManager] \u{2303}\u{21E7}E \u{2192} Notes space")
            Task { @MainActor in
                NotchController.shared.triggerExpand(trigger: .hotkey)
                NotesStore.shared.enterSpace()
                // The space opens ready to write, and typing needs real
                // keyboard focus — the panel is a non-activating window in an
                // accessory app, so being "key within Otto" is not enough.
                NotchController.shared.makeKeyForTyping()
            }

        case .quickEntry:
            print("[HotkeyManager] ⌥⌘N → notch creation tab")
            Task { @MainActor in
                // Design PRD §3: one creation surface — the panel's "+" tab.
                NotchController.shared.toggleCreate()
                NotificationCenter.default.post(name: .quickEntryFired, object: nil)
            }

        case .joinMeeting:
            CalendarStore.shared.join()

        case .openTodos:
            print("[HotkeyManager] ⌃⇧T → Notch on To-dos")
            Task { @MainActor in
                NotchController.shared.triggerExpand(trigger: .hotkey)
                // Opening IS the intent to interact: the caret lands in the
                // draft row so typing works immediately, and — since a
                // nonactivating panel never takes focus on its own — this is
                // also what lets Esc and every other shortcut reach the
                // panel at all (keyboard-first, Thomas 2026-09-01).
                NotchController.shared.makeKeyForTyping()
            }
        }
    }
}
