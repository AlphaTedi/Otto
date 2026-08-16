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
            store.cancelDraft()
        case "create-tab":
            // Same path the Tab key takes: re-aim the draft, leave it alone.
            store.cycleDraftDestination()
        case "browse-mode":
            store.setMode(.browsing)
        case "expand-focused":
            if let focused = store.focusedItemID ?? store.activeCollection.flatMap({ store.openItems(in: $0).first?.id }) {
                withAnimation(NotchAnimation.contentHug) { store.expandedItemID = focused }
            }
        case "collapse-row":
            withAnimation(NotchAnimation.contentHug) { store.expandedItemID = nil }
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
            } else if command.hasPrefix("setdefault ") {
                // setdefault <index> — mark the collection at tab index default.
                if let i = Int(command.dropFirst(11)), i >= 0, i < store.collections.count {
                    store.setDefaultCollection(store.collections[i].id)
                }
            } else if command == "defaultcat" {
                let name = store.collection(id: store.defaultCreationCollectionID ?? UUID())?.name ?? "nil"
                // The draft has no collection of its own any more: the
                // active tab IS its destination.
                appendState("defaultCreationCollection=\(name) mode=\(store.panelMode) "
                            + "drafting=\(store.isCreatingDraft) destination=\(store.activeCollection?.name ?? "nil")")
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
        expandedRow=\(store.expandedItemID != nil) \
        findQuery='\(store.findQuery)' findMatches=\(store.findMatches.count) \
        drafting=\(store.isCreatingDraft) draft='\(store.draftTitle)' \
        todoContentHeight=\(app.todoContentHeight) \
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
