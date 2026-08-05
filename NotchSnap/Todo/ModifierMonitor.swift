import AppKit
import SwiftUI

// MARK: - ModifierMonitor — ⌘-held shortcut reveal (KB-4 / PRD §7.2)
//
// CURRENTLY UNUSED. Its only consumer was the index badge over each category
// tab, removed on Marcello's request (2026-08-05). Kept because the reveal
// mechanism is sound and may return for another surface; costs nothing while
// dormant, since the singleton is lazy and nothing touches `.shared`, so the
// flagsChanged monitor is never installed. Delete the file if it is still
// unreferenced next time this area is touched.
//
// Holding ⌘ temporarily surfaces the small shortcut badges (number badges on
// category tabs, combo-box key hints in quick entry); releasing hides them.
// One shared app-wide flagsChanged monitor rather than per-view monitors, so
// every badge in every window flips from the same source of truth.
//
// A local monitor only fires while NotchSnap is active — which is exactly
// right: badges are an in-app affordance, not a global overlay.

@MainActor
final class ModifierMonitor: ObservableObject {
    static let shared = ModifierMonitor()

    @Published private(set) var commandHeld = false

    private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.contains(.command)
            MainActor.assumeIsolated {
                self?.setHeld(held)
            }
            return event
        }
        // A ⌘-up delivered while the app is inactive never reaches a local
        // monitor — without this reset the badges could stick on until the
        // next in-app flags change (drift table §10 #2: badges must NEVER
        // read as permanent).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setHeld(false) }
        }
    }

    private func setHeld(_ held: Bool) {
        guard commandHeld != held else { return }
        // §8.1: badge reveal must feel immediate — a fast, light fade,
        // clearly distinct from the weighty content spring.
        withAnimation(NotchAnimation.hintFade) {
            commandHeld = held
        }
    }
}
