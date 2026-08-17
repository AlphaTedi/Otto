import SwiftUI

// MARK: - Notch presence indicator
//
// Otto used to give no passive sign that it was running. Unless you hovered
// the notch deliberately there was nothing to see, so you had to already know
// the app existed and remember to check it (Marcello's spec, 2026-08-17).
//
// This is the always-on answer to two questions: is Otto alive, and is
// something coming up. It lives in the COLLAPSED silhouette, in the wings
// either side of the camera housing — the same place the capture notification
// puts its content, because on a notch Mac the middle is not ours to draw in.
//
// ── On the shape ────────────────────────────────────────────────────────────
//
// The spec proposed building the flare as two overlapping rectangles of the
// same fill: a thin bezel strip on top, and a wider rounded rect whose top
// corner radius exceeds the strip's height, so the seam disappears and the
// wide shape reads as growing out of the bezel.
//
// That is not needed here, because `NotchShape` already draws exactly that
// silhouette as ONE path: its `filletRadius` is a concave quarter-curve at
// each top corner, which is precisely the "flare out of the bezel" the two-rect
// trick approximates — and being one path it has no seam to hide, animates as
// a single shape, and already masks the content. So the indicator is content
// inside the existing shape, not a new shape beside it.
//
// The one thing deliberately NOT built: a full-width black strip across the
// top of the screen. On a MacBook the black bezel the shape flares out of is
// the physical notch, which is already there; painting our own strip would
// cover the menu bar edge-to-edge on every Mac to simulate something this one
// has in hardware. See the note in the release for how to turn that on if it
// really is wanted.

// MARK: - Platform

/// Where an upcoming meeting happens. Drives the left glyph.
///
/// NOTE ON MARKS: these are SF Symbols in a brand-ish tint, NOT the Meet /
/// Zoom / Teams logos. Shipping the real marks means bundling someone else's
/// trademarked artwork under their brand terms, which is a decision to make
/// deliberately rather than incidentally — and a hand-drawn lookalike would be
/// worse than an honest generic glyph.
enum MeetingPlatform: Equatable {
    case meet
    case zoom
    case teams
    case otherVideo
    case inPerson

    /// From the platform label CalendarStore already parses, falling back to
    /// the join URL's host when the label is missing.
    static func detect(platform: String?, url: URL?) -> MeetingPlatform {
        let haystack = ((platform ?? "") + " " + (url?.host ?? "")).lowercased()
        if haystack.contains("meet") || haystack.contains("google") { return .meet }
        if haystack.contains("zoom") { return .zoom }
        if haystack.contains("teams") || haystack.contains("microsoft") { return .teams }
        if url != nil { return .otherVideo }
        return .inPerson
    }

    var symbol: String {
        switch self {
        case .meet, .zoom, .teams, .otherVideo: return "video.fill"
        case .inPerson:                         return "person.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .meet:        return Color(hex: "#3BA55C")
        case .zoom:        return Color(hex: "#4A8CFF")
        case .teams:       return Color(hex: "#6264A7")
        case .otherVideo:  return DSColor.textPrimaryBright
        case .inPerson:    return DSColor.textSecondary
        }
    }
}

// MARK: - What the indicator is showing

enum NotchPresenceState: Equatable {
    /// Nothing due. Otto is simply running.
    case resting
    /// Something with a start time close enough to be worth surfacing.
    case countdown(Countdown)

    struct Countdown: Equatable {
        /// nil for a plain to-do — nothing hosts it.
        let platform: MeetingPlatform?
        let minutes: Int
    }
}

extension NotchPresenceState.Countdown {
    /// "in 34′" — a prime mark for minutes, no unit word, no leading zero.
    /// Under a minute it reads "now" rather than counting a zero down.
    var label: String {
        minutes <= 0 ? L10n.t("presence.now") : "\(L10n.t("presence.in")) \(minutes)\u{2032}"
    }

    /// PURELY time-based, and deliberately not category-tinted.
    ///
    /// The spec flagged the choice: urgency or which section the item belongs
    /// to. It cannot be both — this dot is the only accent in an element that
    /// carries no label, so a second meaning has nothing to disambiguate it
    /// against. "How soon" is the question the indicator exists to answer, so
    /// it is the one the colour answers: it warms as the clock runs down.
    var dotColor: Color {
        switch minutes {
        case ..<2:  return DSColor.urgencyHigh      // now-ish
        case ..<6:  return DSColor.CategoryPalette.coral
        case ..<16: return DSColor.CategoryPalette.amber
        default:    return DSColor.CategoryPalette.blue
        }
    }
}

// MARK: - Model

/// Decides what the collapsed notch should be showing, and re-publishes on a
/// clock so "in 34′" is never stale.
@MainActor
final class NotchPresence: ObservableObject {
    static let shared = NotchPresence()

    @Published private(set) var state: NotchPresenceState = .resting

    /// How far ahead a plain to-do's due time starts counting down. Meetings
    /// use CalendarStore's own ambient window, which the user can already set.
    private let todoHorizonMinutes = 60

    private var ticker: Timer?

    #if DEBUG
    /// Forces a state so the headless harness can drive the indicator without
    /// a real meeting 34 minutes away. Never compiled into Release.
    var debugOverride: NotchPresenceState? {
        didSet { recompute() }
    }
    #endif

