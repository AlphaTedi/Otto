import Foundation
import SwiftUI

// MARK: - QuickNote — one quick-capture note

struct QuickNote: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    /// EKReminder identifier if this note was promoted to a reminder.
    /// Promotion keeps both — the note stays in history, linked.
    var promotedReminderID: String?

    var firstLine: String {
        content.split(separator: "\n").first.map(String.init) ?? content
    }
}

// MARK: - NotesStore — notes.json persistence (same pattern as ShelfStore)
//
// Notes persist indefinitely (a running log, no expiry — unlike the tray).
// The composer auto-saves into a draft note; committing (new-note action or
// promoting to a reminder) moves it into history.

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [QuickNote] = []
    /// Live composer text — auto-saved to disk with the notes list.
    @Published var draft: String = ""

    private var saveWork: Task<Void, Never>?

    private static var notesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("\(AppBuild.supportRoot)/Notes", isDirectory: true)
    }
    private var indexURL: URL { Self.notesDirectory.appendingPathComponent("notes.json") }
    private var draftURL: URL { Self.notesDirectory.appendingPathComponent("draft.txt") }

    private init() {
        try? FileManager.default.createDirectory(at: Self.notesDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) {
            notes = decoded
        }
        draft = (try? String(contentsOf: draftURL, encoding: .utf8)) ?? ""
    }

    // MARK: - Mutations

    /// Commit the current draft into history and clear the composer.
    /// Returns the committed note (nil if the draft was empty).
    @discardableResult
    func commitDraft(promotedReminderID: String? = nil) -> QuickNote? {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let note = QuickNote(
            id: UUID(), content: content,
            createdAt: Date(), updatedAt: Date(),
            promotedReminderID: promotedReminderID
        )
        withAnimation(NotchAnimation.newScreenshot) {
            notes.insert(note, at: 0)
        }
        draft = ""
        scheduleSave()
        return note
    }

    func draftChanged() {
        scheduleSave()
    }

    func delete(_ id: UUID) {
        withAnimation(Motion.swap) {
            notes.removeAll { $0.id == id }
        }
        HapticManager.shared.itemDeleted()
        scheduleSave()
    }

    /// Load a history note back into the composer for editing.
    func edit(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        // Anything already in the composer is committed first, not lost.
        commitDraft()
        draft = notes[idx].content
        notes.remove(at: idx)
        scheduleSave()
    }

    // MARK: - Persistence (debounced)

    private func scheduleSave() {
        // Notes ride along in the Markdown storage folder too (Notes.md).
        MarkdownVault.shared.scheduleExport()
        saveWork?.cancel()
        saveWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.write()
        }
    }

    /// Quit-time flush — same contract as TodoStore.saveNow().
    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(notes) {
            // Atomic, matching every other store — a crash mid-write must
            // not be able to truncate the notes index.
            try? data.write(to: indexURL, options: .atomic)
        }
        try? draft.write(to: draftURL, atomically: true, encoding: .utf8)
    }
}
