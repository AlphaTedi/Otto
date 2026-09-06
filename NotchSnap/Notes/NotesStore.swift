import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - QuickNote — one note in the stream

/// Where a note's title came from.
///
/// It is stored, not inferred, because the whole disclosure contract hangs off
/// it: a generated title wears a badge and can be regenerated, a hand-typed
/// one wears nothing and must never be touched by the model again.
enum NoteTitleSource: String, Codable {
    /// The model proposed it. Shows the badge, answers ⌘⇧R.
    case generated
    /// The date fallback — no subject found, or no engine available.
    case date
    /// The user typed it. Permanent: generation is off for this note forever.
    case user
}

struct QuickNote: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    /// EKReminder identifier if this note was promoted to a reminder.
    /// Promotion keeps both — the note stays in history, linked.
    var promotedReminderID: String?
    /// Proposed, never required. A note is filed by its body; the title is a
    /// way to find it again, which is why nothing waits for one.
    var title: String
    var titleSource: NoteTitleSource

    var firstLine: String {
        content.split(separator: "\n").first.map(String.init) ?? content
    }

    /// Everything after the first line, for the stream's preview when the
    /// title came from that first line.
    var previewLine: String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        let body = lines.dropFirst().first.map(String.init)
        return (body?.isEmpty == false ? body! : firstLine)
    }

    /// Words, not markers: `# `, `- ` and `**` are formatting, and counting
    /// them would make the number climb every time the note was styled.
    var wordCount: Int {
        NoteMarkdown.plainText(content)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    init(id: UUID = UUID(), content: String, createdAt: Date = Date(),
         updatedAt: Date = Date(), promotedReminderID: String? = nil,
         title: String, titleSource: NoteTitleSource) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.promotedReminderID = promotedReminderID
        self.title = title
        self.titleSource = titleSource
    }

    // MARK: Hand-rolled decoding
    //
    // Synthesized Codable REJECTS a file that is missing a key, so adding
    // `title` and `titleSource` to the struct would have made every existing
    // notes.json undecodable — and the store's loader silently falls back to
    // an empty array on a decode failure, so the failure mode is not an error
    // message, it is the user's notes being gone (CLAUDE.md, storage rules).
    // Every new field gets a decodeIfPresent line here.

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, updatedAt, promotedReminderID, title, titleSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        promotedReminderID = try c.decodeIfPresent(String.self, forKey: .promotedReminderID)
        // A note written before titles existed is named from its own first
        // line rather than from the date: the text is right there, and
        // "Note del 3 agosto" for a note that plainly says what it is would
        // be a worse name than the one the note already gives itself.
        let stored = try c.decodeIfPresent(String.self, forKey: .title)
        if let stored, !stored.isEmpty {
            title = stored
            titleSource = try c.decodeIfPresent(NoteTitleSource.self, forKey: .titleSource) ?? .generated
        } else if let drawn = NoteTitler.heuristicTitle(for: content) {
            // Drawn from the body, so it is a PROPOSAL: it wears the badge and
            // answers ⌘⇧R like any other. Filing it as `.date` would have hidden
            // the badge on exactly the notes whose names the user is most likely
            // to want to change.
            title = drawn
            titleSource = .generated
        } else {
            title = NoteTitler.dateTitle(for: createdAt)
            titleSource = .date
        }
    }
}

// MARK: - Pending delete — the 5-second undo window

struct PendingNoteDelete: Equatable {
    let note: QuickNote
    /// Where it was, so undo puts it back where the eye left it rather than
    /// at the top of the stream.
    let index: Int
    let title: String
}

