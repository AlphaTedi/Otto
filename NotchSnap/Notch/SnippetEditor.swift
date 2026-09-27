import AppKit
import SwiftUI

// MARK: - NewSnippetTile — "+" affordance at the end of the Snippets section

struct NewSnippetTile: View {
    @State private var hover = false

    var body: some View {
        Button {
            SnippetEditorController.shared.show(editing: nil)
        } label: {
            VStack(spacing: 6) {
                OttoIcon("plus", pointSize: 16)
                Text(L10n.t("snippet.new"))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.white.opacity(hover ? 0.9 : 0.55))
            .frame(width: 76, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(hover ? 0.4 : 0.2),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(hover ? 0.06 : 0.02))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - SnippetEditorController — compact floating editor panel

@MainActor
final class SnippetEditorController {
    static let shared = SnippetEditorController()
    private var panel: NSPanel?

    /// Pass nil to create a new snippet, or an existing snippet to edit it.
    func show(editing snippet: ClipboardItem?) {
        close()

        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 380, height: 300)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width, height: size.height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: SnippetEditorView(
            editingID: snippet?.id,
            initialLabel: snippet?.label ?? "",
            initialContent: snippet?.previewText ?? "",
            onDone: { [weak self] in self?.close() }
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - SnippetEditorView

private struct SnippetEditorView: View {
    let editingID: UUID?
    @State var initialLabel: String
    @State var initialContent: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editingID == nil ? L10n.t("snippet.newTitle") : L10n.t("snippet.editTitle"))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)

            TextField(L10n.t("snippet.labelPlaceholder"), text: $initialLabel)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $initialContent)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .frame(minHeight: 120)

            HStack {
                Spacer()
                Button(L10n.t("snippet.cancel")) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(editingID == nil ? L10n.t("snippet.create") : L10n.t("snippet.saveButton")) {
                    let label = initialLabel.trimmingCharacters(in: .whitespaces)
                    let content = initialContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return }
                    if let id = editingID {
                        AppState.shared.updateSnippet(
                            id: id,
                            label: label.isEmpty ? "Snippet" : label,
                            content: content
                        )
                    } else {
                        AppState.shared.addSnippet(
                            label: label.isEmpty ? "Snippet" : label,
                            content: content
                        )
                    }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(initialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 16)
        .background(FrostedGlassBackground().ignoresSafeArea())
    }
}
