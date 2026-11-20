import SwiftUI

// MARK: - Menus
//
// Every Otto menu is drawn in the panel, not by the system: SwiftUI `Menu`
// cannot present from a non-activating panel (CONTEXT §5). One surface
// (`.ottoMenuSurface()`), one row (`DSMenuRow`), one placement
// (`.menuAnchor` + `.anchoredMenu`). Keyboard: ↑/↓ move `isHighlighted`,
// ⏎ performs, Esc closes — the owning store routes it.

// MARK: - One look for every menu in the panel
//
// The gear menu, the Notes · Meetings dropdown and the Aa block menu had
// three looks — the dropdown's see-through ground among them (Marcello,
// 2026-09-26: "il background è troppo trasparente", pointing at this menu as
// the reference). One surface and one row treatment now.

enum OttoMenuStyle {
    static let radius: CGFloat = DSRadius.menu
    static let padding: CGFloat = 10
    static let rowRadius: CGFloat = DSRadius.menuRow
    static let rowFont: CGFloat = 13.5
    static let rowPaddingH: CGFloat = 13
    static let rowPaddingV: CGFloat = 11
    static let shortcutFont: CGFloat = 11

    /// Under the glass: enough body that rows behind the menu do not read
    /// through it, whatever the glass tier.
    /// Light mode is near-opaque: glass over the glass panel has nothing to
    /// sample and comes out dark, so at 60 % white every menu looked greyed
    /// out, as if disabled (Marcello, 2026-11-02).
    static let ground = Color.dynamic(light: NSColor(white: 0.985, alpha: 0.96),
                                      dark: NSColor(srgbRed: 0.105, green: 0.105, blue: 0.12, alpha: 0.78))

    /// Space between a menu and the control it opened from, whichever side
    /// it opens on (2026-09-27: the two menus sat at different distances).
    static let anchorGap: CGFloat = 8

    /// Coordinate space the menus and their triggers are measured in — the
    /// panel's (TodoTabView).
    static let space = "otto.menus"

    /// Hover and keyboard highlight: the neutral wash rows use everywhere
    /// else, never a colour (2026-09-27). Being the current item is shown by
    /// its check or weight, not by a fill.
    static func rowFill(highlighted: Bool, current: Bool = false) -> Color {
        highlighted ? SpaceInk.a(0.08) : .clear
    }
}

/// The controls a panel menu opens from. Each reports its frame in the
/// panel's space so its menu can open a fixed `anchorGap` away from it.
enum MenuAnchor: Hashable {
    case gear, notesKind
    /// The B3 dock's right-clicked space (DockSpaceMenu).
    case dockItem
    /// The B3 dock's right-clicked note (DockNoteMenu).
    case noteRow
}

#if DEBUG
/// The anchors in hosting-view coordinates, for DebugDriver's click tests.
@MainActor enum MenuAnchorDebug { static var global: [MenuAnchor: CGRect] = [:] }
#endif

struct MenuAnchorKey: PreferenceKey {
    static let defaultValue: [MenuAnchor: CGRect] = [:]
    static func reduce(value: inout [MenuAnchor: CGRect], nextValue: () -> [MenuAnchor: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func menuAnchor(_ anchor: MenuAnchor) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: MenuAnchorKey.self,
                                   value: [anchor: proxy.frame(in: .named(OttoMenuStyle.space))])
            #if DEBUG
                .onAppear { MenuAnchorDebug.global[anchor] = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { MenuAnchorDebug.global[anchor] = $0 }
            #endif
        })
    }

    /// The anchor only while `active` — for one of many rows. The same view
    /// either way, so the row keeps its state when its menu opens.
    func menuAnchor(_ anchor: MenuAnchor, when active: Bool) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: MenuAnchorKey.self,
                                   value: active ? [anchor: proxy.frame(in: .named(OttoMenuStyle.space))] : [:])
        })
    }

    /// Places a menu against its anchor: trailing edges flush, `anchorGap`
    /// below it (or above, when it opens upward). Used inside a full-panel
    /// overlay, so `size` is the panel's.
    func anchoredMenu(to anchor: CGRect, in size: CGSize, opensUpward: Bool) -> some View {
        self
            .padding(.trailing, max(0, size.width - anchor.maxX))
            .padding(opensUpward ? .bottom : .top,
                     opensUpward ? max(0, size.height - anchor.minY + OttoMenuStyle.anchorGap)
                                 : anchor.maxY + OttoMenuStyle.anchorGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: opensUpward ? .bottomTrailing : .topTrailing)
    }
}

