import AppKit
import SwiftUI

// MARK: - Shared floating-panel helper for the small to-do dialogs

/// Borderless panels can't become key by default — type-ahead fields need it.
final class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private func presentPanel<Content: View>(
    size: NSSize,
    store: inout NSPanel?,
    @ViewBuilder content: () -> Content
) {
    store?.orderOut(nil)
    guard let screen = NSScreen.main else { return }
    let frame = NSRect(
        x: screen.frame.midX - size.width / 2,
        y: screen.frame.midY - size.height / 2 + 60,
        width: size.width, height: size.height
    )
    let panel = QuickEntryPanel(
        contentRect: frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false
    )
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true

    let host = NSHostingView(rootView: content())
    host.frame = NSRect(origin: .zero, size: size)
    host.autoresizingMask = [.width, .height]
    host.wantsLayer = true
    host.layer?.cornerRadius = 14
    host.layer?.cornerCurve = .continuous
    host.layer?.masksToBounds = true
    panel.contentView = host

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    store = panel
}

// MARK: - TodoMovePicker — KB-9, ⇧⌘M type-ahead reassignment

@MainActor
final class TodoMovePicker {
    static let shared = TodoMovePicker()
    private var panel: NSPanel?

    func show(itemID: UUID) {
        presentPanel(size: NSSize(width: 320, height: 260), store: &panel) {
            MovePickerView(itemID: itemID) { [weak self] in self?.close() }
        }
    }

    /// ⇧⌘M with no explicit item: operate on the focused row.
    func showForFocusedItem() {
        guard let id = TodoStore.shared.focusedItemID else { return }
        show(itemID: id)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct MovePickerView: View {
    @ObservedObject private var store = TodoStore.shared
    let itemID: UUID
    let onDone: () -> Void

    @State private var query = ""
    @FocusState private var queryFocused: Bool

    /// Type-ahead beats scrolling (Things 3's Move dialog).
    private var matches: [TodoCollection] {
        let assignable = store.collections.filter { !$0.isSystemToday }
        guard !query.isEmpty else { return assignable }
        return assignable.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("todo.moveTo").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(DSColor.textFaint)

            TextField(L10n.t("todo.searchCollections"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(DSColor.textPrimary)
                .focused($queryFocused)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DSColor.fieldBackground)
                )
                .onSubmit { commit(matches.first) }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { c in
                        Button { commit(c) } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(c.color)
                                    .frame(width: 12, height: 12)
                                Text(c.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(DSColor.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FrostedGlassBackground().ignoresSafeArea())
        .onExitCommand { onDone() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { queryFocused = true }
        }
    }

    private func commit(_ collection: TodoCollection?) {
        guard let collection else { return }
        store.move(itemID, toCollection: collection.id)
        onDone()
    }
}
