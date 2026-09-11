import Foundation
import SwiftUI

// MARK: - Todo models
//
// NotchSnap's own lightweight to-do system. This is DELIBERATELY distinct
// from the EventKit-backed reminders in ReminderStore: a TodoItem is local,
// collection-scoped, and never touches Apple Reminders. The two coexist —
// the Notes composer still promotes to EKReminder; to-dos are their own
// keyboard-first system.

enum TodoUrgency: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low:    return L10n.t("urgency.low")
        case .medium: return L10n.t("urgency.medium")
        case .high:   return L10n.t("urgency.high")
        }
    }

    /// UG-4: the full concept, stated in words — "Medium priority", never a
    /// bare "Medium". Used everywhere urgency is the subject (creation combo,
    /// its options, the dot tooltip).
    var fullLabel: String {
        L10n.t("urgency.\(rawValue).full")
    }

    /// TD-7: secondary to the collection colour — a small dot, never an accent
    /// competing with the collection's identity. Values from DesignSystem.
    var color: Color {
        switch self {
        case .low:    return DSColor.urgencyLow
        case .medium: return DSColor.urgencyMedium
        case .high:   return DSColor.urgencyHigh
        }
    }

    /// KB-4: cycle order, wrapping back to low.
    var next: TodoUrgency {
        switch self {
        case .low:    return .medium
        case .medium: return .high
        case .high:   return .low
        }
    }
}

struct TodoCollection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var shortcutKey: String?
    /// TD-8: true only for the built-in smart Today aggregation. Today is a
    /// live query across every collection, not a membership bucket.
    var isSystemToday: Bool = false

    var color: Color {
        Color(nsColor: NSColor.fromHex(colorHex) ?? .systemBlue)
    }
}

/// NC-3: a step inside a to-do's checklist — a sub-detail, never a peer of
/// top-level to-dos (no urgency, no collection, no completion timestamp).
struct ChecklistItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool = false
}

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var collectionID: UUID
    var urgency: TodoUrgency = .low
    var isCompleted: Bool = false
    var completedAt: Date?
    var dueDate: Date?
    var sortOrder: Int
    let createdAt: Date
    /// NC-1: freeform note, shown only in the row's expanded state.
    var note: String = ""
    /// NC-3: sub-steps, shown only in the expanded state.
    var checklist: [ChecklistItem] = []

    /// The note this to-do was lifted out of, and the phrase it was lifted
    /// from — the link that lets an underline in a note show whether it is
    /// done.
    ///
    /// THE LINK LIVES HERE, and that is the whole storage decision. The other
    /// option was writing `- [ ] phrase` into the note's markdown, which would
    /// be readable in Obsidian and would also EDIT THE USER'S FILE — the one
    /// thing this feature promises not to do. A to-do pointing back at a phrase
    /// costs nothing on the note's side: the `.md` stays exactly what the user
    /// typed.
    ///
    /// The phrase, not a character range: ranges do not survive editing the
    /// text above them, and a link that silently points at the wrong words is
    /// worse than one that quietly stops matching.
    var sourceNoteID: UUID?
    var sourcePhrase: String?

    var hasDetails: Bool { !note.isEmpty || !checklist.isEmpty }

    init(id: UUID, title: String, collectionID: UUID, urgency: TodoUrgency,
         isCompleted: Bool, completedAt: Date?, dueDate: Date?,
         sortOrder: Int, createdAt: Date,
         note: String = "", checklist: [ChecklistItem] = [],
         sourceNoteID: UUID? = nil, sourcePhrase: String? = nil) {
        self.id = id
        self.title = title
        self.collectionID = collectionID
        self.urgency = urgency
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.note = note
        self.checklist = checklist
        self.sourceNoteID = sourceNoteID
        self.sourcePhrase = sourcePhrase
    }

    // Hand-rolled decode so pre-note/checklist todos.json files (which lack
    // the new keys) keep loading — synthesized Codable would throw on them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        collectionID = try c.decode(UUID.self, forKey: .collectionID)
        urgency = try c.decodeIfPresent(TodoUrgency.self, forKey: .urgency) ?? .low
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        // decodeIfPresent, like every field added after the first release: a
        // todos.json written before this feature existed has neither key, and
        // synthesized Codable would throw on the whole file rather than on the
        // two values it cannot find.
        sourceNoteID = try c.decodeIfPresent(UUID.self, forKey: .sourceNoteID)
        sourcePhrase = try c.decodeIfPresent(String.self, forKey: .sourcePhrase)
    }
}
