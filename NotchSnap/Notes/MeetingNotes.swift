import AppKit
import SwiftUI

/// Calendar identity is separate from the alert's transient ID. No title or
/// video URL participates in matching. Unvalidated EventKit series stay manual.
struct MeetingEventReference: Codable, Equatable, Hashable {
    var provider: String
    var account: String
    var calendar: String
    var event: String
    var series: String?
    var originalStart: Date?
    var exact: Bool

    var occurrenceKey: String? {
        guard exact, !account.isEmpty, !calendar.isEmpty, !event.isEmpty else { return nil }
        let parts = [provider, account, calendar, series ?? event,
                     series == nil ? "single" : originalStart.map { String($0.timeIntervalSince1970) } ?? event]
        return String(data: try! JSONEncoder().encode(parts), encoding: .utf8)
    }
    var seriesKey: String? {
        guard exact, let series, !account.isEmpty, !calendar.isEmpty else { return nil }
        return String(data: try! JSONEncoder().encode([provider, account, calendar, series]), encoding: .utf8)
    }
}

struct MeetingNoteContext: Codable, Equatable {
    var conversationID: UUID
    var eventReference: MeetingEventReference?
    var title: String
    var start: Date
    var end: Date
    var timeZoneID: String
    var calendarLabel: String
    var lastObservedAt: Date
    var manuallyLinked: Bool = false

    init(meeting: DetectedMeeting, conversationID: UUID = UUID()) {
        self.conversationID = conversationID
        eventReference = meeting.noteReference
        title = meeting.title; start = meeting.start; end = meeting.end
        timeZoneID = meeting.timeZoneID
        calendarLabel = meeting.calendarLabel
        lastObservedAt = Date()
    }
    var dateLabel: String {
        let f = DateFormatter()
        f.locale = L10n.locale; f.timeZone = TimeZone(identifier: timeZoneID)
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        let from = f.string(from: start)
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return from + "–" + f.string(from: end)
    }
}

struct MeetingDraftEnvelope: Codable {
    var version = 1
    var pendingNote: QuickNote?
    var taskDrafts: [UUID: String] = [:]
}

/// Pure resolver: ambiguous mappings deliberately produce no match.
enum MeetingNoteResolver {
    static func note(for reference: MeetingEventReference?, in notes: [QuickNote]) -> QuickNote? {
        guard let key = reference?.occurrenceKey else { return nil }
        let matches = notes.filter { $0.meetingContext?.eventReference?.occurrenceKey == key }
        return matches.count == 1 ? matches[0] : nil
    }
    static func conversation(for reference: MeetingEventReference?, in notes: [QuickNote]) -> UUID? {
        guard let key = reference?.seriesKey else { return nil }
        let groups = Set(notes.filter { $0.meetingContext?.eventReference?.seriesKey == key }
            .compactMap { $0.meetingContext?.conversationID })
        return groups.count == 1 ? groups.first : nil
    }
}

struct MeetingNotesButton: View {
    let meeting: DetectedMeeting
    @ObservedObject private var notes = NotesStore.shared
    var body: some View {
        Button { CalendarStore.shared.openNotes(for: meeting) } label: {
            Text(L10n.t(notes.meetingNote(for: meeting) == nil ? "meeting.notes" : "meeting.openNotes"))
                .font(DSFont.checklistItem)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(DSColor.fieldBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("meeting.notes") + ": " + meeting.title)
    }
}

struct MeetingNotesFilter: View {
    @FocusState private var searchFocused: Bool
    @ObservedObject private var notes = NotesStore.shared
    var body: some View {
        HStack(spacing: 12) {
            Button(L10n.t("meeting.all")) { notes.meetingOnly = false }
                .foregroundStyle(notes.meetingOnly ? DSColor.textSecondary : DSColor.textPrimary)
            Button(L10n.t("meeting.filter")) { notes.meetingOnly = true }
                .foregroundStyle(notes.meetingOnly ? DSColor.textPrimary : DSColor.textSecondary)
            if notes.meetingOnly {
                TextField(L10n.t("meeting.search"), text: $notes.meetingQuery)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(L10n.t("meeting.search"))
                    .focused($searchFocused)
            }
            Spacer(minLength: 0)
            if let pending = notes.pendingMeetingNote, !(notes.meetingTaskDrafts[pending.id] ?? "").isEmpty {
                Button(L10n.t("meeting.resumeDraft")) { notes.open(pending.id) }
            }
        }
        .buttonStyle(.plain).font(DSFont.checklistItem).padding(.horizontal, 20).padding(.vertical, 8)
        .onChange(of: notes.meetingSearchFocus) { searchFocused = $0 }
    }
}

struct MeetingSelectionView: View {
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var calendar = CalendarStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(L10n.t("notes.back")) { notes.cancelMeetingPicker() }
                Spacer()
                Text(L10n.t("meeting.choose"))
            }
            if calendar.upcomingToday.isEmpty { Text(L10n.t("meeting.noEvents")).foregroundStyle(DSColor.textSecondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(calendar.upcomingToday.enumerated()), id: \.element.id) { index, meeting in
                            Button { calendar.openNotes(for: meeting) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(meeting.title).font(DSFont.todoTitle)
                                    Text(meeting.timeRangeLabel).font(DSFont.checklistItem).foregroundStyle(DSColor.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(notes.meetingSelection == index ? DSColor.fieldBackground : Color.clear)
                            }.id(index)
                        }
                    }
                }.frame(maxHeight: 300)
                .onChange(of: notes.meetingSelection) { proxy.scrollTo($0) }
            }
        }
        .buttonStyle(.plain).padding(16)
    }
}

