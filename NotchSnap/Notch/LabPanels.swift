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
    /// 6, per the export — rows are 37 tall on a 43pt pitch. At 2 the rows
    /// were 37 tall but nearly touching, which is the other half of why the
    /// spacing "looked off".
    static let listRowGap: CGFloat = 6
    static let rowPaddingH: CGFloat = 12
    /// Between a row's checkbox and its text. 6 read as the two touching;
    /// the checkbox is 18pt and needs air to be its own object.
    static let rowInnerGap: CGFloat = 12
    /// 4, not the export's 8. Two 8s stack into 16pt of air inside every
    /// single-line row, which is where most of the distance was coming from.
    static let rowTextInset: CGFloat = 4
    /// The list fades out before it reaches the tabs underneath.
    /// The trailing affordances on a row: ⏎ in its own box, a hairline, then
    /// the grip, hard against the right edge.
    static let rowActionGap: CGFloat = 6
    /// A row is 37 tall with an 18pt checkbox, so the checkbox gets 9.5 above
    /// and below against 12 either side — near enough to read as even. Letting
    /// the height fall out of the text instead is what left the checkbox
    /// touching top and bottom while it had 12pt of air left and right.
    static let rowMinHeight: CGFloat = 37
    static let rowRadius: CGFloat = 12
    /// ⏎ badge: 23x18, 1pt border, radius 6.
    static let enterBadgeWidth: CGFloat = 23
    static let enterBadgeHeight: CGFloat = 18
    static let enterBadgeRadius: CGFloat = 6
    /// Grip: 3pt dots, 2pt apart, in a 16pt box.
    static let gripDot: CGFloat = 3
    static let gripGap: CGFloat = 2
    static let gripBox: CGFloat = 16
    /// The trailing gutter, RESERVED on every row whether anything is drawn in
    /// it or not: badge 23 + 6 + rule 1 + 6 + grip 16. Held open permanently
    /// so the title's width never changes — see the comment at its use.
    static let rowActionsWidth: CGFloat = 52

    // Section tabs, now at the BOTTOM
    static let tabsInset: CGFloat = 24
    static let tabsDividerPaddingV: CGFloat = 12
    static let tabsTopPadding: CGFloat = 8
    // 24 → 16: with the block hugging, the foot read as a slab of empty
    // glass under the tabs (Thomas, 2026-09-01).
    static let tabsBottomPadding: CGFloat = 16
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
    /// The collapsed Completed row: chevron, label, count.
    static let completedHeaderHeight: CGFloat = 24
    /// How far the pinned Completed section may grow before it scrolls on its
    /// own. Enough for a handful of rows — the archive is a record, not a
    /// second list to work in.
    static let completedExpandedMaxHeight: CGFloat = 160

    /// From the bottom of the notch to the first panel.
    static let notchGap: CGFloat = 72
    /// Between the two panels.
    static let blockGap: CGFloat = 24
    /// 24, matching `listInset` — the to-do panel's own side spacing.
    ///
    /// At 16 the meeting card's contents sat 8pt closer to the edge than the
    /// list did directly below it, and against a 32pt corner that reads as the
    /// two blocks being built to different rules (Marcello, 2026-08-23).
    static let blockPadding: CGFloat = 24
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
    /// 25 was long enough that an alert nobody wanted sat there being
    /// ignored (Marcello, 2026-09-06). Long enough to read a meeting title
    /// and decide, not long enough to become furniture.
    static let autoSnoozeSeconds: Double = 15

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
            .shadow(color: DSColor.shadowStrong,
                    radius: LabMetrics.shadowRadius, y: LabMetrics.shadowOffsetY)
    }
}

