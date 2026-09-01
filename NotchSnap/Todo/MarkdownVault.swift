import Foundation

// MARK: - MarkdownVault — the human-readable home of every to-do and note
//
// todos.json stays the machine's source of truth (atomic writes, backup,
// crash recovery — see TodoStore). This is the HUMAN's copy: one Markdown
// file per section in a folder the user chooses in Settings › Storage, so
// everything ever typed into the notch is findable with Spotlight, grep, or
// an Obsidian vault pointed at the folder. Full two-way sync with external
// editors is deliberately out of scope ("that gets way too hard" — Thomas,
// 2026-09-01); the contract is simpler and keeps: the folder always contains
// a faithful, current, readable copy of everything.
//
//   <storage folder>/
//     Work.md            one file per section, open items then Completed
//     Personal.md
//     Notes.md           the legacy quick notes, when any exist
//     Archive/
//       2026-08-30.md    completed to-dos, one file per completion day
//
// Task lines use the Obsidian Tasks conventions (📅 due, ⏫/🔼 priority,
// ✅ completion date) so the files are not merely readable in a vault but
// actually queryable by the plugin people already run.
//
// Section files are REWRITTEN whole on every change (atomic, debounced —
// same rhythm as todos.json). Archive files are APPEND-ONLY: once a
// completed to-do is older than a day it is moved out of the live store and
// its archive file becomes its only home, so those files are history and
// are never regenerated. A manifest (.otto-vault.json) records which section
// files the app wrote, so renaming or deleting a section removes its old
// file rather than stranding it — without ever touching a file the user
// created themselves.

@MainActor
final class MarkdownVault {
    static let shared = MarkdownVault()

    private var exportWork: Task<Void, Never>?

    // MARK: Location

