import SwiftUI

// MARK: - NotchAnimation — Centralized spring parameters
//
// All animation values in one place for consistent tuning.
// Springs preserve velocity when interrupted — beziers don't.

enum NotchAnimation {

    // EXPAND: notch opens downward
    // response 0.35 = ~300ms perceived, not too fast
    // dampingFraction 0.75 = small organic overshoot, then settles
    static let expand = Animation.spring(response: 0.35, dampingFraction: 0.75)

    // COLLAPSE: notch closes back up
    // Faster than expand (lower response) — like closing a drawer
    // More damped (higher dampingFraction) — decisive close, no bounce
    static let collapse = Animation.spring(response: 0.25, dampingFraction: 0.88)

    // HOVER: micro-expand on cursor
    // Very fast, almost no bounce — must feel reactive, not animated
    static let hover = Animation.spring(response: 0.20, dampingFraction: 0.90)

    // CONTENT FADE-IN: content appears inside the notch
    // Spring (not bezier) so an interrupted appear reverses with velocity.
    // delay 0.06s = waits until shape is already mid-expansion
    // Without this delay the content "fights" the shape — looks amateur
    static let contentIn = Animation.spring(response: 0.32, dampingFraction: 0.85).delay(0.06)

    // CONTENT FADE-OUT: content disappears before the shape
    // Must finish BEFORE the shape starts collapsing
    static let contentOut = Animation.spring(response: 0.16, dampingFraction: 1.0)

    // CARD STAGGER: each thumbnail enters with increasing delay
    static func cardEntry(index: Int) -> Animation {
        .spring(response: 0.38, dampingFraction: 0.62)
        .delay(Double(index) * 0.045)  // 0ms, 45ms, 90ms, 135ms...
    }

    // HOVER ON THUMBNAIL: light scale
    static let thumbnailHover = Animation.spring(response: 0.22, dampingFraction: 0.72)

    // NEW SCREENSHOT INSERTED: slide from right
    static let newScreenshot = Animation.spring(response: 0.42, dampingFraction: 0.65)

    // SCREENSHOT BOUNCE: notch pulses when screenshot arrives
    static let bounce = Animation.spring(response: 0.18, dampingFraction: 0.5)

    // MARK: - Capture Notification (Dynamic Island style)

    // NOTIFICATION EXPAND: pill widens horizontally — visible overshoot
    static let notificationExpand = Animation.spring(response: 0.45, dampingFraction: 0.6)

    // NOTIFICATION THUMBNAIL: smooth slide-in (no bounce/scale)
    static let notificationThumbnail = Animation.spring(response: 0.32, dampingFraction: 0.72)

    // NOTIFICATION CONTENT FADE-IN: springs in just after the pill starts
    // widening (the sequence in NotchController supplies the delay)
    static let notificationContentIn = Animation.spring(response: 0.28, dampingFraction: 0.8)

    // NOTIFICATION CONTENT FADE-OUT: fast critically-damped spring —
    // disappears decisively, no bounce, blends if interrupted
    static let notificationContentOut = Animation.spring(response: 0.14, dampingFraction: 1.0)

    // NOTIFICATION CONTRACT: fast, decisive, no bounce
    static let notificationContract = Animation.spring(response: 0.30, dampingFraction: 0.82)

    // MARK: - To-do hugging panel (PRD §8)

    // CONTENT HUG: the hero spring — panel height, row enter/exit, and the
    // Completed section all share this ONE spring so container and content
    // visibly move together instead of racing each other (§8.3). Slightly
    // underdamped on purpose: the panel should feel alive, not utilitarian.
    static let contentHug = Animation.spring(response: 0.45, dampingFraction: 0.60)

    // HINT FADE: contextual shortcut hints and ⌘-held badges (§7.1/7.2).
    // Deliberately a different weight of motion from contentHug — quick and
    // light, never competing with the height/row animation (§8.4).
    static let hintFade = Animation.spring(response: 0.18, dampingFraction: 1.0)
}

// MARK: - Panel content entry (Marcello, 2026-07-26)
//
// The problem this solves: the expanded content used to fade in as ONE rigid
// slab — a single opacity/scale/blur over the whole block. While the notch
// silhouette morphed (width, height, corner fillet all springing), the content
// inside just... appeared, fully formed, and sat there. With small rows nobody
// noticed. With a 124pt meeting card it read as a static picture pasted into a
// moving frame: "the block with the call is kind of fixed there".
//
// The fix is phase-based rather than one-shot: each child resolves into place
// on its own slightly-delayed spring, overlapping the shape's motion instead of
// following it. Overlapping is the point — fully sequential phases read as a
// slideshow.
//
// Applies ONLY to the notch opening. Tab and mode switches stay a pure opacity
// crossfade, because a previous round of feedback was specifically that content
// sliding in on a tab switch looked wrong (FB2).

extension NotchAnimation {
    /// Stagger step. Small enough that four cards finish within the shape's own
    /// expansion, so the whole thing still reads as one gesture.
    static let contentStaggerStep: Double = 0.035

    /// Entry spring for one child of the expanded panel.
    /// Damping 0.82 sits in the "UI chrome" band — it settles cleanly, with no
    /// overshoot that would read as bouncy on a utilitarian card.
    static func contentEntry(index: Int) -> Animation {
        .spring(response: 0.34, dampingFraction: 0.82)
        .delay(0.05 + Double(min(index, 6)) * contentStaggerStep)
    }
}

// MARK: - Environment: has the notch finished opening?

private struct NotchContentAppearedKey: EnvironmentKey {
    /// True by default so anything rendered outside the notch (Settings,
    /// onboarding, previews) is simply visible and never waits on a flag it
    /// will not receive.
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var notchContentAppeared: Bool {
        get { self[NotchContentAppearedKey.self] }
        set { self[NotchContentAppearedKey.self] = newValue }
    }
}

extension View {
    /// Resolve this view into place as the notch opens, `index` positions
    /// behind the one before it. A no-op once the panel is already open, which
    /// is what keeps tab switches a clean crossfade.
    func notchEntry(index: Int) -> some View {
        modifier(NotchEntryModifier(index: index))
    }
}

private struct NotchEntryModifier: ViewModifier {
    let index: Int
    @Environment(\.notchContentAppeared) private var appeared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            // Rises the last few points into place. Small: this is a settle,
            // not an entrance.
            .offset(y: appeared || reduceMotion ? 0 : 10)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.97, anchor: .top)
            .animation(reduceMotion ? .easeOut(duration: 0.12)
                                    : NotchAnimation.contentEntry(index: index),
                       value: appeared)
    }
}