/// The stack's tap target, present only when tapping it would do something.
private struct StackTapGesture: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        } else {
            content
        }
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
    /// Whether this card's Snooze shows a running countdown. False on a card
    /// the user opened deliberately — nothing there has interrupted them, so
    /// nothing there should time out.
    var countsDown: Bool = true
    let action: () -> Void

    @ObservedObject private var calendar = CalendarStore.shared
    /// The fill, 0...1 — PRESENTATION only. It is written once per resume and
    /// animated to 1, so reading it back tells you nothing about how much time
    /// is left: `withAnimation` sets the value immediately and interpolates
    /// only the drawing. The old code did read it back, which is why one pass
    /// of the pointer over this button filled the capsule instantly and
    /// stopped the clock for good.
    @State private var progress: CGFloat = 0
    @State private var hover = false

    var body: some View {
        // A Button, not `.onTapGesture`.
        //
        // This is why Snooze "did not take the click the first or second time"
        // while Join, right beside it, always worked: Join is a Button and
        // this was a bare tap gesture sitting under an ancestor that claimed
        // the whole card as its own tap target. Two peer tap gestures over one
        // point resolve unpredictably; a Button's press gesture takes
        // precedence over an ancestor's (Marcello, 2026-09-06).
        Button(action: action) {
            HStack(spacing: 6) {
                Text(L10n.t("cal.snoozeShort"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hover ? DSColor.textPrimaryBright : DSColor.textSecondary)
                Keycap(text: "S", tone: .onDark, size: 9)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                // The fill is the clock. It grows from the leading edge inside
                // the same capsule the label sits in, so there is one object
                // here, not a button with a progress bar bolted underneath it.
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
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hover = hovering
            guard countsDown else { return }
            // Pause, do not reset. Restarting the clock every time the pointer
            // crossed the button would make it effectively never fire.
            if hovering { calendar.pauseAutoSnooze() } else { calendar.resumeAutoSnooze() }
        }
        // The store owns the deadline; this only draws it. Mirror whatever it
        // is doing now, and again whenever it starts or stops.
        .onAppear { syncFill() }
        .onChange(of: calendar.autoSnoozeRunning) { _ in syncFill() }
        .help(L10n.t("cal.snoozeAutoHint"))
    }

    /// Drive the fill to match the store's clock: animate to full over
    /// whatever is left while it runs, freeze where it got to while it does
    /// not.
    private func syncFill() {
        guard countsDown else { return }
        let elapsed = 1 - CGFloat(calendar.autoSnoozeRemaining / LabMetrics.autoSnoozeSeconds)
        if calendar.autoSnoozeRunning {
            withAnimation(.linear(duration: 0)) { progress = elapsed }
            withAnimation(.linear(duration: calendar.autoSnoozeRemaining)) { progress = 1 }
        } else {
            withAnimation(.linear(duration: 0)) { progress = elapsed }
        }
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

    var body: some View {
        // ONE snapshot per evaluation, and this is a crash fix, not tidying.
        //
        // `upcomingToday` re-filters `meetings` against a FRESH `Date()` on
        // every single access, and this body read it four times: once for
        // isEmpty, once to subscript [0], twice for the peek count. A meeting
        // whose end passed between the isEmpty check and the subscript left
        // the array empty and `[0]` trapped — the app died on opening the
        // notch, at exactly the moment a meeting was ending (Marcello,
        // 2026-08-22, with a 12:00-13:00 event).
        //
        // Invisible on a Mac with no meetings, which is every test run here:
        // an empty list always takes the isEmpty branch and never reaches the
        // subscript at all.
        let list = calendar.upcomingToday
        content(for: list)
    }

    @ViewBuilder
    private func content(for meetings: [DetectedMeeting]) -> some View {
        // `.first` rather than `[0]`, so even a snapshot that is somehow empty
        // renders nothing instead of trapping.
        if let next = meetings.first {
            body(for: meetings, next: next)
        }
    }

    @ViewBuilder
    private func body(for meetings: [DetectedMeeting], next: DetectedMeeting) -> some View {
        if expanded {
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
            LabMeetingCard(meeting: next, isNext: true)
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
                    ForEach(0..<peekCount(meetings), id: \.self) { i in
                        let depth = CGFloat(i + 1)
                        // A FLAT fill, not glass.
                        //
                        // Each of these used to be its own glass surface,
                        // stacked directly under another one — and glass
                        // cannot sample glass, so they sampled the card above
                        // them and came out inconsistent with it. They also
                        // cost a backdrop layer each (three offscreen textures
                        // apiece) to render a 4pt sliver that is 96% hidden.
                        // A fill is indistinguishable here and free.
                        RoundedRectangle(cornerRadius: LabMetrics.meetingRadius,
                                         style: .continuous)
                            // The slivers are the same object as the card in
                            // front of them, seen from further back — so they
                            // deepen the appearance rather than being black.
                            // On a light panel a black sliver read as a shadow
                            // cast by nothing.
                            // `depth` is a CGFloat because the scale and offset
                            // below need one; `opacity` wants a Double, and the
                            // literal on its own left the compiler unable to
                            // choose. Stated rather than inferred.
                            .fill(DSColor.stackedCardFill.opacity(Double(1 - 0.22 * depth)))
                            .overlay(
                                RoundedRectangle(cornerRadius: LabMetrics.meetingRadius,
                                                 style: .continuous)
                                    .strokeBorder(DSColor.hairlineOnPanel, lineWidth: 1)
                            )
                            .scaleEffect(1 - LabMetrics.stackScaleStep * depth, anchor: .top)
                            .offset(y: LabMetrics.stackOffset * depth)
                            .shadow(color: DSColor.shadowSoft, radius: 8, y: 3)
                            // Furthest back, furthest down the z-order.
                            .zIndex(-depth)
                    }
                }
                // One target: the visible card and the slivers under it do the
                // same thing, the way a notification stack behaves.
                //
                // Installed ONLY when there is a deck to open. It used to be
                // unconditional with a `guard meetings.count > 1` inside, so
                // on the ordinary single-meeting card there was a full-card
                // tap target that swallowed clicks and did nothing with them —
                // and `contentShape(Rectangle())` here covers the buttons.
                // A gesture that competes with the controls it sits over and
                // then declines to act is the worst of both.
                .modifier(StackTapGesture(enabled: meetings.count > 1) {
                    withAnimation(NotchAnimation.contentHug) { expanded = true }
                })
                .transition(.opacity)
        }
    }

    private func peekCount(_ meetings: [DetectedMeeting]) -> Int {
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
            // NO height frame at all: the block is its content's height.
            //
            // It was pinned at 556 for a while so the tab bar never moved
            // between sections — but that left a three-item list floating in
            // mostly empty glass, and hugging is the product's own second
            // principle. Restored by explicit call (Thomas, 2026-09-01).
            //
            // Not even `.frame(maxHeight: 556)`: in SwiftUI a max frame is
            // "grow to this if the parent offers it", exactly as
            // `maxWidth: .infinity` claims the width — so with the column
            // proposing the whole window the block still drew 556 with the
            // list top-aligned inside it (Thomas's screenshot, 2026-09-01).
            // The ceiling lives where it can be enforced without stretching:
            // the scroll region's own budget (TodoBrowsingView.maxRegion),
            // which is derived from todoBlockMaxHeight.
            // While an alert is live the card is ALONE.
            //
            // The notch opened itself for the meeting; putting the whole to-do
            // panel under it makes the user find the one thing that summoned
            // it. It also removes the duplicate: the panel used to draw its
            // own copy of the alert card inside itself, so the same meeting
            // appeared twice, once above the other (Marcello, 2026-08-23).
            if calendar.activeAlert == nil, !calendar.alertLeaving {
                TodoTabView()
                    // FIXED, in the floating panels only.
                    //
                    // This reverses a deliberate change (Thomas, 2026-09-01,
                    // "Hug the block itself"), and the reasoning behind that
                    // one still holds where it applies: inside the notch the
                    // silhouette IS the window, so a half-empty block is
                    // half-empty glass and hugging is right.
                    //
                    // A floating panel is a different object. It is a card on
                    // the desktop, and a card that changes size every time you
                    // look at a different section moves the tabs, the foot and
                    // its own shadow with it — which is what Marcello asked to
                    // stop (2026-09-05). Hugging stays in the container, where
                    // it belongs.
                    //
                    // A definite height, not `maxHeight`: a max frame is "grow
                    // to this if offered", which is exactly what drew the block
                    // at 556 with the list stranded at the top of it.
                    .frame(height: LabMetrics.todoBlockMaxHeight, alignment: .top)
                    .labBlock()
                    .transition(.opacity)
            }
        }
        .animation(NotchAnimation.contentHug, value: calendar.activeAlert?.id)
        // The two panels are neighbours, so they sample as one.
        //
        // Without this each block opens its own sampling region and the two
        // can resolve differently over the same desktop — the meeting card
        // reading a shade apart from the to-do panel directly beneath it. The
        // spacing matches the gap between them so the container knows how near
        // "near" is.
        .glassGroup(spacing: LabMetrics.blockGap)
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
