//
//  DesignTokens.swift
//  Otto
//
//  The design tokens — DSColor, DSSpacing, DSRadius, DSShape, DSFont —
//  matching the approved mockups in the design reference PRD. The reusable
//  components built on them are in DesignComponents.swift.
//
//  WHY: earlier PRDs described styling in prose ("border radius 8px", "muted
//  gray text") and the look drifted with every re-derivation. These are
//  literal, importable constants instead — this folder IS the design system.
//  Reference these types in every screen rather than re-specifying colours,
//  spacing or radii inline per view.
//

import SwiftUI

// MARK: - Design Tokens

// MARK: - Dynamic tokens
//
// Every colour here used to be a fixed hex, chosen for a dark panel. With the
// system in Light the panels went pale and the TEXT STAYED WHITE, so nothing
// could be read at all (Marcello, 2026-08-22) — the tokens had no opposite to
// switch to, because there was only ever one value.
//
// A token is now a PAIR, resolved by AppKit at draw time against whatever
// appearance the view is actually being drawn in. That is the same mechanism
// Spotlight and Raycast use, and it is why they simply work in both: they do
// not pick colours, they name roles and let the system resolve them.
//
// Wherever Apple already has a semantic colour for the role, that is used
// directly rather than hand-mixing a pair. `labelColor` IS the text colour
// Spotlight draws with, in both appearances, including the exact contrast
// Apple ships for accessibility — reinventing it with two hex values would be
// strictly worse and would drift.

extension Color {
    /// One token, two values. Resolved per appearance, at draw time.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Same, for a pair expressed as translucent white/black — the usual way
    /// to state a surface that has to sit on top of a material.
    static func dynamicOverlay(light: Double, dark: Double) -> Color {
        .dynamic(light: NSColor.black.withAlphaComponent(light),
                 dark: NSColor.white.withAlphaComponent(dark))
    }
}

enum DSColor {
    /// THE row hover — to-dos and notes alike (Marcello, 2026-09-25: the
    /// to-do's is the right one). A 4% wash; selection keeps its own fill.
    static var rowHover: Color { .dynamicOverlay(light: 0.04, dark: 0.04) }
    /// The notch container sits on pure black (or white), where 4% all but
    /// disappears (Marcello, 2026-09-27: "I almost don't see the hover").
    /// Stronger there, in both appearances.
    static var containerRowHover: Color { .dynamicOverlay(light: 0.06, dark: 0.10) }
    static func rowHover(container: Bool) -> Color { container ? containerRowHover : rowHover }
    // Panel & structure
    static let panelBackground = Color.dynamic(light: .white, dark: NSColor(white: 0.067, alpha: 1))
    /// Apple's own hairline. It already differs per appearance.
    static let panelBorder = Color(nsColor: .separatorColor)
    static let divider = Color(nsColor: .separatorColor)

    // Text — Apple's semantic ladder, which is what Spotlight and Raycast
    // draw with. Dark-on-light and light-on-dark come for free, at the
    // contrast Apple ships.
    static let textPrimary = Color(nsColor: .labelColor)
    static let textPrimaryBright = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textMuted = Color(nsColor: .secondaryLabelColor)
    static let textFaint = Color(nsColor: .tertiaryLabelColor)
    static let textHint = Color(nsColor: .placeholderTextColor)

    // Interactive / focus
    /// The system accent, so a panel matches the rest of the user's Mac.
    static let focusAccent = Color(nsColor: .controlAccentColor)
    /// Surfaces that sit ON the glass: a wash of the OPPOSITE of the
    /// appearance, never a fixed near-black — which on a light panel read as a
    /// hole punched through it.
    static let fieldBackground = Color.dynamicOverlay(light: 0.05, dark: 0.08)
    /// The focused row's slab. #525252 in the export — a plainly visible
    /// block, not a tint. It reads stronger than it used to because it is now
    /// carrying the focus signal ALONE: the accent stroke that used to ring a
    /// focused row is gone (Marcello, 2026-08-22 — "looks pretty weird, and I
    /// really don't like it").
    static let focusedRowBackground = Color.dynamicOverlay(light: 0.10, dark: 0.17)

    /// The ⏎ badge and the drag grip on a row. #878787 in the export.
    static let rowAffordance = Color.dynamic(light: NSColor(white: 0.463, alpha: 1),
                                             dark: NSColor(white: 0.529, alpha: 1))

    /// A rule drawn INSIDE a panel — under the tab row, between two row
    /// affordances. Deliberately not `panelBorder`: that is Apple's window
    /// separator, which is meant to divide one surface from another and is far
    /// too strong for a line within one.
    static let hairlineOnPanel = Color.dynamicOverlay(light: 0.08, dark: 0.06)