    /// nonisolated: AppSettings reads this for its default value from
    /// nonisolated decode paths.
    nonisolated static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/\(AppBuild.vaultFolderName)", isDirectory: true)
    }

    var directory: URL { AppState.shared.settings.vaultDirectory }
    private var archiveDirectory: URL { directory.appendingPathComponent("Archive", isDirectory: true) }
    private var manifestURL: URL { directory.appendingPathComponent(".otto-vault.json") }

    // MARK: Export (debounced mirror of the live store)

    /// Same debounce rhythm as TodoStore's own save, so a burst of edits
    /// lands as one rewrite.
    func scheduleExport() {
        exportWork?.cancel()
        exportWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.exportNow()
        }
    }

    /// Synchronous full rewrite — also the quit-time flush.
    func exportNow() {
        exportWork?.cancel()
        exportWork = nil
        let store = TodoStore.shared
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [String] = []
        var usedNames = Set<String>()
        for collection in store.collections where !collection.isSystemToday {
            let name = uniqueFileName(for: collection.name, used: &usedNames)
            let url = directory.appendingPathComponent(name)
            let body = sectionMarkdown(for: collection, store: store)
            try? body.write(to: url, atomically: true, encoding: .utf8)
            written.append(name)
        }

        if let notes = notesMarkdown() {
            let name = "Notes.md"
            let url = directory.appendingPathComponent(name)
            try? notes.write(to: url, atomically: true, encoding: .utf8)
            written.append(name)
        }

        // Remove files WE wrote for sections that no longer exist — and only
        // those. The manifest is the boundary between the app's files and
        // the user's own; anything not in it is never deleted.
        let previous = (try? JSONDecoder().decode([String].self,
                                                  from: Data(contentsOf: manifestURL))) ?? []
        for stale in Set(previous).subtracting(written) {
            try? fm.removeItem(at: directory.appendingPathComponent(stale))
        }
        if let data = try? JSONEncoder().encode(written.sorted()) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    /// The user picked a new folder: write the current state there
    /// immediately, so "choose a folder" visibly does something. Files at
    /// the old location are left alone — they are the user's Markdown.
    func locationChanged() {
        exportNow()
    }

    // MARK: Archive (append-only history)

    /// Move `items` (already-completed to-dos older than the live window)
    /// into per-day archive files. Returns the ids that were durably
    /// written — the caller only removes those from the live store, so a
    /// failed write can never lose a to-do.
    func archive(_ items: [TodoItem], from store: TodoStore) -> Set<UUID> {
        guard !items.isEmpty else { return [] }
        let fm = FileManager.default
        try? fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

        let dayKey = VaultFormatters.cached("yyyy-MM-dd")
        let timeKey = VaultFormatters.cached("HH:mm")
        var archived = Set<UUID>()

        let byDay = Dictionary(grouping: items) {
            dayKey.string(from: $0.completedAt ?? $0.createdAt)
        }
        for (day, dayItems) in byDay {
            let url = archiveDirectory.appendingPathComponent("\(day).md")
            var body = (try? String(contentsOf: url, encoding: .utf8)) ?? "# \(day)\n"
            for item in dayItems.sorted(by: {
                ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
            }) {
                let section = store.collection(id: item.collectionID)?.name
                var line = "\n- [x] \(item.title)"
                if let section { line += " (\(section))" }
                if let at = item.completedAt { line += " ✅ \(day) \(timeKey.string(from: at))" }
                body += line + "\n"
                body += detailLines(for: item, indent: "  ")
            }
            do {
                try body.write(to: url, atomically: true, encoding: .utf8)
                dayItems.forEach { archived.insert($0.id) }
            } catch {
                // Leave these in the live store; they'll be retried next time.
            }
        }
        return archived
    }

    // MARK: Rendering

    private func sectionMarkdown(for collection: TodoCollection, store: TodoStore) -> String {
        let open = store.items
            .filter { $0.collectionID == collection.id && !$0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
        let done = store.items
            .filter { $0.collectionID == collection.id && $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        var out = "# \(collection.name)\n\n"
        if open.isEmpty && done.isEmpty {
            out += "*Nothing here yet.*\n"
            return out
        }
        for item in open { out += taskLine(item) }
        if !done.isEmpty {
            out += "\n## Completed\n\n"
            for item in done { out += taskLine(item) }
        }
        return out
    }

    private func taskLine(_ item: TodoItem) -> String {
        let dayKey = VaultFormatters.cached("yyyy-MM-dd")
        var line = "- [\(item.isCompleted ? "x" : " ")] \(item.title)"
        switch item.urgency {
        case .high:   line += " ⏫"
        case .medium: line += " 🔼"
        case .low:    break
        }
        if let due = item.dueDate { line += " 📅 \(dayKey.string(from: due))" }
        if item.isCompleted, let at = item.completedAt {
            line += " ✅ \(dayKey.string(from: at))"
        }
        return line + "\n" + detailLines(for: item, indent: "  ")
    }

    /// Steps and the note, indented under their to-do the way Obsidian nests
    /// sub-tasks. The note rides as a blockquote so it can never be mistaken
    /// for a task line.
    private func detailLines(for item: TodoItem, indent: String) -> String {
        var out = ""
        for step in item.checklist {
            out += "\(indent)- [\(step.isDone ? "x" : " ")] \(step.title)\n"
        }
        if !item.note.isEmpty {
            for noteLine in item.note.split(separator: "\n", omittingEmptySubsequences: false) {
                out += "\(indent)> \(noteLine)\n"
            }
        }
        return out
    }

    private func notesMarkdown() -> String? {
        let notes = NotesStore.shared.notes
        guard !notes.isEmpty else { return nil }
        let stamp = VaultFormatters.cached("yyyy-MM-dd HH:mm")
        var out = "# Notes\n"
        for note in notes.sorted(by: { $0.createdAt > $1.createdAt }) {
            out += "\n## \(stamp.string(from: note.createdAt))\n\n\(note.content)\n"
        }
        return out
    }

    /// "Work" → "Work.md", with the characters a filename can't carry
    /// replaced and collisions ("Home" the section vs "home" the section)
    /// suffixed rather than silently merged into one file.
    private func uniqueFileName(for name: String, used: inout Set<String>) -> String {
        var base = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Untitled" }
        if base.hasPrefix(".") { base = "_" + base.dropFirst() }
        var candidate = base
        var counter = 2
        while !used.insert(candidate.lowercased()).inserted {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate + ".md"
    }
}

/// DateFormatter construction is expensive; these are tiny and few, so one
/// cached instance per format is enough. Main-actor-bound like the vault
/// itself, so the cache needs no locking.
@MainActor
private enum VaultFormatters {
    static var cache: [String: DateFormatter] = [:]
    static func cached(_ format: String) -> DateFormatter {
        if let existing = cache[format] { return existing }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        cache[format] = formatter
        return formatter
    }
}
