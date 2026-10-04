import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Completed, grouped by day (handoff direction 7b)
//
// `Completed 36` said how much, never when. One collapsible row per day answers
// both while CLOSED — seven rows, seven counts, and the first words of each
// day's work — where the flat list answered neither without scrolling through
// all thirty-six of them.
//
// Live completions and archived ones sit in the same rows, because to the
// person reading them they are the same event; only the checkbox differs. A
// live one can be un-ticked. An archived one has left the store and says so by
// not offering.

struct CompletedDayList: View {
    let days: [CompletedDay]
    @ObservedObject private var store = TodoStore.shared

    /// Seven, then the rest on request. A week is the span the sparkline above
    /// covers and about as far back as "what did I finish" is ever asked.
    private static let initialDays = 7

    var body: some View {
        let shown = store.completedShowsAllDays ? days : Array(days.prefix(Self.initialDays))
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shown) { day in
                CompletedDayRow(day: day)
            }
            if days.count > Self.initialDays {
                Button {
                    withAnimation(NotchAnimation.contentHug) {
                        store.completedShowsAllDays.toggle()
                    }
                } label: {
                    Text(store.completedShowsAllDays
                         ? L10n.t("todo.showFewer")
                         : L10n.t("todo.showAll"))
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
}

struct CompletedDayRow: View {
    let day: CompletedDay
    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    private var isToday: Bool { Calendar.current.isDateInToday(day.day) }
    private var isOpen: Bool { store.expandedCompletedDays.contains(day.day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NotchAnimation.contentHug) { store.toggleCompletedDay(day.day) }
            } label: {
                HStack(spacing: 12) {
                    OttoIcon("chevron.right", pointSize: 9)
                        .foregroundStyle(DSColor.textFaint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 10, alignment: .leading)

                    Text(CompletedDayRow.label(for: day.day))
                        .font(.system(size: 13, weight: isToday ? .semibold : .medium))
                        .foregroundStyle(isToday ? DSColor.textPrimaryBright : DSColor.textSecondary)
                        .fixedSize()
                        .frame(minWidth: 96, alignment: .leading)

                    // Single line, ellipsis, never wrapping: a row whose
                    // height depends on its content is what puts the counts on
                    // a ragged right edge.
                    Text(day.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textHint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(day.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isToday ? PanelMetrics.accent : DSColor.textMuted)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                // Hover is a WASH and nothing else (handoff part 3): one
                // channel per state, so it can never be mistaken for the
                // keyboard selection, which owns border and inset bar.
                .background(
                    RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                        .fill(hover ? Color.white.opacity(0.05) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(NotchAnimation.hoverFade) { hover = hovering }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(day.completions) { completion in
                        CompletedEntryRow(completion: completion)
                    }
                }
                .padding(.leading, 34)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
    }

    /// Today and Yesterday carry their own meaning; anything older is given the
    /// weekday and the date, which is what memory actually searches by.
    static func label(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day)     { return L10n.t("todo.todayLabel") }
        if calendar.isDateInYesterday(day) { return L10n.t("todo.yesterdayLabel") }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEEd")
        return formatter.string(from: day)
    }
}

/// One finished thing inside an open day.
///
/// The checkbox is the whole difference between the two sources: a LIVE
/// completion can be un-ticked and goes back to the list, an ARCHIVED one has
/// left the store and is drawn as a record — same tick, no press, no hover.
struct CompletedEntryRow: View {
    let completion: Completion
    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            box
            Text(completion.title)
                .font(.system(size: 13))
                .foregroundStyle(DSColor.textHint)
                .strikethrough(true, color: DSColor.textFaint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(CompletedEntryRow.time(completion.completedAt))
                // The system face: monospace is for code only.
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(DSColor.textFaint)
                .fixedSize()
        }
        .opacity(hover && completion.isLive ? 1 : 0.92)
        .onHover { hovering in
            guard completion.isLive else { return }
            withAnimation(NotchAnimation.hoverFade) { hover = hovering }
        }
        .help(completion.isLive ? L10n.t("todo.untickHint") : L10n.t("todo.archivedHint"))
    }

    @ViewBuilder
    private var box: some View {
        if let id = completion.liveID {
            Button {
                withAnimation(NotchAnimation.contentHug) { store.toggleComplete(id) }
            } label: { tick(filled: true) }
                .buttonStyle(.plain)
        } else {
            // No button: there is nothing behind it to act on, and a control
            // that cannot do anything is worse than no control.
            tick(filled: false)
        }
    }

    private func tick(filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(filled ? PanelMetrics.accent.opacity(0.9) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(filled ? Color.clear : DSColor.textFaint, lineWidth: 1.2)
            )
            .overlay(
                OttoIcon("checkmark", pointSize: 8)
                    .foregroundStyle(filled ? DSColor.onAccentFill : DSColor.textFaint)
            )
            .frame(width: 16, height: 16)
    }

    private static func time(_ at: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("Hmm")
        return formatter.string(from: at)
    }
}

// MARK: - CompletionSparkline — seven days of volume, in the header
//
// Every mark is a shape; no chart library, no image. Today is full accent, the
// rest scale with volume, and a day with nothing gets a floor bar rather than
// vanishing — the gaps are the information.

struct CompletionSparkline: View {
    let counts: [Int]
    /// The menu draws a smaller copy of the same mark. One view at two sizes,
    /// not two drawings that can come to disagree about what a day looks like.
    var barWidth: CGFloat = 4
    var barGap: CGFloat = 3
    var maxHeight: CGFloat = 16

    var body: some View {
        let peak = max(counts.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: barGap) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                let isToday = index == counts.count - 1
                let ratio = Double(count) / Double(peak)
                Capsule(style: .continuous)
                    .fill(fill(count: count, isToday: isToday, ratio: ratio))
                    .frame(width: barWidth,
                           height: count == 0 ? 3 : max(4, maxHeight * ratio))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .accessibilityLabel(L10n.t("todo.completed"))
    }

    private func fill(count: Int, isToday: Bool, ratio: Double) -> Color {
        if count == 0 { return Color.white.opacity(0.08) }
        if isToday    { return PanelMetrics.accent }
        return PanelMetrics.accent.opacity(0.30 + 0.30 * ratio)
    }
}
