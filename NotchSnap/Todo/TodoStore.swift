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
enum TodoPanelMode: Equatable {
    case browsing
    case create
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

    /// KB-11: a creation draft survives leaving the "+" tab, cleared on Create.
    @Published var draftTitle = ""
    @Published var draftCollectionID: UUID?
    @Published var draftUrgency: TodoUrgency = .low

    /// QF: Quick Find state — query, cross-category matches, ↑↓ selection.
    @Published var findQuery = ""
    @Published var findSelection = 0

    /// FB8: the user's explicitly chosen default category for new to-dos —
    /// the one preselected (and listed first) in the creation flow. Set from
    /// a tab's context menu; persisted. Independent of tab order.
    @Published var defaultCollectionID: UUID?

    /// The category the creation flow should default to: the explicit choice
    /// if still valid and not the smart Today view, else the first real tab.
    var defaultCreationCollectionID: UUID? {
        if let id = defaultCollectionID, let c = collection(id: id), !c.isSystemToday {
            return id
        }
        return firstUserCollection?.id
    }

    func setDefaultCollection(_ id: UUID) {
        guard let c = collection(id: id), !c.isSystemToday else { return }
        defaultCollectionID = id
        scheduleSave()
    }

    /// A global "new to-do" entry point (⌃⇧N / ⌥⌘N) starts on the user's
    /// default category rather than whatever was last browsed.
    func prepareGlobalCreateDraft() {
        draftCollectionID = defaultCreationCollectionID
    }

    /// While any non-browsing surface is up, the notch must not auto-collapse
    /// under the user mid-typing. Checked by NotchController.triggerCollapse.
    var isPanelPinnedOpen: Bool {
        panelMode != .browsing || showShortcuts
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
            if mode == .create, draftCollectionID == nil {
                draftCollectionID = defaultCreationCollectionID
            }
        }
    }

    /// "Each tab has a prompt to create a to-do in that tab" — creation
    /// opened from a category's own footer (or ⌘N while browsing it) files
    /// there by default. Today is a smart view, so it falls back to the
    /// last-used real collection.
    func presetDraftToActiveCollection() {
        if let active = activeCollection, !active.isSystemToday {
            draftCollectionID = active.id
        } else {
            draftCollectionID = defaultCreationCollectionID
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
        return base.appendingPathComponent("NotchSnap/Todo", isDirectory: true)
    }
    private var fileURL: URL { Self.directory.appendingPathComponent("todos.json") }

    private struct Payload: Codable {
        var collections: [TodoCollection]
        var items: [TodoItem]
        var lastUsedCollectionID: UUID?
        var defaultCollectionID: UUID?   // FB8; decodeIfPresent for old files
    }

    private init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        load()
        if collections.isEmpty { seedStarterCollections() }
        activeCollectionID = collections.first?.id
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

    var activeCollection: TodoCollection? {
        collections.first { $0.id == activeCollectionID } ?? collections.first
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

    /// KB-8: ⌘1…⌘9 select by tab order.
    func selectCollection(atIndex index: Int) {
        let ordered = collections.sorted { $0.sortOrder < $1.sortOrder }
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

        let next = (items.filter { $0.collectionID == target }.map(\.sortOrder).max() ?? -1) + 1
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
        defaultCollectionID = payload.defaultCollectionID
    }

    private func scheduleSave() {
        saveWork?.cancel()
        saveWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let payload = Payload(
                collections: self.collections,
                items: self.items,
                lastUsedCollectionID: self.lastUsedCollectionID,
                defaultCollectionID: self.defaultCollectionID
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
