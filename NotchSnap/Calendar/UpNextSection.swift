import SwiftUI

// MARK: - UpNextSection — meetings inside the Today tab (calendar PRD §4)
//
// No section headers and no empty-state line (Marcello, 2026-07-26): the Today
// tab is just today's meetings followed by today's to-dos. A meeting card and
// a to-do row look nothing alike, so "UP NEXT" / "TO-DOS" were labelling
// something the eye already separates — and "No more meetings today" was a
// sentence to read every time nothing was happening. This supersedes CT-3/CT-4.

struct UpNextSection: View {
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        let events = calendar.upcomingToday
        if calendar.isConnected, !events.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(events.prefix(4).enumerated()), id: \.element.id) { index, event in
                    MeetingCard(event: event, isNext: index == 0)
                        .notchEntry(index: index + 1)
                }
            }
            .padding(.bottom, 16)
            .transition(.opacity)
        } else if !calendar.isConnected {
            // SU-6/SU-7: the in-notch discovery path, gone for good once
            // connected. This one stays — it is an action, not a label.
            CalendarNudgeCard()
                .padding(.bottom, 14)
                .transition(.opacity)
        }
        // Connected with nothing left today: render nothing at all.
    }
}

// MARK: - MeetingCard — the calendar event (Marcello's sketch, 2026-07-26)
//
// Built to his design, which fixes the element positions exactly:
//
//   ┌─────────────────────────────────────────────────────────┐
//   │  [icon]  9:30 PM - 10:30 PM              in 34 min       │
//   │          Design feedback session                         │
//   │          ( Join )                          (o)(o)(o)(+2) │
//   └─────────────────────────────────────────────────────────┘
//
// The icon sits in its own column; everything else — time, title, Join, and
// the avatar stack — shares the second column, which is why Join lines up
// under the title rather than under the icon.
//
// Sizes are derived from the sketch's proportions scaled to the panel's real
// content width (~616pt at the default 680pt panel). They are NOT from the
// Figma file: the Dev Mode MCP server was off, so exact tokens could not be
// read. If it gets enabled, re-check the numbers marked "sketch-derived".

struct MeetingCard: View {
    /// The same card in two situations. The alert used to be a SEPARATE view
    /// with its own filled background, plain (non-squircle) corners, a blue
    /// Join button and a different element order — so the thing that appears
    /// two minutes before a meeting looked like it came from another app than
    /// the list you had been reading all morning (Marcello, 2026-08-05).
    /// One component, one look; the variant only adds Snooze and leads with
    /// the countdown.
    enum Variant {
        case listed
        case alert
    }

    let event: DetectedMeeting
    /// Later events in the day are dimmed rather than restyled, so the list
    /// still reads as one component (CT-2).
    var isNext: Bool = true
    var variant: Variant = .listed
    /// Supplied by the alert only.
    var onSnooze: (() -> Void)? = nil
    @State private var hover = false

