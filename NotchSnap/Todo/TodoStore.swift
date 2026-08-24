import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Private drag type
//
// Reordering used to hand SwiftUI an NSString, which registers as
// `public.plain-text`. The notch's own shelf accepts `.plainText`, so dragging
// a to-do lit the ENTIRE panel with the system's green drop-target ring
// (Marcello, 2026-07-26) — the app was offering to drop the row into itself.
//
// A private type that conforms to nothing public means only our own reorder
// targets can ever match it. Declared in Info.plist under
// UTExportedTypeDeclarations.
extension UTType {
    static let notchSnapInternalItem = UTType(exportedAs: "com.notchsnap.internal-item")
}
import SwiftUI

// MARK: - TodoStore — source of truth for collections + to-dos
//
// Persistence reuses the app's established pattern (one JSON file in
// Application Support, debounced writes) — same as ShelfStore/NotesStore.

/// The panel is ONE surface with modes (design PRD §§3-5): browsing is home;
/// creation is the "+" tab; category creation and Quick Find replace the
/// content in place. No floating windows.
///
/// There is no `create` mode any more. Creating a to-do used to replace the
/// whole panel with a card — a title field, two combo boxes and a Create
/// button, detached from the section it was filing into. It is now a draft row
/// pinned above the list you are already looking at (Marcello's spec,
/// 2026-08-16), which needs no mode of its own: see `draftTitle`.
enum TodoPanelMode: Equatable {
    case browsing
    case newCategory
    case find
    /// Voice brain-dump: listening → parsing → review (see
    /// VoiceCaptureController). Owned by that controller, not this store.
    case voice
}

