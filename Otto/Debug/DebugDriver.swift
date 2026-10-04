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
//     .postNotificationName(Notification.Name("otto.debug.command"),
//                           object: "expand", userInfo: nil,
//                           deliverImmediately: true)'
//
// Commands: expand | collapse | add <title> | complete-first |
//           uncomplete-first | delete-first | switch <index> | dump
// `dump` appends the hugging-height state to /tmp/otto-debug-state.txt.
// Never compiled into Release.

@MainActor
enum DebugDriver {
    private static let stateFile = URL(fileURLWithPath: "/tmp/otto-debug-state.txt")
    private static var verificationNoteID: UUID?
    private static var verificationTodoID: UUID?

    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("otto.debug.command"),
            object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { handle(command) }
        }
        // `open -n Otto.app --args -debugCommand "<command>"`: for shells
        // whose distributed notifications never reach the app.
        if let command = UserDefaults.standard.string(forKey: "debugCommand") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MainActor.assumeIsolated { handle(command) }
            }
        }
    }

    private static func handle(_ command: String) {
        let store = TodoStore.shared
        switch command {
        case "verify-presentation":
            Task { @MainActor in
                let controller = NotchController.shared
                var failures = 0
                for _ in 0..<30 {
                    controller.collapse()
                    controller.triggerExpand()
                    if controller.state != .expanded || !controller.contentVisible { failures += 1 }
                    controller.triggerCollapse(force: true)
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    controller.cancelCollapse()
                    if controller.state != .expanded || !controller.contentVisible { failures += 1 }
                    controller.triggerCollapse(force: true)
                    controller.triggerExpand()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if controller.state != .expanded || !controller.contentVisible { failures += 1 }
                    controller.collapse()
                    if controller.contentVisible { failures += 1 }
                }
                controller.triggerExpand()
                appendState("presentation regression: 30 cycles, failures=\(failures)")
            }
        case "expand":
            NotchController.shared.triggerExpand()
        case "collapse":
            NotchController.shared.triggerCollapse()
        case "complete-first":
            if let collection = store.activeCollection,
               let first = store.openItems(in: collection).first {
                store.toggleComplete(first.id)
            }
        // Test items land in the REAL store, so verification needs a way to
        // take them back out again — otherwise every run leaves a row behind
        // in someone's actual list.
        case "delete-first":
            if let collection = store.activeCollection,
               let first = store.openItems(in: collection).first {
                store.delete(first.id)
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
        case "step-preview-status":
            if let item = store.items.max(by: { $0.checklist.count < $1.checklist.count }) {
                let previous = store.expandedItemID
                store.expandedItemID = nil
                let closedVisible = ChecklistDisclosure.visibleCount(
                    total: item.checklist.count, expanded: false
                )
                let closedHidden = ChecklistDisclosure.hiddenCount(
                    total: item.checklist.count, expanded: false
                )
                store.expandedItemID = item.id
                let openVisible = ChecklistDisclosure.visibleCount(
                    total: item.checklist.count, expanded: true
                )
                appendState("step preview: total=\(item.checklist.count) "
                            + "closedVisible=\(closedVisible) closedHidden=\(closedHidden) "
                            + "openVisible=\(openVisible)")
                store.expandedItemID = previous
            } else {
                appendState("step preview: no items")
            }
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
                    store.addItem(title: title, collectionID: target)
                }
            } else if command.hasPrefix("analytics-consent ") {
                // analytics-consent yes|no|reset — reset puts it back to "never asked".
                switch command.dropFirst(18) {
                case "yes": Analytics.setConsent(true)
                case "no": Analytics.setConsent(false)
                default: AppState.shared.updateSettings { $0.analyticsConsent = nil }
                }
                appendState("analytics " + AnalyticsQueue.shared.debugDump())
            } else if command == "analytics-flush" {
                Analytics.flush()
                appendState("analytics flush requested")
            } else if command.hasPrefix("chip-snap-pid ") {
                // chip-snap-pid <pid> <dir> — a to-do title with an image chip,
                // at rest and hovered, and the hover preview's card.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                let directory = URL(fileURLWithPath: String(parts[2]))
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let title = "Send the deck ![Image 2026-09-27T19.15.43.png](Attachments/debug sample 000000.png) to the team tomorrow"
                let host = NSHostingView(rootView: EntityTitleView(title: title, isBright: true, onTap: {})
                    .frame(width: 420).padding(12).background(Color(hex: "#1B1F35"))
                    .environment(\.colorScheme, .dark))
                host.appearance = NSAppearance(named: .darkAqua)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: host.frame.width, height: host.frame.height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.orderBack(nil)
                @MainActor func snap(_ view: NSView, _ name: String) {
                    view.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
                }
                snap(host, "row")
                func textViews(_ v: NSView) -> [EntityTextView] { (v as? EntityTextView).map { [$0] } ?? v.subviews.flatMap(textViews) }
                if let tv = textViews(host).first, let storage = tv.textStorage {
                    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                        if let cell = (value as? ImageChipAttachment)?.attachmentCell as? ImageChipCell {
                            cell.hovered = true; cell.showsRemove = true
                        }
                    }
                    tv.needsDisplay = true
                }
                snap(host, "row-hover")
                ImagePreviewPanel.shared.show("Attachments/debug sample 000000.png",
                                              above: NSRect(x: 200, y: 200, width: 100, height: 20), owner: window) {}
                if let card = NSApp.windows.first(where: { $0 is NSPanel && $0.contentView?.subviews.first is NSImageView })?.contentView {
                    snap(card, "preview")
                }
                ImagePreviewPanel.shared.hide()
                window.orderOut(nil)
                appendState("chip-snap done")
            } else if command.hasPrefix("entity-chip-snap-pid ") {
                // entity-chip-snap-pid <pid> <dir> — a title with date, link and
                // @name chips in light and in dark. Writes nothing.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                let directory = URL(fileURLWithPath: String(parts[2]))
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let saved = NSApp.appearance
                for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    NSApp.appearance = NSAppearance(named: look)
                    let view = EntityTitleView(title: "Call @simon today about https://skiper-ui.com and `code`",
                                               isBright: false, onTap: {})
                        .frame(width: 520, height: 40)
                        .padding(12)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let host = NSHostingView(rootView: view)
                    host.appearance = NSAppearance(named: look)
                    host.frame = NSRect(x: 0, y: 0, width: 544, height: 64)
                    host.layoutSubtreeIfNeeded()
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: directory.appendingPathComponent("chips-\(name).png"))
                    }
                }
                NSApp.appearance = saved
                appendState("entity-chip-snap done")
            } else if command.hasPrefix("empty-snap-pid ") {
                // empty-snap-pid <pid> <dir> — the empty state, floating and
                // container, a few moments apart in its loop. Writes nothing.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                let directory = URL(fileURLWithPath: String(parts[2]))
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                NotchController.shared.triggerExpand()
                let floating = NSHostingView(rootView: EmptyListView(fillHeight: 380)
                    .frame(width: 657, height: 420, alignment: .top)
                    .background(LinearGradient(colors: [Color(hex: "#1B1F35"), Color(hex: "#261F35")],
                                               startPoint: .top, endPoint: .bottom))
                    .environment(\.colorScheme, .dark))
                floating.frame = NSRect(x: 0, y: 0, width: 657, height: 420)
                let container = NSHostingView(rootView: EmptyListView(compact: true)
                    .frame(width: 560)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark))
                container.frame = NSRect(x: 0, y: 0, width: 560, height: 260)
                let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 700, height: 700),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                let holder = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 700))
                holder.addSubview(floating); holder.addSubview(container)
                window.contentView = holder
                window.orderBack(nil)
                Task { @MainActor in
                    for i in 0..<6 {
                        try? await Task.sleep(nanoseconds: 1_300_000_000)
                        for (name, host) in [("floating", floating), ("container", container)] {
                            host.layoutSubtreeIfNeeded()
                            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                                host.cacheDisplay(in: host.bounds, to: rep)
                                try? rep.representation(using: .png, properties: [:])?
                                    .write(to: directory.appendingPathComponent("\(name)-\(i).png"))
                            }
                        }
                    }
                    window.orderOut(nil)
                    appendState("empty-snap done")
                }
            } else if command.hasPrefix("presence-snap-pid ") {
                // presence-snap-pid <pid> <dir> — the collapsed notch's meeting
                // indicator for each platform, and the card icons. Writes nothing.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                let directory = URL(fileURLWithPath: String(parts[2]))
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let platforms: [(String, MeetingPlatform)] = [("meet", .meet), ("zoom", .zoom), ("teams", .teams), ("other", .otherVideo)]
                let view = VStack(spacing: 8) {
                    ForEach(platforms, id: \.0) { item in
                        NotchPresenceView(state: .countdown(.init(platform: item.1, minutes: 0)),
                                          notchWidth: 180, wingWidth: 53)
                            .frame(width: 286, height: 32)
                            .background(Color.black)
                    }
                    HStack(spacing: 12) {
                        ForEach(["Google Meet", "Zoom", "Microsoft Teams"], id: \.self) { name in
                            MeetingPlatformIcon(platform: name).frame(width: 22, height: 22)
                        }
                    }
                    .padding(8)
                    .background(Color(white: 0.15))
                }
                .padding(10)
                .background(Color(white: 0.3))
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
                host.layoutSubtreeIfNeeded()
                host.frame.size = host.fittingSize
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: directory.appendingPathComponent("presence.png"))
                }
                appendState("presence-snap done")
            } else if command.hasPrefix("settings-snap-pid ") {
                // settings-snap-pid <pid> <dir> — every Settings page, light
                // and dark, rendered off screen. Writes nothing.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                let directory = URL(fileURLWithPath: String(parts[2]))
                Task { @MainActor in
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                        // On screen but behind every other window: an
                        // off-screen window never draws its scroll views.
                        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 860, height: 640),
                                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                        window.titlebarAppearsTransparent = true
                        window.appearance = NSAppearance(named: appearance)
                        let host = NSHostingView(rootView: SettingsView().environmentObject(AppState.shared))
                        window.contentView = host
                        window.orderBack(nil)
                        // The detail pane alone too: cacheDisplay draws a
                        // Form, it does not draw a split view.
                        let pageWindow = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 620, height: 640),
                                                  styleMask: [.borderless], backing: .buffered, defer: false)
                        pageWindow.appearance = NSAppearance(named: appearance)
                        for section in SettingsSection.allCases {
                            let pageHost = NSHostingView(rootView: SettingsPageDebugHost(section: section)
                                .environmentObject(AppState.shared))
                            pageWindow.contentView = pageHost
                            pageWindow.orderBack(nil)
                            try? await Task.sleep(nanoseconds: 700_000_000)
                            pageHost.layoutSubtreeIfNeeded()
                            if let rep = pageHost.bitmapImageRepForCachingDisplay(in: pageHost.bounds) {
                                pageHost.cacheDisplay(in: pageHost.bounds, to: rep)
                                try? rep.representation(using: .png, properties: [:])?
                                    .write(to: directory.appendingPathComponent("page-\(name)-\(section.rawValue).png"))
                            }
                        }
                        let sidebarHost = NSHostingView(rootView: SettingsSidebar(selection: .constant(.appearance))
                            .frame(width: 230, height: 520))
                        pageWindow.contentView = sidebarHost
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if let rep = sidebarHost.bitmapImageRepForCachingDisplay(in: sidebarHost.bounds) {
                            sidebarHost.cacheDisplay(in: sidebarHost.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?
                                .write(to: directory.appendingPathComponent("sidebar-\(name).png"))
                        }
                        pageWindow.orderOut(nil)
                        for section in SettingsSection.allCases {
                            AppState.shared.pendingSettingsSection = section
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            // The split view and Form are layer trees that
                            // cacheDisplay leaves blank; render the layers.
                            host.layoutSubtreeIfNeeded()
                            window.display()
                            CATransaction.flush()
                            if let layer = window.contentView?.superview?.layer ?? host.layer {
                                let scale: CGFloat = 2
                                let size = layer.bounds.size
                                if let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                                       bitsPerComponent: 8, bytesPerRow: 0,
                                                       space: CGColorSpaceCreateDeviceRGB(),
                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                                    ctx.scaleBy(x: scale, y: scale)
                                    layer.render(in: ctx)
                                    if let image = ctx.makeImage() {
                                        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                                            .write(to: directory.appendingPathComponent("\(name)-\(section.rawValue).png"))
                                    }
                                }
                            }
                        }
                        window.orderOut(nil)
                    }
                    appendState("settings-snap done")
                }
            } else if command.hasPrefix("feedback-snap-pid ") {
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                FeedbackWindowController.debugSnapshot(to: URL(fileURLWithPath: String(parts[2])))
                appendState("feedback-snap done")
            } else if command == "analytics-dump" {
                appendState("analytics " + AnalyticsQueue.shared.debugDump())
            } else if command == "onboarding-flow-test" {
                Task { @MainActor in
                    for line in await OnboardingWindowController.debugFlowTest() { appendState("flow " + line) }
                    appendState("onboarding-flow-test done")
                }
            } else if command.hasPrefix("onboarding-snap-pid ") {
                // onboarding-snap-pid <pid> <dir> [steps] — only that process
                // answers, so a Debug instance run from Xcode stays still.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                handle("onboarding-snap " + String(parts[2]))
            } else if command.hasPrefix("onboarding-snap ") {
                // onboarding-snap <dir> [step,step…] — PNGs of the real window.
                let parts = command.dropFirst(16).split(separator: " ")
                let directory = URL(fileURLWithPath: String(parts.first ?? "/tmp/otto-onboarding"))
                let steps = parts.count > 1
                    ? parts[1].split(separator: ",").compactMap { Int($0) }.compactMap { OnboardingStep(rawValue: $0) }
                    : OnboardingStep.allCases
                Task { @MainActor in
                    await OnboardingWindowController.debugSnapshots(to: directory, steps: steps)
                    appendState("onboarding-snap done: \(directory.path)")
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
                            + "notch=\(NotchController.shared.state) "
                            + "joinHotKey=\(HotkeyManager.shared.joinHotKeyActive) status=\(HotkeyManager.shared.joinHotKeyStatus) "
                            + "panelKey=\(NSApp.keyWindow is NotchPanel)")
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
            } else if command == "force-collapse" {
                NotchController.shared.forceCollapse()
            } else if command == "reopen-click" {
                // The click path: open, then take the caret.
                NotchController.shared.triggerExpand()
                NotchController.shared.makeKeyForTyping()
            } else if command.hasPrefix("panel-render-pid ") {
                // panel-render-pid <pid> <dir> — only the process with that pid
                // answers, so a second Debug instance (Xcode's) stays still.
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                handle("panel-render " + String(parts[2]))
            } else if command.hasPrefix("panel-render ") {
                // panel-render <dir> — renders the panel in every U5 state. Writes
                // nothing: selection, a typed draft (cleared) and a highlight.
                let directory = URL(fileURLWithPath: String(command.dropFirst(13)))
                Task { @MainActor in
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let controller = NotchController.shared
                    let notes = NotesStore.shared
                    let original = store.activeCollectionID
                    controller.triggerExpand()
                    GlassDebug.forceOpaque = true
                    // The live panel draws inside system glass, which a
                    // bitmap cache cannot capture — so the same view is hosted
                    // off screen on the spec's own panel background instead.
                    let container = AppState.shared.notchLayout == .container
                    let size = NSSize(width: container ? 560 : PanelMetrics.blockWidth,
                                      height: container ? 520 : PanelMetrics.todoBlockMaxHeight)
                    let shape = RoundedRectangle(cornerRadius: container ? 30 : PanelMetrics.blockRadius,
                                                 style: .continuous)
                    let root = TodoTabView()
                        .frame(width: size.width, height: container ? nil : size.height,
                               alignment: .top)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .background(container ? AnyView(Color.black) : AnyView(LinearGradient(
                            stops: [.init(color: Color(hex: "#1B1F35"), location: 0),
                                    .init(color: Color(hex: "#1E1D33"), location: 0.55),
                                    .init(color: Color(hex: "#261F35"), location: 1)],
                            startPoint: .top, endPoint: .bottom)))
                        .clipShape(shape)
                        .environmentObject(AppState.shared)
                        .environment(\.colorScheme, .dark)
                    let host = NSHostingView(rootView: root)
                    host.frame = NSRect(origin: .zero, size: size)
                    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.contentView = host
                    window.orderBack(nil)
                    @MainActor func snap(_ name: String) async {
                        try? await Task.sleep(nanoseconds: 1_300_000_000)
                        let view: NSView = host
                        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: directory.appendingPathComponent(name + ".png"))
                    }
                    @MainActor func list(_ name: String) -> TodoCollection? {
                        store.collections.first { $0.name.lowercased() == name }
                    }
                    for name in ["work", "grocery", "personal", "otto things to do"] {
                        if let c = list(name) { notes.leaveSpace(); store.selectCollection(c.id) }
                        await snap("space-" + name)
                    }
                    // Empty state B: the first user list with nothing open.
                    if let empty = store.collections.first(where: {
                        !$0.isSystemToday && store.openItems(in: $0).isEmpty
                    }) {
                        notes.leaveSpace(); store.selectCollection(empty.id)
                        await snap("space-empty")
                    }
                    notes.enterSpace(); await snap("space-notes")
                    // Inner pages: the context bar replaces the capture field.
                    if let first = notes.stream.first {
                        notes.open(first.id); await snap("page-note"); await snap("page-note-late")
                        appendState("page-note path=\(store.panelPath.map(\.title))")
                        if let storage = NoteEditorController.shared.textView?.textStorage {
                            var done = 0, actions = 0
                            storage.enumerateAttribute(.noteActionDone, in: NSRange(location: 0, length: storage.length)) { v, _, _ in if v != nil { done += 1 } }
                            storage.enumerateAttribute(.noteAction, in: NSRange(location: 0, length: storage.length)) { v, _, _ in if v != nil { actions += 1 } }
                            appendState("page-note actions=\(actions) linked=\(done) detected=\(NoteEditorController.shared.detectedCount)")
                        }
                        store.goBack()
                    }
                    notes.enterCalendarSpace(); await snap("space-calendar")
                    notes.openKindMenu(); await snap("space-calendar-menu")
                    notes.closeKindMenu()
                    store.openAvatarMenu(); await snap("space-calendar-gear")
                    store.closeAvatarMenu()
                    notes.openKindMenu()
                    notes.chooseKind(meetings: false); await snap("space-notes-after-menu")
                    appendState("kind menu: open=\(notes.kindMenuOpen) mode=\(store.panelMode)")
                    notes.leaveSpace()
                    store.enterInsights(); await snap("page-insights")
                    store.goBack()
                    store.setMode(.newCategory); await snap("page-newsection")
                    store.goBack()
                    appendState("after back: mode=\(store.panelMode) path=\(store.panelPath.map(\.title))")
                    if let work = list("work") {
                        store.selectCollection(work.id)
                        store.draftTitle = "Send deck ![debug-sample.png](Attachments/debug-sample-000000.png) to Roos"
                        await snap("input-typing")
                        store.draftTitle = "A much longer to-do title that would have wrapped onto a second and a third line before"
                        await snap("input-long")
                        store.draftTitle = ""
                        if let first = store.openItems(in: work).first {
                            store.focusedItemID = first.id
                            await snap("row-focused")
                            store.focusedItemID = nil
                            store.expandedItemID = first.id
                            await snap("row-expanded")
                            store.expandedItemID = nil
                        }
                    }
                    // The longest list, walked down to its last to-do the way
                    // ↓ does: the row must end up above the floating pills.
                    if let long = store.collections.max(by: { store.openItems(in: $0).count < store.openItems(in: $1).count }) {
                        store.selectCollection(long.id)
                        await snap("long-top")
                        for item in store.openItems(in: long) {
                            store.focusedItemID = item.id
                            try? await Task.sleep(nanoseconds: 250_000_000)
                        }
                        await snap("row-focused-last")
                        store.focusedItemID = nil
                    }
                    if let original { store.selectCollection(original) }
                    window.orderOut(nil)
                    GlassDebug.forceOpaque = false
                    controller.forceCollapse()
                    appendState("u5-snap done: \(directory.path) layout=\(AppState.shared.notchLayout)")
                }
            } else if command == "place-test" {
                // Close-and-reopen keeps the place: once in a note, once in a
                // to-do section. Opens an existing note; writes nothing.
                Task { @MainActor in
                    let controller = NotchController.shared
                    let notes = NotesStore.shared
                    @MainActor func report(_ label: String) {
                        appendState("\(label): state=\(controller.state) mode=\(store.panelMode) "
                            + "section=\(store.activeCollection?.name ?? "nil") "
                            + "openNote=\(notes.openNoteID != nil) draftWantsFocus=\(store.draftWantsFocus) "
                            + "bodyFocus=\(notes.bodyFocusRequest)")
                    }
                    controller.triggerExpand()
                    notes.enterSpace()
                    if let first = notes.stream.first { notes.open(first.id) }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    report("notes before close")
                    controller.forceCollapse()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    report("notes after close")
                    controller.triggerExpand(); controller.makeKeyForTyping()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    report("notes after reopen")

                    notes.leaveSpace()
                    if let second = store.visibleCollections.dropFirst().first(where: { !$0.isSystemToday }) {
                        store.selectCollection(second.id)
                    }
                    report("list before close")
                    controller.forceCollapse()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    controller.triggerExpand(); controller.makeKeyForTyping()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    report("list after reopen")
                    controller.forceCollapse()
                }
            } else if command == "place" {
                let notes = NotesStore.shared
                appendState("place: state=\(NotchController.shared.state) mode=\(store.panelMode) "
                            + "section=\(store.activeCollection?.name ?? "nil") "
                            + "openNote=\(notes.openNoteID.flatMap { notes.note(id: $0)?.title } ?? "nil") "
                            + "draftWantsFocus=\(store.draftWantsFocus) bodyFocus=\(notes.bodyFocusRequest)")
            } else if command == "notes-enter" {
                NotesStore.shared.enterSpace()
            } else if command == "notes-verification-create" {
                let notes = NotesStore.shared
                notes.enterSpace()
                notes.draft = "Otto verification: chiamare agenzia e chiedere preventivo aggiornato"
                if let created = notes.commitDraft() {
                    verificationNoteID = created.id
                    notes.open(created.id)
                }
            } else if command == "notes-verification-delete" {
                if let id = verificationNoteID {
                    NotesStore.shared.delete(id)
                    verificationNoteID = nil
                }
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
            } else if command.hasPrefix("kind-click-pid ") {
                // kind-click-pid <pid> — opens the Notes · Meetings menu and
                // sends a real mouse click (through NSWindow.sendEvent, the
                // path a hardware click takes) to its Meetings row, then to
                // the gear menu's first row. Logs what each click changed.
                guard Int32(command.dropFirst(15)) == ProcessInfo.processInfo.processIdentifier else { return }
                Task { @MainActor in
                    let notes = NotesStore.shared
                    NotchController.shared.triggerExpand()
                    notes.enterSpace()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard let window = NSApp.windows.first(where: { $0 is NotchPanel }),
                          let host = window.contentView.flatMap(Self.hostingView(in:)) else {
                        appendState("kind-click: no panel"); return
                    }
                    @MainActor func click(_ point: CGPoint) async {
                        let inWindow = host.convert(point, to: nil)
                        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [],
                                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                                              windowNumber: window.windowNumber, context: nil,
                                                              eventNumber: 0, clickCount: 1, pressure: 1) {
                                window.sendEvent(event)
                            }
                            try? await Task.sleep(nanoseconds: 60_000_000)
                        }
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    guard let trigger = MenuAnchorDebug.global[.notesKind] else { appendState("kind-click: no trigger"); return }
                    await click(CGPoint(x: trigger.midX, y: trigger.midY))
                    appendState("kind-click after trigger: open=\(notes.kindMenuOpen)")
                    // Second row: gap 8, padding 10, row 1 is ~40 tall.
                    await click(CGPoint(x: trigger.maxX - 60, y: trigger.maxY + 8 + 10 + 41 + 20))
                    appendState("kind-click after Meetings row: open=\(notes.kindMenuOpen) mode=\(store.panelMode)")
                    notes.enterSpace()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if let gear = MenuAnchorDebug.global[.gear] {
                        await click(CGPoint(x: gear.midX, y: gear.midY))
                        appendState("gear-click: menu=\(store.showsAvatarMenu) highlight=\(store.avatarMenuHighlight)")
                        store.closeAvatarMenu()
                    }
                    NotchController.shared.forceCollapse()
                    appendState("kind-click done")
                }
            } else if command.hasPrefix("kind-hit-pid ") {
                // kind-hit-pid <pid> — what a click over the Notes · Meetings
                // menu's column reaches, with the menu closed and open.
                guard Int32(command.dropFirst(13)) == ProcessInfo.processInfo.processIdentifier else { return }
                Task { @MainActor in
                    let notes = NotesStore.shared
                    NotchController.shared.triggerExpand()
                    notes.enterSpace()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard let window = NSApp.windows.first(where: { $0 is NotchPanel }),
                          let content = window.contentView else { return }
                    @MainActor func sample(_ label: String) {
                        let x = content.bounds.midX + PanelMetrics.blockWidth / 2 - 90
                        var line = label + ":"
                        for fromTop in stride(from: 100, through: 400, by: 15) {
                            let y = content.isFlipped ? CGFloat(fromTop) : content.bounds.maxY - CGFloat(fromTop)
                            let hit = content.hitTest(NSPoint(x: x, y: y))
                            line += " \(fromTop)=\(hit.map { String(reflecting: type(of: $0)).components(separatedBy: ".").suffix(2).joined(separator: ".") } ?? "nil")"
                        }
                        appendState(line)
                    }
                    sample("closed")
                    notes.openKindMenu()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    sample("open")
                    notes.closeKindMenu()
                    NotchController.shared.forceCollapse()
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
                                + "insideContent=\(NotchController.shared.isInsidePanelContent(screenPoint)) "
                                + "hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
                } else {
                    appendState("hittest: no notch panel")
                }
            } else if command == "panel-hit-regions" {
                let controller = NotchController.shared
                if let panel = controller.panelForDebug {
                    let frames = controller.panelContentFramesForDebug.map { frame in
                        NSRect(x: panel.frame.minX + frame.minX,
                               y: panel.frame.maxY - frame.maxY,
                               width: frame.width, height: frame.height)
                    }
                    appendState("panel-hit-regions window=\(panel.frame) cards=\(frames)")
                } else {
                    appendState("panel-hit-regions: no notch panel")
                }
            } else if command.hasPrefix("notes-move ") {
                // notes-move <fromIndex> <beforeIndex>
                let parts = command.dropFirst(11).split(separator: " ")
                let n = NotesStore.shared
                if parts.count == 2, let from = Int(parts[0]), let to = Int(parts[1]),
                   from < n.stream.count, to < n.stream.count {
                    n.reorder(n.stream[from].id, before: n.stream[to].id)
                }
            } else if command == "meeting-notes-open" {
                let meeting = DetectedMeeting(id: "otto-verification-meeting", title: "Meeting notes verification",
                    start: Date(), end: Date().addingTimeInterval(1800), attendees: [], attendeeEmails: [], isAllDay: false)
                NotchController.shared.presentMeetingAlert()
                CalendarStore.shared.openNotes(for: meeting)
            } else if command.hasPrefix("meeting-layout ") {
                let name = String(command.dropFirst(15))
                UserDefaults.standard.set(name == "container" ? "container" : "panels", forKey: "notchLayout")
                AppState.shared.todoContentHeight = 0
                AppState.shared.panelColumnHeight = 0
            } else if command == "meeting-notes-status" {
                let notes = NotesStore.shared
                let editor = NoteEditorController.shared
                let key = NSApp.keyWindow
                appendState("meeting-status open=\(notes.openNote?.meetingContext != nil) persisted=\(notes.openNoteID.flatMap { notes.note(id: $0) } != nil) focus=\(notes.meetingFocus) bodyResponder=\(key?.firstResponder === editor.textView) alert=\(CalendarStore.shared.activeAlert != nil) contentHeight=\(AppState.shared.todoContentHeight)")
            } else if command == "notes-calendar" {
                NotesStore.shared.enterCalendarSpace()
            } else if command.hasPrefix("actions-underline ") {
                let phrase = String(command.dropFirst(18))
                if let view = NoteEditorController.shared.textView {
                    let range = (view.string as NSString).range(of: phrase)
                    if range.location != NSNotFound {
                        view.setSelectedRange(range)
                        NoteEditorController.shared.refreshState()
                        NoteEditorController.shared.toggleUnderline()
                    }
                }
            } else if command == "meeting-notes-tests" {
                for line in MeetingNotesVerification.run() { appendState(line) }
            } else if command.hasPrefix("notes-format-snap-pid ") {
                let parts = command.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, Int32(parts[1]) == ProcessInfo.processInfo.processIdentifier else { return }
                handle("notes-format-snap " + String(parts[2]))
            } else if command.hasPrefix("notes-format-snap ") {
                // notes-format-snap <dir> — the note body with inline code, a
                // quote and a code block, dark and light, as PNGs. Off screen:
                // no note is opened or written.
                let directory = URL(fileURLWithPath: String(command.dropFirst(18)))
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let sample = "## Deploy\nRun `make build` then check the `dist/` folder, **bold** too.\n"
                    + "> Slack-style quote with `code` inside, long enough to wrap onto a second line of the note body.\n> second quote line\n"
                    + "```\nfunc hello() {\n    print(\"hi\")\n\n}\nlong_unbroken_" + String(repeating: "x", count: 90) + "\n```\n- a list row after"
                    + "\nScreenshot of the bug: ![debug-sample.png](Attachments/debug-sample-000000.png) as a chip"
                for dark in [true, false] {
                    let scroll = ActionTextView.scrollableTextView()
                    let view = scroll.documentView as! ActionTextView
                    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    view.drawsBackground = true
                    view.backgroundColor = dark ? NSColor(white: 0.11, alpha: 1) : .white
                    view.textContainerInset = NSSize(width: 28, height: 16)
                    view.textContainer?.lineFragmentPadding = 0
                    scroll.frame = NSRect(x: 0, y: 0, width: 560, height: 420)
                    view.textStorage!.setAttributedString(NoteMarkdown.attributed(from: sample,
                        textColor: .labelColor, accent: .labelColor, mutedColor: .tertiaryLabelColor))
                    view.applyCodeSpacing()
                    view.layoutManager!.ensureLayout(for: view.textContainer!)
                    view.setSelectedRange(NSRange(location: 0, length: 0))
                    scroll.appearance = view.appearance
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: directory.appendingPathComponent(dark ? "format-dark.png" : "format-light.png"))
                }
                appendState("notes-format-snap: wrote \(directory.path)")
            } else if command == "notes-copy-test" || command == "notes-copy-test general" {
                // Copy a note holding an image chip, the way ⌘C does, onto a
                // private pasteboard: what would another app receive?
                guard let path = (try? FileManager.default.contentsOfDirectory(atPath: AttachmentStore.directory.path))?
                    .first(where: { AttachmentStore.isImage(URL(fileURLWithPath: $0)) })
                    .map({ AttachmentStore.folderName + "/" + $0 }) else {
                    appendState("notes-copy-test: no image in Attachments/"); return
                }
                let scroll = ActionTextView.scrollableTextView()
                let view = scroll.documentView as! ActionTextView
                view.textStorage!.setAttributedString(NoteMarkdown.attributed(
                    from: "- Prima riga \(AttachmentStore.token(for: path)) dopo\n**fine**",
                    textColor: .labelColor, accent: .labelColor, mutedColor: .tertiaryLabelColor))
                view.selectAll(nil)
                let board = command.hasSuffix("general") ? NSPasteboard.general
                    : NSPasteboard(name: NSPasteboard.Name("otto.copy-test"))
                board.clearContents()
                _ = view.writeSelection(to: board, types: view.writablePasteboardTypes)
                let rtfd = board.data(forType: .rtfd).flatMap { NSAttributedString(rtfd: $0, documentAttributes: nil) }
                var embedded = 0
                rtfd?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rtfd?.length ?? 0)) { value, _, _ in
                    if (value as? NSTextAttachment)?.fileWrapper?.regularFileContents != nil { embedded += 1 }
                }
                let html = board.string(forType: .html) ?? ""
                appendState("notes-copy-test: types=\(board.types?.map(\.rawValue) ?? []) rtfdImages=\(embedded) rtfdText=\(rtfd?.string.debugDescription ?? "nil") htmlImg=\(html.contains("src=\"data:image/")) htmlColor=\(html.contains("color: #ffffff")) png=\(board.data(forType: .png)?.count ?? 0) string=\((board.string(forType: .string) ?? "nil").debugDescription) markdown=\((board.string(forType: NoteEditorController.markdownPasteboardType) ?? "nil").debugDescription)")
                if !command.hasSuffix("general") { board.releaseGlobally() }
            } else if command == "notes-editor-tests" {
                let editor = NoteEditorController.shared
                let previousView = editor.textView
                let scroll = ActionTextView.scrollableTextView()
                let view = scroll.documentView as! ActionTextView
                view.allowsUndo = true
                let testWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
                testWindow.contentView = scroll
                editor.textView = view
                defer { editor.textView = previousView; editor.refreshState() }
                var failures = 0
                var checks = 0
                func load(_ markdown: String) {
                    view.textStorage!.setAttributedString(NoteMarkdown.attributed(from: markdown,
                        textColor: .labelColor, accent: .labelColor, mutedColor: .tertiaryLabelColor))
                    view.setSelectedRange(NSRange(location: view.textStorage!.length, length: 0))
                    view.typingAttributes = view.textStorage!.length > 0
                        ? view.textStorage!.attributes(at: view.textStorage!.length - 1, effectiveRange: nil)
                        : [.noteBlock: NoteBlock.body.rawValue, .font: NoteType.font(for: .body)]
                    editor.refreshState()
                }
                func check(_ name: String, _ expected: String) {
                    checks += 1
                    let actual = NoteMarkdown.markdown(from: view.textStorage!)
                    if actual != expected {
                        failures += 1
                        appendState("EDITOR FAIL \(name): \(actual.debugDescription) expected \(expected.debugDescription)")
                    }
                }
                for (source, continued) in [("- prima", "- prima\n- "), ("1. prima", "1. prima\n2. "), ("- [x] fatta", "- [x] fatta\n- [ ] ")] {
                    load(source)
                    _ = editor.handleReturn()
                    check("continue", continued)
                    _ = editor.handleReturn()
                    check("exit", source + "\n")
                    view.insertText("testo", replacementRange: view.selectedRange())
                    check("body after list", source + "\ntesto")
                }
                load("# Titolo")
                _ = editor.handleReturn()
                view.insertText("corpo", replacementRange: view.selectedRange())
                check("heading return", "# Titolo\ncorpo")
                load("riga\n")
                editor.setBlock(.bullet)
                check("format trailing paragraph", "riga\n- ")
                load("")
                editor.setBlock(.bullet)
                view.insertText("👩🏽‍💻 prova", replacementRange: view.selectedRange())
                check("empty list caret UTF16", "- 👩🏽‍💻 prova")
                load("# Titolo")
                editor.setBlock(.body)
                check("heading to body", "Titolo")
                load("**devo mandare il report**\n- [x] fatto")
                let before = NoteMarkdown.markdown(from: view.textStorage!)
                editor.refreshDetections(noteID: UUID())
                check("decorations preserve markdown", before)
                load("- prima")
                view.insertLineBreak(nil)
                view.insertText("continua", replacementRange: view.selectedRange())
                check("soft return", "- prima\u{2028}continua")
                load("- ")
                _ = editor.handleBackspace()
                check("backspace list marker", "")
                load("parola")
                view.undoManager?.removeAllActions()
                view.undoManager?.beginUndoGrouping()
                editor.setBlock(.h1)
                view.undoManager?.endUndoGrouping()
                view.undoManager?.undo()
                check("format undo", "parola")
                view.undoManager?.redo()
                check("format redo", "# parola")
                load((1...9).map { "\($0). riga" }.joined(separator: "\n"))
                _ = editor.handleReturn()
                view.insertText("dieci", replacementRange: view.selectedRange())
                check("numbered caret 9 to 10", (1...9).map { "\($0). riga" }.joined(separator: "\n") + "\n10. dieci")
                // Code and quote (NOTES_RICH_TEXT_FORMATTING_SPEC).
                func select(_ location: Int, _ length: Int) {
                    view.setSelectedRange(NSRange(location: location, length: length))
                    editor.refreshState()
                }
                load("riga")
                select(0, 4)
                editor.toggleQuote()
                check("quote on", "> riga")
                editor.toggleQuote()
                check("quote off", "riga")
                load("uno\n  due")
                select(0, 9)
                editor.toggleCodeBlock()
                check("code block over lines", "```\nuno\n  due\n```")
                select(0, 9)
                editor.toggleQuote()
                check("code block to quote", "> uno\n>   due")
                load("> citata\nnormale")
                select(0, 12)
                editor.toggleQuote()
                check("mixed quote applies to all", "> citata\n> normale")
                load("ciao mondo")
                select(5, 5)
                editor.toggleInlineCode()
                check("inline code on selection", "ciao `mondo`")
                editor.toggleInlineCode()
                check("inline code off", "ciao mondo")
                load("ciao `mondo`")
                select(0, 10)
                editor.toggleInlineCode()
                check("mixed inline code applies to all", "`ciao mondo`")
                load("a `b` c")
                select(0, 5)
                editor.toggleBold()
                check("bold skips code", "**a** `b` **c**")
                load("- punto")
                select(0, (view.textStorage!.string as NSString).length)
                editor.toggleInlineCode()
                check("inline code skips list marker", "- `punto`")
                load("ciao")
                view.undoManager?.removeAllActions()
                select(0, 4)
                view.undoManager?.beginUndoGrouping()
                editor.toggleCodeBlock()
                view.undoManager?.endUndoGrouping()
                view.undoManager?.undo()
                check("code block undo", "ciao")
                if view.selectedRange() != NSRange(location: 0, length: 4) {
                    failures += 1
                    appendState("EDITOR FAIL code block undo selection: \(view.selectedRange())")
                }
                view.undoManager?.redo()
                check("code block redo", "```\nciao\n```")
                load("> q")
                _ = editor.handleReturn()
                view.insertNewline(nil)
                editor.refreshState()
                _ = editor.handleReturn()
                check("return on empty quote line leaves", "> q\n")
                load("```\nc\n```")
                view.insertNewline(nil)
                editor.refreshState()
                _ = editor.handleReturn()
                view.insertText("fuori", replacementRange: view.selectedRange())
                check("return on empty last code line leaves", "```\nc\n```\nfuori")
                load("> q")
                select(0, 0)
                _ = editor.handleBackspace()
                check("backspace at quote start", "q")
                load("")
                editor.paste(markdown: "> q `x`\n```\n  c\n```")
                check("paste keeps blocks", "> q `x`\n```\n  c\n```")
                load("abc")
                select(1, 0)
                editor.paste(markdown: "> `q`")
                check("paste mid-line joins the line", "a`q`bc")
                appendState("editor-tests: \(checks - failures)/\(checks) passed")
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
                    // Nesting, and the trailing blank line — the two things
                    // the round-trip did not cover when it was written.
                    "- padre\n  - figlio\n  - figlio due\n- padre due",
                    "1. uno\n  1. uno a\n  2. uno b\n2. due",
                    "- a\n  - b\n    - c\n      - d",
                    "- [ ] compito\n  - [ ] sotto\n  - [x] sotto fatto",
                    "- **grassetto**\n  - *corsivo* annidato",
                    "riga finale seguita da una vuota\n",
                    "\n",
                    "1. a\n2. b\n- un punto interrompe\n1. riparte",
                    "corpo\n  rientrato a mano, non un elenco\ncorpo di nuovo",
                    "> citazione",
                    "> uno\n> due\ncorpo",
                    "> con `code` dentro e **grassetto**",
                    // Image chips (2026-09-27): alone, mid-sentence, in a list,
                    // next to emphasis, and a file name holding * and _.
                    "![shot.png](Attachments/shot-3f2a9c.png)",
                    "prima ![a.png](Attachments/a-111111.png) e dopo **grassetto**",
                    "- punto con ![b.jpg](Attachments/b-222222.jpg)",
                    "![x_y*z.png](Attachments/x_y*z-333333.png) ![c.png](Attachments/c-444444.png)",
                    "`![non è un chip](Attachments/code.png)` resta codice",
                    "> a\n>\n> b",
                    "codice `inline` qui",
                    "```\n  indentato\n\tcon tab\n\nriga lunghissima_senza_spazi_" + String(repeating: "x", count: 200) + "\n```",
                    "```\nc\n```\n> q",
                    "\\> non una citazione",
                    "backtick letterale \\` qui",
                    "> 👩🏽‍💻 ciao · «virgolette» — ok",
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
            } else if command == "actions-status" {
                let editor = NoteEditorController.shared
                let notes = NotesStore.shared
                var report = "actions detected=\(editor.detectedCount)"
                report += " picker=" + (editor.pickerTarget?.phrase ?? "nil")
                if let noteID = notes.openNoteID, let view = editor.textView,
                   let storage = view.textStorage {
                    let full = NSRange(location: 0, length: storage.length)
                    var spans: [String] = []
                    storage.enumerateAttribute(.noteAction, in: full, options: []) { v, r, _ in
                        if let phrase = v as? String {
                            let linked = TodoStore.shared.todo(forNote: noteID, phrase: phrase)
                            spans.append("'\(phrase)'" + (linked == nil ? "" :
                                (linked!.isCompleted ? "[done]" : "[linked]")))
                        }
                        _ = r
                    }
                    report += " spans=[" + spans.joined(separator: " ") + "]"
                    // Automatic action hints must never reach Markdown. An
                    // explicit underline made by the user is real formatting
                    // and is expected to serialize as <u>.
                    report += " markdownHasU=\(NoteMarkdown.markdown(from: storage).contains("<u>"))"
                    report += " dismissed=\(notes.dismissed(in: noteID).count)"
                }
                appendState(report)
            } else if command.hasPrefix("actions-detect ") {
                let text = String(command.dropFirst(15))
                let found = ActionItemDetector.detect(in: text)
                appendState("actions-detect n=\(found.count) phrases=["
                            + found.map { "'\($0.phrase)'" }.joined(separator: " ") + "]")
            } else if command == "actions-file" {
                // File the first underlined span into the first offered
                // section — the picker's own path, without the pointer.
                let editor = NoteEditorController.shared
                guard let noteID = NotesStore.shared.openNoteID,
                      let storage = editor.textView?.textStorage,
                      let section = TodoStore.shared.pickerSections().first else { return }
                let full = NSRange(location: 0, length: storage.length)
                var phrase: String?
                storage.enumerateAttribute(.noteAction, in: full, options: []) { v, _, stop in
                    if let p = v as? String { phrase = p; stop.pointee = true }
                }
                if let phrase {
                    NotesStore.shared.createTodo(from: phrase, in: section.id, note: noteID)
                }
            } else if command == "actions-verification-file" {
                // File the synthetic verification note's action and remember
                // the exact created ID, so cleanup can never touch user data.
                guard let noteID = verificationNoteID,
                      NotesStore.shared.openNoteID == noteID,
                      let phrase = NoteEditorController.shared.pickerTarget?.phrase,
                      let section = TodoStore.shared.pickerSections().first else { return }
                NotesStore.shared.createTodo(from: phrase, in: section.id, note: noteID)
                verificationTodoID = TodoStore.shared.todo(forNote: noteID, phrase: phrase)?.id
                appendState("actions-filed=\(verificationTodoID != nil) linked=\(TodoStore.shared.todo(forNote: noteID, phrase: phrase) != nil)")
            } else if command == "actions-verification-delete" {
                if let id = verificationTodoID {
                    TodoStore.shared.delete(id)
                    verificationTodoID = nil
                }
            } else if command == "actions-complete" {
                // Tick the linked to-do from the LIST side, to prove the note
                // follows.
                let store = TodoStore.shared
                if let item = store.items.first(where: { $0.sourceNoteID != nil && !$0.isCompleted }) {
                    store.toggleComplete(item.id)
                }
            } else if command == "actions-refresh" {
                if let id = NotesStore.shared.openNoteID {
                    NoteEditorController.shared.refreshDetections(noteID: id)
                }
            } else if command.hasPrefix("draft-height ") {
                // The field's height is computed from a WIDTH. Report both, so
                // "it wraps wrong" is a number rather than an impression.
                let text = String(command.dropFirst(13))
                TodoStore.shared.draftTitle = text
                let panelWidth = CGFloat(NotchController.shared.expandedWidth)
                let estimate = max(120, panelWidth - CGFloat(DSSpacing.panelPadding) * 2 - 20 - 24 - 112)
                func height(at width: CGFloat) -> CGFloat {
                    let measured = NSAttributedString(
                        string: text.isEmpty ? " " : text,
                        attributes: [.font: NSFont.systemFont(ofSize: DSFont.todoTitleSize)]
                    ).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading]).height
                    return max(HighlightingTitleField.lineHeight,
                               min(ceil(measured), HighlightingTitleField.maxHeight))
                }
                var report = "draft-height chars=\(text.count) panelWidth=\(Int(panelWidth))"
                report += " estimate=\(Int(estimate)) hEstimate=\(Int(height(at: estimate)))"
                report += " cap=\(Int(HighlightingTitleField.maxHeight))"
                appendState(report)
            } else if command == "space-anchor" {
                var report = "space-anchor " + SpaceAnchor.debugDescription
                if let panel = NotchController.shared.panelForDebug {
                    let pinned = SpaceAnchor.pin(panel)
                    report += " windowNumber=\(panel.windowNumber) pinned=\(pinned)"
                    report += " level=\(panel.level.rawValue)"
                    report += " joinsAll=\(panel.collectionBehavior.contains(.canJoinAllSpaces))"
                } else {
                    report += " (nessun pannello)"
                }
                appendState(report)
            } else if command == "menu-open" {
                TodoStore.shared.openAvatarMenu()
            } else if command == "menu-close" {
                TodoStore.shared.closeAvatarMenu()
            } else if command.hasPrefix("menu-move ") {
                let store = TodoStore.shared
                let rows = AvatarMenu.rows(store: store)
                store.moveAvatarMenuHighlight(Int(command.dropFirst(10)) ?? 1, count: rows.count)
            } else if command == "menu-status" {
                let store = TodoStore.shared
                let rows = AvatarMenu.rows(store: store)
                let spark = CompletionStats.dailyCounts(section: nil, days: 7, store: store,
                                                        archive: CompletedArchive.shared)
                var report = "menu open=\(store.showsAvatarMenu)"
                report += " overflow=\(NotchController.shared.overflowMenuRect.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "nil")"
                report += " shape=\(NotchController.shared.visibleShapeScreenRect().integral)"
                report += " card=\(NotchController.shared.containerCardRect.map { "\($0.integral)" } ?? "nil")"
                report += " highlight=\(store.avatarMenuHighlight)"
                report += " rows=[" + rows.map { $0.label }.joined(separator: "|") + "]"
                report += " folder=" + (rows.first { $0.id == .notesFolder }?.detail ?? "-")
                report += " spark=\(spark) sparkShown=\(spark.contains { $0 > 0 })"
                appendState(report)
            } else if command == "insights-status" {
                let store = TodoStore.shared
                let archive = CompletedArchive.shared
                archive.reload()
                let week = CompletionStats.week(containing: InsightsState.shared.anchor,
                                                store: store, archive: archive)
                let behind = CompletionStats.leftBehind(store: store)
                let weeks = CompletionStats.weeksOfHistory(store: store, archive: archive)
                let split = CompletionStats.splitBySpace(in: week, store: store)
                let spark = CompletionStats.dailyCounts(section: nil, days: 7,
                                                        store: store, archive: archive)
                var report = "insights mode=\(store.panelMode) label=\(InsightsState.shared.weekLabel)"
                report += " week=\(week.count) behind=\(behind.count) weeksOfHistory=\(weeks)"
                report += " grid=\(weeks >= 8) spark=\(spark)"
                report += " split=[" + split.prefix(4).map { "\($0.name):\($0.count)" }
                    .joined(separator: " ") + "]"
                report += " focus=\(store.insightsFocusedItemID != nil)"
                appendState(report)
            } else if command == "insights-enter" {
                TodoStore.shared.enterInsights()
            } else if command == "insights-leave" {
                TodoStore.shared.leaveInsights()
            } else if command.hasPrefix("insights-week ") {
                InsightsState.shared.step(Int(command.dropFirst(14)) ?? -1)
            } else if command.hasPrefix("insights-focus ") {
                let store = TodoStore.shared
                let ids = CompletionStats.leftBehind(store: store).map(\.id)
                store.moveInsightsFocus(Int(command.dropFirst(15)) ?? 1, in: ids)
            } else if command == "completed-days" {
                let store = TodoStore.shared
                let archive = CompletedArchive.shared
                archive.reload()
                let scoped = store.activeCollection?.isSystemToday == true
                    ? nil : store.activeCollection?.name
                let days = CompletionStats.days(section: scoped, store: store, archive: archive)
                var report = "completed-days section=" + (scoped ?? "ALL")
                report += " days=\(days.count) total=\(days.reduce(0) { $0 + $1.count })"
                report += " open=\(store.expandedCompletedDays.count)"
                report += " rows=[" + days.prefix(4).map { day in
                    "\(CompletedDayRowLabelProbe.label(for: day.day)):\(day.count)"
                }.joined(separator: " ") + "]"
                appendState(report)
            } else if command == "archive-status" {
                let a = CompletedArchive.shared
                a.reload()
                let collection = TodoStore.shared.activeCollection
                let live = TodoStore.shared.completedItems(in: collection ?? TodoStore.shared.collections[0])
                let liveIDs = Set(live.map {
                    CompletedArchive.identity(title: $0.title, at: $0.completedAt ?? .distantPast)
                })
                let scoped = (collection?.isSystemToday ?? false) ? nil : collection?.name
                let days = a.history(section: scoped, excluding: liveIDs)
                let shown: Int = days.reduce(0) { $0 + $1.entries.count }
                let sample: [String] = (days.first?.entries.prefix(3) ?? []).map { entry in
                    let section: String = entry.sectionName ?? "-"
                    return "'" + entry.title + "'@" + section
                }
                var report = "archive entries=\(a.entries.count) live=\(live.count)"
                report += " section=" + (scoped ?? "ALL")
                report += " days=\(days.count) shown=\(shown)"
                report += " first=[" + sample.joined(separator: " ") + "]"
                appendState(report)
            } else if command == "notes-body" {
                // What the EDITOR is holding, not what the store thinks. The
                // two came apart once — the text view was built from an empty
                // string and then refused to reload — and the only way to see
                // that without pixels is to ask the view itself.
                let view = NoteEditorController.shared.textView
                let held = view.flatMap { $0.textStorage.map(NoteMarkdown.markdown(from:)) }
                let stored = NotesStore.shared.openNote?.content
                appendState("notes-body view=\(view == nil ? "nil" : "yes") "
                            + "shown=\(held?.debugDescription ?? "nil") "
                            + "stored=\(stored?.debugDescription ?? "nil") "
                            + "match=\(held == stored)")
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
        draftFocused=\(store.draftFocused) draftWantsFocus=\(store.draftWantsFocus) \
        dest=\(store.draftDestination?.name ?? "nil") \
        draft='\(store.draftTitle)' \
        layout=\(app.notchLayout) \
        todoContentHeight=\(app.todoContentHeight) \
        panelColumnHeight=\(app.panelColumnHeight) \
        notchExtraHeight=\(app.notchExtraHeight) \
        chromeDraftBlock=\(PanelChrome.shared.draftBlock) \
        chromeTabRow=\(PanelChrome.shared.tabRow)
        """)
    }

    static func note(_ text: String) { appendState(text) }

    /// The SwiftUI hosting view inside the notch panel — hosting-view
    /// coordinates are what `.global` frames are measured in.
    @MainActor
    private static func hostingView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("HostingView") { return view }
        for sub in view.subviews { if let found = hostingView(in: sub) { return found } }
        return nil
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

/// Day labels for the debug probe. The view's own formatter is private to it,
/// and a probe that formats dates its own way would report something the panel
/// never shows.
@MainActor
enum CompletedDayRowLabelProbe {
    static func label(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day)     { return "today" }
        if calendar.isDateInYesterday(day) { return "yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd"
        return f.string(from: day)
    }
}
#endif
