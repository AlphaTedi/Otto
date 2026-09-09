import SwiftUI

// MARK: - Insights — a weekly overview (handoff directions 11a + 12a)
//
// Read-mostly. The ONLY interactive thing on the page is the checkbox on a
// left-behind to-do, and that is deliberate: this is a page you look at once a
// week, not one you work in.
//
// WHAT IS NOT HERE is the more considered half of the design, and it is written
// down so it does not get re-litigated: no completion rate (it depends on how
// much you write, not how much you do, so heavy note-takers look delinquent);
// no streaks (turns a list into a game and punishes taking a weekend — a
// "current streak: 0" with six empty circles is the screen that gets an app
// deleted); no average time to close (a task ticked three days late may have
// taken ten minutes — the number does not exist); no week-over-week delta (a
// "−18%" in a personal app is a reprimand without context). The filter applied
// throughout: keep only what you can act on or would want to reread.
//
// PROGRESSIVE DISCLOSURE. A panel with not enough behind it is not drawn at
// all, never drawn empty. Someone who opens this in their first week should see
// a page that is small and true, not a wall of zeroes.

struct InsightsView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var archive = CompletedArchive.shared
    @ObservedObject private var state = InsightsState.shared
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels
    @ObservedObject private var chrome = PanelChrome.shared
    @State private var contentHeight: CGFloat = 0

    private var isContainer: Bool { notchLayout == .container }

    /// What is left of the panel once the header and the space bar have taken
    /// theirs.
    ///
    /// The page HAS to be capped. Measured, it wants 1290pt — a year grid, two
    /// panels and twenty-five left-behind rows — against a block of 556, and an
    /// uncapped page does here exactly what the Completed section did: pushes
    /// the space bar out through the bottom edge and off the panel. `min` with
    /// the natural height, never a fixed frame, so a thin page still hugs.
    private var budget: CGFloat {
        max(160, LabMetrics.todoBlockMaxHeight
            - LabMetrics.panelTopPadding
            - LabMetrics.barHeight
            // The space bar, in BOTH layouts. The container's copy is drawn by
            // this page, the floating panels' one at the foot of the card — it
            // is in a different place, not absent, and a budget that only
            // counted the copy it could see put the page 55pt over its block.
            - chrome.tabRow
            - 24)
    }

    private var weekCompletions: [Completion] {
        CompletionStats.week(containing: state.anchor, store: store, archive: archive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // The space bar, under the header — the same rule the lists and the
            // Notes stream follow: FIELD FIRST, SECTIONS UNDER IT. It is also
            // the way out of here for anyone who arrived by clicking, so a page
            // without it would be a page you can only leave by keyboard.
            if isContainer, store.showsSpaceBar {
                TodoTabRow(rulePosition: .below)
                    .measureHeight(TabRowHeightKey.self)
                    .padding(.horizontal, -LabMetrics.barOuterInset)
            }

            let week = weekCompletions
            let behind = CompletionStats.leftBehind(store: store)
            let weeks = CompletionStats.weeksOfHistory(store: store, archive: archive)
            let showsWeek = !week.isEmpty
            let showsBehind = !behind.isEmpty
            // Eight weeks before a year grid earns its place. Below that it is
            // a mostly-empty texture that says "you have not used this yet",
            // which is not an insight.
            let showsGrid = weeks >= 8

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    body_
                }
                .measureHeight(InsightsContentKey.self)
            }
            .frame(height: min(max(contentHeight, 1), budget))
            .onPreferenceChange(InsightsContentKey.self) { contentHeight = $0 }
        }
        .padding(.horizontal, LabMetrics.barOuterInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            archive.reloadIfNeeded()
            state.surfaceLastWeekIfDue(store: store, archive: archive)
        }
        .onReceive(store.$archiveRevision) { _ in archive.reload() }
    }

    /// The page's own content, below the header and the space bar.
    @ViewBuilder
    private var body_: some View {
        let week = weekCompletions
        let behind = CompletionStats.leftBehind(store: store)
        let weeks = CompletionStats.weeksOfHistory(store: store, archive: archive)
        let showsWeek = !week.isEmpty
        let showsBehind = !behind.isEmpty
        // Eight weeks before a year grid earns its place. Below that it is a
        // mostly-empty texture that says "you have not used this yet", which is
        // not an insight.
        let showsGrid = weeks >= 8

        Group {
            if let line = state.surfacedWeek {
                // Once a week, on the first open after it turns over. Without
                // it only people who go looking would ever read this page,
                // which is the same as not having built it — and a nudge that
                // repeats is a nag, so it is shown once and never again that
                // week.
                HStack(spacing: 8) {
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textSecondary)
                    Button {
                        state.step(-1)
                        state.dismissSurfacing()
                    } label: {
                        Text(L10n.t("insights.view") + " \u{203A}")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LabMetrics.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    Button { state.dismissSurfacing() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DSColor.textFaint)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LabMetrics.accent.opacity(0.10))
                )
                .transition(.opacity)
            }

            if !showsWeek && !showsBehind && !showsGrid {
                emptyState
            } else {
                if showsGrid { YearGrid(store: store, archive: archive) }
                // Side by side until the grid arrives, so the page is full at
                // every stage of its life rather than growing into place.
                HStack(alignment: .top, spacing: 12) {
                    if showsWeek {
                        // maxWidth rather than a fixed width: the handoff's
                        // 320 was drawn against a wide floating card, and under
                        // the notch a panel that cannot shrink is a panel that
                        // overflows.
                        WeekPanel(completions: week, store: store)
                            .frame(maxWidth: showsBehind ? 280 : .infinity, alignment: .leading)
                    }
                    if showsBehind {
                        LeftBehindPanel(items: behind)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: Header — title and the week stepper

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.t("insights.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DSColor.textPrimaryBright)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                stepButton(systemName: "chevron.left", enabled: true) { state.step(-1) }
                Text(state.weekLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize()
                    .frame(minWidth: 92)
                // Forward is disabled on the current week: there is nothing
                // ahead to look at, and a stepper that walks into the future
                // shows a page of zeroes.
                stepButton(systemName: "chevron.right", enabled: state.canStepForward) { state.step(1) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(DSColor.panelBorder, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: LabMetrics.barHeight)
        .background(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .strokeBorder(DSColor.panelBorder, lineWidth: 1)
        )
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? DSColor.textSecondary : DSColor.textFaint)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var emptyState: some View {
        Text(L10n.t("insights.empty"))
            .font(.system(size: 13))
            .foregroundStyle(DSColor.textHint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }
}

private struct InsightsContentKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Panel chrome, shared by the three

private struct InsightsPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

/// A panel's header line: label on the left, total and unit on the right, all
/// on one baseline.
///
/// The total is 15pt and NOT a hero number. An earlier pass put it at 52pt
/// directly above the year grid and the huge digits fought the 3pt texture —
/// two rhythms at twelve points of distance. The grid is the only large object
/// in its panel; the one hero number on the page lives in the week panel, where
/// there is no texture to argue with.
private struct PanelHeader: View {
    let label: String
    let total: Int
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textFaint)
            Spacer(minLength: 8)
            Text("\(total)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textPrimaryBright)
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textHint)
        }
    }
}

// MARK: - Panel 1 — the year grid

private struct YearGrid: View {
    let store: TodoStore
    let archive: CompletedArchive

    /// Elastic columns, square cells. The grid fills whatever width the panel
    /// has rather than being drawn at a fixed cell size and cropped — under the
    /// notch that width changes with the display.
    private static let rows = 7

    var body: some View {
        let weeks = 53
        let counts = CompletionStats.dailyCounts(section: nil, days: weeks * Self.rows,
                                                 store: store, archive: archive)
        InsightsPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(label: L10n.t("insights.lastTwelveMonths"),
                            total: counts.reduce(0, +),
                            unit: L10n.t("insights.closed"))
                GeometryReader { geo in
                    // Below 560pt of width the grid drops to six months rather
                    // than shrinking the cells further — past a point a smaller
                    // square stops being readable and becomes noise.
                    let columns = geo.size.width < 560 ? 26 : weeks
                    let gap: CGFloat = 3
                    let cell = max(4, (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
                    let shown = Array(counts.suffix(columns * Self.rows))
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            VStack(spacing: gap) {
                                ForEach(0..<Self.rows, id: \.self) { row in
                                    let index = column * Self.rows + row
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Self.fill(index < shown.count ? shown[index] : 0))
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
                .frame(height: 7 * 11 + 6 * 3)
            }
        }
    }

    /// Four steps, by that day's count. Intensity IS the measure here, which is
    /// why the grid is not coloured by space: a per-space palette would look
    /// richer and would stop answering "how much".
    private static func fill(_ count: Int) -> Color {
        switch count {
        case 0:     return Color.white.opacity(0.05)
        case 1...2: return LabMetrics.accent.opacity(0.28)
        case 3...5: return LabMetrics.accent.opacity(0.55)
        default:    return LabMetrics.accent.opacity(0.80)
        }
    }
}

// MARK: - Panel 2 — this week, and where the days went

private struct WeekPanel: View {
    let completions: [Completion]
    let store: TodoStore

    /// Three spaces and then "N more". With ten lists this panel must not
    /// become a list inside a panel.
    private static let maxSpaces = 3

    var body: some View {
        let split = CompletionStats.splitBySpace(in: completions, store: store)
        let shown = Array(split.prefix(Self.maxSpaces))
        let peak = max(shown.first?.count ?? 1, 1)
        InsightsPanel {
            VStack(alignment: .leading, spacing: 14) {
                // THE hero number of the page, and the only one.
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(completions.count)")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(LabMetrics.accent)
                        .contentTransition(.numericText())
                    Text(L10n.t("insights.closedThisWeek"))
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textHint)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(shown, id: \.name) { space in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(space.name)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(DSColor.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(space.count)")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(DSColor.textHint)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.06))
                                    Capsule()
                                        .fill(space.color)
                                        .frame(width: max(4, geo.size.width
                                                          * CGFloat(space.count) / CGFloat(peak)))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                    if split.count > Self.maxSpaces {
                        Text(String(format: L10n.t("insights.more"), "\(split.count - Self.maxSpaces)"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(DSColor.textFaint)
                    }
                }
            }
        }
    }
}

// MARK: - Panel 3 — left behind, the one thing you can act on

private struct LeftBehindPanel: View {
    let items: [TodoItem]
    @ObservedObject private var store = TodoStore.shared

    var body: some View {
        InsightsPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(label: L10n.t("insights.leftBehind"),
                            total: items.count,
                            unit: L10n.t("insights.open"))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        LeftBehindRow(item: item,
                                      isFocused: store.insightsFocusedItemID == item.id)
                    }
                }
            }
        }
    }
}

private struct LeftBehindRow: View {
    let item: TodoItem
    let isFocused: Bool
    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(NotchAnimation.contentHug) { store.toggleComplete(item.id) }
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(LabMetrics.accent, lineWidth: 1.6)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(DSColor.textPrimaryBright)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(LeftBehindRow.age(item.createdAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DSColor.textFaint)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // One channel per state (handoff part 3). Hover is a wash; the keyboard
        // selection is a border plus an inset bar, so with the pointer on one
        // row and the caret on another you can still tell which one ⏎ acts on.
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isFocused ? LabMetrics.accent.opacity(0.10)
                      : (hover ? Color.white.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isFocused ? LabMetrics.accent.opacity(0.45) : Color.clear,
                              lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(LabMetrics.accent)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchAnimation.hoverFade) { hover = hovering }
        }
    }

    private static func age(_ from: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: from, to: Date()).day ?? 0
        return "\(max(days, 0))\(L10n.t("insights.dayShort"))"
    }
}

// MARK: - InsightsState — which week is on screen, and the Monday nudge
//
// Not persisted except for the one flag that has to be: which week the
// "last week you closed N" line was last shown for. Everything else is a
// session's worth of looking around.

@MainActor
final class InsightsState: ObservableObject {
    static let shared = InsightsState()

    /// Any date inside the week being shown.
    @Published private(set) var anchor = Date()
    /// The Monday-morning line, once a week and never twice.
    @Published var surfacedWeek: String?

    private static let surfacedKey = "insightsSurfacedWeek"

    /// Forward is refused on the current week — there is nothing ahead to look
    /// at, and a stepper that walks into the future shows a page of zeroes.
    var canStepForward: Bool {
        let thisWeek = CompletionStats.weekRange(containing: Date()).start
        return CompletionStats.weekRange(containing: anchor).start < thisWeek
    }

    func step(_ weeks: Int) {
        guard weeks < 0 || canStepForward else { return }
        if let moved = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: anchor) {
            anchor = moved
        }
    }

    func reset() { anchor = Date() }

    /// "2 – 8 Sep", the span the page is showing.
    var weekLabel: String {
        let range = CompletionStats.weekRange(containing: anchor)
        let last = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let day = DateFormatter()
        day.locale = Locale.current
        day.setLocalizedDateFormatFromTemplate("d")
        let dayMonth = DateFormatter()
        dayMonth.locale = Locale.current
        dayMonth.setLocalizedDateFormatFromTemplate("dMMM")
        return "\(day.string(from: range.start)) – \(dayMonth.string(from: last))"
    }

    // MARK: The Monday surfacing
    //
    // Without it only people who go looking will ever read this page, which is
    // the same as not shipping it. Once per week, dismissible, and it never
    // comes back that week — a nudge that repeats is a nag.

    func surfaceLastWeekIfDue(store: TodoStore, archive: CompletedArchive) {
        let key = Self.weekKey(for: Date())
        guard UserDefaults.standard.string(forKey: Self.surfacedKey) != key else { return }
        let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        let closed = CompletionStats.week(containing: lastWeek, store: store, archive: archive)
        // Nothing to report is not a notification.
        guard !closed.isEmpty else { return }
        UserDefaults.standard.set(key, forKey: Self.surfacedKey)
        surfacedWeek = String(format: L10n.t("insights.lastWeek"), "\(closed.count)")
    }

    func dismissSurfacing() { surfacedWeek = nil }

    private static func weekKey(for date: Date) -> String {
        let range = CompletionStats.weekRange(containing: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: range.start)
    }
}
