import Foundation
import SwiftUI

// MARK: - CompletionStats — one answer to "what did I finish, and when"
//
// Completed-by-day and Insights ask the same questions of the same two sources,
// so they ask them HERE. A second derivation would be a second definition of
// "how many did I close on Tuesday", and the two would disagree the first time
// one of them was changed — which is exactly how the Completed section came to
// be drawn and budgeted by different rules (2026-09-07).
//
// The two sources overlap by design. A completion is written to
// Archive/<day>.md the moment its box is ticked, while the row itself stays in
// the live store until the next daily sweep. So for about a day the same event
// exists twice, and everything here dedupes on `CompletedArchive.identity`.
//
// LIVE entries carry their TodoItem and can be un-ticked. ARCHIVED ones have
// left the store and are a record: read-only, and honest about it.

/// One finished thing, from either source.
struct Completion: Identifiable {
    let id: String
    let title: String
    let sectionName: String?
    let completedAt: Date
    /// Present only while the to-do is still in the store — which is what
    /// makes un-ticking possible. nil means this is history.
    let liveID: UUID?

    var isLive: Bool { liveID != nil }
}

/// A day's worth of them.
struct CompletedDay: Identifiable {
    let day: Date
    let completions: [Completion]

    var id: Date { day }
    var count: Int { completions.count }

    /// The first words of the day's tasks, joined — what the collapsed row
    /// shows so the day answers "what" as well as "how many" without opening.
    var preview: String {
        completions.map(\.title).joined(separator: ", ")
    }
}

@MainActor
enum CompletionStats {

    // MARK: The merged record

    /// Every completion in `section` (nil = every section), newest first.
    ///
    /// Live rows win over archived ones for the same event, because the live
    /// one carries the id that lets you un-tick it.
    static func all(section: String?, store: TodoStore, archive: CompletedArchive) -> [Completion] {
        var seen = Set<String>()
        var out: [Completion] = []

        for item in store.items where item.isCompleted {
            guard let at = item.completedAt else { continue }
            let name = store.collection(id: item.collectionID)?.name
            if let section, name != section { continue }
            let id = CompletedArchive.identity(title: item.title, at: at)
            guard seen.insert(id).inserted else { continue }
            out.append(Completion(id: id, title: item.title, sectionName: name,
                                  completedAt: at, liveID: item.id))
        }

        for entry in archive.entries {
            if let section, entry.sectionName != section { continue }
            guard seen.insert(entry.id).inserted else { continue }
            out.append(Completion(id: entry.id, title: entry.title,
                                  sectionName: entry.sectionName,
                                  completedAt: entry.completedAt, liveID: nil))
        }

        return out.sorted { $0.completedAt > $1.completedAt }
    }

    /// Grouped into days, newest first. Days with nothing in them are absent
    /// rather than empty — the handoff is explicit that a zero day is not a row.
    static func days(section: String?, store: TodoStore, archive: CompletedArchive) -> [CompletedDay] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: all(section: section, store: store, archive: archive)) {
            calendar.startOfDay(for: $0.completedAt)
        }
        return groups.keys.sorted(by: >).map { day in
            CompletedDay(day: day, completions: groups[day]!.sorted { $0.completedAt > $1.completedAt })
        }
    }

    /// How many were closed on each of the last `count` days, oldest first —
    /// the sparkline's bars, and the same series the year grid reads.
    ///
    /// Returns zeros for empty days deliberately: a sparkline needs the gaps,
    /// even though a day LIST must not show them.
    static func dailyCounts(section: String?, days count: Int,
                            store: TodoStore, archive: CompletedArchive) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var tally: [Date: Int] = [:]
        for completion in all(section: section, store: store, archive: archive) {
            tally[calendar.startOfDay(for: completion.completedAt), default: 0] += 1
        }
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { tally[$0] ?? 0 }
        }
    }

    // MARK: Insights

    /// Completions inside a week, for the "closed this week" number.
    static func week(containing date: Date, store: TodoStore,
                     archive: CompletedArchive) -> [Completion] {
        let range = weekRange(containing: date)
        return all(section: nil, store: store, archive: archive).filter {
            $0.completedAt >= range.start && $0.completedAt < range.end
        }
    }

    /// Monday-to-Sunday, whatever the locale's first weekday is.
    static func weekRange(containing date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar.current
        // Weeks start on Monday here regardless of locale: the stepper's label
        // reads "2 – 8 set" and a week that starts on Sunday would put the
        // weekend at both ends of it.
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
        return (start, end)
    }

    /// This week's completions split by the space they belong to, largest
    /// first. Capped by the caller — with ten lists this must not become a
    /// list inside a panel.
    static func splitBySpace(in completions: [Completion],
                             store: TodoStore) -> [(name: String, count: Int, color: Color)] {
        var tally: [String: Int] = [:]
        for completion in completions {
            guard let name = completion.sectionName else { continue }
            tally[name, default: 0] += 1
        }
        return tally.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { name, count in
            (name, count, store.collections.first { $0.name == name }?.color ?? DSColor.textMuted)
        }
    }

    /// Open to-dos that have been open a long time — the only actionable thing
    /// on the Insights page.
    ///
    /// Older than the threshold, oldest first; and if that leaves almost
    /// nothing, the oldest three regardless of age, so the panel is never
    /// nearly empty (the handoff's own rule).
    static func leftBehind(store: TodoStore, thresholdDays: Int = 14,
                           minimum: Int = 3) -> [TodoItem] {
        let open = store.items.filter { !$0.isCompleted }
            .sorted { $0.createdAt < $1.createdAt }
        let cutoff = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: Date()) ?? Date()
        let stale = open.filter { $0.createdAt < cutoff }
        return stale.count >= minimum ? stale : Array(open.prefix(minimum))
    }

    /// How many whole weeks of history there are, which is what decides
    /// whether the year grid has earned its place on the page.
    static func weeksOfHistory(store: TodoStore, archive: CompletedArchive) -> Int {
        let completions = all(section: nil, store: store, archive: archive)
        guard let oldest = completions.map(\.completedAt).min() else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0
        return days / 7
    }
}
