import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - FeedbackWindow — "Send feedback", Raycast-style (docs/TELEMETRY.md §5)
//
// A small window of its own, opened from the gear menu. Marcello chose this
// over an in-panel mode (2026-09-27): it departs from principle 1 on purpose,
// the way Raycast's and Slack's feedback forms do.
//
// "Send" posts the message straight to Otto's Worker, which relays it to
// Marcello's inbox by email (Resend) and keeps nothing — no table holds it.
// No mail app is involved: the user presses Send and it is sent. Offline, it
// waits in `FeedbackOutbox` and goes when the network is back. With consent,
// the telemetry also counts that a feedback of some category was sent — never
// its words.

@MainActor
final class FeedbackWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: FeedbackWindowController?

    /// Needs the service: without OTTO_SERVICE_HOST there is nowhere to send.
    static var isAvailable: Bool { Analytics.serviceURL != nil }

    static func show() {
        if shared == nil { shared = FeedbackWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        shared?.showWindow(nil)
        shared?.window?.center()
        shared?.window?.makeKeyAndOrderFront(nil)
        Analytics.track(.feedbackOpened)
    }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L10n.t("feedback.title")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: FeedbackForm { [weak self] in self?.close() })
        host.sizingOptions = [.preferredContentSize]
        window.contentView = host
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in FeedbackWindowController.shared = nil }
    }
}

// MARK: The form

private struct FeedbackForm: View {
    let close: () -> Void

