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

    /// Delete, and anything else that destroys. The one red in the app —
    /// iOS's dark-mode systemRed, which reads on black and on glass alike.
    static let destructive = Color(hex: "#FF6961")

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

// MARK: - Spacing
//
// The scale the app already used most (audit 2026-11-08: 2/4/6/8/10/12/16
// cover ~75% of every padding and stack spacing). New code takes a step from
// here. 3, 5 and 9 survive in old code as optical nudges; a new one needs a
// `// ds-allow:` comment saying why.

enum DSSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 16
    /// Between blocks: the panel's own padding, the gap between two cards.
    static let section: CGFloat = 24
}

/// The older names. Kept so existing call sites read the same; new code uses
/// `DSSpace`.
enum DSSpacing {
    static let panelPadding: CGFloat = DSSpace.xxl
    static let rowInternalGap: CGFloat = DSSpace.l
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
/// The steps are the values the app actually draws with, smallest first.
enum DSRadius {
    /// A checklist step's checkbox.
    static let checkbox: CGFloat = 3
    /// Keycaps, badges, a to-do's checkbox, tooltips.
    static let keycap: CGFloat = 6
    /// Inline chips, small square buttons.
    static let chip: CGFloat = 7
    /// Controls: fields, segmented items.
    static let control: CGFloat = 10
    /// A row inside a menu.
    static let menuRow: CGFloat = 11
    /// A list row's hover/focus slab, the opened to-do card.
    static let row: CGFloat = 14
    /// The draft row's well, input bars.
    static let bar: CGFloat = 16
    /// Menus and popovers.
    static let menu: CGFloat = 20
    /// A floating panel block.
    static let block: CGFloat = 24
    /// The meeting card.
    static let card: CGFloat = 32

    // Older names.
    static let controlCorner: CGFloat = control
    static let chipCorner: CGFloat = chip
    static let checklistCheckboxCorner: CGFloat = checkbox
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

/// Fixed sizes of controls. A control's size is part of its identity: a 34pt
/// round button next to a 32pt one reads as a mistake, not a choice.
enum DSSize {
    /// Pills, tabs, compact controls.
    static let control: CGFloat = 28
    /// Round icon buttons.
    static let iconSmall: CGFloat = 28
    static let icon: CGFloat = 34
    static let iconLarge: CGFloat = 38
    /// Checkboxes: a to-do, a checklist step in the dock, a step in panels.
    static let box: CGFloat = 18
    static let stepBox: CGFloat = 14
    static let miniBox: CGFloat = 10
    /// A hairline.
    static let hairline: CGFloat = 1
}

/// Type ROLES. A view picks what the text IS, never a point size.
///
/// The app is set in SF (the system face) throughout; Onboarding's Host
/// Grotesk is its own theme and does not leak here. Where the two surfaces
/// differ (a row title is 14 medium in the panels, 15 regular in the
/// container), use `DSType.rowTitle(_:)` with the view's `ottoSurface`.
enum DSType {
    // Titles
    static let cardTitleSize: CGFloat = 15
    static let cardTitle: Font = .system(size: cardTitleSize, weight: .medium)
    /// A space's title in its header bar ("Notes", a section name).
    static let pageTitle: Font = .system(size: 18, weight: .medium)
    /// An open note's title, set like a document's.
    static let editorTitle: Font = DSType.editorTitle

    // Rows
    static let rowTitleSizePanels: CGFloat = 14
    static let rowTitleSizeContainer: CGFloat = 15
    static func rowTitleSize(_ surface: OttoSurface) -> CGFloat {
        surface == .container ? rowTitleSizeContainer : rowTitleSizePanels
    }
    static func rowTitle(_ surface: OttoSurface) -> Font {
        surface == .container ? .system(size: rowTitleSizeContainer)
                              : .system(size: rowTitleSizePanels, weight: .medium)
    }

    // Running text
    static let body: Font = .system(size: 13)
    /// A checklist step, a note preview line.
    static let step: Font = DSType.step
    /// Meta lines under a title: dates, counts, "3 more steps".
    static let meta: Font = DSType.meta
    /// "Completed · 2" — a quiet header inside a list.
    static let quiet: Font = .system(size: 12.5, weight: .semibold)

    // Controls
    /// Pills and tabs.
    static let label: Font = .system(size: 13, weight: .semibold)
    /// Menu rows.
    static let menu: Font = .system(size: 13.5)
    static let button: Font = .system(size: 12, weight: .medium)
    static let buttonCompact: Font = .system(size: 11, weight: .medium)
    static let tooltip: Font = .system(size: 11, weight: .medium)
    static let keycap: Font = .system(size: 10, weight: .medium)

