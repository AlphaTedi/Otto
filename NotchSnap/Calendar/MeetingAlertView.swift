import SwiftUI

// MARK: - MeetingAlertView — the self-opening meeting alert (calendar PRD §3.2)
//
// This is MeetingCard in its `.alert` variant, nothing more.
//
// It used to be a second, hand-built card: filled background, plain (non-
// squircle) corners, a blue Join button, the avatar stack on top and the
// platform as trailing text. So the card that opened by itself two minutes
// before a meeting looked like it came from a different product than the ones
// the user had been reading in Today all morning (Marcello, 2026-08-05).
//
// Collapsing it into the shared component is both the fix and the guarantee:
// there is no longer a second place for the design to drift to. Anything the
// alert needs that a listed card does not — the Snooze button, a countdown
// that leads — lives in the variant, not in a parallel view.

struct MeetingAlertView: View {
    let meeting: DetectedMeeting
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        MeetingCard(event: meeting,
                    isNext: true,
                    variant: .alert,
                    onSnooze: calendar.snooze)
    }
}

// MARK: - AmbientMeetingDot — the passive signal on the collapsed pill (CA-2)

struct AmbientMeetingDot: View {
    var body: some View {
        Circle()
            .fill(DSColor.CategoryPalette.amber)
            .frame(width: 6, height: 6)
            .shadow(color: DSColor.CategoryPalette.amber.opacity(0.6), radius: 3)
            .transition(.opacity.combined(with: .scale(scale: 0.5)))
    }
}
