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
    // Straight from the Figma CSS export (node 1098-4805). Not measured off a
    // render this time — every number below is quoted, which is why the panel
    // is 657 and not the 592 two rounds of pixel-reading produced.

    /// THE accent. One cyan for every checkbox and the active tab, replacing
    /// the per-section colours those used to take. Stated as the source of
    /// truth, superseding the purple explored earlier.
    static let accent = Color(hex: "#10EFF2")

    static let blockWidth: CGFloat = 657
    static let blockRadius: CGFloat = 40
    /// 16 top, nothing on the other sides — the children carry their own.
    static let panelTopPadding: CGFloat = 16
    /// Between the creation-bar block and the list block.
    static let sectionGap: CGFloat = 16

    // Creation bar
    static let barOuterInset: CGFloat = 16     // the wrapper's 0 16px
    static let barPaddingH: CGFloat = 20
    static let barPaddingV: CGFloat = 12
    static let barRadius: CGFloat = 24
    static let barHeight: CGFloat = 59
    static let barInnerGap: CGFloat = 6

    // Checkboxes — one size everywhere now, bar and rows alike
    static let checkboxSize: CGFloat = 18
    static let checkboxStroke: CGFloat = 2
    static let checkboxRadius: CGFloat = 6

    // List
    static let listInset: CGFloat = 24
    /// Tightened from the export's 6. The rows were reading far too far
    /// apart against the previous build, and the gap plus the label's own box
    /// were compounding.
    static let listRowGap: CGFloat = 2
    static let rowPaddingH: CGFloat = 12
    static let rowInnerGap: CGFloat = 6
    /// 4, not the export's 8. Two 8s stack into 16pt of air inside every
    /// single-line row, which is where most of the distance was coming from.
    static let rowTextInset: CGFloat = 4
    /// The list fades out before it reaches the tabs underneath.
    static let listFadeHeight: CGFloat = 54

    // Section tabs, now at the BOTTOM
    static let tabsInset: CGFloat = 24
    static let tabsDividerPaddingV: CGFloat = 12
    static let tabsTopPadding: CGFloat = 8
    static let tabsBottomPadding: CGFloat = 24
    static let tabsGap: CGFloat = 14
    static let tabPaddingH: CGFloat = 12
    static let tabPaddingV: CGFloat = 8
    /// Active is a full pill, inactive is barely rounded. The asymmetry is
    /// deliberate — it is what makes the active one read as selected rather
    /// than merely tinted.
    static let tabActiveRadius: CGFloat = 48
    static let tabInactiveRadius: CGFloat = 8
    static let avatarSize: CGFloat = 24

    /// The to-do panel STOPS. 556 is the drawn height.
    static let todoBlockMaxHeight: CGFloat = 556

    /// From the bottom of the notch to the first panel.
    static let notchGap: CGFloat = 72
    /// Between the two panels.
    static let blockGap: CGFloat = 24
    static let blockPadding: CGFloat = 16
    static let meetingRadius: CGFloat = 32

    /// CONCENTRIC CORNERS. An inner radius must be the outer one minus the gap
    /// between them, or the two curves are not parallel and the inner box
    /// visibly fights the corner it sits in.
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }

    /// The deck behind the top meeting.
    static let stackOffset: CGFloat = 6
    static let stackScaleStep: CGFloat = 0.04
    static let maxStackPeek = 2
    static let stackExpandedGap: CGFloat = 8
    static let meetingBlockMaxHeight: CGFloat = 300

    /// How long the alert waits before snoozing itself.
    static let autoSnoozeSeconds: Double = 25

    // The drop shadow, and the room it needs.
    //
    // 44 was not enough and the halo was still being sliced. A SwiftUI shadow
    // RADIUS is a blur sigma, not an extent — the visible falloff reaches
    // roughly three times it, so a 24pt shadow was still painting 70pt out
    // and meeting a hard window edge, which reads as a cropped black band
    // rather than as a shadow at all.
    //
    // So the shadow is softer AND the margin is computed from it rather than
    // typed beside it. The two cannot drift apart, and if the shadow is ever
    // retuned the window follows on its own.
    static let shadowRadius: CGFloat = 18
    static let shadowOffsetY: CGFloat = 8
    static let shadowMargin: CGFloat = shadowRadius * 3 + shadowOffsetY   // 62
}