struct MeetingContextControls: View {
    let note: QuickNote
    @ObservedObject private var notes = NotesStore.shared
    var body: some View {
        if let context = note.meetingContext {
            VStack(alignment: .leading, spacing: 6) {
                Text(context.dateLabel).font(DSFont.checklistItem).foregroundStyle(DSColor.textSecondary)
                HStack(spacing: 12) {
                    Button { notes.meetingHistory = true; notes.meetingSelection = 0 } label: {
                        Text(L10n.t("meeting.previous") + " · \(notes.sessions(for: note).count)")
                    }
                    Button(L10n.t("meeting.link")) { notes.meetingLinkPicker = true; notes.meetingSelection = 0 }
                    if notes.canUndoMeetingLink { Button(L10n.t("notes.undo")) { notes.undoMeetingLink() } }
                }.buttonStyle(.plain).font(.system(size: 11))
                if notes.meetingFocus == 3 {
                    Text("H · " + L10n.t("meeting.previous") + "   L · " + L10n.t("meeting.link") + "   A · " + L10n.t("meeting.openPrevious"))
                        .font(.system(size: 10)).foregroundStyle(DSColor.textSecondary)
                }
            }.padding(.horizontal, 22).padding(.top, 6)
                .background(notes.meetingFocus == 3 ? DSColor.fieldBackground : Color.clear)
        }
    }
}

struct MeetingHistoryView: View {
    let note: QuickNote
    @ObservedObject private var notes = NotesStore.shared
    private var rows: [QuickNote] { notes.meetingHistoryRows }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(L10n.t("notes.back")) { notes.meetingHistory = false; notes.meetingLinkPicker = false; notes.focusBody() }
            Text(L10n.t(notes.meetingLinkPicker ? "meeting.link" : "meeting.previous")).font(DSFont.todoTitle)
            if notes.meetingLinkPicker {
                TextField(L10n.t("meeting.search"), text: $notes.meetingLinkQuery).textFieldStyle(.plain)
            }
            if rows.isEmpty { Text(L10n.t("meeting.noSessions")).foregroundStyle(DSColor.textSecondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            if notes.meetingLinkPicker, let group = row.meetingContext?.conversationID { notes.linkMeeting(to: group) }
                            else { notes.openSession(row.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(DSFont.todoTitle)
                                Text(row.meetingContext?.dateLabel ?? "").font(DSFont.checklistItem)
                                Text(NoteMarkdown.plainText(row.content)).font(DSFont.checklistItem).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(notes.meetingSelection == index ? DSColor.fieldBackground : Color.clear)
                        }
                    }
                }
            }.frame(maxHeight: 300)
        }.buttonStyle(.plain).padding(18)
    }
}

struct MeetingTasksView: View {
    let note: QuickNote
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var todos = TodoStore.shared
    @ObservedObject private var archive = CompletedArchive.shared
    @State private var destination: UUID?
    @State private var showDestinations = false
    @State private var showPrevious = false
    @State private var showCompleted = false
    @State private var taskContentHeight: CGFloat = 0
    @State private var editingID: UUID?
    @State private var editedTitle = ""
    @FocusState private var draftFocused: Bool
    @FocusState private var editFocused: Bool

