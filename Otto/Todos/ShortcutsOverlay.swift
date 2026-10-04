import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ShortcutsOverlay — in-panel `?` reference (§2.3)

struct ShortcutsOverlay: View {
    private let rows: [(String, String)] = [
        ("\u{2191} \u{2193}", "todo.sc.moveFocus"),
        ("\u{2423}", "todo.sc.toggleComplete"),
        ("\u{2318}\u{21A9}", "todo.sc.completeOrJoin"),
        ("\u{21A9}", "todo.sc.editTitle"),
        ("\u{2192} \u{2190}", "todo.sc.expandRow"),
        ("\u{2318}N", "todo.sc.newTodo"),
        ("\u{2318}\u{21E7}I", "todo.sc.addImage"),
        ("Esc", "todo.sc.clearDraft"),
        ("\u{21E5}", "todo.switchSection"),
        ("\u{2318}1\u{2013}9 / \u{2318}", "todo.sc.switchCollection"),
        ("\u{2325}\u{2191}\u{2193}", "todo.sc.reorder"),
        ("\u{21E7}\u{2318}M", "todo.sc.moveItem"),
        ("\u{2325}\u{2318}N", "todo.sc.quickEntry"),
        ("\u{2303}\u{21E7}E", "todo.sc.notes"),
        ("\u{2318}B / I / U", "todo.sc.format"),
        ("\u{2318}\u{21E7}C", "notes.sc.inlineCode"),
        ("\u{2318}\u{2325}\u{21E7}C", "notes.sc.codeBlock"),
        ("\u{2318}'", "notes.sc.quote"),
        ("\u{2318}1 \u{2318}2", "notes.sc.kind"),
        ("\u{21E7}\u{2318}C", "todo.sc.toggleCompleted"),
        ("\u{21E5} / \u{21E7}\u{21E5}", "todo.sc.nestList"),
        ("\u{2318}I", "todo.sc.insights"),
        ("\u{21E7}\u{2318}A", "todo.sc.toggleAllDays"),
        ("\u{2318},", "todo.sc.preferences"),
        ("\u{2318}Q", "todo.sc.quit"),
        ("\u{2325}\u{21A9}", "notes.sc.actionPicker"),
        ("\u{21E7}\u{2318}N", "todo.sc.newSection"),
        ("1–3 / ↑↓ / ↩ / Esc", "notes.sc.pickerKeys"),
        ("⌃Tab / ⌃⇧Tab", "meeting.focusShortcut"),
        ("H / L / A / C / U", "meeting.contextShortcut"),
        ("⌘F", "meeting.searchShortcut"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.t("todo.shortcuts").uppercased())
                    .font(DSFont.sectionLabel)
                    .tracking(0.4)
                    .foregroundStyle(DSColor.textMuted)
                Spacer()
                Text(L10n.t("todo.sc.closeHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textHint)
            }
            .padding(.bottom, 4)

            ForEach(rows, id: \.0) { keys, labelKey in
                HStack {
                    Text(L10n.t(labelKey))
                        .font(DSFont.checklistItem)
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    ShortcutHintBadge(text: keys)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#0A0A0A").opacity(0.94))
        )
    }
}
