import SwiftUI

// MARK: - Buttons
//
// Three kinds of button exist in Otto, and only three (docs/DESIGN_SYSTEM.md §4):
//
//   PrimaryActionButton   words: Join, Save, Snooze, Create (DSButtonStyle —
//                         reui's shadcn button: 5 variants, 4 sizes).
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
//
// Modelled on reui's shadcn button (reui.io/components/button, "nova" style,
// Marcello 2026-11-12): a rounded rectangle, not a capsule — radius 10, 8 on
// the two small sizes — medium-weight label, five variants, four sizes, and a
// 1-pt drop when pressed. Colours are shadcn's neutral theme
// (`DSButtonColor`), resolved per appearance; the notch container is always
// dark, so it takes the dark values.

/// The chrome of every button with words. Use it through `PrimaryActionButton`;
/// apply it directly only when the label is not plain text plus a shortcut
/// (the auto-snooze countdown passes its `progress`).
struct DSButtonStyle: ButtonStyle {
    enum Variant {
        /// The ONE primary action in view (Join, Create).
        case primary
        /// A filled, quieter alternative.
        case secondary
        /// A bordered button: the usual second action (Snooze, Cancel).
        case outline
        /// No chrome until hovered: tertiary actions in a dense row.
        case ghost
        /// Delete and nothing else.
        case destructive
    }

    enum Size {
        /// 24 pt — inside a card, beside other content (Join on a meeting).
        case xs
        /// 28 pt — compact forms and bars.
        case sm
        /// 32 pt — the default.
        case md
        /// 36 pt — a form's main action.
        case lg

        var height: CGFloat {
            switch self {
            case .xs: return DSSize.buttonXS
            case .sm: return DSSize.buttonSM
            case .md: return DSSize.button
            case .lg: return DSSize.buttonLG
            }
        }
        var radius: CGFloat { self == .xs || self == .sm ? DSRadius.buttonSmall : DSRadius.button }
        var padding: CGFloat { self == .xs ? DSSpace.m : DSSpace.l }
        var gap: CGFloat { self == .xs || self == .sm ? DSSpace.xs : DSSpace.s }
        var font: Font {
            switch self {
            case .xs: return DSType.buttonXS
            case .sm: return DSType.buttonSM
            case .md, .lg: return DSType.button
            }
        }
        var keycapSize: CGFloat { self == .xs || self == .sm ? 9 : 10 }
    }

    var variant: Variant = .primary
    var size: Size = .md
    /// Span the container (a form's action) instead of hugging the label.
    var fillsWidth = false
    /// 0…1 — a fill growing from the leading edge, under the label: the
    /// auto-snooze countdown. Nil draws nothing.
    var progress: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(style: self, configuration: configuration)
    }
}

private struct DSButtonBody: View {
    let style: DSButtonStyle
    let configuration: ButtonStyleConfiguration
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    private typealias C = DSButtonColor

    private var fill: Color {
        switch style.variant {
        case .primary:     return hover ? C.primaryHover : C.primary
        case .secondary:   return hover ? C.secondaryHover : C.secondary
        case .outline:     return hover ? C.outlineHover : C.outline
        case .ghost:       return hover ? C.ghostHover : .clear
        case .destructive: return hover ? C.destructiveHover : C.destructiveFill
        }
    }

    private var ink: Color {
        switch style.variant {
        case .primary:     return C.onPrimary
        case .secondary:   return C.onSecondary
        case .outline, .ghost: return C.foreground
        case .destructive: return C.destructive
        }
    }

    var body: some View {
        let shape = DSShape.squircle(style.size.radius)
        configuration.label
            .font(style.size.font)
            .foregroundStyle(ink)
            .padding(.horizontal, style.size.padding)
            .frame(maxWidth: style.fillsWidth ? .infinity : nil)
            .frame(height: style.size.height)
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(fill)
                    if let progress = style.progress {
                        GeometryReader { proxy in
                            Rectangle().fill(C.progress)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(style.variant == .outline ? C.outlineBorder : .clear,
                                        lineWidth: DSSize.hairline))
            .contentShape(shape)
            // shadcn's press: the button drops one point.
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hover = $0 }
            .animation(Motion.hoverFade, value: hover)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A button with words: Join, Save, Snooze, Create. One `.primary` per view;
/// the shortcut, when there is one, sits on the button as a `Keycap`.
struct PrimaryActionButton: View {
    let title: String
    var shortcutHint: String = ""
    var variant: DSButtonStyle.Variant = .primary
    var size: DSButtonStyle.Size = .md
    /// Form buttons span the panel; a button sitting inline next to other
    /// content (Join, on a meeting card) hugs its label.
    var fillsWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.gap) {
                Text(title).lineLimit(1)
                if !shortcutHint.isEmpty {
                    // `.onLight` on the filled primary: its fill is the
                    // INVERSE of the appearance.
                    Keycap(text: shortcutHint,
                           tone: variant == .primary ? .onLight : .onDark,
                           size: size.keycapSize)
                }
            }
        }
        .buttonStyle(DSButtonStyle(variant: variant, size: size, fillsWidth: fillsWidth))
    }
}