@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    @Published private(set) var collections: [TodoCollection] = []
    @Published private(set) var items: [TodoItem] = []

    /// The collection currently being browsed. `nil` never happens after init.
    @Published var activeCollectionID: UUID?
    /// Persisted across quick-entry invocations (KB-3: category defaults to
    /// the last-used collection).
    @Published var lastUsedCollectionID: UUID?
    /// TD-3: Completed is collapsed by default.
    @Published var completedExpanded = false
    /// KB-6: keyboard focus within the browsing list.
    @Published var focusedItemID: UUID?
    /// §8.3 completion sequencing: items already marked complete whose row is
    /// still holding its place in the open list. The checkbox fill and
    /// strike-through land instantly; ~0.35s later the item leaves this set
    /// and its row exits together with the panel-height shrink.
    @Published private(set) var settlingItemIDs: Set<UUID> = []
    private var settleTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Panel modes (design PRD §§2-5)

    @Published var panelMode: TodoPanelMode = .browsing
    /// §2.3: the `?` reference lives INSIDE the panel as an overlay.
    @Published var showShortcuts = false
    /// NC-1/NC-2: at most one row shows its note + checklist at a time.
    @Published var expandedItemID: UUID?

    // MARK: - Inline creation
    //
    // The draft row. It is ALWAYS on screen, at the top of the list — not
    // summoned by a shortcut. Making it appear only on ⌃⇧N left the panel
    // with no visible way to create anything at all: "when I open the notch
    // normally, I don't see, and I don't know how to actually create new
    // to-do items" (Marcello, 2026-08-16). It is the same reasoning that put
    // an always-open trailing row in the step checklist, one level up.
    //
    // ⌃⇧N now puts the CARET in it rather than conjuring it, ⇥ re-aims it at
    // another section, and ⏎ files it there.
    //
    // The row is fixed at the top and ⇥ changes the destination and the list
    // beneath it, never the row itself. That is why the draft lives here
    // rather than in the view — the list below is rebuilt
    // (`.id(collection.id)`) on every section switch, and anything owned by
    // that subtree would lose its text and its caret exactly when the user is
    // mid-sentence.

    /// What is being typed into the draft row.
    @Published var draftTitle = ""
    /// True while the caret is actually in the draft row.
    ///
    /// Distinct from "the row exists", which is now always. Only the caret
    /// pins the panel open; a row merely sitting there must not stop the
    /// notch from ever auto-collapsing again.
    @Published var draftFocused = false
    /// Set to ask the view to take the caret; the field clears it once it has.
    /// A flag rather than a direct call because the field may not exist yet —
    /// ⌃⇧N from another app asks for focus before the panel has even opened.
    @Published var draftWantsFocus = false

    /// Where a committed draft will actually land.
    ///
    /// Today is a live query across every collection, not a bucket, so it can
    /// never be a destination. A draft aimed at it files into the default
    /// section instead — and the row wears THAT section's color, so the
    /// redirection is visible while typing rather than a surprise on ⏎.
    var draftDestination: TodoCollection? {
        if let active = activeCollection, !active.isSystemToday { return active }
        return defaultCreationCollectionID.flatMap { collection(id: $0) }
    }

    /// ⌃⇧N / ⌘N: put the caret in the draft row.
    ///
    /// `fromGlobalShortcut` also jumps to the user's default section, never
    /// whatever was last browsed — someone summoning the notch from another
    /// app has no idea which tab it was left on.
    func focusDraft(fromGlobalShortcut: Bool) {
        if fromGlobalShortcut, let target = defaultCreationCollectionID {
            withAnimation(NotchAnimation.contentHug) { activeCollectionID = target }
        }
        panelMode = .browsing
        // The caret is about to belong to the draft; nothing in the list below
        // should still look selected or open underneath it.
        focusedItemID = nil
        expandedItemID = nil
        draftWantsFocus = true
    }

    /// Step out of the draft field, keeping what was typed.
    ///
    /// Deliberately not a discard. Escape backs out ONE level everywhere else
    /// in this panel (close policy rule 3), so here it hands the caret back to
    /// the list and a second Escape closes the notch — two presses to get all
    /// the way out, and a half-written to-do survives both. Clicking dead
    /// space in the panel lands here too.
    ///
    /// It actually resigns first responder rather than only lowering a flag.
    /// `draftFocused` is REPORTED by the text view, not obeyed by it, so
    /// clearing it alone left the caret blinking in a field the app had
    /// already decided was unfocused (Marcello, 2026-08-16).
    func blurDraft() {
        draftWantsFocus = false
        draftFocused = false
        guard let window = NSApp.keyWindow,
              (window.firstResponder as? NSView)?.identifier
                  == HighlightingTitleField.fieldIdentifier else { return }
        window.makeFirstResponder(nil)
    }

    /// The panel closed: the caret is gone with it, but the text is not.
    /// Close policy rule 2 — an outside click always closes, and "the creation
    /// draft survives (KB-11), nothing is lost".
    func releaseDraftFocus() {
        draftWantsFocus = false
        draftFocused = false
    }

    /// ⇥ — the tab cycle, which is also plain section switching.
    ///
    /// One function for both: with the draft row always present, "change the
    /// destination" and "switch tabs" are the same act, and Marcello asked for
    /// ⇥ to switch sections whether or not he is typing. Today IS included
    /// here — it is a tab like any other to read — and `draftDestination`
    /// handles the fact that nothing can be filed into it.
    func cycleCollection(by offset: Int = 1) {
        let row = visibleCollections
        guard row.count > 1 else { return }
        let idx = row.firstIndex { $0.id == activeCollectionID } ?? 0
        let count = row.count
        let next = ((idx + offset) % count + count) % count
        withAnimation(NotchAnimation.contentHug) {
            activeCollectionID = row[next].id
        }
        focusedItemID = nil
        expandedItemID = nil
    }

    /// ⏎ — file the draft into the destination the row is pointing at, and
    /// hand the caret back.
    ///
    /// Keeping focus so a second to-do was "just more typing" cost more than
    /// it saved: writing one to-do and then closing the notch took two
    /// Escapes, one to leave a field the user had already finished with
    /// (Marcello, 2026-08-16). Committing is the end of the sentence, so the
    /// row returns to its resting placeholder state and a single Escape now
    /// closes the panel. ⌃⇧N is one keystroke away for the next one.
    @discardableResult
    func commitDraft() -> Bool {
        // NL-4: a recognized date phrase leaves the title and becomes a real
        // due date, exactly as the old creation card did.
        let parsed = NLDateParser.parse(draftTitle)
        let title = parsed?.cleanedTitle ?? draftTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let target = draftDestination?.id,
              addItem(title: title, collectionID: target,
                      urgency: .low, dueDate: parsed?.date) != nil else { return false }
        draftTitle = ""
        blurDraft()
        return true
    }

    /// While any non-browsing surface is up, the notch must not auto-collapse
    /// under the user mid-typing. Checked by NotchController.triggerCollapse.
    /// A caret in the draft row counts; the row merely existing does not.
    var isPanelPinnedOpen: Bool {
        panelMode != .browsing || showShortcuts || draftFocused
    }

    /// QF: Quick Find state — query, cross-category matches, ↑↓ selection.
    @Published var findQuery = ""
    @Published var findSelection = 0

    /// Where ⌃⇧N starts: simply the FIRST real section in the tab row.
    ///
    /// It used to be an explicitly chosen default (FB8), stored per-category
    /// and set from a tab's context menu, which took precedence over tab
    /// order. Two mechanisms for one outcome, and the invisible one won —
    /// so a user who dragged Work to the front and then pressed ⌃⇧N still
    /// landed in Personal, with nothing on screen explaining why (Marcello,
    /// 2026-08-16). Order is the visible mechanism, so order is the only one:
    /// drag the section you use most to the front and the shortcut follows it.
    ///
    /// Today is skipped because it is a live query, not a bucket.
    var defaultCreationCollectionID: UUID? {
        firstUserCollection?.id
    }

    /// Leaving voice mode must also tear the capture session down, so mode
    /// changes route through here rather than assigning panelMode directly.
    func exitVoiceIfNeeded(_ newMode: TodoPanelMode) {
        if panelMode == .voice, newMode != .voice {
            VoiceCaptureController.shared.cancel()
        }
    }

    func setMode(_ mode: TodoPanelMode) {
        guard panelMode != mode else { return }
        exitVoiceIfNeeded(mode)
        withAnimation(NotchAnimation.contentHug) {
            panelMode = mode
            if mode == .find { findQuery = ""; findSelection = 0 }
            // A surface that replaces the list replaces the draft row sitting
            // above it too — there is nothing left for the caret to be in.
            if mode != .browsing { draftFocused = false; draftWantsFocus = false }
        }
    }

    /// QF-1: cross-category title search.
    var findMatches: [TodoItem] {
        let q = findQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return items
            .filter { !$0.isCompleted && $0.title.localizedCaseInsensitiveContains(q) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// QF-3: jump straight to the match and its category.
    func jumpToFindSelection() {
        let matches = findMatches
        guard !matches.isEmpty else { setMode(.browsing); return }
        let item = matches[min(findSelection, matches.count - 1)]
        withAnimation(NotchAnimation.contentHug) {
            panelMode = .browsing
            activeCollectionID = item.collectionID
            focusedItemID = item.id
        }
    }

    // MARK: - Notes & checklist (NC-1..4)

    /// End whatever is being typed in the panel, committing it.
    ///
    /// Two different edits can be live: a row's title, and the draft row at
    /// the top. Clicking dead space means "stop typing" for both — singling
    /// out one of them is the bug this exists to prevent.
    ///
    /// Closing the row is what actually releases the caret: the editor only
    /// exists while a row is expanded, so collapsing removes the focused
    /// field, and TodoItemRow's `onChange(of: isExpanded)` saves the draft on
    /// the way out. One path, so clicking off a field can never diverge from
    /// what Return and clicking-the-row-shut already do.
    func endEditing() {
        blurDraft()
        // Selection goes too, not just the open row.
        //
        // Clicking a to-do rings it blue and there was no way to un-ring it:
        // arrows moved the selection along, but nothing put it back to nobody
        // selected (Marcello, 2026-08-19). A selection you cannot clear is a
        // mode the user has been put into and cannot leave.
        focusedItemID = nil
        guard expandedItemID != nil else { return }
        withAnimation(NotchAnimation.contentHug) { expandedItemID = nil }
    }

    /// Rename an existing to-do.
    ///
    /// Until now a title was write-once: you could add a note or a step to a
    /// row but never fix the words themselves, so a typo meant deleting the
    /// item and retyping it — "kind of a blocker" for a developer using this
    /// daily (Marcello's tester, 2026-08-10).
    ///
    /// An empty or whitespace-only title is REFUSED rather than saved: a row
    /// with no text is unidentifiable and unrecoverable from the list, so the
    /// edit is simply discarded and the old title stands.
    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].title != trimmed else { return }
        items[idx].title = trimmed
        scheduleSave()
    }

    func setNote(_ note: String, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].note = note
        scheduleSave()
    }

    func addChecklistItem(_ title: String, to id: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(NotchAnimation.contentHug) {
            items[idx].checklist.append(ChecklistItem(id: UUID(), title: trimmed, isDone: false))
        }
        scheduleSave()
    }

    /// Rename a step.
    ///
    /// Steps were write-once: you could tick one or delete it, but the words
    /// themselves were fixed, so a typo meant deleting the step and retyping
    /// it — the same dead end the to-do TITLE had before `rename` (a user of
    /// Marcello's, 2026-08-18).
    ///
    /// Empty is REFUSED rather than saved, exactly as `rename` refuses it: a
    /// step with no text is unidentifiable and cannot be recovered from the
    /// list, so the edit is discarded and the old title stands. Deleting is
    /// what the × is for.
    func renameChecklistItem(_ stepID: UUID, in id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = items.firstIndex(where: { $0.id == id }),
              let step = items[idx].checklist.firstIndex(where: { $0.id == stepID }),
              items[idx].checklist[step].title != trimmed else { return }
        items[idx].checklist[step].title = trimmed
        scheduleSave()
    }

    func toggleChecklistItem(_ stepID: UUID, in id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              let step = items[idx].checklist.firstIndex(where: { $0.id == stepID }) else { return }
        withAnimation(NotchAnimation.hintFade) {
            items[idx].checklist[step].isDone.toggle()
        }
        scheduleSave()
    }

    func deleteChecklistItem(_ stepID: UUID, in id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(NotchAnimation.contentHug) {
            items[idx].checklist.removeAll { $0.id == stepID }
        }
        scheduleSave()
    }

    // MARK: - Tab indicators (PR-1..3, revised 2026-07-23)

    /// How many to-dos are still open in a category — the number shown on its
    /// tab. nil when the category holds nothing at all (no indicator); 0 means
    /// "everything here is done" and renders as a checkmark.
    func remainingCount(for collection: TodoCollection) -> Int? {
        let open = openItems(in: collection).filter { !$0.isCompleted }.count
        let done = completedItems(in: collection).count
            + openItems(in: collection).filter(\.isCompleted).count
        guard open + done > 0 else { return nil }
        return open
    }

    /// Completed fraction — no longer drives the tab chip (the ring proved
    /// unreadable at 14pt), kept for any larger progress affordance.
    func progress(for collection: TodoCollection) -> Double? {
        let open = openItems(in: collection).filter { !$0.isCompleted }.count
        let done = completedItems(in: collection).count + openItems(in: collection).filter(\.isCompleted).count
        let total = open + done
        guard total > 0 else { return nil }
        return Double(done) / Double(total)
    }

    private var saveWork: Task<Void, Never>?

    // MARK: - Storage

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("\(AppBuild.supportRoot)/Todo", isDirectory: true)
    }
    private var fileURL: URL { Self.directory.appendingPathComponent("todos.json") }

    private struct Payload: Codable {
        var collections: [TodoCollection]
        var items: [TodoItem]
        var lastUsedCollectionID: UUID?
        // `defaultCollectionID` (FB8) was removed 2026-08-16 — tab order is now
        // the only thing that decides where ⌃⇧N files. Old files still carry
        // the key; Codable ignores keys the struct no longer declares, so they
        // keep loading and the value is simply dropped on the next save.
    }

    private init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        load()
        if collections.isEmpty { seedStarterCollections() }
        activeCollectionID = firstUserCollection?.id ?? collections.first?.id
        lastUsedCollectionID = lastUsedCollectionID ?? firstUserCollection?.id
    }

    /// TD-1: a starter set, fully renameable/deletable.
    private func seedStarterCollections() {
        // Seed colors come from the design reference palette (DT §0).
        collections = [
            TodoCollection(id: UUID(), name: "Today", colorHex: "#E8C15A",
                           sortOrder: 0, shortcutKey: "1", isSystemToday: true),
            TodoCollection(id: UUID(), name: "Work", colorHex: "#7FB8E0",
                           sortOrder: 1, shortcutKey: "2"),
            TodoCollection(id: UUID(), name: "Personal", colorHex: "#C99EE0",
                           sortOrder: 2, shortcutKey: "3"),
        ]
        scheduleSave()
    }

    // MARK: - Derived

    var firstUserCollection: TodoCollection? {
        collections.first { !$0.isSystemToday }
    }

    /// LAB: the sections a user actually sees. Today is not one of them.
    ///
    /// Today was a smart view aggregating meetings and anything due today.
    /// Meetings have their own panel now, and what was left was a section you
    /// could not file into, could not reorder meaningfully, and which sat
    /// first in a row whose first entry decides where ⌃⇧N lands. It is hidden
    /// rather than deleted — the collection still exists in the file, so
    /// nothing a user made goes anywhere, and turning it back on is one line.
    var visibleCollections: [TodoCollection] {
        collections.filter { !$0.isSystemToday }
    }

    var activeCollection: TodoCollection? {
        // Falls back to a VISIBLE section: resolving to Today would light no
        // tab and list nothing, which reads as the panel being broken.
        collections.first { $0.id == activeCollectionID }
            ?? firstUserCollection ?? collections.first
    }

    func collection(id: UUID) -> TodoCollection? {
        collections.first { $0.id == id }
    }

    /// TD-8: Today is a live smart aggregation — anything due today (or
    /// overdue) or flagged High urgency, pulled from every collection.
    /// Every other collection is a plain membership query.
    func openItems(in collection: TodoCollection) -> [TodoItem] {
        // A settling item is technically completed but its row hasn't exited
        // yet — it keeps its slot so the strike-through is visible in place.
        let stillVisible: (TodoItem) -> Bool = { [settlingItemIDs] in
            !$0.isCompleted || settlingItemIDs.contains($0.id)
        }
        let base: [TodoItem]
        if collection.isSystemToday {
            let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
            base = items.filter { item in
                guard stillVisible(item) else { return false }
                if item.urgency == .high { return true }
                if let due = item.dueDate, due < endOfToday { return true }
                return false
            }
        } else {
            base = items.filter { stillVisible($0) && $0.collectionID == collection.id }
        }
        return base.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// TD-3: Completed is scoped to the CATEGORY being browsed, most recent
    /// first. Today — being a smart cross-collection view — shows what was
    /// completed today, anywhere.
    func completedItems(in collection: TodoCollection) -> [TodoItem] {
        let base = items.filter { $0.isCompleted && !settlingItemIDs.contains($0.id) }
        let scoped: [TodoItem]
        if collection.isSystemToday {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            scoped = base.filter { ($0.completedAt ?? .distantPast) >= startOfToday }
        } else {
            scoped = base.filter { $0.collectionID == collection.id }
        }
        return scoped.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: - Collections

    @discardableResult
    func addCollection(name: String, colorHex: String) -> TodoCollection {
        let next = (collections.map(\.sortOrder).max() ?? -1) + 1
        let shortcut = next < 9 ? String(next + 1) : nil
        let collection = TodoCollection(
            id: UUID(), name: name, colorHex: colorHex,
            sortOrder: next, shortcutKey: shortcut
        )
        withAnimation(NotchAnimation.contentHug) { collections.append(collection) }
        scheduleSave()
        return collection
    }

    func deleteCollection(_ id: UUID) {
        guard let victim = collection(id: id), !victim.isSystemToday else { return }
        withAnimation(NotchAnimation.contentHug) {
            collections.removeAll { $0.id == id }
            items.removeAll { $0.collectionID == id }
        }
        if activeCollectionID == id { activeCollectionID = collections.first?.id }
        if lastUsedCollectionID == id { lastUsedCollectionID = firstUserCollection?.id }
        scheduleSave()
    }

    /// Tab order is the user's to own — "if my use case is mostly Work,
    /// Personal first is annoying" (Marcello, 2026-07-15). ⌘1…⌘9 and the
    /// default landing tab follow the new order automatically.
    func moveCollection(_ id: UUID, by offset: Int) {
        guard let from = collections.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard to >= 0, to < collections.count else { return }
        withAnimation(NotchAnimation.contentHug) {
            collections.swapAt(from, to)
            for (i, _) in collections.enumerated() {
                collections[i].sortOrder = i
            }
        }
        scheduleSave()
    }

    /// Drag-to-reorder for the tab row: drop `id` into `targetID`'s slot.
    /// Any tab can move, including Today — the "+" chips aren't collections
    /// so they're never part of this (Marcello, 2026-07-23).
    func moveCollection(_ id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = collections.firstIndex(where: { $0.id == id }),
              let to = collections.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(NotchAnimation.contentHug) {
            let moved = collections.remove(at: from)
            collections.insert(moved, at: to)
            for (i, _) in collections.enumerated() {
                collections[i].sortOrder = i
            }
        }
        scheduleSave()
    }

    /// Drop past the last tab. `moveCollection(_:before:)` can only ever land a
    /// section in FRONT of another one, so without this the trailing slot is
    /// unreachable by drag — the same gap the to-do list has `moveToEnd` for.
    func moveCollectionToEnd(_ id: UUID) {
        guard let from = collections.firstIndex(where: { $0.id == id }),
              from != collections.count - 1 else { return }
        withAnimation(NotchAnimation.contentHug) {
            let moved = collections.remove(at: from)
            collections.append(moved)
            for (i, _) in collections.enumerated() {
                collections[i].sortOrder = i
            }
        }
        scheduleSave()
    }

    /// KB-8: ⌘1…⌘9 select by tab order.
    func selectCollection(atIndex index: Int) {
        let ordered = visibleCollections.sorted { $0.sortOrder < $1.sortOrder }
        guard index >= 0, index < ordered.count else { return }
        withAnimation(NotchAnimation.contentHug) {
            activeCollectionID = ordered[index].id
            panelMode = .browsing
        }
        focusedItemID = nil
        expandedItemID = nil
    }

    func selectCollection(_ id: UUID) {
        withAnimation(NotchAnimation.contentHug) {
            activeCollectionID = id
            panelMode = .browsing
        }
        focusedItemID = nil
        expandedItemID = nil
    }

    // MARK: - Items

    @discardableResult
    func addItem(title: String, collectionID: UUID, urgency: TodoUrgency,
                 dueDate: Date? = nil) -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Today is a smart view, never a home — file into the last real
        // collection instead so the item is never stranded (KB-5 fallback).
        var target = collectionID
        if collection(id: target)?.isSystemToday ?? true {
            target = firstUserCollection?.id ?? collectionID
        }

        // TOP of the list, not the bottom. A new to-do appended below a long
        // list lands off-screen, which reads as nothing having happened at all
        // (Marcello, 2026-08-16). Ordering is the user's to change by dragging
        // — but the thing they just made has to be the thing they can see.
        let next = (items.filter { $0.collectionID == target }.map(\.sortOrder).min() ?? 0) - 1
        let item = TodoItem(
            id: UUID(), title: trimmed, collectionID: target,
            urgency: urgency, isCompleted: false, completedAt: nil,
            dueDate: dueDate, sortOrder: next, createdAt: Date()
        )
        withAnimation(NotchAnimation.contentHug) { items.append(item) }
        lastUsedCollectionID = target
        // Step 5 of the capture flow: the created to-do's collection becomes
        // the active tab, so it's visibly filed where the user put it.
        activeCollectionID = target
        HapticManager.shared.copyConfirmed()
        scheduleSave()
        // Onboarding's practice step waits for this: the shortcut opening the
        // notch is only half the lesson, and someone who stops there has not
        // yet made anything. See OnboardingPracticeView.
        NotificationCenter.default.post(name: .todoCreated, object: nil)
        // The notch deliberately stays open — see close policy rule 8, which
        // was withdrawn. The new row is at the top of the list behind the
        // draft; closing over it hid the only confirmation that anything
        // happened.
        return item
    }

    /// TD-4/TD-5: completing files into Completed; un-completing restores it
    /// to its original collection (collectionID was never cleared).
    ///
    /// §8.3 sequence on completion: the checkbox fill/strike-through land as
    /// near-instant feedback while the row HOLDS its slot ("settling"); the
    /// row exit and the panel shrink then fire together on contentHug.
    /// Re-toggling mid-settle cancels cleanly — springs preserve velocity, so
    /// an interrupted exit reverses instead of snapping.
    func toggleComplete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if items[idx].isCompleted {
            settleTasks[id]?.cancel()
            settleTasks[id] = nil
            withAnimation(NotchAnimation.contentHug) {
                settlingItemIDs.remove(id)
                items[idx].isCompleted = false
                items[idx].completedAt = nil
            }
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                items[idx].isCompleted = true
                items[idx].completedAt = Date()
                settlingItemIDs.insert(id)
            }
            settleTasks[id] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, let self else { return }
                withAnimation(NotchAnimation.contentHug) {
                    _ = self.settlingItemIDs.remove(id)
                }
                self.settleTasks[id] = nil
            }
        }
        HapticManager.shared.thumbnailSelect()
        scheduleSave()
    }

    func setUrgency(_ urgency: TodoUrgency, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            items[idx].urgency = urgency
        }
        scheduleSave()
    }

    /// KB-9: reassign an existing to-do to another collection.
    func move(_ id: UUID, toCollection collectionID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              let target = collection(id: collectionID), !target.isSystemToday else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            items[idx].collectionID = collectionID
        }
        scheduleSave()
    }

    func delete(_ id: UUID) {
        withAnimation(NotchAnimation.contentHug) {
            items.removeAll { $0.id == id }
        }
        HapticManager.shared.itemDeleted()
        scheduleSave()
    }

    /// TD-5: mouse drag-to-reorder — live re-slotting as the drag passes
    /// over a sibling row. Same sortOrder rewrite as the keyboard path.
    ///
    /// Works in EVERY tab including Today (Marcello, 2026-07-23). Today is a
    /// cross-collection smart view, so a full 0..n reindex there would also
    /// shuffle those items inside their own categories — instead we SWAP the
    /// two items' sortOrder values, which moves them in the Today view while
    /// leaving every other list untouched.
    /// Drop past the last row. `reorder(_:before:)` can only ever land an item
    /// in front of another one, so without this the bottom slot is unreachable.
    /// Sweep: drop every completed item in a category. The pile is history,
    /// not data — it accumulates forever otherwise, and Marcello had 19 sitting
    /// in Work (2026-08-04). Only ever removes items already marked done.
    func clearCompleted(in collectionID: UUID) {
        let before = items.count
        items.removeAll { $0.collectionID == collectionID && $0.isCompleted }
        guard items.count != before else { return }
        scheduleSave()
    }

    func moveToEnd(_ id: UUID) {
        guard let collection = activeCollection,
              let sourceIdx = items.firstIndex(where: { $0.id == id }) else { return }
        let ordered = openItems(in: collection)
        guard ordered.last?.id != id else { return }   // already last

        if collection.isSystemToday {
            // Today is a smart aggregation ordered by sortOrder, so "last"
            // just means one past the current maximum.
            let maxOrder = ordered.map(\.sortOrder).max() ?? 0
            withAnimation(NotchAnimation.contentHug) {
                items[sourceIdx].sortOrder = maxOrder + 1
            }
        } else {
            var reordered = ordered.filter { $0.id != id }
            if let moved = ordered.first(where: { $0.id == id }) { reordered.append(moved) }
            withAnimation(NotchAnimation.contentHug) {
                for (i, item) in reordered.enumerated() {
                    if let idx = items.firstIndex(where: { $0.id == item.id }) {
                        items[idx].sortOrder = i
                    }
                }
            }
        }
        scheduleSave()
    }

    func reorder(_ id: UUID, before targetID: UUID) {
        guard id != targetID, let collection = activeCollection else { return }
        let ordered = openItems(in: collection)
        guard let from = ordered.firstIndex(where: { $0.id == id }),
              let to = ordered.firstIndex(where: { $0.id == targetID }),
              let sourceIdx = items.firstIndex(where: { $0.id == id }),
              let targetIdx = items.firstIndex(where: { $0.id == targetID }) else { return }

        if collection.isSystemToday {
            withAnimation(NotchAnimation.contentHug) {
                let sourceOrder = items[sourceIdx].sortOrder
                items[sourceIdx].sortOrder = items[targetIdx].sortOrder
                items[targetIdx].sortOrder = sourceOrder
            }
        } else {
            var reordered = ordered
            let moved = reordered.remove(at: from)
            reordered.insert(moved, at: to)
            withAnimation(NotchAnimation.contentHug) {
                for (i, item) in reordered.enumerated() {
                    if let idx = items.firstIndex(where: { $0.id == item.id }) {
                        items[idx].sortOrder = i
                    }
                }
            }
        }
        scheduleSave()
    }

    /// TD-11: keyboard-accessible reorder (⌥↑/⌥↓). Routes through `reorder`
    /// so the keyboard and drag paths can never diverge — and so it works in
    /// Today too.
    func moveItem(_ id: UUID, by offset: Int) {
        guard let collection = activeCollection else { return }
        let ordered = openItems(in: collection)
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard to >= 0, to < ordered.count else { return }
        reorder(id, before: ordered[to].id)
    }

    // MARK: - Keyboard focus (KB-6)

    func moveFocus(_ offset: Int) {
        guard let collection = activeCollection else { return }
        let rows = openItems(in: collection)
        guard !rows.isEmpty else { focusedItemID = nil; return }
        guard let current = focusedItemID,
              let idx = rows.firstIndex(where: { $0.id == current }) else {
            focusedItemID = rows.first?.id
            return
        }
        let next = max(0, min(rows.count - 1, idx + offset))
        focusedItemID = rows[next].id
    }

    /// Where a row sits in the section currently on screen.
    ///
    /// The list uses it to tell which way the focus is travelling, so it can
    /// scroll the row to the near edge rather than always the same one.
    func visibleFocusIndex(of id: UUID) -> Int? {
        guard let collection = activeCollection else { return nil }
        return openItems(in: collection).firstIndex { $0.id == id }
    }

    // MARK: - Persistence

    private var backupURL: URL { Self.directory.appendingPathComponent("todos.backup.json") }

    private func load() {
        // Reinstall safety: the app is NOT sandboxed, so this file lives in
        //   ~/Library/Application Support/NotchSnap/Todo/todos.json
        // which survives deleting and reinstalling the .app — data is only
        // lost if that folder is manually removed. We additionally keep a
        // .backup copy and fall back to it if the main file is missing or
        // corrupt (e.g. a write interrupted by a crash or force-quit).
        if let payload = decodePayload(at: fileURL) {
            apply(payload)
            return
        }
        if let payload = decodePayload(at: backupURL) {
            print("[TodoStore] primary store unreadable — restored from backup")
            apply(payload)
            // Re-materialize the primary from the recovered data.
            scheduleSave()
        }
    }

    private func decodePayload(at url: URL) -> Payload? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func apply(_ payload: Payload) {
        collections = payload.collections.sorted { $0.sortOrder < $1.sortOrder }
        items = payload.items
        lastUsedCollectionID = payload.lastUsedCollectionID
    }

    private func scheduleSave() {
        saveWork?.cancel()
        saveWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let payload = Payload(
                collections: self.collections,
                items: self.items,
                lastUsedCollectionID: self.lastUsedCollectionID
            )
            guard let data = try? JSONEncoder().encode(payload) else { return }
            // Promote the last-known-good primary to the backup BEFORE
            // overwriting it, then write the new primary atomically so a
            // crash mid-write can never leave a truncated file.
            if let existing = try? Data(contentsOf: self.fileURL), !existing.isEmpty {
                try? existing.write(to: self.backupURL, options: .atomic)
            }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }
}
