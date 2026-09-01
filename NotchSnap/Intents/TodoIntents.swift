import AppIntents
import Foundation

// MARK: - App Intents — the to-do store, exposed to the system
//
// Shortcuts, Spotlight, Siri, and — the actual reason this exists now —
// every AI surface Apple routes through App Intents get first-class verbs
// into the store (Thomas, 2026-09-01: build the fundamentals so new
// system/AI features land on a real seam instead of a retrofit).
//
// The intents are thin: parameter resolution here, one TodoStore call, done.
// Anything richer (NL date parsing, urgency words) belongs in the store and
// its parsers, where the in-app paths already live — an intent that grew its
// own logic would be a second creation path that drifts from the first.
//
// Deployment target is macOS 13.0, the AppIntents floor, so nothing here
// needs an @available guard.

// MARK: Entities

/// A section (collection), pickable in Shortcuts.
struct TodoSectionEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Otto Section")
    static let defaultQuery = TodoSectionQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    @MainActor
    static func from(_ collection: TodoCollection) -> TodoSectionEntity {
        TodoSectionEntity(id: collection.id, name: collection.name)
    }
}

struct TodoSectionQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TodoSectionEntity] {
        TodoStore.shared.visibleCollections
            .filter { identifiers.contains($0.id) }
            .map(TodoSectionEntity.from)
    }

    @MainActor
    func suggestedEntities() async throws -> [TodoSectionEntity] {
        TodoStore.shared.visibleCollections.map(TodoSectionEntity.from)
    }
}

/// One to-do, addressable from outside the app.
struct TodoEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Otto To-Do")
    static let defaultQuery = TodoQuery()

    let id: UUID
    let title: String
    let sectionName: String
    let isCompleted: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(sectionName)")
    }

    @MainActor
    static func from(_ item: TodoItem) -> TodoEntity {
        TodoEntity(
            id: item.id,
            title: item.title,
            sectionName: TodoStore.shared.collection(id: item.collectionID)?.name ?? "",
            isCompleted: item.isCompleted
        )
    }
}

struct TodoQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TodoEntity] {
        TodoStore.shared.items
            .filter { identifiers.contains($0.id) }
            .map(TodoEntity.from)
    }

    /// "Complete <which one?>" — Siri/Shortcuts hand over whatever words the
    /// user said; match them against OPEN titles, the same case-insensitive
    /// containment Quick Find uses.
    @MainActor
    func entities(matching string: String) async throws -> [TodoEntity] {
        TodoStore.shared.items
            .filter { !$0.isCompleted && $0.title.localizedCaseInsensitiveContains(string) }
            .map(TodoEntity.from)
    }

    @MainActor
    func suggestedEntities() async throws -> [TodoEntity] {
        TodoStore.shared.items.filter { !$0.isCompleted }.map(TodoEntity.from)
    }
}

// MARK: Intents

struct AddTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add To-Do"
    static let description = IntentDescription(
        "Adds a to-do to Otto. Date phrases in the title (\"tomorrow\", \"fri\") become the due date, exactly as they do in the app."
    )

    @Parameter(title: "Title") var text: String
    @Parameter(title: "Section") var section: TodoSectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to \(\.$section)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TodoEntity> & ProvidesDialog {
        let store = TodoStore.shared
        // Same pipeline as the draft row: NL date out of the title first.
        let parsed = NLDateParser.parse(text)
        let title = parsed?.cleanedTitle ?? text
        let target = section?.id
            ?? store.defaultCreationCollectionID
            ?? store.collections.first?.id
        guard let target,
              let item = store.addItem(title: title, collectionID: target,
                                       urgency: .low, dueDate: parsed?.date) else {
            throw AddTodoError.emptyTitle
        }
        let entity = TodoEntity.from(item)
        return .result(value: entity,
                       dialog: "Added “\(entity.title)” to \(entity.sectionName).")
    }

    enum AddTodoError: Error, CustomLocalizedStringResourceConvertible {
        case emptyTitle
        var localizedStringResource: LocalizedStringResource {
            "The to-do needs a title."
        }
    }
}

struct CompleteTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete To-Do"
    static let description = IntentDescription("Marks an open Otto to-do as completed.")

    @Parameter(title: "To-Do") var todo: TodoEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$todo)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TodoStore.shared
        guard let item = store.items.first(where: { $0.id == todo.id }) else {
            throw CompleteTodoError.notFound
        }
        if !item.isCompleted { store.toggleComplete(item.id) }
        return .result(dialog: "Completed “\(item.title)”.")
    }

    enum CompleteTodoError: Error, CustomLocalizedStringResourceConvertible {
        case notFound
        var localizedStringResource: LocalizedStringResource {
            "That to-do no longer exists."
        }
    }
}

struct GetOpenTodosIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Open To-Dos"
    static let description = IntentDescription(
        "Returns Otto's open to-dos, optionally from one section — for Shortcuts glue and anything that wants to reason over the list."
    )

    @Parameter(title: "Section") var section: TodoSectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get open to-dos in \(\.$section)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TodoEntity]> {
        let store = TodoStore.shared
        let open = store.items
            .filter { !$0.isCompleted }
            .filter { section == nil || $0.collectionID == section?.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        return .result(value: open.map(TodoEntity.from))
    }
}

struct OpenTodosIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Otto"
    static let description = IntentDescription("Opens the notch on the to-do panel, ready to type.")
    /// The panel lives in this process; nothing to show without it running.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotchController.shared.triggerExpand()
        // Opening is the intent to interact — same contract as ⌃⇧T.
        NotchController.shared.makeKeyForTyping()
        return .result()
    }
}

// MARK: App Shortcuts (zero-setup phrases)

struct OttoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTodoIntent(),
            // A free-text parameter may not appear in a phrase (App Shortcut
            // phrases only interpolate AppEntity/AppEnum), so the phrase asks
            // and Siri follows up for the title.
            phrases: ["Add a to-do in \(.applicationName)"],
            shortTitle: "Add To-Do",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteTodoIntent(),
            phrases: ["Complete a to-do in \(.applicationName)"],
            shortTitle: "Complete To-Do",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: OpenTodosIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Otto",
            systemImageName: "macbook"
        )
    }
}
