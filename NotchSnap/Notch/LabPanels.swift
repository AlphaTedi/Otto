import SwiftUI
import AppKit

// MARK: - Lab: panels that hang BELOW the notch instead of inside it
//
// The experiment (Marcello's Figma, 2026-08-19): stop treating the notch as a
// container. It goes back to being a small always-there object that carries
// only meeting presence — icon on the left, "in 34'" on the right — and
// clicking it summons two panels that float in the middle of the screen and
// are visibly NOT part of it.
//
// Everything is drawn in the same transparent panel window that already
// exists, with real gaps between the pieces. That is what makes them read as
// separate objects: the desktop shows through the gaps, so there is nothing to
// fake. Three separate NSWindows would have to be moved, ordered and collapsed
// in lockstep for no visual gain.
//
// EVERY number the design cares about is in LabMetrics, in one place, because
// these are exactly the values that get retuned against the Figma file.

enum LabMetrics {
    /// Panel width. Both blocks share it — they are a column, not two shapes
    /// that happen to be near each other.
    static let blockWidth: CGFloat = 600

    /// From the bottom of the notch to the first panel. Big on purpose: this
    /// gap is the entire argument that the panels are not part of the notch.
    static let notchGap: CGFloat = 56
    /// Between the two panels.
    static let blockGap: CGFloat = 20

    static let blockRadius: CGFloat = 18
    static let blockPadding: CGFloat = 14

    /// The peeking cards behind the top meeting.
    static let stackOffset: CGFloat = 7
    static let stackInset: CGFloat = 14
    static let maxStackPeek = 2

    /// How long the alert waits before snoozing itself.
    static let autoSnoozeSeconds: Double = 25
}

private extension View {
    /// The shared surface both panels sit on.
    func labBlock() -> some View {
        self
            .frame(width: LabMetrics.blockWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LabMetrics.blockRadius, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LabMetrics.blockRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }
}

// MARK: - Auto-snoozing Snooze

/// Snooze that snoozes itself if you ignore it.
///
/// The alert opens the panel on its own, so it also has to be able to close
/// itself — an interruption that waits forever for a click is just a modal
/// with extra steps. The button fills over `LabMetrics.autoSnoozeSeconds` and
/// fires at the end, so the countdown IS the button rather than a separate
/// progress bar competing with it.
///
/// Hovering pauses it. Someone whose pointer is on the button is deciding, and
/// deciding must not be punished by having the thing decide for them.
struct AutoSnoozeButton: View {
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var hover = false
    @State private var fired = false

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.t("cal.snoozeShort"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hover ? DSColor.textPrimaryBright : DSColor.textSecondary)
            Keycap(text: "S", tone: .onDark, size: 9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            // The fill is the clock. It grows from the leading edge inside the
            // same capsule the label sits in, so there is one object here, not
            // a button with a progress bar bolted underneath it.
            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.13))
                    .frame(width: proxy.size.width * progress)
            }
        )
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(DSColor.panelBorder, lineWidth: 0.5)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { fire() }
        .onHover { hovering in
            hover = hovering
            // Pause, do not reset. Restarting the clock every time the pointer
            // crosses the button would make it effectively never fire.
            withAnimation(.linear(duration: 0.15)) { }
            if hovering { pause() } else { resume() }
        }
        .onAppear { resume() }
        .help(L10n.t("cal.snoozeAutoHint"))
    }

    private func pause() {
        // Freeze wherever it got to: re-asserting the current value with no
        // animation cancels the in-flight one at its present position.
        let now = progress
        withAnimation(.linear(duration: 0)) { progress = now }
    }

    private func resume() {
        guard !fired, progress < 1 else { return }
        let remaining = LabMetrics.autoSnoozeSeconds * Double(1 - progress)
        withAnimation(.linear(duration: remaining)) { progress = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, !hover, !fired else { return }
            fire()
        }
    }

    private func fire() {
        guard !fired else { return }
        fired = true
        action()
    }
}

// MARK: - Meeting block

/// The nearest meeting, with the rest of the day stacked behind it.
///
/// Collapsed, later meetings are two narrower slivers peeking out from under
/// the top card — the iOS notification-stack idea. It says "there is more"
/// using the cards themselves rather than a count, and clicking anywhere on
/// the stack opens the full list.
struct LabMeetingBlock: View {
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var expanded = false

    private var meetings: [DetectedMeeting] { calendar.upcomingToday }