    private var current: [TodoItem] { todos.items.filter { $0.meetingNoteID == note.id } }
    private var older: [TodoItem] {
        let ids = Set(notes.sessions(for: note).map(\.id))
        return todos.items.filter { !$0.isCompleted && $0.meetingNoteID.map(ids.contains) == true }
            .sorted { ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt) }
    }
    private var visible: [TodoItem] { current.filter { !$0.isCompleted } + (showPrevious ? older : []) + (showCompleted ? current.filter(\.isCompleted) : []) }
    private var completed: [ArchivedCompletion] {
        let live = Set(current.map(\.id))
        return archive.entries.filter { $0.meetingNoteID == note.id && !live.contains($0.taskID ?? UUID()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t("meeting.tasks")).font(DSFont.sectionLabel)
                Spacer()
                Button(todos.collection(id: destination ?? todos.firstUserCollection?.id ?? UUID())?.name ?? L10n.t("meeting.chooseList")) {
                    showDestinations.toggle()
                }.font(DSFont.checklistItem)
            }
            if showDestinations {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(todos.pickerSections()) { section in
                            Button(section.name) { destination = section.id; showDestinations = false }
                        }
                    }
                }.font(DSFont.checklistItem)
            }
            TextField(L10n.t("meeting.taskPlaceholder"), text: Binding(
                get: { notes.meetingTaskDrafts[note.id] ?? "" },
                set: { notes.meetingDraftChanged($0, noteID: note.id) }))
                .textFieldStyle(.plain).font(DSFont.todoTitle).focused($draftFocused)
                .onSubmit {
                    if let target = destination ?? todos.firstUserCollection?.id { _ = notes.submitMeetingTask(to: target) }
                    draftFocused = true
                }
                .onChange(of: draftFocused) { if $0 { notes.meetingFocus = 1 } }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Button { todos.toggleComplete(item.id) } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square").accessibilityLabel(L10n.t("todo.sc.toggleComplete"))
                                }
                                if editingID == item.id {
                                    TextField("", text: $editedTitle).textFieldStyle(.plain).focused($editFocused)
                                        .onSubmit { todos.rename(item.id, to: editedTitle); editingID = nil; notes.meetingFocus = 2 }
                                } else {
                                    Button { edit(item) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title).lineLimit(2).strikethrough(item.isCompleted)
                                            if let due = item.dueDate {
                                                Text(due, format: .dateTime.day().month()).font(.system(size: 10)).foregroundStyle(DSColor.textSecondary)
                                            }
                                            if item.meetingNoteID != note.id, let origin = item.meetingNoteID.flatMap({ notes.note(id: $0) }) {
                                                Text(origin.meetingContext?.dateLabel ?? origin.title).font(.system(size: 10)).foregroundStyle(DSColor.textSecondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.font(DSFont.checklistItem).padding(5)
                                .background(notes.meetingFocus == 2 && notes.meetingTaskSelection == index ? DSColor.fieldBackground : Color.clear).id(index)
                        }
                        if !older.isEmpty {
                            Button(L10n.t("meeting.openPrevious") + " · \(older.count)") { showPrevious.toggle() }
                        }
                        if archive.readError { Text(L10n.t("meeting.archiveUnavailable")).foregroundStyle(DSColor.textSecondary) }
                        if !current.filter(\.isCompleted).isEmpty || !completed.isEmpty {
                            Button(L10n.t("meeting.completed")) { showCompleted.toggle() }
                            if showCompleted {
                                ForEach(completed) { item in Text("✓ " + item.title).strikethrough().foregroundStyle(DSColor.textSecondary) }
                            }
                        }
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: MeetingTaskContentHeight.self, value: geometry.size.height)
                    })
                }
                .frame(idealHeight: min(130, taskContentHeight), maxHeight: min(130, taskContentHeight))
                .fixedSize(horizontal: false, vertical: true)
                .onPreferenceChange(MeetingTaskContentHeight.self) { taskContentHeight = $0 }
                .onChange(of: notes.meetingTaskSelection) { proxy.scrollTo($0) }
            }
        }
        .buttonStyle(.plain).padding(.horizontal, 22).padding(.vertical, 8)
        .onAppear { destination = todos.pickerSections().first?.id; archive.reloadIfNeeded() }
        .onChange(of: notes.meetingTaskSelection) { value in
            if value >= visible.count { notes.meetingTaskSelection = max(0, visible.count - 1) }
        }
        .onChange(of: notes.meetingFocus) { value in
            draftFocused = value == 1
            if value != 1 { NSApp.keyWindow?.makeFirstResponder(nil) }
            if value == 0 { notes.focusBody() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingTaskCommand)) { notification in
            switch notification.object as? String {
            case "complete": if visible.indices.contains(notes.meetingTaskSelection) { todos.toggleComplete(visible[notes.meetingTaskSelection].id) }
            case "edit": if visible.indices.contains(notes.meetingTaskSelection) { edit(visible[notes.meetingTaskSelection]) }
            case "previous": showPrevious.toggle()
            case "completed": showCompleted.toggle()
            case "destination":
                let sections = todos.pickerSections()
                if !sections.isEmpty {
                    let index = sections.firstIndex { $0.id == destination } ?? -1
                    destination = sections[(index + 1) % sections.count].id
                }
            case "cancel": editingID = nil
            default: break
            }
        }
    }
    private func edit(_ item: TodoItem) {
        guard !item.isCompleted else { return }
        editedTitle = item.title; editingID = item.id
        DispatchQueue.main.async { editFocused = true }
    }
}

extension Notification.Name {
    static let meetingTaskCommand = Notification.Name("otto.meeting.task.command")
}

private struct MeetingTaskContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