    // Sized against the panel's OWN scale, not the sketch's canvas: a to-do
    // title is 13pt and a tab label is 11pt, so a meeting title at 20pt made
    // the card "look huge compared to the rest of the interface"
    // (Marcello, 2026-07-26). The card is still the heaviest thing in the
    // list — it just no longer belongs to a different app.
    private let iconSize: CGFloat = 16
    // 24, matching the meeting alert. At 18 the "+N" overflow disc rendered a
    // ~6pt glyph — present but unreadable (Marcello, 2026-07-26).
    private let avatarSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MeetingPlatformIcon(platform: event.platform, hasVideo: event.videoURL != nil)
                .frame(width: iconSize, height: iconSize)
                .padding(.top, 1)
                .opacity(isNext ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.timeRangeLabel)
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(isNext ? DSColor.CategoryPalette.amber
                                                : DSColor.textFaint)
                    Spacer(minLength: 8)
                    // The alert leads with the countdown — it is the reason
                    // the panel opened by itself — but in the same slot and at
                    // the same size as the list's, so the card is recognisably
                    // the same object.
                    Text(countdownLabel)
                        .font(.system(size: 11,
                                      weight: variant == .alert ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(variant == .alert ? DSColor.CategoryPalette.amber
                                                           : DSColor.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Text(event.title.isEmpty ? L10n.t("cal.untitled") : event.title)
                    // One step ABOVE a to-do row: the card is a single item
                    // that has to carry, the rows are many.
                    .font(.system(size: DSFont.cardTitleSize, weight: .medium))
                    .foregroundStyle(isNext ? DSColor.textPrimaryBright : DSColor.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)

                HStack(alignment: .center, spacing: 8) {
                    // JOIN only exists when there is actually a link to open —
                    // a dead button would be worse than no button.
                    if event.videoURL != nil {
                        JoinButton(showsShortcut: isNext) { open() }
                    }
                    if let onSnooze {
                        SnoozeButton(minutes: CalendarStore.shared.snoozeMinutes,
                                     action: onSnooze)
                    }
                    Spacer(minLength: 8)
                    AvatarStack(
                        names: event.avatarNames,
                        emails: event.avatarEmails,
                        diameter: avatarSize,
                        maxVisible: 3,          // 3 faces, then one "+N" disc
                        isMuted: !isNext,
                        // The ring exists to separate overlapping discs, so it
                        // has to be whatever is actually behind them. With the
                        // card's fill removed that is the panel, not the old
                        // field colour — otherwise each avatar wears a halo.
                        ringColor: DSColor.panelBackground
                    )
                }
                .padding(.top, 9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Outline only — no fill (Marcello, 2026-07-26). The card sits
        // directly on the panel, so hover is carried by the stroke alone.
        .contentShape(DSShape.squircle(DSRadius.controlCorner))
        .overlay(
            DSShape.squircle(DSRadius.controlCorner)
                .strokeBorder(DSColor.panelBorder.opacity(hover ? 1 : 0.55), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        .help(event.subtitle.isEmpty ? event.title : "\(event.title) — \(event.subtitle)")
    }

    private func open() {
        if let url = event.videoURL { NSWorkspace.shared.open(url) }
    }

    /// Short form for the top-right corner: "in 34 min" / "in 2h 10m" / "now".
    /// Long meetings later in the day would otherwise read "in 380 min".
    private var countdownLabel: String {
        let minutes = event.minutesUntilStart
        if variant == .alert {
            // Spelled out, because this card arrives unannounced and has to
            // say what is happening on its own.
            return minutes <= 0
                ? L10n.t("cal.startingNow")
                : String(format: L10n.t("cal.startingIn"), minutes)
        }
        if minutes <= 0 { return L10n.t("cal.now") }
        if minutes < 60 { return String(format: L10n.t("cal.inMinutes"), minutes) }
        return String(format: L10n.t("cal.inHours"), minutes / 60, minutes % 60)
    }
}

// MARK: - JoinButton

/// The same control as Create, in compact form — not a one-off blue pill.
/// It was the only blue button in the app (Marcello, 2026-07-26).
private struct JoinButton: View {
    /// Only the next meeting advertises the shortcut, because ⌘↩ joins THAT
    /// meeting; showing it on every card would promise something false.
    var showsShortcut: Bool = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            PrimaryActionButton(
                title: L10n.t("cal.join"),
                shortcutHint: showsShortcut ? "\u{2318}\u{21A9}" : "",
                fillsWidth: false,
                isCompact: true
            )
            .opacity(hover ? 0.85 : 1)
            .contentShape(DSShape.action)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        .help(L10n.t("cal.joinHelp"))
    }
}

// MARK: - SnoozeButton

/// Join's quiet sibling. Same capsule and the same compact metrics, outlined
/// instead of filled — the alert offers two ways out and only one of them is
/// the point.
private struct SnoozeButton: View {
    let minutes: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(String(format: L10n.t("cal.snooze"), minutes))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hover ? DSColor.textPrimaryBright : DSColor.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .overlay(DSShape.action.strokeBorder(DSColor.panelBorder,
                                                     lineWidth: 0.5))
                .contentShape(DSShape.action)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
    }
}

// MARK: - CalendarNudgeCard (SU-6)

private struct CalendarNudgeCard: View {
    @State private var hover = false

    var body: some View {
        Button {
            SettingsWindowController.showCalendarTab()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(DSColor.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("cal.nudgeTitle"))
                        .font(DSFont.checklistItem)
                        .foregroundStyle(Color(hex: "#CCCCCC"))
                    Text(L10n.t("cal.nudgeSubtitle"))
                        .font(.system(size: 10))
                        .foregroundStyle(DSColor.textFaint)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textHint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                DSShape.squircle(DSRadius.controlCorner)
                    .fill(hover ? DSColor.focusedRowBackground : DSColor.fieldBackground)
            )
            // Dashed border — the app's convention for "not yet configured".
            .overlay(
                DSShape.squircle(DSRadius.controlCorner)
                    .strokeBorder(Color(hex: "#3A3A3A"),
                                  style: StrokeStyle(lineWidth: 0.5, dash: [3, 2.5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - MeetingPlatformIcon
//
// The platform's own mark, drawn as vectors so it stays crisp at any size and
// carries no bundled binary.
//
// IMPORTANT: these are hand-built approximations of the brand marks, not the
// official artwork. To use the real logos, drop images named
// `platform-meet`, `platform-zoom`, or `platform-teams` into
// Assets.xcassets — this view prefers a bundled asset whenever one exists, so
// no code has to change.

struct MeetingPlatformIcon: View {
    let platform: String?
    var hasVideo: Bool = true

    private var slug: String? {
        guard let platform = platform?.lowercased() else { return nil }
        if platform.contains("meet") { return "meet" }
        if platform.contains("zoom") { return "zoom" }
        if platform.contains("teams") { return "teams" }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let slug, let asset = NSImage(named: "platform-\(slug)") {
                    Image(nsImage: asset).resizable().aspectRatio(contentMode: .fit)
                } else {
                    switch slug {
                    case "meet":  GoogleMeetMark()
                    case "zoom":  BrandGlyph(fill: Color(hex: "#2D8CFF"), symbol: "video.fill")
                    case "teams": BrandGlyph(fill: Color(hex: "#5059C9"), symbol: "person.2.fill")
                    default:
                        // No recognized platform: a calendar block, or a camera
                        // when there is some other video link.
                        Image(systemName: hasVideo ? "video.fill" : "calendar")
                            .font(.system(size: side * 0.62))
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: side, height: side)
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A solid rounded tile with a white glyph — used for platforms whose mark is
/// a wordmark rather than a shape we can honestly reproduce.
private struct BrandGlyph: View {
    let fill: Color
    let symbol: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .fill(fill)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: side * 0.46, weight: .medium))
                        .foregroundStyle(.white)
                )
                .frame(width: side, height: side)
        }
    }
}

/// The Google Meet camera mark, transcribed from the official artwork
/// (viewBox 0 0 87.5 72) so the proportions are exact rather than eyeballed.
/// Paths are painted in source order; the later fills overlap the earlier ones,
/// which is what produces the folded-corner look.
private struct GoogleMeetMark: View {
    /// Artboard → view transform. The mark is 87.5 × 72, so it letterboxes
    /// inside a square frame.
    private func pt(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat) -> CGPoint {
        CGPoint(x: x * k, y: y * k)
    }

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / 87.5, geo.size.height / 72)
            ZStack(alignment: .topLeading) {
                // #00832d — the dark-green lens wedge
                Path { p in
                    p.move(to: pt(49.5, 36, k))
                    p.addLine(to: pt(58.03, 45.75, k))
                    p.addLine(to: pt(69.5, 53.08, k))
                    p.addLine(to: pt(71.5, 36.06, k))
                    p.addLine(to: pt(69.5, 19.42, k))
                    p.addLine(to: pt(57.81, 25.86, k))
                    p.closeSubpath()
                }.fill(Color(hex: "#00832D"))

                // #0066da — bottom-left corner
                Path { p in
                    p.move(to: pt(0, 51.5, k))
                    p.addLine(to: pt(0, 66, k))
                    p.addCurve(to: pt(6, 72, k),
                               control1: pt(0, 69.315, k), control2: pt(2.685, 72, k))
                    p.addLine(to: pt(20.5, 72, k))
                    p.addLine(to: pt(23.5, 61.04, k))
                    p.addLine(to: pt(20.5, 51.5, k))
                    p.addLine(to: pt(10.55, 48.5, k))
                    p.closeSubpath()
                }.fill(Color(hex: "#0066DA"))

                // #e94235 — top-left corner
                Path { p in
                    p.move(to: pt(20.5, 0, k))
                    p.addLine(to: pt(0, 20.5, k))
                    p.addLine(to: pt(10.55, 23.5, k))
                    p.addLine(to: pt(20.5, 20.5, k))
                    p.addLine(to: pt(23.45, 11.09, k))
                    p.closeSubpath()
                }.fill(Color(hex: "#E94235"))

                // #2684fc — left edge
                Path { p in
                    p.addRect(CGRect(x: 0, y: 20.5 * k, width: 20.5 * k, height: 31 * k))
                }.fill(Color(hex: "#2684FC"))

                // #00ac47 — the right pane plus the lower body
                Path { p in
                    p.move(to: pt(82.6, 8.68, k))
                    p.addLine(to: pt(69.5, 19.42, k))
                    p.addLine(to: pt(69.5, 53.08, k))
                    p.addLine(to: pt(82.66, 63.87, k))
                    p.addCurve(to: pt(87.51, 61.5, k),
                               control1: pt(84.63, 65.41, k), control2: pt(87.51, 64.005, k))
                    p.addLine(to: pt(87.51, 11, k))
                    p.addCurve(to: pt(82.6, 8.68, k),
                               control1: pt(87.51, 8.465, k), control2: pt(84.565, 7.075, k))
                    p.closeSubpath()

                    p.move(to: pt(49.5, 36, k))
                    p.addLine(to: pt(49.5, 51.5, k))
                    p.addLine(to: pt(20.5, 51.5, k))
                    p.addLine(to: pt(20.5, 72, k))
                    p.addLine(to: pt(63.5, 72, k))
                    p.addCurve(to: pt(69.5, 66, k),
                               control1: pt(66.815, 72, k), control2: pt(69.5, 69.315, k))
                    p.addLine(to: pt(69.5, 53.08, k))
                    p.closeSubpath()
                }.fill(Color(hex: "#00AC47"))

                // #ffba00 — the upper body
                Path { p in
                    p.move(to: pt(63.5, 0, k))
                    p.addLine(to: pt(20.5, 0, k))
                    p.addLine(to: pt(20.5, 20.5, k))
                    p.addLine(to: pt(49.5, 20.5, k))
                    p.addLine(to: pt(49.5, 36, k))
                    p.addLine(to: pt(69.5, 19.43, k))
                    p.addLine(to: pt(69.5, 6, k))
                    p.addCurve(to: pt(63.5, 0, k),
                               control1: pt(69.5, 2.685, k), control2: pt(66.815, 0, k))
                    p.closeSubpath()
                }.fill(Color(hex: "#FFBA00"))
            }
            .frame(width: 87.5 * k, height: 72 * k)
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // centre in the square
        }
    }
}