private extension View {
    /// The shared surface both panels sit on.
    func labBlock(radius: CGFloat = LabMetrics.blockRadius) -> some View {
        self
            .frame(width: LabMetrics.blockWidth, alignment: .leading)
            // Glass, not a black fill. A black panel on a dark desktop has no
            // edge to find; what separates glass from what is behind it is the
            // blur and the lit rim, which work at any background brightness.
            .liquidGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            // The shadow stays and matters MORE on glass: a translucent panel
            // needs the ground shadow to sit above the desktop rather than
            // dissolve into it.
            .shadow(color: .black.opacity(0.40),
                    radius: LabMetrics.shadowRadius, y: LabMetrics.shadowOffsetY)
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
    /// Whether the fill runs and fires on its own. False on a card the user
    /// opened deliberately — nothing there has interrupted them, so nothing
    /// there should time out.
    var countsDown: Bool = true
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
                    .fill(Color.dynamicOverlay(light: 0.10, dark: 0.13))
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
        guard countsDown, !fired, progress < 1 else { return }
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
            VStack(alignment: .trailing, spacing: LabMetrics.stackExpandedGap) {
                // Apple puts the control above the opened stack, on the right.
                Button {
                    withAnimation(NotchAnimation.contentHug) { expanded = false }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.t("cal.showLess"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous)
                        .fill(Color.dynamicOverlay(light: 0.09, dark: 0.12)))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                // Each meeting is its OWN card with air between, exactly as an
                // opened notification stack becomes a list of notifications —
                // not one container that happens to hold several rows.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: LabMetrics.stackExpandedGap) {
                        ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                            LabMeetingCard(meeting: meeting, isNext: index == 0)
                                .padding(LabMetrics.blockPadding)
                                .labBlock(radius: LabMetrics.meetingRadius)
                        }
                    }
                }
                .frame(maxHeight: LabMetrics.meetingBlockMaxHeight)
            }
            .frame(width: LabMetrics.blockWidth, alignment: .trailing)
            .transition(.opacity)
        } else {
            LabMeetingCard(meeting: meetings[0], isNext: true)
                .padding(LabMetrics.blockPadding)
                .labBlock(radius: LabMetrics.meetingRadius)
                // The deck, drawn as the card's BACKGROUND rather than as
                // siblings in a ZStack.
                //
                // That placement is the fix, not a detail: a background is
                // handed the card's own frame, so the rounded rects get a
                // definite height. As ZStack siblings they had a width and no
                // height, and a Shape with no height is greedy — it grew to
                // fill the window and painted the screen black (Marcello,
                // 2026-08-19).
                //
                // Scaled from the TOP so they stay pinned under the card's top
                // edge and only their bottom sliver shows, then nudged down —
                // the lock-screen stack, where the deck reads as depth rather
                // than as a list you have to parse.
                .background(alignment: .top) {
                    ForEach(0..<peekCount, id: \.self) { i in
                        let depth = CGFloat(i + 1)
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(
                                cornerRadius: LabMetrics.meetingRadius, style: .continuous))
                            .scaleEffect(1 - LabMetrics.stackScaleStep * depth, anchor: .top)
                            .offset(y: LabMetrics.stackOffset * depth)
                            .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
                            // Furthest back, furthest down the z-order.
                            .zIndex(-depth)
                    }
                }
                // One target: the visible card and the slivers under it do the
                // same thing, the way a notification stack behaves.
                .contentShape(Rectangle())
                .onTapGesture {
                    guard meetings.count > 1 else { return }
                    withAnimation(NotchAnimation.contentHug) { expanded = true }
                }
                .transition(.opacity)
        }
    }

    private var peekCount: Int {
        min(LabMetrics.maxStackPeek, max(0, meetings.count - 1))
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
                    // ALWAYS. A meeting with no video link had a Join button
                    // and nothing else, so its card sat visibly empty on the
                    // left and there was no way to dismiss it at all — a plain
                    // "Lunch" placeholder could not be told to go away
                    // (Marcello, 2026-08-22).
                    //
                    // The countdown fill is a different matter: it only runs
                    // on the meeting that actually interrupted, or every card
                    // on screen would quietly snooze itself after 25 seconds.
                    AutoSnoozeButton(
                        countsDown: calendar.activeAlert?.id == meeting.id
                    ) { calendar.snooze(meeting) }
                    Spacer(minLength: 8)
                    AvatarStack(
                        names: meeting.avatarNames,
                        emails: meeting.avatarEmails,
                        diameter: 24,
                        maxVisible: 3,
                        isMuted: !isNext,
                        // The ring separates overlapping discs, so it has to be
                        // whatever is actually behind them — glass, not black.
                        ringColor: Color.dynamicOverlay(light: 0.10, dark: 0.10)
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
                    // .onLight because it sits on primaryFill, which is the
                    // INVERSE of the appearance — a light chip in Dark and a
                    // dark one in Light. The tone tracks the button, not the
                    // system.
                    Keycap(text: "\u{2318}\u{21A9}", tone: .onLight, size: 9)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous)
                .fill(DSColor.primaryFill.opacity(hover ? 1 : 0.92)))
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

            // No padding here: TodoTabView carries its own, to the same
            // number. Applying both is what made the panel's insets read as
            // roughly twice the design.
            // FIXED height, not a maximum.
            //
            // As a maximum the panel shrank to its content, so the tab bar
            // rose and fell with however many to-dos a section happened to
            // hold — the one row that must never move, moving most. The panel
            // is 556 whatever is in it; the list takes the slack.
            TodoTabView()
                .frame(height: LabMetrics.todoBlockMaxHeight, alignment: .top)
                .labBlock()
        }
        .padding(.top, LabMetrics.notchGap)
        .padding(.bottom, LabMetrics.shadowMargin)
        .padding(.horizontal, LabMetrics.shadowMargin)
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
