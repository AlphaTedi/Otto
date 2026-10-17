import SwiftUI

// MARK: - The note editor in the B3 dock (final flow §4.11, screen 12)
//
// No top navigation: the bordered header card (back, title, Saved, ⌘[) is
// gone. The note opens on a quiet meta line and its title, set in the content
// like a document; the controls live in the bar at the foot, in the same grid
// as everywhere else — back where the Notes button stands, so the control
// that brought you in never moves, the formatting tools centred, export on
// the right.

/// "Note · Oct 12 · 48 words" … "Saved", then the title.
struct DockNoteHeader: View {
    let note: QuickNote
    @Binding var title: String
    @FocusState.Binding var titleFocused: Bool
    let onCommit: () -> Void
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text([L10n.t("dock.noteMeta"),
                      note.updatedAt.formatted(.dateTime.month(.abbreviated).day()),
                      String(format: L10n.t("dock.words"), note.wordCount)]
                    .joined(separator: "  \u{00B7}  "))
                Spacer(minLength: 12)
                Text(store.saveError != nil ? L10n.t("meeting.saveFailed")
                     : (store.isWriting ? L10n.t("notes.saving") : L10n.t("notes.saved")))
            }
            .font(DSDock.quietLabel)
            .foregroundStyle(DSDock.text3)
            .lineLimit(1)

            TextField("", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DSDock.editorTitle)
                .tracking(-0.3)
                .foregroundStyle(DSDock.textStrong)
                .lineLimit(1...3)
                .focused($titleFocused)
                .onSubmit { onCommit(); store.focusBody() }
                .onChange(of: titleFocused) { if !$0 { onCommit() } }
        }
        .padding(.horizontal, NotchContainerMetrics.contentInFrame)
        .padding(.top, 2)
    }
}

/// Back · the formatting tools · export.
struct DockEditorBar: View {
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        HStack(alignment: .center, spacing: NotchContainerMetrics.barGap) {
            DockRoundButton(label: L10n.t("dock.back"), shortcut: "\u{2318}[",
                            iconColor: DSDock.notes) {
                DockIcon(.back, size: NotchContainerMetrics.roundIcon + 2)
            } action: {
                TodoStore.shared.goBack()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NoteFormatBar(docked: true)

            DockRoundButton(label: L10n.t("dock.export"), shortcut: "\u{2318}\u{21E7}S",
                            iconColor: DSDock.settingsIcon) {
                DockIcon(.export, size: NotchContainerMetrics.roundIcon + 2)
            } action: {
                store.exportOpenNote()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
