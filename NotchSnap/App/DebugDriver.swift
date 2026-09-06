#if DEBUG
import AppKit
import SwiftUI

// MARK: - DebugDriver — headless test harness (DEBUG builds only)
//
// TCC blocks synthetic mouse/keyboard input and window capture for agents
// and CI, which makes the notch impossible to drive from outside the
// process. This listener gives Debug builds a scriptable side door:
//
//   swift -e 'import Foundation; DistributedNotificationCenter.default()
//     .postNotificationName(Notification.Name("com.notchsnap.debug.command"),
//                           object: "expand", userInfo: nil,
//                           deliverImmediately: true)'
//
// Commands: expand | collapse | add <title> | complete-first |
//           uncomplete-first | switch <index> | dump
// `dump` appends the hugging-height state to /tmp/notchsnap-debug-state.txt.
// Never compiled into Release.

@MainActor
enum DebugDriver {
    private static let stateFile = URL(fileURLWithPath: "/tmp/notchsnap-debug-state.txt")

    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.notchsnap.debug.command"),
            object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { handle(command) }
        }
    }

    private static func handle(_ command: String) {
        let store = TodoStore.shared
        switch command {
        case "expand":
            NotchController.shared.expand()
        case "collapse":
            NotchController.shared.triggerCollapse()
        case "complete-first":
            if let collection = store.activeCollection,
               let first = store.openItems(in: collection).first {
                store.toggleComplete(first.id)
            }
        case "uncomplete-first":
            if let collection = store.activeCollection,
               let first = store.completedItems(in: collection).first {
                store.toggleComplete(first.id)
            }
        case "toggle-completed-section":
            withAnimation(NotchAnimation.contentHug) { store.completedExpanded.toggle() }
        case "create-mode":
            NotchController.shared.openCreate()
        case "create-submit":
            // Same path the Return key takes in the pinned draft row.
            store.commitDraft()
        case "jump":
            // Same path Return takes in find mode.
            store.jumpToFindSelection()
        case "create-cancel":
            store.blurDraft()
        case "create-tab":
            // Same path the Tab key takes: switch section, leave the row alone.
            store.cycleCollection()
        case "create-shift-tab":
            store.cycleCollection(by: -1)
        case "browse-mode":
            store.setMode(.browsing)
        case "expand-focused":
            if let focused = store.focusedItemID ?? store.activeCollection.flatMap({ store.openItems(in: $0).first?.id }) {
                withAnimation(NotchAnimation.contentHug) { store.expandedItemID = focused }
            }
        case "deselect":
            // The exact path a click on dead panel space takes.
            store.endEditing()
        case "focus-first":
            if let collection = store.activeCollection,
               let first = store.openItems(in: collection).first {
                store.focusedItemID = first.id
            }
        case "collapse-row":
            withAnimation(NotchAnimation.contentHug) { store.expandedItemID = nil }
        case "presence":
            appendState("presence: " + NotchPresence.shared.state.debugDescription)
        case "presence-rest":
            NotchPresence.shared.debugOverride = .resting
        case "presence-auto":
            NotchPresence.shared.debugOverride = nil
        case "dump":
            dumpState()
        default:
            if command.hasPrefix("add ") {
                let title = String(command.dropFirst(4))
                if let target = store.lastUsedCollectionID ?? store.firstUserCollection?.id {
                    store.addItem(title: title, collectionID: target, urgency: .low)
                }
            } else if command.hasPrefix("switch ") {
                if let index = Int(command.dropFirst(7)) {
                    store.selectCollection(atIndex: index)
                }
            } else if command.hasPrefix("find ") {
                store.setMode(.find)
                store.findQuery = String(command.dropFirst(5))
            } else if command.hasPrefix("draft ") {
                store.draftTitle = String(command.dropFirst(6))
            } else if command.hasPrefix("movecat ") {
                if let offset = Int(command.dropFirst(8)), let active = store.activeCollectionID {
                    store.moveCollection(active, by: offset)
                }
            } else if command == "collections" {
                appendState("collections: " + store.collections.map(\.name).joined(separator: " > "))
            } else if command.hasPrefix("braindump ") {
                let transcript = String(command.dropFirst(10))
                let collections = store.collections
                Task { @MainActor in
                    let parsed = await BrainDumpParser.parse(transcript: transcript,
                                                             collections: collections)
                    let rendered = parsed.map { todo in
                        "{title='\(todo.title)' cat=\(todo.suggestedCategoryName ?? "nil") "
                        + "urg=\(todo.urgency.rawValue) date=\(todo.dueDatePhrase ?? "nil")}"
                    }.joined(separator: " | ")
                    appendState("braindump engine=\(BrainDumpParser.activeEngine) "
                                + "count=\(parsed.count) -> \(rendered)")
                }
            } else if command.hasPrefix("meeting ") {
                // meeting <minutesFromNow> [nolink]
                let args = command.dropFirst(8).split(separator: " ")
                let minutes = Int(args.first ?? "2") ?? 2
                let withLink = !args.contains("nolink")
                CalendarStore.shared.injectTestMeeting(minutesFromNow: minutes,
                                                       withLink: withLink)
            } else if command == "cal-status" {
                let cal = CalendarStore.shared
                appendState("calConnected=\(cal.isConnected) "
                            + "account=\(cal.accountDescription ?? "nil") "
                            + "upcoming=\(cal.upcomingToday.count) "
                            + "ambient=\(cal.ambientMeeting?.title ?? "nil") "
                            + "activeAlert=\(cal.activeAlert?.title ?? "nil") "
                            + "alertLeaving=\(cal.alertLeaving) "
                            + "leads=\(cal.ambientLeadMinutes)m/\(cal.alertLeadMinutes)m "
                            + "notch=\(NotchController.shared.state)")
            } else if command == "cal-debug" {
                let cal = CalendarStore.shared
                appendState("cal-debug connected=\(cal.isConnected)")
                appendState("  calendars (\(cal.visibleCalendars.count)):")
                for c in cal.visibleCalendars {
                    appendState("    • \(c.title) [\(c.source) / \(c.sourceType)]")
                }
                let rows = cal.diagnoseToday()
                appendState("  today's raw events (\(rows.count)):")
                for r in rows { appendState("    • \(r)") }
                appendState("  surfaced upcoming: \(cal.upcomingToday.count)")
            } else if command == "cal-connect" {
                Task { @MainActor in
                    await CalendarStore.shared.connect()
                    appendState("cal-connect → connected=\(CalendarStore.shared.isConnected) "
                                + "error=\(CalendarStore.shared.lastError ?? "none")")
                }
            } else if command == "cal-attendees" {
                for line in CalendarStore.shared.diagnoseAttendees() { appendState(line) }
            } else if command == "cal-probe" {
                for line in CalendarStore.shared.probeWideWindow() { appendState(line) }
            } else if command == "cal-refresh" {
                Task { @MainActor in await CalendarStore.shared.refresh() }
            } else if command == "notes-enter" {
                NotesStore.shared.enterSpace()
            } else if command == "notes-leave" {
                NotesStore.shared.leaveSpace()
            } else if command.hasPrefix("notes-draft ") {
                NotesStore.shared.draft = String(command.dropFirst(12))
                NotesStore.shared.draftChanged()
            } else if command == "notes-commit" {
                NotesStore.shared.commitDraft()
            } else if command == "notes-open-first" {
                if let first = NotesStore.shared.stream.first { NotesStore.shared.open(first.id) }
            } else if command == "notes-close" {
                NotesStore.shared.closeNote()
            } else if command == "notes-delete-first" {
                if let first = NotesStore.shared.stream.first { NotesStore.shared.delete(first.id) }
            } else if command == "notes-undo" {
                NotesStore.shared.undoDelete()
            } else if command.hasPrefix("notes-rename ") {
                if let open = NotesStore.shared.openNoteID {
                    NotesStore.shared.rename(open, to: String(command.dropFirst(13)))
                }
            } else if command.hasPrefix("space-cycle ") {
                TodoStore.shared.cycleSpace(by: Int(command.dropFirst(12)) ?? 1)
            } else if command.hasPrefix("notes-select ") {
                NotesStore.shared.moveSelection(Int(command.dropFirst(13)) ?? 1)
            } else if command == "notes-open-selected" {
                if let s = NotesStore.shared.selectedNoteID { NotesStore.shared.open(s) }
            } else if command == "viewtree" {
                // Every AppKit view in the notch panel, with its frame in
                // SCREEN coordinates. AppKit hit-testing beats SwiftUI gesture
                // resolution, so a real NSView lying over the content is the
                // one thing that can make a SwiftUI row unclickable while the
                // window-level hitTest still succeeds.
                if let window = NSApp.windows.first(where: { $0 is NotchPanel }),
                   let root = window.contentView {
                    func walk(_ view: NSView, _ depth: Int) {
                        let inWindow = view.convert(view.bounds, to: nil)
                        let onScreen = window.convertToScreen(inWindow)
                        appendState(String(repeating: "  ", count: depth)
                                    + "\(type(of: view)) "
                                    + "x=\(Int(onScreen.minX)) y=\(Int(onScreen.minY)) "
                                    + "w=\(Int(onScreen.width)) h=\(Int(onScreen.height)) "
                                    + "hidden=\(view.isHidden)")
                        for sub in view.subviews { walk(sub, depth + 1) }
                    }
                    walk(root, 0)
                }
            } else if command.hasPrefix("hittest ") {
                // Ask the panel what it would hand a click at this SCREEN
                // point. No synthetic input needed, and it tests the exact
                // path a real click takes: NotchHostingView.hitTest first,
                // then AppKit's own walk down the view tree.
                let parts = command.dropFirst(8).split(separator: " ")
                let x = Double(parts.first ?? "0") ?? 0
                let y = Double(parts.count > 1 ? parts[1] : "0") ?? 0
                let screenPoint = NSPoint(x: x, y: y)
                let shape = NotchController.shared.visibleShapeScreenRect()
                if let window = NSApp.windows.first(where: { $0 is NotchPanel }) {
                    let inWindow = window.convertPoint(fromScreen: screenPoint)
                    let hit = window.contentView?.hitTest(inWindow)
                    appendState("hittest screen=(\(Int(x)),\(Int(y))) "
                                + "window=(\(Int(inWindow.x)),\(Int(inWindow.y))) "
                                + "shapeRect=\(shape) insideShape=\(shape.contains(screenPoint)) "
                                + "hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
                } else {
                    appendState("hittest: no notch panel")
                }
            } else if command.hasPrefix("notes-move ") {
                // notes-move <fromIndex> <beforeIndex>
                let parts = command.dropFirst(11).split(separator: " ")
                let n = NotesStore.shared
                if parts.count == 2, let from = Int(parts[0]), let to = Int(parts[1]),
                   from < n.stream.count, to < n.stream.count {
                    n.reorder(n.stream[from].id, before: n.stream[to].id)
                }
            } else if command == "notes-roundtrip" {
                // markdown -> attributed -> markdown. Anything that does not
                // come back identical is a format the editor would silently
                // eat the moment the user saved.
                let cases: [String] = [
                    "plain line",
                    "# Scadenze",
                    "## Da chiarire prima di firmare",
                    "- chi paga la caldaia il primo anno",
                    "- [ ] aperta",
                    "- [x] fatta",
                    "1. primo\n2. secondo\n3. terzo",
                    "il preavviso e di **tre mesi**, spedita entro il *31 luglio*",
                    "una riga con <u>sottolineato</u> dentro",
                    "# Titolo\n\nparagrafo con **bold** e *corsivo*\n\n## Sotto\n- uno\n- due\n\n1. a\n2. b\n\n- [ ] da fare\n- [x] fatto",
                    "",
                    "riga\n\nriga dopo una vuota",
                ]
                var failures = 0
                for source in cases {
                    let attributed = NoteMarkdown.attributed(
                        from: source, textColor: .labelColor,
                        accent: .controlAccentColor, mutedColor: .tertiaryLabelColor)
                    let back = NoteMarkdown.markdown(from: attributed)
                    if back != source {
                        failures += 1
                        appendState("ROUNDTRIP FAIL\n  in:  \(source.debugDescription)\n  out: \(back.debugDescription)")
                    }
                }
                appendState("roundtrip: \(cases.count - failures)/\(cases.count) identical")
            } else if command == "notes-status" {
                let n = NotesStore.shared
                appendState("notes count=\(n.notes.count) mode=\(TodoStore.shared.panelMode) "
                            + "open=\(n.openNote?.title ?? "nil") "
                            + "draft='\(n.draft)' selected=\(n.selectedNoteID.flatMap { id in n.note(id: id)?.title } ?? "nil") "
                            + "collection=\(TodoStore.shared.activeCollection?.name ?? "nil") "
                            + "top=[" + n.stream.prefix(3).map {
                                "'\($0.title)'/\($0.titleSource.rawValue)"
                            }.joined(separator: " ") + "]")
            } else if command == "cal-release" {
                CalendarStore.shared.debugReleaseInjectedMeetings()
            } else if command == "cal-snooze" {
                CalendarStore.shared.snooze()
            } else if command == "cal-dismiss" {
                CalendarStore.shared.dismissAlert()
            } else if command == "cal-disconnect" {
                CalendarStore.shared.disconnect()
            } else if command == "voice-status" {
                appendState("voiceOnDevice=\(VoiceTranscriber.isOnDeviceAvailable) "
                            + "engine=\(BrainDumpParser.activeEngine) "
                            + "phase=\(VoiceCaptureController.shared.phase)")
            } else if command == "create-fresh" {
                NotchController.shared.openCreateFresh()
            } else if command.hasPrefix("movecat-before ") {
                // movecat-before <from> <to> — the drop delegate's own path.
                let parts = command.dropFirst(15).split(separator: " ").compactMap { Int($0) }
                if parts.count == 2, parts.allSatisfy({ $0 >= 0 && $0 < store.collections.count }) {
                    store.moveCollection(store.collections[parts[0]].id,
                                         before: store.collections[parts[1]].id)
                }
            } else if command.hasPrefix("step-rename ") {
                // step-rename <index> <text> — the path the field's commit takes.
                let rest = command.dropFirst(12)
                if let sp = rest.firstIndex(of: " "), let i = Int(rest[rest.startIndex..<sp]),
                   let collection = store.activeCollection,
                   let first = store.openItems(in: collection).first,
                   i >= 0, i < first.checklist.count {
                    store.renameChecklistItem(first.checklist[i].id, in: first.id,
                                              to: String(rest[rest.index(after: sp)...]))
                }
            } else if command == "steps" {
                if let collection = store.activeCollection,
                   let first = store.openItems(in: collection).first {
                    appendState("steps of '\(first.title)': "
                        + first.checklist.map { "\($0.title)\($0.isDone ? " [x]" : "")" }
                            .joined(separator: " | "))
                }
            } else if command.hasPrefix("presence-meet ") {
                if let m = Int(command.dropFirst(14)) {
                    NotchPresence.shared.debugOverride =
                        .countdown(.init(platform: .meet, minutes: m))
                }
            } else if command.hasPrefix("presence-todo ") {
                if let m = Int(command.dropFirst(14)) {
                    NotchPresence.shared.debugOverride =
                        .countdown(.init(platform: nil, minutes: m))
                }
            } else if command.hasPrefix("movecat-end ") {
                if let i = Int(command.dropFirst(12)), i >= 0, i < store.collections.count {
                    store.moveCollectionToEnd(store.collections[i].id)
                }
            } else if command == "defaultcat" {
                let name = store.collection(id: store.defaultCreationCollectionID ?? UUID())?.name ?? "nil"
                // The draft has no collection of its own any more: the
                // active tab IS its destination.
                appendState("defaultCreationCollection=\(name) mode=\(store.panelMode) "
                            + "draftFocused=\(store.draftFocused) destination=\(store.draftDestination?.name ?? "nil")")
            } else if command.hasPrefix("entities ") {
                let text = String(command.dropFirst(9))
                let segments = EntityParser.parse(text).map { segment -> String in
                    switch segment {
                    case .text(let run): return "text('\(run)')"
                    case .entity(let kind, let display, let url):
                        return "\(kind)('\(display)'\(url.map { ", \($0)" } ?? ""))"
                    }
                }
                appendState("entities '\(text)' -> [" + segments.joined(separator: ", ") + "]")
            } else if command.hasPrefix("parse ") {
                let text = String(command.dropFirst(6))
                let result = NLDateParser.parse(text)
                appendState("parse '\(text)' -> " + (result.map {
                    "range=\($0.nsRange) display='\($0.display)' cleaned='\($0.cleanedTitle)' date=\($0.date)"
                } ?? "nil"))
            } else if command.hasPrefix("note ") {
                if let collection = store.activeCollection,
                   let first = store.openItems(in: collection).first {
                    store.setNote(String(command.dropFirst(5)), for: first.id)
                }
            } else if command.hasPrefix("step ") {
                if let collection = store.activeCollection,
                   let first = store.openItems(in: collection).first {
                    store.addChecklistItem(String(command.dropFirst(5)), to: first.id)
                }
            } else if command == "step-focus-draft" || command == "detail-title" || command == "step-down" || command == "step-up" {
                // Step focus, drivable without a keyboard.
                //
                // The arrow-key walk lives in the key router, which needs real
                // key events; these reach the same store methods so the
                // model half — where the off-by-one would be — can be checked
                // headlessly on a machine with no synthetic input.
                if let collection = store.activeCollection,
                   let first = store.openItems(in: collection).first {
                    switch command {
                    case "step-focus-draft": store.focusStepDraft(in: first.id)
                    case "detail-title":     store.focusDetail(.title, in: first.id)
                    case "step-down":        store.moveDetailFocus(1, in: first.id)
                    default:                 store.moveDetailFocus(-1, in: first.id)
                    }
                    let where_: String
                    switch store.focusedDetail?.target {
                    case .title:     where_ = "title"
                    case .note:      where_ = "note"
                    case .stepDraft: where_ = "draft"
                    case .step(let id):
                        let idx = first.checklist.firstIndex { $0.id == id }
                        where_ = "step[\(idx.map(String.init) ?? "?")]"
                    case nil:        where_ = "nil"
                    }
                    // Into the state file, not stdout: the app is launched
                    // detached, so `print` goes nowhere an agent can read.
                    appendState("stepFocus=\(where_) of \(first.checklist.count) steps")
                }
            }
        }
    }

    private static func dumpState() {
        let app = AppState.shared
        let store = TodoStore.shared
        let open = store.activeCollection.map { store.openItems(in: $0).count } ?? -1
        let done = store.activeCollection.map { store.completedItems(in: $0).count } ?? -1
        let progress = store.activeCollection.flatMap { store.progress(for: $0) }
        appendState("""
        state=\(NotchController.shared.state) mode=\(store.panelMode) \
        activeCollection=\(store.activeCollection?.name ?? "nil") \
        open=\(open) completed=\(done) settling=\(store.settlingItemIDs.count) \
        progress=\(progress.map { String(format: "%.2f", $0) } ?? "nil") \
        expandedRow=\(store.expandedItemID != nil) focused=\(store.focusedItemID != nil) \
        findQuery='\(store.findQuery)' findMatches=\(store.findMatches.count) \
        draftFocused=\(store.draftFocused) dest=\(store.draftDestination?.name ?? "nil") \
        draft='\(store.draftTitle)' \
        layout=\(app.notchLayout) \
        todoContentHeight=\(app.todoContentHeight) \
        labColumnHeight=\(app.labColumnHeight) \
        notchExtraHeight=\(app.notchExtraHeight)
        """)
    }

    private static func appendState(_ text: String) {
        let line = "[\(Date())] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: stateFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: stateFile)
        }
    }
}
#endif
