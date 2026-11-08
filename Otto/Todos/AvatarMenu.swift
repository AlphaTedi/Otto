import AppKit
import SwiftUI

// MARK: - AvatarMenu — direction 13a
//
// Insights used to be a pill in the space bar, next to Notes. Adjacent pills
// made them the same RANK, and they are not: Notes is a space you work in every
// day, Insights is a page you read once a week. Moving it in here makes that
// difference structural rather than typographic, and the menu is where
// per-user, non-daily things belong anyway.
//
// Three groups, and the order is a rule rather than an accident:
//
//   1. DESTINATIONS   — open a page inside the panel (Insights, today alone)
//   2. SETTINGS       — open a window, a picker, or toggle a value
//   3. APP-LEVEL      — updates, help, quit
//
// Never interleaved. When this passes roughly nine rows the dividers become
// small uppercase headers (direction 13c) — an additive change, not a redesign.
// Not now: three headers for five rows is scaffolding without a building.
//
// AN OVERLAY, NOT A POPOVER. A popover is its own window, and this panel is a
// nonactivating one whose keys arrive through a local monitor — a menu in a
// second window would be a menu the ↑↓↩ in that monitor cannot reach. Drawn
// inside the panel it is keyboard-driven for free, and its clicks land in the
// same window as everything else.

struct AvatarMenu: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var archive = CompletedArchive.shared

    /// The rows, in order. The array IS the keyboard order, so there is no
    /// second list to keep in step with this one.
    static func rows(store: TodoStore) -> [AvatarMenuRow] {
        [
            AvatarMenuRow(id: .insights, label: L10n.t("insights.title"),
                          shortcut: "\u{2318}I", detail: nil, isDestination: true),
            AvatarMenuRow(id: .preferences, label: L10n.t("menu.preferences"),
                          shortcut: "\u{2318},", detail: nil, isDestination: false),
            AvatarMenuRow(id: .notesFolder, label: L10n.t("menu.notesFolder"),
                          shortcut: nil,
                          detail: MarkdownVault.shared.directory.lastPathComponent,
                          isDestination: false),
        ]
        // App-level, before Quit — and only when there is somewhere to send
        // it (OTTO_FEEDBACK_EMAIL). No shortcut, by choice (2026-09-27).
        + (FeedbackWindowController.isAvailable
            ? [AvatarMenuRow(id: .feedback, label: L10n.t("feedback.menu"),
                             shortcut: nil, detail: nil, isDestination: false)]
            : [])
        + [
            AvatarMenuRow(id: .quit, label: L10n.t("menu.quit"),
                          shortcut: "\u{2318}Q", detail: nil, isDestination: false),
        ]
    }

    /// Seven days of volume, or nothing at all.
    ///
    /// The handoff is firm about this and it is right: a row that says only
    /// "Insights" reads as a settings item, while one carrying a live miniature
    /// of the week says there is something to LOOK AT behind it. With too
    /// little history it is drawn WITHOUT the sparkline rather than with a flat
    /// one — a row of empty bars advertises that there is nothing there.
    private var sparkline: [Int]? {
        let counts = CompletionStats.dailyCounts(section: nil, days: 7,
                                                 store: store, archive: archive)
        return counts.contains(where: { $0 > 0 }) ? counts : nil
    }

    var body: some View {
        let rows = Self.rows(store: store)
        VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                AvatarMenuRowView(
                    row: row,
                    sparkline: row.id == .insights ? sparkline : nil,
                    isHighlighted: store.avatarMenuHighlight == index
                ) {
                    AvatarMenu.perform(row.id)
                }
                // The dividers, which are what the three groups are made of.
                if row.id == .insights || row.id == .notesFolder {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
            }
        }
        .padding(OttoMenuStyle.padding)
        .frame(width: 276)
        .ottoMenuSurface()
    }

    /// One implementation per verb, reachable from the click and from ↩.
    @MainActor
    static func perform(_ id: AvatarMenuRow.ID) {
        let store = TodoStore.shared
        store.closeAvatarMenu()
        switch id {
        case .insights:
            store.enterInsights()
            NotchController.shared.focusPanel()
        case .preferences:
            SettingsWindowController.show()
        case .notesFolder:
            // Reveal, not open: the point is to make it concrete that notes are
            // real .md files on disk, and the Finder showing them does that
            // more cheaply than any settings screen could.
            NSWorkspace.shared.activateFileViewerSelecting([MarkdownVault.shared.directory])
        case .feedback:
            // The panel floats above ordinary windows; left open, it covered
            // the feedback form it had just opened (2026-09-27).
            NotchController.shared.forceCollapse()
            FeedbackWindowController.show()
            // And again once the click is over. The collapse is refused while
            // a drag looks in flight, and the click that chose this row can
            // read as one (a hair of movement, a stale drag pasteboard) until
            // its mouse-up is handled — so the panel stayed over the form
            // (Marcello, 2026-10-19).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotchController.shared.collapseForWindow()
            }
        case .quit:
            NSApp.terminate(nil)
        }
    }
}