// MARK: - NotesStore — notes.json persistence (same pattern as ShelfStore)
//
// Notes persist indefinitely (a running log, no expiry — unlike the tray).
// The composer auto-saves into a draft — on disk from the first keystroke —
// and ↩ closes that draft into the stream. It does NOT mean "persist":
// persistence already happened.

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [QuickNote] = []
    /// Live composer text — auto-saved to disk with the notes list.
    @Published var draft: String = ""

    // MARK: UI state
    //
    // The note model is unchanged by any of this; it is all "which one is
    // open" and "what is the composer doing".

    /// Non-nil while one note fills the space instead of the stream.
    @Published var openNoteID: UUID?
    /// The row the keyboard is on in the stream. Independent of `openNoteID`.
    @Published var selectedNoteID: UUID?
    /// The entry that just landed — drives the drop and the brief highlight.
    @Published private(set) var landingNoteID: UUID?
    /// Two words, and only two: `Saved`, or `Saving…` while a write is in
    /// flight. No timestamps, no "all changes saved".
    @Published private(set) var isWriting = false
    /// The row is gone from the stream immediately; the file follows only when
    /// this expires. No confirmation dialog anywhere in this surface.
    @Published private(set) var pendingDelete: PendingNoteDelete?

    /// One-shot requests, the same pattern the to-do panel uses for its own
    /// focus: the store knows where the caret belongs, the view answers after
    /// the redraw rather than racing it.
    @Published private(set) var composerFocusRequest: UInt = 0
    @Published private(set) var renameRequest: UInt = 0

    private var saveWork: Task<Void, Never>?
    private var landingWork: Task<Void, Never>?
    private var deleteWork: Task<Void, Never>?
    private var titleWork: [UUID: Task<Void, Never>] = [:]

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

    // MARK: - Reading

    /// The stream, in the order the user has it.
    ///
    /// Was `sorted(by: updatedAt)`. A sort and a drag cannot both own the
    /// order: every manual move would have been undone by the next edit, and
    /// silently, because the row would spring back only when something else
    /// touched it. The array IS the order now — new notes go in at the top,
    /// which is the same default the sort produced — and a drag rewrites it.
    var stream: [QuickNote] { notes }

    func note(id: UUID) -> QuickNote? { notes.first { $0.id == id } }

    var openNote: QuickNote? { openNoteID.flatMap(note(id:)) }

    // MARK: - Mutations

    /// Close the draft into the stream and ask for a title.
    ///
    /// The title is requested AFTER the entry lands, never while the user is
    /// typing: a title that mutates mid-sentence is noise.
    @discardableResult
    func commitDraft(promotedReminderID: String? = nil) -> QuickNote? {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let note = QuickNote(
            content: content,
            promotedReminderID: promotedReminderID,
            // Named from its own words for the instant between landing and the
            // model answering, so the row never appears blank and never has to
            // shift when the real title arrives.
            title: NoteTitler.heuristicTitle(for: content) ?? NoteTitler.dateTitle(for: Date()),
            titleSource: .date
        )
        withAnimation(Motion.contentHug) {
            notes.insert(note, at: 0)
            landingNoteID = note.id
        }
        draft = ""
        scheduleSave()
        holdLanding(note.id)
        requestTitle(for: note.id)
        return note
    }

    func draftChanged() {
        scheduleSave()
    }

    /// Take the row out of the stream now; move the file later.
    ///
    /// No confirmation. A dialog asks the user to be certain about something
    /// they can simply undo, and the undo is the honest version of the same
    /// safety (handoff, decision 7).
    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]
        if openNoteID == id { openNoteID = nil }
        withAnimation(Motion.swap) {
            notes.remove(at: index)
            pendingDelete = PendingNoteDelete(note: note, index: index, title: note.title)
        }
        HapticManager.shared.itemDeleted()
        scheduleSave()
        deleteWork?.cancel()
        deleteWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Motion.hintFade) { self.pendingDelete = nil }
        }
    }

    /// Put it back where it was. The state is rewritten, not recovered from a
    /// file — nothing has been moved yet, which is the point of the window.
    func undoDelete() {
        guard let pending = pendingDelete else { return }
        deleteWork?.cancel()
        deleteWork = nil
        withAnimation(Motion.contentHug) {
            notes.insert(pending.note, at: min(pending.index, notes.count))
            pendingDelete = nil
        }
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

    /// Edit a note's body in place. There is no edit mode and no Save button:
    /// the open note IS the editor.
    func setBody(_ text: String, for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }), notes[idx].content != text else { return }
        notes[idx].content = text
        notes[idx].updatedAt = Date()
        scheduleSave()
    }

    /// A hand-typed title is final. The badge goes, and the model is locked
    /// out of this note permanently.
    func rename(_ id: UUID, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = notes.firstIndex(where: { $0.id == id }), !clean.isEmpty else { return }
        titleWork[id]?.cancel()
        titleWork[id] = nil
        notes[idx].title = clean
        notes[idx].titleSource = .user
        notes[idx].updatedAt = Date()
        scheduleSave()
    }

    func duplicate(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let source = notes[idx]
        let copy = QuickNote(content: source.content,
                             title: source.title,
                             titleSource: source.titleSource)
        withAnimation(Motion.contentHug) { notes.insert(copy, at: idx) }
        scheduleSave()
    }

    // MARK: - Navigation
    //
    // Switching space is a TodoStore mode change, because the space bar and
    // the panel chrome belong to it. Notes owns only what happens inside.

    /// Enter the Notes space with the caret in the composer.
    func enterSpace() {
        closeNoteState()
        TodoStore.shared.setMode(.notes)
        focusComposer()
    }

    /// Leave Notes and go back to the list that was on screen.
    func leaveSpace() {
        closeNoteState()
        TodoStore.shared.setMode(.browsing)
    }

    func focusComposer() {
        composerFocusRequest &+= 1
    }

    func beginRename() {
        renameRequest &+= 1
    }

    func open(_ id: UUID) {
        guard note(id: id) != nil else { return }
        withAnimation(Motion.swap) {
            openNoteID = id
            selectedNoteID = id
        }
        // The CONTENT, not the title. Opening a note is "let me get at what I
        // wrote", and landing in the title with it selected offered a rename
        // nobody asked for — one keystroke from replacing the name of the note
        // you meant to read (Marcello, 2026-09-06). Renaming is still a click
        // into the title, or Rename in the row menu.
        focusBody()
    }

    /// ⌘[, the chevron, or Esc. One level, not all the way out.
    func closeNote() {
        withAnimation(Motion.swap) { openNoteID = nil }
        focusComposer()
    }

    private func closeNoteState() {
        openNoteID = nil
    }

    /// Move the keyboard selection through the stream. Not animated: this is a
    /// key repeated dozens of times a minute, and animating it would put the
    /// highlight permanently behind the user's fingers.
    func moveSelection(_ offset: Int) {
        let entries = stream
        guard !entries.isEmpty else { return }
        guard let current = selectedNoteID,
              let index = entries.firstIndex(where: { $0.id == current }) else {
            selectedNoteID = entries.first?.id
            return
        }
        let next = min(max(index + offset, 0), entries.count - 1)
        selectedNoteID = entries[next].id
    }

    // MARK: - Export
    //
    // A standalone .md for ONE note, written where the user chooses. It does
    // not touch the Notes.md mirror and does not become a second writer of it:
    // the mirror is the app's copy of everything, this is the user's copy of
    // one thing.
    func exportOpenNote() {
        guard let note = openNote else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = Self.fileName(for: note)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let stamp = DateFormatter()
        stamp.locale = Locale.current
        stamp.dateStyle = .long
        stamp.timeStyle = .short
        let document = "# \(note.title)\n\n_\(stamp.string(from: note.createdAt))_\n\n\(note.content)\n"
        try? document.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func fileName(for note: QuickNote) -> String {
        var base = note.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Note" }
        return base + ".md"
    }

    /// Move a note in front of another. Reordering the array, not a field:
    /// there is nothing to sort by any more.
    func reorder(_ id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = notes.firstIndex(where: { $0.id == id }),
              let target = notes.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(Motion.contentHug) {
            let note = notes.remove(at: from)
            let insertAt = notes.firstIndex(where: { $0.id == targetID }) ?? target
            notes.insert(note, at: insertAt)
        }
        HapticManager.shared.reorderCommitted()
        scheduleSave()
    }

    func moveToEnd(_ id: UUID) {
        guard let from = notes.firstIndex(where: { $0.id == id }), from != notes.count - 1 else { return }
        withAnimation(Motion.contentHug) {
            let note = notes.remove(at: from)
            notes.append(note)
        }
        HapticManager.shared.reorderCommitted()
        scheduleSave()
    }

    /// One-shot: put the caret in the OPEN note's body.
    @Published private(set) var bodyFocusRequest: UInt = 0
    func focusBody() { bodyFocusRequest &+= 1 }

    // MARK: - Titles

    /// Ask for a title, unless the user has already given one.
    func requestTitle(for id: UUID, force: Bool = false) {
        guard let note = note(id: id) else { return }
        guard force || note.titleSource != .user else { return }
        titleWork[id]?.cancel()
        titleWork[id] = Task { @MainActor [weak self] in
            let proposed = await NoteTitler.title(for: note.content)
            guard !Task.isCancelled, let self,
                  let idx = self.notes.firstIndex(where: { $0.id == id }) else { return }
            // The user may have typed a title while the request was in flight.
            // Theirs wins, always.
            guard self.notes[idx].titleSource != .user else { return }
            guard let proposed else { return }
            withAnimation(Motion.hintFade) {
                self.notes[idx].title = proposed.text
                self.notes[idx].titleSource = proposed.source
            }
            self.scheduleSave()
        }
    }

    /// Hold the landing highlight, then let it fade. Skipped entirely under
    /// Reduce Motion — there is no drop to explain.
    private func holdLanding(_ id: UUID) {
        landingWork?.cancel()
        guard !Motion.isReduced else { landingNoteID = nil; return }
        landingWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, self.landingNoteID == id else { return }
            withAnimation(Motion.hintFade) { self.landingNoteID = nil }
        }
    }

    // MARK: - Persistence (debounced)

    private func scheduleSave() {
        // Notes ride along in the Markdown storage folder too (Notes.md).
        // ONE writer: nothing in this surface writes a second copy anywhere.
        MarkdownVault.shared.scheduleExport()
        isWriting = true
        saveWork?.cancel()
        saveWork = Task { @MainActor [weak self] in
            // 400ms, the handoff's debounce. Short enough that "Saved" is true
            // by the time the eye reaches it.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.write()
            self.isWriting = false
        }
    }

    /// Quit-time flush — same contract as TodoStore.saveNow().
    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        write()
        isWriting = false
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
