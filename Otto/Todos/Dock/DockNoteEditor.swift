import SwiftUI

// MARK: - The note editor in the B3 dock (final flow §4.11, screen 12)
//
// No top navigation: the bordered header card (back, title, Saved, ⌘[) is
// gone. The note opens on a quiet meta line and its title, set in the content
// like a document; the controls live in the bar at the foot, in the same grid
// as everywhere else — back where the Notes button stands, so the control
// that brought you in never moves, the formatting tools centred, export on
// the right.

/// The title, then the day — nothing else (Marcello, 2026-10-18: "Note ·
/// date · words … Saved" over the title read busy). Saving is silent; only a
/// FAILED save says so, beside the date, because that one needs you.
struct DockNoteHeader: View {
    let note: QuickNote
    @Binding var title: String
    @FocusState.Binding var titleFocused: Bool
    let onCommit: () -> Void
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DSDock.editorTitle)
                .tracking(-0.4)
                .foregroundStyle(DSDock.textStrong)
                .lineLimit(1...3)
                .focused($titleFocused)
                .onSubmit { onCommit(); store.focusBody() }
                .onChange(of: titleFocused) { if !$0 { onCommit() } }

            HStack(spacing: 8) {
                Text(note.createdAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .foregroundStyle(DSDock.text3)
                if store.saveError != nil {
                    Text(L10n.t("meeting.saveFailed"))
                        .foregroundStyle(Color(hex: "#FF6961"))
                }
            }
            .font(DSDock.noteDate)
            .lineLimit(1)
        }
        .padding(.horizontal, NotchContainerMetrics.contentInFrame)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// Back · the formatting tools · export.
struct DockEditorBar: View {
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        HStack(alignment: .center, spacing: NotchContainerMetrics.barGap) {
            // Grey like every round button (Insights' Back included), and no
            // shortcut in its tooltip: only the tools show theirs
            // (Marcello, 2026-10-18). ⌘[ still goes back.
            DockRoundButton(label: L10n.t("dock.back"), iconColor: DSDock.settingsIcon) {
                DockIcon(.back, size: NotchContainerMetrics.roundIcon + 2)
            } action: {
                TodoStore.shared.goBack()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NoteFormatBar(docked: true)

            DockRoundButton(label: L10n.t("dock.export"), iconColor: DSDock.settingsIcon) {
                DockIcon(.export, size: NotchContainerMetrics.roundIcon + 2)
            } action: {
                store.exportOpenNote()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