extension AvatarMenuRow.ID {
    var symbol: String {
        switch self {
        case .insights: return "chart.bar"
        case .preferences: return "gearshape"
        case .notesFolder: return "folder"
        case .feedback: return "bubble.left"
        case .quit: return "power"
        }
    }
}

struct AvatarMenuRow: Identifiable {
    enum ID: Hashable { case insights, preferences, notesFolder, feedback, quit }
    let id: ID
    let label: String
    let shortcut: String?
    /// The current value, shown on the right — the notes folder's name.
    let detail: String?
    /// A destination is slightly stronger than a setting; selection itself is
    /// transient, following the standard macOS menu pattern.
    let isDestination: Bool
}

private struct AvatarMenuRowView: View {
    let row: AvatarMenuRow
    let sparkline: [Int]?
    let isHighlighted: Bool
    let action: () -> Void

    @State private var hover = false
    @Environment(\.ottoMenuGlass) private var glass

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                // A glyph per row, like Raycast's menu: the list reads at a
                // glance instead of word by word (Marcello, 2026-09-27).
                OttoIcon(row.id.symbol, pointSize: 13)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 16)
                Text(row.label)
                    .font(.system(size: OttoMenuStyle.rowFont, weight: row.isDestination ? .medium : .regular))
                    .foregroundStyle(row.isDestination ? DSColor.textPrimaryBright
                                                       : DSColor.textPrimary)
                Spacer(minLength: 8)
                if let sparkline {
                    CompletionSparkline(counts: sparkline,
                                        barWidth: 3.5, barGap: 2, maxHeight: 15)
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(DSColor.textFaint)
                        .lineLimit(1)
                }
                if let shortcut = row.shortcut {
                    if glass {
                        // One keycap per key, Raycast-style.
                        HStack(spacing: 3) {
                            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, key in
                                KeyBadge(text: String(key), color: DSColor.textSecondary,
                                         minWidth: 20, height: 20)
                            }
                        }
                        .fixedSize()
                    } else {
                        Text(shortcut)
                            .font(.system(size: 11))
                            .foregroundStyle(DSColor.textHint)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, OttoMenuStyle.rowPaddingH)
            .padding(.vertical, OttoMenuStyle.rowPaddingV)
            .background(
                RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous).fill(background)
            )
            .overlay(
                // Pressed sits ON TOP as one more wash rather than replacing
                // the row's own fill, so the destination's standing tint is
                // still underneath it and the row does not change identity for
                // the length of a click.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(pressedWash)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        // Not `.plain`: the press state is part of the spec, and `.plain`
        // does not expose one.
        .buttonStyle(MenuRowPressStyle())
        .onHover { hovering in
            withAnimation(NotchAnimation.hoverFade) { hover = hovering }
        }
    }

    /// The current destination uses the same quiet cyan glass selection as
    /// the formatting popover. Hover and keyboard focus extend that treatment
    /// to any row without changing the menu's hierarchy.
    /// Only under the pointer or the keyboard: nothing is lit when the menu
    /// opens (Insights was, as a standing "destination" tint — 2026-09-27).
    private var background: Color {
        // On glass the highlight is a brighter wash, as in Raycast.
        guard glass else { return OttoMenuStyle.rowFill(highlighted: hover || isHighlighted) }
        return hover || isHighlighted ? Color.white.opacity(0.12) : .clear
    }

    @Environment(\.menuRowPressed) private var isPressed

    private var pressedWash: Color {
        guard isPressed else { return .clear }
        return SpaceInk.a(0.06)
    }
}

/// Reports the press through the environment so the row's own background logic
/// stays in one place. No scale transform: the spec is explicit, and a menu row
/// that shrinks under the pointer is a row that moves while you are aiming.
private struct MenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.menuRowPressed, configuration.isPressed)
    }
}

private struct MenuRowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var menuRowPressed: Bool {
        get { self[MenuRowPressedKey.self] }
        set { self[MenuRowPressedKey.self] = newValue }
    }
}

// The menu system (OttoMenuStyle, .ottoMenuSurface(), anchors, DSMenuRow)
// lives in DesignSystem/DSMenu.swift.

// MARK: - MenuDismissCatcher — click anywhere else closes the menu
//
// An AppKit view rather than a SwiftUI tap gesture, for the reason RowClickCatcher
// exists a few files over: in this panel a full-bleed SwiftUI gesture competes
// with every row, button and scroll view underneath it for the same click, and
// loses often enough to be useless. AppKit hit-testing runs first and is
// unambiguous.
//
// It sits UNDER the menu, so the menu's own rows are hit before it is.

struct MenuDismissCatcher: NSViewRepresentable {
    let onClick: () -> Void

    final class CatcherView: NSView {
        var onClick: () -> Void = {}
        override func mouseDown(with event: NSEvent) { onClick() }
        /// A nonactivating panel in an accessory app would otherwise spend the
        /// first click activating rather than acting.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        /// Scrolling is not clicking: let the wheel through to whatever is
        /// behind, so the menu does not freeze the list underneath it.
        override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    }

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onClick = onClick }
}
