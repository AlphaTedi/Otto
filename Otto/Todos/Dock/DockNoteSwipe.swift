import SwiftUI

// MARK: - Swipe a note to delete it (Marcello, 2026-10-17)
//
// Apple's list rows, on a trackpad: two fingers sideways slide the note left
// and a round red Delete comes up behind it, growing in as the row moves.
// Let go past half the button and the row rests open; short of that it slides
// back. A FULL swipe (past `DockState.swipeCommit`, with a tick as it crosses)
// stretches the button into a capsule and deletes on release. A click on the
// open row, Esc, or a swipe on another row closes it. Deleting is undoable
// for five seconds (⌘Z), as from the menu and ⌘⌫.

struct NoteSwipeDelete: View {
    /// The row's current slide (≤ 0).
    let offset: CGFloat
    let action: () -> Void

    var body: some View {
        let travel = -offset
        let committing = travel >= DockState.swipeCommit
        let progress = min(1, max(0, (travel - 8) / (DockState.swipeReveal - 8)))
        let side = NotchContainerMetrics.roundButton
        Button(action: action) {
            DockIcon(.delete, size: 18)
                .foregroundStyle(Color.white)
                .frame(width: committing ? max(side, travel - 14) : side, height: side)
                .background(Capsule(style: .circular).fill(Color(hex: "#FF5F57")))
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(DockPressStyle())
        .scaleEffect(0.5 + 0.5 * progress)
        .opacity(progress)
        .padding(.trailing, 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: committing)
        .accessibilityLabel(L10n.t("action.delete"))
    }
}
