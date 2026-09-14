import Foundation
import SwiftUI

// MARK: - CompletedArchive — reading back the record of completions
//
// The archive has been WRITE-ONLY since it was introduced (Thomas,
// 2026-09-01). Completed to-dos older than a day leave the live store for
// `Archive/<day>.md`, which fixed a pile that grew forever — and took the
// history off the screen with it. The Completed section shows what is still in
// the store, so after twenty-four hours it holds nothing, and a section with
// nothing in it is not drawn at all: "i completed sono spariti"
// (Marcello, 2026-09-07). Thirty completions were sitting safely on disk with
// no way to look at them from inside the app.
//
// This is the reader. It does not own the format and never writes: MarkdownVault
// is still the only writer, and this parses what that file produced. If the two
// ever disagree the file wins, because the file is what the user can also open
// in Obsidian.

/// One finished to-do, recovered from the archive. Not a `TodoItem`: it has
/// left the store, and pretending otherwise would invite code to try to edit
/// something that is no longer there.
struct ArchivedCompletion: Identifiable, Equatable {
    let id: String
    let title: String
    /// The section it was in when it was finished. The section may since have
    /// been renamed or deleted — this is the name as it was recorded, which is
    /// the honest thing for a historical record to say.
    let sectionName: String?
    let completedAt: Date
    var taskID: UUID? = nil
    var meetingNoteID: UUID? = nil
}

@MainActor
final class CompletedArchive: ObservableObject {
    static let shared = CompletedArchive()

    @Published private(set) var entries: [ArchivedCompletion] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var readError = false

    private var directory: URL {
        MarkdownVault.shared.directory.appendingPathComponent("Archive", isDirectory: true)
    }

