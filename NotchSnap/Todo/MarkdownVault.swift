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
// same rhythm as todos.json). Archive files are the RECORD OF COMPLETIONS:
// an entry is written the moment a to-do is ticked off and removed if it is
// un-ticked; once the completion is older than a day the to-do leaves the
// live store and the archive file is its only home. Those files are never
// regenerated wholesale. A manifest (.otto-vault.json) records which section
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

    // MARK: Archive (the record of completions)
    //
    // A to-do is written to `Archive/<completion day>.md` the moment it is
    // ticked off (Thomas, 2026-09-01) — not a day later when it leaves the
    // panel. The archive is therefore the record of WHAT WAS DONE, kept in
    // step with the checkbox: un-ticking removes the entry again, and the
    // daily sweep that prunes old completions from the live store finds them
    // already recorded and only confirms it. One entry is one block — the
    // task line, then its indented steps and note — keyed by the task line,
    // which carries the title, section and minute of completion.

    /// Record a completion. Idempotent: an entry already present is left
    /// alone, so the sweep can call this for items ticked off hours ago.
    /// Returns true once the entry is durably on disk.
    @discardableResult
    func recordCompletion(_ item: TodoItem, from store: TodoStore) -> Bool {
        guard let at = item.completedAt else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let day = VaultFormatters.cached("yyyy-MM-dd").string(from: at)
        let url = archiveDirectory.appendingPathComponent("\(day).md")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "# \(day)\n")
            .components(separatedBy: "\n")
        let key = archiveKeyLine(for: item, at: at, store: store)
        if lines.contains(key) { return true }
        // Trailing blank kept, so the file ends in a newline after the block.
        while lines.last == "" { lines.removeLast() }
        lines.append("")
        lines.append(key)
        lines.append(contentsOf: detailLines(for: item, indent: "  ")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        lines.append("")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Un-ticking: take the entry back out. `completedAt` is passed
    /// separately because the item has already been cleared by the time
    /// this runs. A day file left with no entries is removed.
    func removeCompletion(_ item: TodoItem, completedAt at: Date, from store: TodoStore) {
        let day = VaultFormatters.cached("yyyy-MM-dd").string(from: at)
        let url = archiveDirectory.appendingPathComponent("\(day).md")
        guard let body = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = body.components(separatedBy: "\n")
        let key = archiveKeyLine(for: item, at: at, store: store)
        guard let start = lines.firstIndex(of: key) else { return }
        var end = start + 1
        while end < lines.count, lines[end].hasPrefix("  ") { end += 1 }
        lines.removeSubrange(start..<end)
        if start > 0, start - 1 < lines.count, lines[start - 1].isEmpty,
           start >= lines.count || lines[start].isEmpty {
            lines.remove(at: start - 1)
        }
        if !lines.contains(where: { $0.hasPrefix("- [x] ") }) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// The daily sweep: confirm every old completion is recorded, and report
    /// which ids are — the caller only removes those from the live store, so
    /// a failed write can never lose a to-do.
    func archive(_ items: [TodoItem], from store: TodoStore) -> Set<UUID> {
        var archived = Set<UUID>()
        for item in items where recordCompletion(item, from: store) {
            archived.insert(item.id)
        }
        return archived
    }

    private func archiveKeyLine(for item: TodoItem, at: Date, store: TodoStore) -> String {
        var line = "- [x] \(item.title)"
        if let section = store.collection(id: item.collectionID)?.name {
            line += " (\(section))"
        }
        line += " ✅ \(VaultFormatters.cached("yyyy-MM-dd").string(from: at))"
            + " \(VaultFormatters.cached("HH:mm").string(from: at))"
        return line
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
