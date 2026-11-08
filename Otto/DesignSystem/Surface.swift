import SwiftUI

// MARK: - The two surfaces, and one set of roles for both
//
// Otto draws the same content on two grounds (docs/DESIGN_SYSTEM.md §2):
//
//   .panels     — Floating Panels: glass cards below the notch. Follows the
//                 system's Light/Dark, so every role is a semantic colour.
//   .container  — the Notch Container (the B3 dock): the silhouette itself
//                 grows and is pure black in every appearance, so every role
//                 is a fixed value tuned for black.
//
// Before this file, each view asked "am I in the container?" and picked a
// `DSColor` or a `DSDock` value itself — ~95 branches, and a new view had to
// know which palette to reach for. Now a view names the ROLE and the surface
// resolves it:
//
//     @Environment(\.dsPalette) private var palette
//     Text(title).foregroundStyle(palette.textPrimary)
//
// The surface is set ONCE, at NotchRootView. Nothing else writes it.
// Code that is not a view (geometry, key routing) keeps reading
// `DockExperiment.isOn`.

enum OttoSurface: Equatable {
    case panels
    case container

    init(_ layout: NotchLayout) {
        self = layout == .container ? .container : .panels
    }
}

private struct OttoSurfaceKey: EnvironmentKey {
    /// Panels by default: Settings, previews and anything else drawn outside
    /// the notch follow the system appearance, which is what `.panels` does.
    static let defaultValue: OttoSurface = .panels
}

extension EnvironmentValues {
    var ottoSurface: OttoSurface {
        get { self[OttoSurfaceKey.self] }
        set { self[OttoSurfaceKey.self] = newValue }
    }

    /// The colour roles for the surface this view is drawn on.
    var dsPalette: DSPalette { DSPalette.for(ottoSurface) }
}

extension View {
    /// Declares which surface everything inside is drawn on. Called once, at
    /// the notch root — never in a component.
    func ottoSurface(_ surface: OttoSurface) -> some View {
        environment(\.ottoSurface, surface)
    }
}

/// Colour ROLES. Every value already existed (as a `DSColor` for the panels
/// or a `DSDock` for the container); this only gives each pair one name.
struct DSPalette {
    /// Titles, row text, anything the eye should land on.
    let textPrimary: Color
    /// Supporting text: meta lines, counts, secondary labels.
    let textSecondary: Color
    /// The quietest readable text: hints, timestamps.
    let textTertiary: Color
    /// Placeholder in an empty field.
    let placeholder: Color
    /// A completed to-do's struck-through title.
    let textDone: Color
    /// Drawn glyphs and resting icons (gear, plus, grip).
    let glyph: Color
    /// An icon under the pointer.
    let iconHover: Color
    /// Row under the pointer.
    let rowHover: Color
    /// Row with keyboard focus.
    let rowFocus: Color
    /// A raised card inside the panel (the opened to-do).
    let card: Color
    let cardBorder: Color
    /// A rule inside one surface (never between two).
    let hairline: Color
    /// A field that sits IN the panel and goes down from it.
    let fieldWell: Color
    /// The checklist's connector line.
    let stepLine: Color
    /// The quiet fill behind a hovered control (pill, small button).
    let controlHover: Color

    static let panels = DSPalette(
        textPrimary: DSColor.textPrimary,
        textSecondary: DSColor.textSecondary,
        textTertiary: DSColor.textFaint,
        placeholder: DSColor.textHint,
        textDone: DSColor.textHint,
        glyph: DSColor.glyph,
        iconHover: DSColor.textPrimary,
        rowHover: DSColor.rowHover,
        rowFocus: DSColor.focusedRowBackground,
        card: DSColor.fieldBackground,
        cardBorder: .clear,
        hairline: DSColor.hairlineOnPanel,
        fieldWell: DSColor.fieldWell,
        stepLine: DSColor.panelBorder,
        controlHover: DSColor.fieldBackground
    )

    static let container = DSPalette(
        textPrimary: DSDock.text,
        textSecondary: DSDock.text2,
        textTertiary: DSDock.text3,
        placeholder: DSDock.placeholder,
        textDone: DSDock.doneText,
        glyph: DSDock.settingsIcon,
        iconHover: DSDock.iconHover,
        rowHover: DSDock.rowHover,
        rowFocus: DSDock.rowFocus,
        card: DSDock.card,
        cardBorder: DSDock.cardBorder,
        hairline: DSDock.divider,
        fieldWell: Color.white.opacity(0.10),
        stepLine: DSDock.stepLine,
        controlHover: Color.white.opacity(0.08)
    )

    static func `for`(_ surface: OttoSurface) -> DSPalette {
        surface == .container ? .container : .panels
    }
}