    /// Glyphs that are DRAWN rather than set — the "+" cross, the six-dot
    /// grip. They carry the same weight as secondary text and must fade the
    /// same way, so they take the icon end of the same ladder rather than a
    /// hand-mixed grey.
    static let glyph = Color(nsColor: .secondaryLabelColor)

    /// Anything drawn ON a filled accent, category dot or checkbox.
    ///
    /// This is the one place a near-black is correct in BOTH appearances, and
    /// it is not an oversight: those fills are light in both — a pastel
    /// category colour, the system accent, a cyan checkbox — so the thing on
    /// top of them is always dark. Making these semantic would turn the
    /// checkmark white on a pale blue box in Dark mode.
    static let onAccentFill = Color.black
    /// The avatar menu's own ground. Nearly opaque on purpose: it floats over
    /// the panel's own material, and a translucent menu over a translucent
    /// panel is two blurs stacked and text you cannot read through either.
    static let menuBackground = Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 0.985))

    /// The ring that marks a chosen swatch. It has to beat both the swatch's
    /// own colour and the panel behind it, which is what `labelColor` is:
    /// white on a dark panel, near-black on a light one.
    static let selectionRing = Color(nsColor: .labelColor)

    /// Text and glyphs drawn ON the notch silhouette.
    ///
    /// Literal white on purpose, and the one token in this file that has no
    /// opposite — because its GROUND has none either. The silhouette is
    /// `Color.black` in every appearance (it is pretending to be a hole in the
    /// hardware), so a semantic label colour is exactly wrong there: on a
    /// Light system it resolved near-black and the countdown line disappeared
    /// into the notch. Views on the notch also sit under
    /// `darkGroundSurface()`; this states the same thing in the one place it
    /// must hold even if that environment is ever lost.
    static let onNotchSurface = Color.white
    static let onNotchSurfaceMuted = Color.white.opacity(0.75)

    /// A field that sits IN a panel — the new-section name box. The same
    /// idea as the creation bar's well (which varies with hover and focus and
    /// so stays local to it): it goes DOWN from the panel, and how far down
    /// depends on how much room there is beneath it. A fixed 40% black is a
    /// well on a dark panel and a hole punched in a light one.
    static let fieldWell = Color.dynamic(light: NSColor.black.withAlphaComponent(0.05),
                                         dark: NSColor.black.withAlphaComponent(0.40))

    // Shadows.
    //
    // A shadow is not appearance-neutral. The same 40% black that reads as
    // depth under a dark panel reads as dirt under a light one, because on
    // white there is nothing for it to sink into — Apple's own light surfaces
    // carry a far softer one. Two levels, both stated here so no view has to
    // guess: `shadowSoft` lifts a chip off its panel, `shadowStrong` lifts a
    // whole panel off the desktop.
    static let shadowSoft = Color.dynamic(light: NSColor.black.withAlphaComponent(0.10),
                                          dark: NSColor.black.withAlphaComponent(0.30))
    static let shadowStrong = Color.dynamic(light: NSColor.black.withAlphaComponent(0.18),
                                            dark: NSColor.black.withAlphaComponent(0.45))

    // Primary action. The pair inverts together: a near-white button carries
    // near-black text in Dark, and the reverse in Light, so the button never
    // disappears into the panel behind it.
    static let primaryFill = Color.dynamic(light: NSColor(white: 0.12, alpha: 1),
                                           dark: NSColor(white: 0.93, alpha: 1))
    static let primaryText = Color.dynamic(light: NSColor(white: 0.98, alpha: 1),
                                           dark: NSColor(white: 0.07, alpha: 1))

    // Reference category palette (actual colors are user-assigned per
    // category at creation time — see CT-1 in the to-do pivot PRD.
    // These are the values used across every mockup for consistency when
    // building preview/seed data.)
    enum CategoryPalette {
        static let blue = Color(hex: "#7FB8E0")     // "Work" in mockups
        static let purple = Color(hex: "#C99EE0")   // "Personal" in mockups
        static let amber = Color(hex: "#E8C15A")
        static let green = Color(hex: "#8FBF7A")
        static let coral = Color(hex: "#E07A5F")

        static let all: [Color] = [blue, purple, amber, green, coral]
    }

    /// Attendee avatars. A separate family from CategoryPalette, which is
    /// tuned to carry meaning at 7pt as a category dot — at 24pt behind a
    /// letter those same colours were "too pushy" (Marcello, 2026-08-05).
    ///
    /// Each entry is a PAIR: a pastel ground and a saturated letter of the
    /// same hue. That relationship is what makes the reference set read as one
    /// system rather than ten unrelated chips — the letter is never black, it
    /// is the ground turned up.
    enum AvatarPalette {
        struct Tone {
            let background: Color
            let foreground: Color
        }

        static let all: [Tone] = [
            Tone(background: Color(hex: "#C9D6FB"), foreground: Color(hex: "#22409E")), // blue
            Tone(background: Color(hex: "#F6EDC8"), foreground: Color(hex: "#8A6A12")), // gold
            Tone(background: Color(hex: "#CBE8D2"), foreground: Color(hex: "#22683C")), // green
            Tone(background: Color(hex: "#FAD6CC"), foreground: Color(hex: "#A94526")), // coral
            Tone(background: Color(hex: "#E1D4F6"), foreground: Color(hex: "#5A34A0")), // violet
            Tone(background: Color(hex: "#C8E7E6"), foreground: Color(hex: "#166C69")), // teal
            Tone(background: Color(hex: "#F8D3E2"), foreground: Color(hex: "#9C2F68")), // pink
            Tone(background: Color(hex: "#FADFC3"), foreground: Color(hex: "#95530F")), // amber
            Tone(background: Color(hex: "#E3EFC2"), foreground: Color(hex: "#566E1C")), // lime
            Tone(background: Color(hex: "#D7DEE7"), foreground: Color(hex: "#3D4B5C")), // slate
        ]

        /// The hairline inside every avatar's edge. Dark and nearly invisible
        /// on its own — it exists so a pale disc still has a defined boundary
        /// against a pale photo or a neighbouring disc.
        static let innerStroke = Color.black.opacity(0.10)
    }

}

