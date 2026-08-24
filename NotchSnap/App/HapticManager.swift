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

    /// Hover is NOT an action, so it no longer taps.
    ///
    /// It fired whenever the pointer crossed the trigger zone at the top of
    /// the screen — which on a notch app happens constantly, and most of the
    /// time on the way to somewhere else entirely. It was rate-limited to
    /// 250ms, which stopped it buzzing but not from firing at moments the
    /// user had not asked for anything.
    ///
    /// Haptics are a budget: every one spent on something the user did not do
    /// makes the ones for things they DID do count for less. Expand and
    /// collapse still tap, because those are commits.
    func notchHoverEntered() {}

    // Legacy aliases
    func hoverTap() { notchHoverEntered() }
    func expandTap() { notchExpanded() }

    // MARK: - Screenshot Events

    /// Screenshot captured: primary action
    func screenshotCaptured() {
        SoundManager.shared.play(.capture)
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }

    func captureFeedback() { screenshotCaptured() }

    // MARK: - Clipboard & Actions

    /// Copy confirmed: double tap for "doppio click" feeling
    func copyConfirmed() {
        SoundManager.shared.play(.copy)
        guard isEnabled else { return }
        performer.perform(.alignment, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.performer.perform(.alignment, performanceTime: .now)
        }
    }

    /// New clipboard item added (passive event — very light)
    func clipboardItemAdded() {
        SoundManager.shared.play(.clipboard)
        guard isEnabled else { return }
        performer.perform(.generic, performanceTime: .now)
    }

    /// Thumbnail selected (tap)
    func thumbnailSelect() {
        guard isEnabled else { return }
        performer.perform(.alignment, performanceTime: .now)
    }

    func thumbnailSelected() { thumbnailSelect() }

    // MARK: - Drag & Drop

    func dragBegan() {
        guard isEnabled else { return }
        performer.perform(.levelChange, performanceTime: .now)
    }

    func dropCompleted() {
        guard isEnabled else { return }
        performer.perform(.alignment, performanceTime: .drawCompleted)
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