extension View {
    /// The menu surface: ground, glass, hairline and shadow — or, in the
    /// notch container, see-through glass (`ottoMenuGlass`).
    func ottoMenuSurface() -> some View { modifier(OttoMenuSurface()) }
}

private struct OttoMenuSurface: ViewModifier {
    @Environment(\.ottoMenuGlass) private var glass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: OttoMenuStyle.radius, style: .continuous)
        if glass {
            // EXPERIMENT (Marcello, 2026-10-03, Raycast as the reference): in
            // the notch container the menu hangs past the silhouette over the
            // desktop, so it is real glass — what is behind it shows through,
            // blurred and darkened — with a lit hairline, instead of the
            // floating panels' near-opaque ground.
            content
                .floatingGlass(in: shape, tint: Color.black.opacity(0.35))
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.26), Color.white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        } else {
            content
                .background(shape.fill(OttoMenuStyle.ground))
                .floatingGlass(in: shape)
                .overlay(shape.strokeBorder(Color.dynamicOverlay(light: 0.10, dark: 0.20), lineWidth: 1))
                .shadow(color: DSColor.shadowSoft, radius: 18, x: 0, y: 8)
        }
    }
}

private struct OttoMenuGlassKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The container's glass menus (see OttoMenuSurface).
    var ottoMenuGlass: Bool {
        get { self[OttoMenuGlassKey.self] }
        set { self[OttoMenuGlassKey.self] = newValue }
    }
}


// MARK: - Menu row

/// One row of any Otto menu. `isHighlighted` is the keyboard selection;
/// hover lights it too. The current item is shown by `isChecked` (a check in
/// the leading column) or `isEmphasized` (medium weight), never by a fill.
struct DSMenuRow: View {
    enum Density { case regular, compact }

    let label: String
    var icon: String? = nil
    /// nil = no check column; true/false = the column, ticked or empty.
    var isChecked: Bool? = nil
    var shortcut: String? = nil
    var isHighlighted = false
    var isEmphasized = false
    var destructive = false
    var density: Density = .regular
    let action: () -> Void

    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dsPalette) private var palette
    @Environment(\.ottoSurface) private var surface
    @Environment(\.ottoMenuGlass) private var glass

    private var fill: Color {
        guard hover || isHighlighted else { return .clear }
        // On glass (the container's see-through menus) the highlight is a
        // brighter wash, as in Raycast.
        return glass || surface == .container ? Color.white.opacity(0.12)
                                              : OttoMenuStyle.rowFill(highlighted: true)
    }

    var body: some View {
        let shape = DSShape.squircle(DSRadius.menuRow)
        Button(action: action) {
            HStack(spacing: DSSpace.m) {
                if let isChecked {
                    OttoIcon("checkmark", pointSize: 11)
                        .foregroundStyle(palette.textPrimary)
                        .opacity(isChecked ? 1 : 0)
                        .frame(width: 14)
                }
                if let icon {
                    OttoIcon(icon, pointSize: 13)
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 16)
                }
                Text(label)
                    .font(.system(size: OttoMenuStyle.rowFont, weight: isEmphasized ? .medium : .regular))
                    .foregroundStyle(destructive ? DSColor.destructive : palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DSSpace.m)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: OttoMenuStyle.shortcutFont))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize()
                }
            }
            .padding(.leading, isChecked != nil ? DSSpace.l : OttoMenuStyle.rowPaddingH)
            .padding(.trailing, OttoMenuStyle.rowPaddingH)
            .padding(.vertical, density == .regular ? OttoMenuStyle.rowPaddingV : 9) // ds-allow: dock menu density
            .background(shape.fill(fill))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering in withAnimation(Motion.hoverFade) { hover = hovering } }
        .accessibilityAddTraits(isChecked == true ? .isSelected : [])
    }
}
