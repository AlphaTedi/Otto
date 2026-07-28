import SwiftUI

// MARK: - MeetingAlertView — the self-opening meeting alert (calendar PRD §3.2)
//
// The one screen in the app that is meant to grab attention: the title is
// 15pt semibold, larger than anything in the normal UI. Everything else still
// comes from DesignSystem so it reads as the same app.

struct MeetingAlertView: View {
    let meeting: DetectedMeeting
    @ObservedObject private var calendar = CalendarStore.shared

    /// Amber — the same color the ambient dot and the "next event" accent use.
    private var accent: Color { DSColor.CategoryPalette.amber }

    var body: some View {
        // §3.2 corrected design: a real card — avatar stack + platform label
        // on top, then title, countdown, actions. The previous dot-and-text
        // stack read as generic/AI-templated; the stripe is gone entirely.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                AvatarStack(names: meeting.avatarNames,
                            emails: meeting.avatarEmails,
                            diameter: 24, maxVisible: 3)
                if let count = meeting.participantCountLabel {
                    Text(count)
                        .font(.system(size: 10))
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.leading, 2)
                }
                Spacer(minLength: 8)
                if let platform = meeting.platform {
                    Text(platform)
                        .font(.system(size: 10))
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.bottom, 10)

            Text(meeting.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textPrimaryBright)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

            // Information, not decoration — small amber text, no badge.
            Text(countdownLabel)
                .font(.system(size: 12))
                .foregroundStyle(accent)

            // The surrounding detail: full span, then who or where.
            HStack(spacing: 4) {
                Text(meeting.timeRangeLabel)
                    .monospacedDigit()
                if !meeting.contextLabel.isEmpty {
                    Text("\u{00B7}")
                    Text(meeting.contextLabel).lineLimit(1)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.top, 3)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                if meeting.videoURL != nil {
                    Button(action: calendar.join) {
                        Text(L10n.t("cal.join"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DSShape.action.fill(DSColor.focusAccent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: calendar.snooze) {
                    Text(String(format: L10n.t("cal.snooze"), calendar.snoozeMinutes))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#999999"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(DSShape.action.strokeBorder(DSColor.panelBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DSColor.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DSColor.panelBorder, lineWidth: 0.5)
        )
    }

    private var countdownLabel: String {
        let minutes = meeting.minutesUntilStart
        if minutes <= 0 { return L10n.t("cal.startingNow") }
        return String(format: L10n.t("cal.startingIn"), minutes)
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