    // No deinit tearing the timer down: this is a `shared` singleton that
    // lives for the process, and a nonisolated deinit cannot touch actor state
    // anyway. The timer holds `self` weakly, so there is no cycle to break.
    private init() {
        recompute()
        // 15s, not 60s: a minute-granularity label ticking on a minute-long
        // timer drifts by up to a minute against the wall clock, and "in 3′"
        // sitting there while it is really 2 is the one thing a countdown
        // cannot do.
        ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    /// Both sources, nearest first.
    ///
    /// Meetings and to-dos both qualify — the spec asked whether this was
    /// calendar-only, and there is no reason a to-do with a real due time is
    /// less worth surfacing than an event. Calendar data is already flowing
    /// (CalendarStore), so nothing new has to be asked of the user for it.
    func recompute() {
        #if DEBUG
        if let forced = debugOverride {
            if forced != state { withAnimation(NotchAnimation.contentHug) { state = forced } }
            return
        }
        #endif
        let calendar = CalendarStore.shared
        var best: NotchPresenceState.Countdown?

        if let meeting = calendar.ambientMeeting {
            best = .init(
                platform: .detect(platform: meeting.platform, url: meeting.videoURL),
                minutes: max(0, meeting.minutesUntilStart)
            )
        }

        let now = Date()
        let horizon = TimeInterval(todoHorizonMinutes * 60)
        let dueSoon = TodoStore.shared.items
            .filter { !$0.isCompleted }
            .compactMap { item -> Int? in
                guard let due = item.dueDate else { return nil }
                let delta = due.timeIntervalSince(now)
                guard delta >= -60, delta <= horizon else { return nil }
                return Int((delta / 60).rounded(.down))
            }
            .min()

        if let minutes = dueSoon, minutes < (best?.minutes ?? .max) {
            // No platform: nothing hosts a to-do, so the left slot carries the
            // to-do's own mark rather than a borrowed meeting glyph.
            best = .init(platform: nil, minutes: max(0, minutes))
        }

        let next: NotchPresenceState = best.map { .countdown($0) } ?? .resting
        guard next != state else { return }
        withAnimation(NotchAnimation.contentHug) { state = next }
    }

}

// MARK: - View

extension NotchPresenceState {
    /// One line for the debug harness — what a person would see.
    var debugDescription: String {
        switch self {
        case .resting: return "resting"
        case .countdown(let c):
            return "countdown(platform=\(c.platform.map(String.init(describing:)) ?? "todo") "
                 + "label='\(c.label)' minutes=\(c.minutes))"
        }
    }
}

/// The content drawn inside the collapsed silhouette.
///
/// Laid out as two wings with a fixed gap between them, because on a notch Mac
/// the middle is the camera housing. `notchWingWidth` is the same environment
/// value the capture notification uses for exactly this reason.
struct NotchPresenceView: View {
    let state: NotchPresenceState
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let wingWidth: CGFloat

    /// The tallest thing either wing draws. Everything is centred against
    /// this, so the gap under the content is the same whichever state is up.
    private static let contentHeight: CGFloat = 14

    /// ONE inset, used against the bottom edge and the outer side edge alike.
    ///
    /// It is derived rather than picked: vertical centring inside the notch's
    /// own height already leaves a specific gap under the content, and the
    /// side inset is set to exactly that number. So the icon is equidistant
    /// from the bottom of the notch and from its edge by construction, and
    /// stays equidistant if the notch height ever changes — rather than being
    /// two hand-tuned constants that drift apart (Marcello, 2026-08-17).
    private var edgeInset: CGFloat {
        max(6, (notchHeight - Self.contentHeight) / 2)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Pushed to the OUTER edge and inset, not floated in the middle of
            // the wing — the same pattern on both sides, mirrored.
            leading
                .padding(.leading, edgeInset)
                .frame(width: wingWidth, alignment: .leading)
            // The housing. Nothing may be drawn here.
            Color.clear.frame(width: notchWidth)
            trailing
                .padding(.trailing, edgeInset)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: notchHeight)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var leading: some View {
        switch state {
        case .resting:
            EmptyView()
        case .countdown(let countdown):
            if let platform = countdown.platform {
                Image(systemName: platform.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(platform.tint)
            } else {
                // A to-do: its own checkbox, at the size the app draws it.
                RoundedRectangle(cornerRadius: DSRadius.checklistCheckboxCorner,
                                 style: .continuous)
                    .strokeBorder(DSColor.textPrimaryBright.opacity(0.8), lineWidth: 1.4)
                    .frame(width: 11, height: 11)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .resting:
            // Glyph-only, as the spec recommended: the least a permanent
            // element can be and still say "running". No dot — a dot with no
            // countdown beside it looks like an unread badge.
            Image(systemName: "circle.dashed")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DSColor.textPrimaryBright.opacity(0.38))
        case .countdown(let countdown):
            HStack(spacing: 5) {
                Circle()
                    .fill(countdown.dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: countdown.dotColor.opacity(0.55), radius: 3)
                Text(countdown.label)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .fixedSize()
            }
            .transition(.opacity)
        }
    }
}
