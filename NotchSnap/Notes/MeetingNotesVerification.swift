#if DEBUG
import AppKit
import Foundation

@MainActor
enum MeetingNotesVerification {
    static func run() -> [String] {
        var results: [String] = []
        var checks = 0
        func expect(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { results.append("MEETING FAIL: " + name) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("otto-meeting-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let ref = MeetingEventReference(provider: "google", account: "a", calendar: "primary", event: "instance",
                                            series: "series", originalStart: date, exact: true)
            var meeting = DetectedMeeting(id: "alert", title: "1:1", start: date, end: date.addingTimeInterval(1800),
                                          attendees: [], attendeeEmails: [], isAllDay: false, noteReference: ref)
            var first = QuickNote(content: "first", title: "1:1", titleSource: .user)
            first.meetingContext = MeetingNoteContext(meeting: meeting)
            let oldKey = ref.occurrenceKey
            meeting.start = date.addingTimeInterval(3600)
            expect(meeting.noteReference?.occurrenceKey == oldKey, "moved instance retains original occurrence")
            expect(MeetingNoteResolver.note(for: ref, in: [first])?.id == first.id, "exact lookup")
            var another = ref; another.account = "b"
            expect(MeetingNoteResolver.note(for: another, in: [first]) == nil, "account namespace")
            another = ref; another.provider = "eventkit"
            expect(MeetingNoteResolver.note(for: another, in: [first]) == nil, "provider namespace")
            another = ref; another.originalStart = date.addingTimeInterval(7 * 86400)
            expect(MeetingNoteResolver.note(for: another, in: [first]) == nil, "different occurrence")
            expect(MeetingNoteResolver.conversation(for: another, in: [first]) == first.meetingContext?.conversationID, "same series")
            another.exact = false
            expect(MeetingNoteResolver.note(for: another, in: [first]) == nil, "unresolved never auto-matches")
            var conflict = QuickNote(content: "second", title: "different", titleSource: .user)
            conflict.meetingContext = MeetingNoteContext(meeting: meeting)
            expect(MeetingNoteResolver.conversation(for: ref, in: [first, conflict]) == nil, "ambiguous series")
            expect(MeetingNoteResolver.note(for: ref, in: [first, conflict]) == nil, "ambiguous occurrence")

            let payload = #"{"items":[{"id":"i","summary":"1:1","recurringEventId":"r","originalStartTime":{"dateTime":"2026-09-14T10:00:00+02:00"},"start":{"dateTime":"2026-09-14T11:00:00+02:00"},"end":{"dateTime":"2026-09-14T11:30:00+02:00"}}]}"#
            let parsed = GoogleCalendarProvider.parse(Data(payload.utf8), account: "test")
            expect(parsed.count == 1, "Google fixture parses")
            expect(parsed.first?.noteReference?.originalStart != parsed.first?.start, "Google original vs displayed start")
            expect(GoogleCalendarProvider.parse(Data(payload.utf8)).first?.noteReference?.occurrenceKey == nil, "unknown account not exact")

            let storage = root.appendingPathComponent("Notes")
            let store = NotesStore(storageDirectory: storage)
            store.pendingMeetingNote = first
            store.pendingMeetingNote?.content = ""
            store.openNoteID = first.id
            expect(store.notes.isEmpty, "opening empty context creates no note")
            expect(!FileManager.default.fileExists(atPath: storage.appendingPathComponent("notes.json").path), "no empty index on browse")
            store.setBody("written", for: first.id)
            expect(store.notes.count == 1, "first body edit materializes once")
            store.setBody("written twice", for: first.id)
            expect(store.saveNow(), "save reports success")
            let loaded = NotesStore(storageDirectory: storage)
            expect(loaded.notes.count == 1 && loaded.notes[0].id == first.id && loaded.notes[0].content == "written twice", "reload identity and body")
            let primary = storage.appendingPathComponent("notes.json")
            let backup = storage.appendingPathComponent("notes.backup.json")
            try Data("corrupt".utf8).write(to: primary)
            let recovered = NotesStore(storageDirectory: storage)
            expect(recovered.notes.count == 1, "validated backup fallback")
            try Data("corrupt".utf8).write(to: backup)
            let blocked = NotesStore(storageDirectory: storage)
            expect(blocked.saveError != nil && !blocked.saveNow(), "both corrupt disables destructive save")
            expect(try String(contentsOf: primary, encoding: .utf8) == "corrupt", "corrupt primary preserved")
            let unwritable = root.appendingPathComponent("file-not-directory")
            try Data().write(to: unwritable)
            let failed = NotesStore(storageDirectory: unwritable)
            expect(!failed.saveNow() && failed.saveError != nil, "write failure visible")

            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
            json.removeValue(forKey: "meetingContext")
            let legacyNote = try JSONDecoder().decode(QuickNote.self, from: JSONSerialization.data(withJSONObject: json))
            expect(legacyNote.content == first.content && legacyNote.meetingContext == nil, "legacy note decoder")
            var task = TodoItem(id: UUID(), title: "Same", collectionID: UUID(), urgency: .low,
                                isCompleted: true, completedAt: date, dueDate: nil, sortOrder: 0, createdAt: date)
            task.meetingNoteID = first.id
            var taskJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as! [String: Any]
            taskJSON.removeValue(forKey: "meetingNoteID")
            let oldTask = try JSONDecoder().decode(TodoItem.self, from: JSONSerialization.data(withJSONObject: taskJSON))
            expect(oldTask.meetingNoteID == nil && oldTask.title == "Same", "legacy task decoder")
            let vault = MarkdownVault(directory: root.appendingPathComponent("Vault"))
            expect(vault.recordCompletion(task, from: TodoStore.shared), "archive writes metadata")
            var second = TodoItem(id: UUID(), title: task.title, collectionID: task.collectionID, urgency: .low,
                                  isCompleted: true, completedAt: date, dueDate: nil, sortOrder: 1, createdAt: date)
            second.meetingNoteID = first.id
            expect(vault.recordCompletion(second, from: TodoStore.shared), "same title same minute second UUID")
            expect(vault.recordCompletion(task, from: TodoStore.shared), "archive idempotent")
            let files = try FileManager.default.contentsOfDirectory(at: vault.directory.appendingPathComponent("Archive"), includingPropertiesForKeys: nil)
            let archiveURL = files[0]
            var entries = CompletedArchive.parseDocument(try String(contentsOf: archiveURL, encoding: .utf8))
            expect(entries.count == 2 && Set(entries.compactMap(\.taskID)).count == 2, "two distinct archive records")
            expect(entries.allSatisfy { $0.meetingNoteID == first.id }, "archive retains meeting")
            task.title = "Renamed"
            vault.removeCompletion(task, completedAt: date, from: TodoStore.shared)
            entries = CompletedArchive.parseDocument(try String(contentsOf: archiveURL, encoding: .utf8))
            expect(entries.count == 1 && entries[0].taskID == second.id, "uncomplete by UUID after rename")
            expect(CompletedArchive.parseDocument("- [x] Legacy (Work) ✅ 2026-09-13 10:30\n").count == 1, "legacy archive")
            let badVault = MarkdownVault(directory: unwritable)
            expect(!badVault.recordCompletion(second, from: TodoStore.shared), "archive write failure cannot prune")
            expect(badVault.archive([second], from: TodoStore.shared).isEmpty, "sweep retains task on failure")
            expect(try JSONDecoder().decode(TodoItem.self, from: JSONEncoder().encode(task)).meetingNoteID == first.id, "durable provenance roundtrip")
        } catch { results.append("MEETING ERROR: \(error)") }
        results.append("meeting-tests: \(checks) checks, \(results.count) failures")
        return results
    }
}
#endif