enum DSSpacing {
    static let panelPadding: CGFloat = 16
    static let rowInternalGap: CGFloat = 10
    static let tabRowBottomMargin: CGFloat = 14
    static let checklistIndent: CGFloat = 24
}

/// Corner scale. Every rounded rectangle in the app is a **squircle**
/// (`style: .continuous`) — the superellipse macOS uses, not the circular-arc
/// corner. Radii step with the element's size (concentric corners) rather than
/// all being one number; that is what keeps a chip inside a card inside a panel
/// looking correct.
///
/// Never write a raw `cornerRadius:` literal in a view — take one from here, or
/// the shapes drift apart again (there were 24 distinct values before this).
enum DSRadius {
    static let controlCorner: CGFloat = 10
    static let chipCorner: CGFloat = 7
    static let checklistCheckboxCorner: CGFloat = 3
}

/// The app's shape vocabulary, so a view never has to decide.
///
/// macOS 26 draws its push buttons as capsules and its containers as
/// continuous-corner rectangles. Following that gives exactly one rule:
/// **if you can click it to do something, it is a capsule; if it holds
/// content, it is a squircle.** Toggles, checkboxes and colour swatches are
/// the deliberate exceptions — those are selection controls, not actions,
/// and macOS keeps them rectangular too.
enum DSShape {
    /// Containers: cards, fields, popovers, chips.
    static func squircle(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// Actions: Join, Create, Continue, Cancel — anything that performs.
    static var action: Capsule { Capsule(style: .continuous) }
}

enum DSFont {
    /// The scale has two steps, deliberately (Marcello, 2026-08-04):
    ///
    ///   cardTitleSize 15  — the meeting card. One item, needs to carry.
    ///   todoTitleSize 13  — a to-do row. There are twenty of these; at 15 they
    ///                       dominated the panel and ate the vertical space.
    ///
    /// They were briefly the same size, which flattened the hierarchy and made
    /// the list feel oversized. Anything rendering a to-do title must use
    /// todoTitleSize — EntityTitleView's TextKit body attributes included, or
    /// the measured row height stops matching the drawn text.
    static let cardTitleSize: CGFloat = 15
    /// 14/17 medium, per the Figma export. EntityTitleView mirrors this in
    /// its own TextKit attributes — if the two drift the measured row height
    /// stops matching the drawn text.
    static let todoTitleSize: CGFloat = 14
    static let todoTitle: Font = .system(size: todoTitleSize, weight: .medium)
    static let tabLabel: Font = .system(size: 11)
    static let sectionLabel: Font = .system(size: 10, weight: .regular)
    static let hint: Font = .system(size: 9)
    static let checklistItem: Font = .system(size: 11)
    static let buttonLabel: Font = .system(size: 12, weight: .medium)
}

// DSAnimation is gone.
//
// It was a second, near-duplicate token set — its own comment conceded it was
// a "rough SwiftUI equivalent" of the PRD spring — and by the end it had one
// live call site, on a component that had already been retired. Two vocabularies
// for one idea is how a codebase ends up with sixty hand-written springs:
// whichever one you happen to reach for is defensible, so neither wins.
// NotchAnimation, and Motion in front of it, is the whole vocabulary now.


// MARK: - Color hex convenience

extension Color {
    init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255
        let b = Double(rgbValue & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