    @State private var category: AnalyticsEvent.FeedbackCategory = .bug
    @State private var text = ""
    @State private var files: [URL] = []
    @State private var diagnostics = true
    @State private var showsDiagnostics = false
    @State private var dropTargeted = false
    @State private var email = ""
    @State private var notice: String?
    @State private var sending = false
    @State private var sent = false
    @FocusState private var textFocused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            field(L10n.t("feedback.category")) {
                Picker("", selection: $category) {
                    ForEach(AnalyticsEvent.FeedbackCategory.allCases, id: \.self) { item in
                        Text(L10n.t("feedback.cat.\(item.rawValue)")).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            field(L10n.t("feedback.description")) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(L10n.t("feedback.placeholder.\(category.rawValue)"))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .focused($textFocused)
                        .padding(.vertical, 8)
                        .onChange(of: text) { if $0.count > 5000 { text = String($0.prefix(5000)) } }
                }
                .frame(height: 120)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(textFocused ? 0.25 : 0.1), lineWidth: 1))
                Text(L10n.t("feedback.required"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            attachments
            field(L10n.t("feedback.email")) {
                TextField(L10n.t("feedback.emailPlaceholder"), text: $email)
                    .textFieldStyle(.roundedBorder)
            }
            diagnosticsRow
            if let notice {
                Text(notice).font(.system(size: 11.5)).foregroundStyle(sent ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .frame(width: 460)
        .onAppear { DispatchQueue.main.async { textFocused = true } }
        // Esc cancels, from anywhere in the form (keyboard-first).
        .background(Button("", action: close).keyboardShortcut(.cancelAction).opacity(0))
    }

    private var header: some View {
        VStack(spacing: 8) {
            OttoIcon("exclamationmark.bubble.fill", pointSize: 30)
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(L10n.t("feedback.title")).font(.system(size: 20, weight: .bold))
            Text(L10n.t("feedback.subtitle"))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t("feedback.attach")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { browse() } label: { OttoIcon("plus") }
                    .disabled(files.count >= 5)
                    .help(L10n.t("feedback.drop"))
            }
            VStack(spacing: 4) {
                if files.isEmpty {
                    Text(L10n.t("feedback.drop")).font(.system(size: 12.5, weight: .medium))
                    Text(L10n.t("feedback.dropHint")).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(files, id: \.self) { url in
                        HStack(spacing: 6) {
                            OttoIcon("doc").foregroundStyle(.secondary)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { files.removeAll { $0 == url } } label: { OttoIcon("xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(dropTargeted ? 0.4 : 0.15),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
            .onTapGesture { if files.isEmpty { browse() } }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in add(url) }
                    }
                }
                return true
            }
        }
    }

    private var diagnosticsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $diagnostics) {
                HStack(spacing: 6) {
                    Text(L10n.t("feedback.diagnostics")).font(.system(size: 13))
                    Button { showsDiagnostics.toggle() } label: {
                        OttoIcon(showsDiagnostics ? "chevron.up" : "chevron.down", pointSize: 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if showsDiagnostics {
                // Exactly what the email will carry — nothing more.
                Text(Self.diagnosticsText())
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 12) {
                Spacer()
                Button(L10n.t("feedback.cancel"), action: close)
                Button(action: send) {
                    HStack(spacing: 6) {
                        if sending { ProgressView().controlSize(.small) }
                        Text(L10n.t("feedback.send") + "  \u{2318}\u{21A9}")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSend || sending || sent)
            }
            Text(L10n.t("feedback.privacyNote")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
    }

    // MARK: Actions

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .pdf, .text, .plainText]
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(add)
    }

    private func add(_ url: URL) {
        guard files.count < 5, !files.contains(url) else { return }
        files.append(url)
    }

    private func send() {
        guard canSend, !sending else { return }
        var attachments: [FeedbackOutbox.Attachment] = []
        var total = 0
        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            total += data.count
            attachments.append(.init(filename: url.lastPathComponent, content: data.base64EncodedString()))
        }
        // The Worker's limit, checked here so the user hears it now, not later.
        guard total <= 10 * 1024 * 1024 else { notice = L10n.t("feedback.tooLarge"); return }

        let message = FeedbackOutbox.Message(
            category: category.rawValue,
            body: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(5000)),
            email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
            diagnostics: diagnostics ? Self.diagnosticsText() : nil,
            // Only when usage data is shared, so a report can be matched to
            // what that install did.
            install_id: Analytics.consent == .granted ? Analytics.installID : nil,
            attachments: attachments)
        Analytics.track(.feedbackSent(category, attachments: files.count, diagnostics: diagnostics))
        sending = true
        notice = nil
        FeedbackOutbox.shared.send(message) { delivered in
            sending = false
            sent = true
            notice = L10n.t(delivered ? "feedback.sent" : "feedback.queued")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { close() }
        }
    }

    static func diagnosticsText() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return [
            "Otto \(Analytics.appVersion) (\(build))",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "Layout: \(AppState.shared.notchLayout.rawValue)",
            "Language: \(Locale.current.language.languageCode?.identifier ?? "?")",
            "Calendar: \(CalendarStore.shared.isConnected ? "connected" : "not connected")",
        ].joined(separator: "\n")
    }
}

// MARK: - FeedbackOutbox — nothing written is lost offline

/// Each unsent message is one JSON file in Application Support, tried again
/// at launch and every few minutes until the Worker takes it.
@MainActor
final class FeedbackOutbox {
    static let shared = FeedbackOutbox()

    struct Attachment: Codable { let filename: String; let content: String }
    struct Message: Codable {
        let category: String
        let body: String
        let email: String?
        let diagnostics: String?
        let install_id: String?
        let attachments: [Attachment]
    }

    private var timer: Timer?

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBuild.supportRoot, isDirectory: true)
            .appendingPathComponent("feedback-outbox", isDirectory: true)
    }

    /// Posts at once; on failure keeps it for later. `done(true)` = delivered.
    func send(_ message: Message, done: @escaping @MainActor (Bool) -> Void) {
        post(message) { [weak self] delivered in
            if !delivered { self?.store(message) }
            done(delivered)
        }
    }

    /// Launch, and every five minutes while something is waiting.
    func retryPending() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let pending = files.filter { $0.pathExtension == "json" }
        guard !pending.isEmpty else { timer?.invalidate(); timer = nil; return }
        scheduleRetry()
        for file in pending {
            guard let data = try? Data(contentsOf: file),
                  let message = try? JSONDecoder().decode(Message.self, from: data) else {
                try? FileManager.default.removeItem(at: file); continue
            }
            post(message) { delivered in
                if delivered { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    private func store(_ message: Message) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".json")
        try? JSONEncoder().encode(message).write(to: file, options: .atomic)
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { FeedbackOutbox.shared.retryPending() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func post(_ message: Message, done: @escaping @MainActor (Bool) -> Void) {
        guard let base = Analytics.serviceURL, let body = try? JSONEncoder().encode(message) else {
            done(false); return
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/feedback"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Analytics.serviceKey, forHTTPHeaderField: "X-Otto-Key")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 400/413 will never succeed on a retry: count them as done.
            let final = (200..<300).contains(status) || status == 400 || status == 413
            Task { @MainActor in done(final) }
        }.resume()
    }
}

#if DEBUG
extension FeedbackWindowController {
    /// DebugDriver `feedback-snap-pid`: the form, dark and light, as PNGs.
    static func debugSnapshot(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let host = NSHostingView(rootView: FeedbackForm(close: {})
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.12, alpha: 1) : .windowBackgroundColor
            window.contentView = host
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("feedback-\(name).png"))
            }
            window.orderOut(nil)
        }
    }
}
#endif