    /// Read every day file. Cheap enough to do outright — these are a handful
    /// of small text files, and the alternative (paging by day) buys nothing
    /// until someone has years of them.
    ///
    /// Reload is not automatic: this is called when the Completed section is
    /// opened and after a sweep, which are the only two moments the contents
    /// can have changed under the panel.
    func reload() {
        let fm = FileManager.default
        readError = false
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil) else {
            readError = !fm.fileExists(atPath: MarkdownVault.shared.directory.path) || fm.fileExists(atPath: directory.path)
            entries = []
            hasLoaded = true
            return
        }
        var found: [ArchivedCompletion] = []
        for url in files where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { readError = true; continue }
            found.append(contentsOf: Self.parseDocument(text))
        }
        // Newest first, the same order the live Completed section uses.
        var seen = Set<String>()
        entries = found.sorted { $0.completedAt > $1.completedAt }.filter { seen.insert($0.id).inserted }
        hasLoaded = true
    }

    /// Called after anything that writes the archive, so the next open reads
    /// the file rather than a stale parse.
    func invalidate() {
        hasLoaded = false
    }

    func reloadIfNeeded() {
        guard !hasLoaded else { return }
        reload()
    }

    // MARK: Parsing
    //
    // The line MarkdownVault writes, and nothing else:
    //
    //     - [x] Title (Section) ✅ 2026-09-06 01:27
    //
    // Indented detail lines (steps, the note) follow it and are skipped — they
    // belong to the to-do's body, not to the record of it having happened.

    struct Metadata: Codable {
        var v = 1
        var taskID: UUID
        var meetingNoteID: UUID?
        var completedAt: Date?
    }

    nonisolated static func metadata(_ line: String) -> Metadata? {
        let clean = line.trimmingCharacters(in: .whitespaces)
        guard clean.hasPrefix("<!-- otto:"), clean.hasSuffix(" -->"),
              let data = String(clean.dropFirst(10).dropLast(4)).data(using: .utf8),
              let value = try? JSONDecoder().decode(Metadata.self, from: data), value.v == 1 else { return nil }
        return value
    }

    nonisolated static func metadataLine(for item: TodoItem) -> String {
        let value = Metadata(taskID: item.id, meetingNoteID: item.meetingNoteID, completedAt: item.completedAt)
        let data = try! JSONEncoder().encode(value)
        return "  <!-- otto:" + String(decoding: data, as: UTF8.self) + " -->"
    }

    nonisolated static func parseDocument(_ text: String) -> [ArchivedCompletion] {
        let lines = text.components(separatedBy: "\n")
        var found: [ArchivedCompletion] = []
        for index in lines.indices {
            guard let old = parse(lines[index]) else { continue }
            if index + 1 < lines.count, let meta = metadata(lines[index + 1]) {
                found.append(ArchivedCompletion(id: meta.taskID.uuidString, title: old.title,
                    sectionName: old.sectionName, completedAt: meta.completedAt ?? old.completedAt,
                    taskID: meta.taskID, meetingNoteID: meta.meetingNoteID))
            } else { found.append(old) }
        }
        let modern = Set(found.filter { $0.taskID != nil }.map { identity(title: $0.title, at: $0.completedAt) })
        return found.filter { $0.taskID != nil || !modern.contains($0.id) }
    }

    /// Read from the RIGHT, not the left.
    ///
    /// A title is free text and can contain anything, brackets and parentheses
    /// included — "call (the) plumber" is a perfectly ordinary to-do. The two
    /// fixed points are the ✅ marker and the end of the line, so the stamp is
    /// taken off the end first and the section off the end of what is left.
    /// Scanning forward instead would have let a title with a bracket in it
    /// eat its own section name.
    nonisolated static func parse(_ raw: String) -> ArchivedCompletion? {
        // Indented lines are the to-do's details, not a completion.
        guard !raw.hasPrefix(" "), !raw.hasPrefix("\t") else { return nil }
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") else { return nil }
        var rest = String(line.dropFirst(6))

        guard let stampRange = rest.range(of: " \u{2705} ", options: .backwards) else { return nil }
        let stamp = String(rest[stampRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        rest = String(rest[..<stampRange.lowerBound])

        guard let at = Self.stampFormatter.date(from: stamp)
                ?? Self.dayOnlyFormatter.date(from: stamp) else { return nil }

        var section: String?
        if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
            section = String(rest[open.upperBound...].dropLast())
            rest = String(rest[..<open.lowerBound])
        }

        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return ArchivedCompletion(id: identity(title: title, at: at), title: title,
                                  sectionName: section, completedAt: at)
    }

    /// What makes a completion unique: its title and the minute it happened.
    ///
    /// Used twice, and it has to be the same function both times — once when
    /// reading a line back, and once to recognise that an archived entry and a
    /// LIVE completed item are the same event. They overlap for a day: the
    /// record is written the moment the box is ticked, while the row stays in
    /// the store until the next sweep, so without this today's to-dos would be
    /// listed twice under each other.
    nonisolated static func identity(title: String, at: Date) -> String {
        "\(stampFormatter.string(from: at))|\(title)"
    }

    /// The archive, minus anything the live store is still showing, and scoped
    /// the way the Completed section is scoped.
    ///
    /// `sectionName` is the name as it was RECORDED. A section since renamed
    /// keeps its old completions under its old name, where browsing the
    /// renamed section will not find them — Today shows everything and is the
    /// way to those. Rewriting history to follow a rename would be the other
    /// choice; it is not obviously better, and it edits files the user may
    /// have open elsewhere.
    func history(section: String?, excluding live: Set<String>) -> [(day: Date, entries: [ArchivedCompletion])] {
        let calendar = Calendar.current
        let kept = entries.filter { shows($0, section: section, excluding: live) }
        let groups = Dictionary(grouping: kept) { calendar.startOfDay(for: $0.completedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.completedAt > $1.completedAt }) }
    }

    /// How many entries the history WOULD show, without building it.
    ///
    /// The header's count and "is there anything here at all" are both asked
    /// on every redraw, including mid-animation. Grouping the whole archive to
    /// answer them would be a dictionary build per frame, growing with a file
    /// that only ever gets longer.
    func historyCount(section: String?, excluding live: Set<String>) -> Int {
        entries.reduce(0) { $0 + (shows($1, section: section, excluding: live) ? 1 : 0) }
    }

    private func shows(_ entry: ArchivedCompletion, section: String?,
                       excluding live: Set<String>) -> Bool {
        guard !live.contains(entry.id) else { return false }
        guard let section else { return true }          // Today: everything
        return entry.sectionName == section
    }

    /// Fixed locale and zone. These strings were written by
    /// `VaultFormatters.cached`, which builds plain `yyyy-MM-dd HH:mm` — under
    /// a Gregorian-but-not-ISO locale (or a 12-hour region) a device formatter
    /// would fail to read back what this very app wrote.
    /// `nonisolated(unsafe)` because parsing is a pure function that has no
    /// business hopping onto the main actor: a DateFormatter that is only ever
    /// READ is thread-safe, and these two are built once and never mutated.
    nonisolated(unsafe) private static let stampFormatter: DateFormatter = fixed("yyyy-MM-dd HH:mm")
    nonisolated(unsafe) private static let dayOnlyFormatter: DateFormatter = fixed("yyyy-MM-dd")

    nonisolated private static func fixed(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}
