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
            AvatarMenuRow(id: .shortcuts, label: L10n.t("menu.shortcuts"),
                          shortcut: nil, detail: nil, isDestination: false),
            AvatarMenuRow(id: .notesFolder, label: L10n.t("menu.notesFolder"),
                          shortcut: nil,
                          detail: MarkdownVault.shared.directory.lastPathComponent,
                          isDestination: false),
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
        case .shortcuts:
            withAnimation(NotchAnimation.hintFade) { store.showShortcuts = true }
        case .notesFolder:
            // Reveal, not open: the point is to make it concrete that notes are
            // real .md files on disk, and the Finder showing them does that
            // more cheaply than any settings screen could.
            NSWorkspace.shared.activateFileViewerSelecting([MarkdownVault.shared.directory])
        case .quit:
            NSApp.terminate(nil)
        }
    }
}

struct AvatarMenuRow: Identifiable {
    enum ID: Hashable { case insights, preferences, shortcuts, notesFolder, quit }
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
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
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(DSColor.textHint)
                        .fixedSize()
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
    private var background: Color {
        OttoMenuStyle.rowFill(highlighted: hover || isHighlighted, current: row.isDestination)
    }

    @Environment(\.menuRowPressed) private var isPressed

    private var pressedWash: Color {
        guard isPressed else { return .clear }
        return LabMetrics.accent.opacity(0.14)
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

// MARK: - One look for every menu in the panel
//
// The gear menu, the Notes · Meetings dropdown and the Aa block menu had
// three looks — the dropdown's see-through ground among them (Marcello,
// 2026-09-26: "il background è troppo trasparente", pointing at this menu as
// the reference). One surface and one row treatment now.

enum OttoMenuStyle {
    static let radius: CGFloat = 20
    static let padding: CGFloat = 10
    static let rowRadius: CGFloat = 11
    static let rowFont: CGFloat = 13.5
    static let rowPaddingH: CGFloat = 13
    static let rowPaddingV: CGFloat = 11
    static let shortcutFont: CGFloat = 11

    /// Under the glass: enough body that rows behind the menu do not read
    /// through it, whatever the glass tier.
    static let ground = Color.dynamic(light: NSColor(white: 1, alpha: 0.6),
                                      dark: NSColor(srgbRed: 0.105, green: 0.105, blue: 0.12, alpha: 0.78))

    /// The current item carries a standing cyan cast; hover and keyboard
    /// highlight deepen it, on any row.
    static func rowFill(highlighted: Bool, current: Bool) -> Color {
        if current { return LabMetrics.accent.opacity(highlighted ? 0.20 : 0.14) }
        return LabMetrics.accent.opacity(highlighted ? 0.18 : 0)
    }
}

extension View {
    /// The menu surface: ground, glass, hairline and shadow.
    func ottoMenuSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: OttoMenuStyle.radius, style: .continuous)
        return self
            .background(shape.fill(OttoMenuStyle.ground))
            .floatingGlass(in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
            .shadow(color: DSColor.shadowSoft, radius: 18, x: 0, y: 8)
    }
}

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
