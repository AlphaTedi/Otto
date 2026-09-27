import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - FeedbackWindow — "Send feedback", Raycast-style (docs/TELEMETRY.md §5)
//
// A small window of its own, opened from the gear menu. Marcello chose this
// over an in-panel mode (2026-09-27): it departs from principle 1 on purpose,
// the way Raycast's and Slack's feedback forms do.
//
// Nothing is uploaded. "Send" hands the message and its attachments to the
// user's mail app, addressed to OTTO_FEEDBACK_EMAIL; the files never touch a
// server. The only thing the telemetry learns — and only with consent — is
// that a feedback of some category was sent.

@MainActor
final class FeedbackWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: FeedbackWindowController?

    /// Where feedback is addressed. Blank hides "Send feedback" entirely.
    static let recipient: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "OttoFeedbackEmail") as? String ?? ""
        return value.contains("$(") ? "" : value.trimmingCharacters(in: .whitespaces)
    }()

    static var isAvailable: Bool { !recipient.isEmpty }

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
    @State private var notice: String?
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
            diagnosticsRow
            if let notice {
                Text(notice).font(.system(size: 11.5)).foregroundStyle(.orange)
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
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 30))
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
                Button { browse() } label: { Image(systemName: "plus") }
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
                            Image(systemName: "doc").foregroundStyle(.secondary)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
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
                        Image(systemName: showsDiagnostics ? "chevron.up" : "chevron.down").font(.system(size: 10))
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
                    Text(L10n.t("feedback.send") + "  \u{2318}\u{21A9}")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
            Text(L10n.t("feedback.viaMail")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
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
        guard canSend else { return }
        let recipient = FeedbackWindowController.recipient
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnostics { body += "\n\n—\n" + Self.diagnosticsText() }
        let subject = "Otto feedback · " + L10n.t("feedback.cat.\(category.rawValue)")
        let items: [Any] = [body as NSString] + files.map { $0 as NSURL }

        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) {
            service.recipients = [recipient]
            service.subject = subject
            service.perform(withItems: items)
            Analytics.track(.feedbackSent(category, attachments: files.count, diagnostics: diagnostics))
            close()
        } else {
            // No mail account: the words at least are not lost.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(subject + "\n\n" + body, forType: .string)
            notice = String(format: L10n.t("feedback.noMail"), recipient)
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
