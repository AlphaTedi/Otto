import SwiftUI

// MARK: - Buttons
//
// Three kinds of button exist in Otto, and only three (docs/DESIGN_SYSTEM.md §4):
//
//   PrimaryActionButton   a capsule with words: Join, Save, Snooze, Create.
//   DSIconButtonStyle     an icon in a circle or squircle: gear, export, back,
//                         a format tool, sweep.
//   DockRoundButton       the container dock's 38-pt glass circle (Dock/).
//
// All three press with `DSPressStyle` or their own pressed fill, hover with
// `Motion.hoverFade`, and print their shortcut in a tooltip, never inline.

/// Pressing scales a control to 0.93 over 150 ms. For round/standalone
/// buttons only — a menu ROW must not move under the pointer while you aim.
struct DSPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(Motion.appear, value: configuration.isPressed)
    }
}

/// An icon in a small shape. Pick the variant by what the button IS:
///
///   .filled — a standalone control that must be findable at rest: the gear,
///             the export button. A 7% disc with a hairline, 12% on hover.
///   .quiet  — a tool among tools, or a control inside a row: format tools,
///             Back, Sweep. Nothing at rest, the palette's hover fill on
///             hover, a tinted fill while `isActive`.
///
/// Sizes come from `DSSize`. Shapes: `.circle` for standalone and toolbar
/// controls, `.squircle` for controls that sit in a row of text.
struct DSIconButtonStyle: ButtonStyle {
    enum Variant { case filled, quiet }
    enum Shape { case circle, squircle }

    var variant: Variant = .quiet
    var shape: Shape = .circle
    var size: CGFloat = DSSize.iconSmall
    /// Width when it differs from the height (a squircle "key").
    var width: CGFloat? = nil
    var isActive = false
    /// The fill and glyph colour while active. Nil = the panel accent.
    var activeTint: Color? = nil
    /// Draws the 1-pt hairline round a `.filled` button.
    var hairline = true
    /// The glyph colour at rest. Nil = the variant's default.
    var restGlyph: Color? = nil
    /// The glyph colour while active. Nil = `activeTint`.
    var activeGlyph: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        DSIconButtonBody(style: self, configuration: configuration)
    }
}

private struct DSIconButtonBody: View {
    let style: DSIconButtonStyle
    let configuration: ButtonStyleConfiguration
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dsPalette) private var palette

    private var tint: Color { style.activeTint ?? PanelMetrics.accent }

    private var shape: AnyShape {
        switch style.shape {
        case .circle: return AnyShape(Circle())
        case .squircle: return AnyShape(DSShape.squircle(style.size >= DSSize.iconSmall ? 8 : DSRadius.chip))
        }
    }

    private var fill: Color {
        switch style.variant {
        case .filled:
            return SpaceInk.a(hover || style.isActive ? 0.12 : 0.07)
        case .quiet:
            if configuration.isPressed { return tint.opacity(0.28) }
            if style.isActive { return tint.opacity(0.18) }
            return hover ? palette.controlHover : .clear
        }
    }

    private var glyph: Color {
        if style.isActive && style.variant == .quiet { return style.activeGlyph ?? tint }
        if let rest = style.restGlyph { return hover ? palette.iconHover : rest }
        return style.variant == .filled ? SpaceInk.a(0.75) : palette.textPrimary
    }

    var body: some View {
        configuration.label
            .foregroundStyle(glyph)
            .frame(width: style.width ?? style.size, height: style.size)
            .background(shape.fill(fill))
            .overlay {
                if style.variant == .filled && style.hairline {
                    shape.stroke(SpaceInk.a(0.10), lineWidth: DSSize.hairline)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hover = $0 }
            .animation(Motion.hoverFade, value: hover)
            .animation(Motion.hoverFade, value: style.isActive)
    }
}

// MARK: - Action button (Join, Snooze, Create…)

/// A capsule, like every other action in the app and like macOS 26's own push
/// buttons. It used to be a rounded rectangle while Join was a capsule — the
/// same control in two shapes (Marcello, 2026-07-26), and later three private
/// copies (PanelJoinButton, JoinButton, SnoozeButton). This is the one.
///
///   isProminent true  — filled `primaryFill`: the ONE primary action on
///                       screen. 92% at rest, 100% under the pointer.
///   isProminent false — a 0.5-pt outline, secondary text that brightens on
///                       hover: the quiet way out beside a primary.
struct PrimaryActionButton: View {
    let title: String
    var shortcutHint: String = ""
    var isProminent: Bool = true
    /// Form buttons span the panel; a button sitting inline next to other
    /// content (Join, on a meeting card) hugs its label instead.
    var fillsWidth: Bool = true
    /// Inline buttons are smaller so they sit inside a card without dominating.
    var isCompact: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpace.s) {
                Text(title)
                    .font(isCompact ? DSType.buttonCompact : DSType.button)
                    .foregroundStyle(isProminent ? DSColor.primaryText
                                     : (hover ? DSColor.textPrimaryBright : DSColor.textSecondary))
                if !shortcutHint.isEmpty {
                    // The shortcut lives ON the control, so the keyboard path
                    // is discoverable. `.onLight` on the filled button: its
                    // fill is the INVERSE of the appearance.
                    Keycap(text: shortcutHint,
                           tone: isProminent ? .onLight : .onDark,
                           size: isCompact ? 9 : 10)
                }
            }
            .padding(.horizontal, fillsWidth ? 0 : (isCompact ? DSSpace.xl : DSSpace.xxl))
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .padding(.vertical, isCompact ? 5 : 9) // ds-allow: the capsule's optical height
            .background(DSShape.action.fill(isProminent ? DSColor.primaryFill.opacity(hover ? 1 : 0.92)
                                                        : Color.clear))
            .overlay(DSShape.action.strokeBorder(isProminent ? .clear : DSColor.panelBorder,
                                                 lineWidth: 0.5))
            .contentShape(DSShape.action)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hintFade) { hover = hovering } }
    }
}