    // Small print
    static let caption: Font = .system(size: 11)
    static let micro: Font = .system(size: 10)
    /// Uppercase section caps ("SECTION NAME"). Pair with `.tracking(0.4)`
    /// and `.textCase(.uppercase)` — `DSSectionLabel` does both.
    static let sectionCaps: Font = .system(size: 10, weight: .medium)
}

/// The older names, kept as aliases of `DSType` so existing call sites
/// compile unchanged. New code uses `DSType`.
enum DSFont {
    static let cardTitleSize: CGFloat = DSType.cardTitleSize
    /// 14/17 medium, per the Figma export. EntityTitleView mirrors this in
    /// its own TextKit attributes — if the two drift the measured row height
    /// stops matching the drawn text.
    static let todoTitleSize: CGFloat = DSType.rowTitleSizePanels
    static let todoTitle: Font = DSType.rowTitle(.panels)
    static let tabLabel: Font = DSType.caption
    static let sectionLabel: Font = DSType.micro
    static let hint: Font = .system(size: 9)
    static let checklistItem: Font = DSType.caption
    static let buttonLabel: Font = DSType.button
}

// DSAnimation is gone.
//
// It was a second, near-duplicate token set — its own comment conceded it was
// a "rough SwiftUI equivalent" of the PRD spring — and by the end it had one
// live call site, on a component that had already been retired. Two vocabularies
// for one idea is how a codebase ends up with sixty hand-written springs:
// whichever one you happen to reach for is defensible, so neither wins.
// NotchAnimation, and Motion in front of it, is the whole vocabulary now.


// MARK: - The B3 dock's neutrals (OTTO-B3-DOCK-SPEC §4.2)
//
// The dock experiment draws on pure black in both appearances (the notch is a
// hole in the hardware), so these are fixed values, not dynamic ones.
//
// These are the VALUES behind `DSPalette.container` (Surface.swift). A view
// asks the palette for a role; reaching for `DSDock` directly is only for
// dock-only furniture (the dot dock, its tooltip, its keycaps).

enum DSDock {
    static let text = Color(hex: "#F2F2F2")
    static let textStrong = Color(hex: "#F5F5F7")
    static let text2 = Color(hex: "#8E8E93")
    static let text3 = Color(hex: "#6E6E73")
    /// The first row's placeholder — ALWAYS this grey, never the space colour.
    static let placeholder = Color(hex: "#77777C")
    static let doneText = Color(hex: "#5E5E63")
    static let chrome = Color(hex: "#111113")
    static let chromeBorder = Color(hex: "#1C1C1E")
    static let tooltip = Color(hex: "#1C1C1E")
    static let tooltipText = Color(hex: "#E5E5EA")
    static let divider = Color(hex: "#121214")
    static let keycapBorder = Color(hex: "#2C2C2E")
    /// Row hover and keyboard focus: white at 4.5 % and 9 % (final flow 3.2).
    static let rowHover = Color.white.opacity(0.045)
    static let rowFocus = Color.white.opacity(0.09)
    /// The opened to-do's card.
    static let card = Color(hex: "#161618")
    static let cardBorder = Color.white.opacity(0.07)
    static let stepText = Color(hex: "#C7C7CC")
    static let stepLine = Color.white.opacity(0.12)
    static let settingsIcon = Color(hex: "#AEAEB2")
    static let keycapFocus = Color(hex: "#48484A")
    static let plus = Color(hex: "#5E5E63")
    static let iconHover = Color(hex: "#E5E5EA")
    /// Notes' gold, and its active tone.
    static let notes = Color(hex: "#E5B66B")
    static let notesLight = Color(hex: "#F0CF98")

    static let rowTitle: Font = DSType.rowTitle(.container)
    /// The to-do row's own type: semibold read heavier than "Add to …" and
    /// the dock's labels beside it (Marcello, 2026-10-17).
    static let noteTitle: Font = DSType.rowTitle(.container)
    static let notePreview: Font = DSType.body
    static let meta: Font = DSType.meta
    /// Medium, one step under the spec's semibold (Marcello, 2026-10-17).
    static let dockLabel: Font = .system(size: 13, weight: .medium)
    static let dockCount: Font = .system(size: 13, weight: .medium)
    static let tooltipFont: Font = .system(size: 12, weight: .semibold)
    static let keycap: Font = .system(size: 11, weight: .semibold)
    static let step: Font = DSType.step
    static let moreSteps: Font = .system(size: 12.5, weight: .medium)
    /// "Completed · 2", the editor's meta line.
    static let quietLabel: Font = DSType.quiet
    /// The open note's title, set like a document's (2026-10-18).
    static let editorTitle: Font = DSType.editorTitle
    /// The day under it.
    static let noteDate: Font = .system(size: 14, weight: .medium)
    static let tooltipShortcut: Font = .system(size: 11, weight: .medium)
}

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