    var body: some View {
        if meetings.isEmpty {
            EmptyView()
        } else if expanded {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(NotchAnimation.contentHug) { expanded = false }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .semibold))
                        Text(L10n.t("cal.showLess"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DSColor.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                    LabMeetingCard(meeting: meeting, isNext: index == 0)
                }
            }
            .padding(LabMetrics.blockPadding)
            .labBlock()
            .transition(.opacity)
        } else {
            ZStack(alignment: .top) {
                // Drawn FIRST so they sit behind, and in reverse order so the
                // furthest card is furthest back. Each is inset and pushed
                // down, which is the whole trick — no shadow, no label, just
                // enough of a sliver to say the deck is deeper than one.
                let peeks = min(LabMetrics.maxStackPeek, max(0, meetings.count - 1))
                ForEach(0..<peeks, id: \.self) { i in
                    let depth = CGFloat(peeks - i)
                    RoundedRectangle(cornerRadius: LabMetrics.blockRadius, style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: LabMetrics.blockRadius,
                                             style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                        )
                        .frame(width: LabMetrics.blockWidth - LabMetrics.stackInset * 2 * depth)
                        .offset(y: LabMetrics.stackOffset * depth)
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                }

                LabMeetingCard(meeting: meetings[0], isNext: true)
                    .padding(LabMetrics.blockPadding)
                    .labBlock()
            }
            // The stack is one target: clicking the visible card or the
            // slivers under it does the same thing, the way a notification
            // stack behaves.
            .contentShape(Rectangle())
            .onTapGesture {
                guard meetings.count > 1 else { return }
                withAnimation(NotchAnimation.contentHug) { expanded = true }
            }
            .transition(.opacity)
        }
    }
}

// MARK: - One meeting card

private struct LabMeetingCard: View {
    let meeting: DetectedMeeting
    var isNext: Bool = true

    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MeetingPlatformIcon(platform: meeting.platform,
                                hasVideo: meeting.videoURL != nil)
                .frame(width: 22, height: 22)
                .opacity(isNext ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(meeting.timeRangeLabel)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(isNext ? DSColor.CategoryPalette.amber
                                                : DSColor.textFaint)
                    Spacer(minLength: 8)
                    Text(countdown)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Text(meeting.title.isEmpty ? L10n.t("cal.untitled") : meeting.title)
                    .font(.system(size: DSFont.cardTitleSize, weight: .medium))
                    .foregroundStyle(isNext ? DSColor.textPrimaryBright : DSColor.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 3)

                HStack(alignment: .center, spacing: 8) {
                    if meeting.videoURL != nil {
                        LabJoinButton(showsShortcut: isNext) { join() }
                    }
                    // Only the meeting that opened the panel snoozes itself —
                    // a card further down the day has not interrupted anyone.
                    if isNext, calendar.activeAlert?.id == meeting.id {
                        AutoSnoozeButton(action: calendar.snooze)
                    }
                    Spacer(minLength: 8)
                    AvatarStack(
                        names: meeting.avatarNames,
                        emails: meeting.avatarEmails,
                        diameter: 24,
                        maxVisible: 3,
                        isMuted: !isNext,
                        ringColor: .black
                    )
                }
                .padding(.top, 10)
            }
        }
    }

    private var countdown: String {
        let m = meeting.minutesUntilStart
        if m <= 0 { return L10n.t("presence.now") }
        if m < 60 { return "\(L10n.t("presence.in")) \(m) min" }
        return "\(L10n.t("presence.in")) \(m / 60)h \(m % 60)m"
    }

    private func join() {
        guard let url = meeting.videoURL else { return }
        NSWorkspace.shared.open(CalendarStore.urlForJoining(url))
        NotchController.shared.attentionLeft()
    }
}

/// White, filled — the one primary action on screen.
private struct LabJoinButton: View {
    var showsShortcut: Bool = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(L10n.t("cal.join"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.primaryText)
                if showsShortcut {
                    Keycap(text: "\u{2318}\u{21A9}", tone: .onLight, size: 9)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(hover ? 1 : 0.92)))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
    }
}

// MARK: - The whole detached column

struct LabPanelsView: View {
    @ObservedObject private var controller = NotchController.shared
    @ObservedObject private var calendar = CalendarStore.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: LabMetrics.blockGap) {
            LabMeetingBlock()

            TodoTabView()
                .padding(LabMetrics.blockPadding)
                .labBlock()
        }
        .padding(.top, LabMetrics.notchGap)
        .frame(maxWidth: .infinity, alignment: .center)
        // The window has to be tall enough to hold the column, and the hover
        // zone has to match it or the notch collapses out from under the
        // panels the moment the pointer leaves the notch itself.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: LabColumnHeightKey.self,
                                       value: proxy.size.height)
            }
        )
        .onPreferenceChange(LabColumnHeightKey.self) { height in
            appState.labColumnHeight = height
        }
    }
}

struct LabColumnHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
