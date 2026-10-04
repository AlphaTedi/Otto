import AppKit

// MARK: - HapticManager — Centralized trackpad haptic + sound feedback
//
// Every user-facing event maps to a specific haptic pattern + sound.
// Gracefully degrades on Macs without Force Touch trackpad.
//
// Sounds are dispatched BEFORE the haptic guard: the "hapticFeedback"
// toggle only controls trackpad taps, while sounds obey their own
// "soundEffectsEnabled" toggle (checked inside SoundManager).

final class HapticManager: @unchecked Sendable {
    static let shared = HapticManager()
    private let performer = NSHapticFeedbackManager.defaultPerformer

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "hapticFeedback")
    }

    // MARK: - Notch Events

    /// Notch expands: transition to gallery visible
    func notchExpanded() {
        SoundManager.shared.play(.expand)
        guard isEnabled else { return }
        // Single tap (like hover) — `.levelChange` produced a double-pulse
        // that felt "laggy / continuous".
        performer.perform(.generic, performanceTime: .now)
    }

    /// Notch collapses: gallery hidden
    func notchCollapsed() {
        SoundManager.shared.play(.collapse)
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }

    /// Hover taps again (Marcello, 2026-09-30: "quando faccio hover sulla
    /// notch il feedback aptico non funziona più").
    ///
    /// It was removed on 2026-08 because it fired on every pass across the
    /// top of the screen. What reaches here now is already filtered: the
    /// controller only enters hover for a SLOW pointer inside the notch's own
    /// rect (fast transits are ignored), and only from idle. The rate limit
    /// keeps a hand hovering in and out from buzzing.
    func notchHoverEntered() {
        guard isEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHoverTap > 0.6 else { return }
        lastHoverTap = now
        performer.perform(.generic, performanceTime: .now)
    }
    private var lastHoverTap: TimeInterval = 0

    // Legacy aliases
    func hoverTap() { notchHoverEntered() }
    func expandTap() { notchExpanded() }

    // MARK: - Screenshot Events

    // MARK: - Clipboard & Actions

    // MARK: - Drag & Drop

    func dragBegan() {
        guard isEnabled else { return }
        performer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: - To-do events
    //
    // Named for what HAPPENED, not for whichever screenshot-era method
    // happened to have the right pattern. The to-do code used to call
    // `copyConfirmed()` to file a to-do and `thumbnailSelect()` to tick one
    // off, which is how the app's most repeated action ended up with its
    // heaviest feedback and its most satisfying one with its lightest.

    /// A to-do is filed.
    ///
    /// ONE tap. This is the single most repeated act in the app, and it used
    /// to fire `copyConfirmed`'s double pulse — over-feedback on the exact
    /// action you perform most is how a user learns to stop noticing all of
    /// it.
    func todoCreated() {
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }

    /// A to-do is ticked off — the signature moment of a to-do app.
    ///
    /// `.levelChange` rather than `.generic`: it is the firmer of the two and
    /// reads as something having changed state rather than as a surface being
    /// touched. No sound, because Otto has no asset that means "done" and the
    /// nearest one means "copied"; a wrong sound is worse than none, and the
    /// row already fills and strikes through on its own spring.
    func todoCompleted() {
        guard isEnabled else { return }
        performer.perform(.levelChange, performanceTime: .now)
    }

    /// Putting one back. Deliberately lighter: undoing is not an achievement,
    /// and giving it the same pulse as finishing would flatten the difference.
    func todoUncompleted() {
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }

    /// Crossing into a new slot while dragging a row.
    ///
    /// `.alignment` is precisely what this pattern is for — it is the one the
    /// system uses for alignment guides, and a reorder is the same act: the
    /// thing in your hand snapping to a position. Fires once per slot
    /// CHANGED, never per frame.
    func reorderTick() {
        guard isEnabled else { return }
        performer.perform(.alignment, performanceTime: .now)
    }

    /// The row lands.
    func reorderCommitted() {
        guard isEnabled else { return }
        performer.perform(.levelChange, performanceTime: .drawCompleted)
    }

    /// The active section changed — ⇥, ⌘1…9, or a click on a tab.
    ///
    /// Worth a tap even though it is frequent: the notch is driven from the
    /// keyboard, and this lets you feel that ⇥ landed without looking up at
    /// which tab lit.
    func sectionChanged() {
        guard isEnabled else { return }
        performer.perform(.alignment, performanceTime: .now)
    }

    /// A meeting was pushed back, by hand or by the auto-snooze running out.
    func meetingSnoozed() {
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }

    // MARK: - Delete

    func itemDeleted() {
        SoundManager.shared.play(.delete)
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }
}
