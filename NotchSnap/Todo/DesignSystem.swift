//
//  DesignSystem.swift
//  NotchSnap
//
//  Concrete design tokens and reusable SwiftUI components matching the
//  approved mockups in notchsnap_design_reference_prd.md.
//
//  PURPOSE: Fable 5 has been drifting from the approved look because prior
//  PRDs described styling in prose ("border radius 8px", "muted gray text").
//  This file gives literal, importable constants and components instead —
//  there is no separate "design system library," this Swift file IS the
//  design system for this app. Reference these types directly in every
//  screen rather than re-specifying colors/spacing/radii inline per view.
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
    // Panel & structure
    static let panelBackground = Color.dynamic(light: .white, dark: NSColor(white: 0.067, alpha: 1))
    static let outerBackground = Color.dynamic(light: .white, dark: .black)
    /// Apple's own hairline. It already differs per appearance.
    static let panelBorder = Color(nsColor: .separatorColor)
    static let divider = Color(nsColor: .separatorColor)
    static let dividerSubtle = Color.dynamicOverlay(light: 0.06, dark: 0.07)

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
    static let glyphStrong = Color(nsColor: .labelColor)

    /// Anything drawn ON a filled accent, category dot or checkbox.
    ///
    /// This is the one place a near-black is correct in BOTH appearances, and
    /// it is not an oversight: those fills are light in both — a pastel
    /// category colour, the system accent, a cyan checkbox — so the thing on
    /// top of them is always dark. Making these semantic would turn the
    /// checkmark white on a pale blue box in Dark mode.
    static let onAccentFill = Color.black
    static let onAccentFillMuted = Color.black.opacity(0.5)

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

    /// A grouped card in an ordinary window — the Settings sections.
    ///
    /// Settings used to borrow the ONBOARDING's tile, which is a flat 30%
    /// black built for that flow's dark purple ground. In a Light window that
    /// drew every section as a dark slab carrying dark system text, which is
    /// the single biggest reason Settings was unreadable in Light mode.
    ///
    /// Elevation flips with the appearance, the way Apple's own grouped boxes
    /// do: a card rises ABOVE a light window and sinks BELOW a dark one.
    static let cardSurface = Color.dynamic(light: NSColor.white.withAlphaComponent(0.70),
                                           dark: NSColor.black.withAlphaComponent(0.30))

    /// The meeting cards peeking out from under the one in front. They are
    /// the same surface seen from further back, so they take the appearance's
    /// side: deeper than the panel in Dark, lighter-but-greyer in Light. A
    /// fixed black read as a shadow cast by nothing on a light panel.
    static let stackedCardFill = Color.dynamic(light: NSColor.black.withAlphaComponent(0.10),
                                               dark: NSColor.black.withAlphaComponent(0.45))

    /// A field that sits IN a panel — the new-section name box. The same
    /// idea as the creation bar's well (which varies with hover and focus and
    /// so stays local to it): it goes DOWN from the panel, and how far down
    /// depends on how much room there is beneath it. A fixed 40% black is a
    /// well on a dark panel and a hole punched in a light one.
    static let fieldWell = Color.dynamic(light: NSColor.black.withAlphaComponent(0.05),
                                         dark: NSColor.black.withAlphaComponent(0.40))

    /// The disc behind an attendee with no photo and no address to colour it
    /// by. A wash of the appearance's opposite, like every other surface that
    /// sits on the panel.
    static let placeholderFill = Color.dynamicOverlay(light: 0.07, dark: 0.08)

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
    // category at creation time — see CT-1 in notchsnap_todo_pivot_prd.md.
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

    // Urgency (see TodoUrgency in notchsnap_todo_pivot_prd.md Section 10)
    static let urgencyLow = Color(hex: "#8FBF7A")
    static let urgencyMedium = Color(hex: "#E8C15A")
    static let urgencyHigh = Color(hex: "#E07A5F")
}

enum DSSpacing {
    static let panelPadding: CGFloat = 16
    static let rowGap: CGFloat = 12
    static let rowInternalGap: CGFloat = 10
    static let tabRowBottomPadding: CGFloat = 12
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
    static let panelCorner: CGFloat = 18
    static let cardCorner: CGFloat = 14
    static let controlCorner: CGFloat = 10
    static let chipCorner: CGFloat = 7
    static let checkboxCorner: CGFloat = 4
    static let checklistCheckboxCorner: CGFloat = 3
    static let hintChipCorner: CGFloat = 4
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

// MARK: - Reusable component: Category tab chip

/// A single tab in the browsing view's tab row. Only the ACTIVE tab is
/// rendered in its category color — inactive tabs are always neutral.
/// See TD-9 / TD-2 in notchsnap_todo_pivot_prd.md — this is not optional
/// styling, it's a functional requirement.
struct CategoryTabChip: View {
    let title: String
    let categoryColor: Color
    let isActive: Bool
    /// How many to-dos are still OPEN in this category. nil = the category is
    /// empty (no indicator at all); 0 = everything done (checkmark).
    ///
    /// This replaces the circular progress ring: a 14pt arc couldn't tell you
    /// how much was left — "I don't understand from that view how much I am
    /// still missing" (Marcello, 2026-07-23). A remaining COUNT answers that
    /// directly, the way Reminders/Things do. Supersedes drift-table item #3
    /// in notchsnap_design_reference_prd.md §10.
    let remaining: Int?

    /// Shared with every other chip in the row, so the active fill can be one
    /// object that MOVES rather than two that cross-fade. Optional because the
    /// static reference rendering in this file has no row to belong to.
    var pillNamespace: Namespace.ID? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                // Active sits on the category's own fill and is therefore
                // always dark; inactive sits on the panel and follows it.
                .foregroundColor(isActive ? DSColor.onAccentFill : DSColor.textPrimary)

            if let remaining {
                if remaining == 0 {
                    // Nothing left — a quiet "all clear", not a zero.
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isActive ? DSColor.primaryText.opacity(0.55)
                                                  : DSColor.textFaint)
                } else {
                    Text("\(remaining)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(isActive ? DSColor.onAccentFillMuted
                                                  : DSColor.textSecondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, LabMetrics.tabPaddingH)
        .padding(.vertical, LabMetrics.tabPaddingV)
        // The active fill TRAVELS between tabs.
        //
        // It used to be `isActive ? categoryColor : .clear` on every chip
        // independently: switching section cross-faded one fill out and
        // another in, and the corner radius jumped between the pill and the
        // 8pt resting shape in a single frame because a `clipShape` radius is
        // a discrete swap, not an interpolation. Nothing moved — two things
        // blinked.
        //
        // With one matched geometry the fill is a single object that slides
        // and resizes into the new tab, which is also what makes ⇥ readable:
        // you see WHERE you went, not just that something changed.
        .background {
            if isActive {
                let shape = RoundedRectangle(cornerRadius: LabMetrics.tabActiveRadius,
                                             style: .continuous)
                if let pillNamespace {
                    shape.fill(categoryColor)
                        .matchedGeometryEffect(id: "activeTabPill", in: pillNamespace)
                } else {
                    shape.fill(categoryColor)
                }
            }
        }
        // Inactive chips still clip to their resting shape; only the active
        // fill is shared, so nothing else has to know about the namespace.
        .clipShape(RoundedRectangle(
            cornerRadius: isActive ? LabMetrics.tabActiveRadius : LabMetrics.tabInactiveRadius,
            style: .continuous))
        // No ⌘-held index badge (Marcello, 2026-08-05). ⌘1-9 still jumps
        // between categories; it is documented in the "?" shortcuts overlay
        // like every other shortcut, rather than printed over the tabs.
    }
}

/// The dedicated "+" creation tab — always present, no category color of
/// its own. See Section 6.1 of notchsnap_todo_pivot_prd.md.
///
/// RETIRED from the tab row (2026-08-16), like ProgressRing before it. A to-do
/// is now made by typing into a draft row inside the list, so there is no
/// creation surface for a chip to lead to, and the filled treatment was
/// advertising an action that no longer exists. The row's "+" is now
/// NewSectionButton — plain, muted, and at the END of the tabs. Kept here
/// because the design PRD still names the type; do not put it back in a tab
/// row without changing the PRD first.
struct CreationTabChip: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 12))
            .foregroundColor(isActive ? DSColor.primaryText : DSColor.textPrimaryBright)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isActive ? DSColor.primaryFill : Color(hex: "#333333"))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
    }
}

// MARK: - Reusable component: Progress ring (Section 9.2)
//
// RETIRED from the tab row (2026-07-23): at 14pt the arc was unreadable —
// it couldn't answer "how much is left in this category?". CategoryTabChip
// now shows a remaining COUNT instead. Kept here because the type is still
// referenced by the design PRD; use it only where an arc is genuinely legible
// (i.e. considerably larger than the tab chip).

struct ProgressRing: View {
    let progress: Double   // 0...1
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.3), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Motion.contentHug, value: progress)
    }
}

// MARK: - Reusable component: To-do row

struct TodoRow: View {
    let title: String
    let categoryColor: Color
    let isFocused: Bool
    let shortcutHint: String?   // only the focused row ever passes non-nil here

    var body: some View {
        HStack(spacing: DSSpacing.rowInternalGap) {
            RoundedRectangle(cornerRadius: DSRadius.checkboxCorner, style: .continuous)
                .strokeBorder(categoryColor, lineWidth: 1.5)
                .frame(width: 14, height: 14)

            Text(title)
                .font(DSFont.todoTitle)
                .foregroundColor(DSColor.textPrimary)

            Spacer()

            if let shortcutHint {
                ShortcutHintBadge(text: shortcutHint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isFocused ? DSColor.focusedRowBackground : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .stroke(isFocused ? DSColor.focusAccent : Color.clear, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous))
    }
}

// MARK: - Reusable component: Drop indicator
//
// Arc's sidebar convention (Marcello, 2026-07-26): while a row is being
// dragged, the slot it would land in is drawn as a bright line with a dot on
// the leading end. It replaces the old six-dot grip handle entirely — the grip
// had to reserve space beside every checkbox, which pushed the whole list
// inward and made the rows look like they were floating away from the left
// edge. The row is now the drag handle, so nothing is indented.

struct DropIndicator: View {
    var tint: Color = DSColor.textPrimaryBright

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(tint)
                .frame(height: 1.5)
        }
        .frame(height: 6)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Reusable component: Keycap
//
// The old shortcut chip was a flat capsule filled at 22% opacity — it read as
// a smudge rather than a key, and on the light Create/Join buttons it was
// barely visible at all (Marcello, 2026-07-26).
//
// This follows the convention GitHub, Linear, Raycast, Arc and every
// command-palette app converged on: a RECTANGULAR cap (keys are not pills),
// a hairline highlight along the top edge, a darker bottom edge plus a 1pt
// drop shadow for physical depth, and a high-contrast label. The depth is
// what makes it read as a key instead of a badge.

struct Keycap: View {
    let text: String
    /// Keycaps sit on both the light action buttons and the dark panel, and a
    /// single tone cannot serve both — the light one needs a DARKER cap, the
    /// dark one a LIGHTER cap, or the shading inverts and looks wrong.
    enum Tone { case onLight, onDark }
    var tone: Tone = .onDark
    var size: CGFloat = 10

    /// Flat, not glass. The cap used to carry a gradient edge, a top
    /// highlight, a bottom shade and a drop shadow — a tiny glossy button
    /// stuck onto a real button, which read as "fake and clumsy"
    /// (Marcello, 2026-08-05). Every design system that shows shortcuts well
    /// — Stripe, Linear, Raycast — draws them as a quiet tint of the surface
    /// they sit on and nothing more. The hint belongs to the control; it
    /// should not compete with it.
    /// `.onDark` means "on the panel", `.onLight` means "on a primary-filled
    /// button" — which is itself the inverse of the appearance. So the panel
    /// tone flips with the system and the button tone flips against it, and
    /// both stay readable in Light and Dark.
    private var capFill: Color {
        tone == .onLight ? DSColor.primaryText.opacity(0.14)
                         : Color.dynamicOverlay(light: 0.08, dark: 0.10)
    }
    private var label: Color {
        tone == .onLight ? DSColor.primaryText.opacity(0.75)
                         : DSColor.textPrimary.opacity(0.80)
    }

    /// "⌘↩" is TWO keys, so it draws as two caps. One wide cap containing
    /// both glyphs is the thing that looked homemade — and at 9pt a pair of
    /// symbols crammed into one box is genuinely hard to read.
    private var keys: [String] { text.map(String.init) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(label)
                    // Symbol glyphs (⌘ ⇧ ⌥ ↩) have wildly different widths;
                    // a floor keeps a row of caps from jittering.
                    .frame(minWidth: size + 3)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(capFill)
                    )
            }
        }
    }
}

/// A keycap for a NAMED key — Tab, Esc, Space.
///
/// `Keycap` draws one cap per CHARACTER, deliberately, because "⌘↩" is two
/// keys. That makes it exactly wrong for a word: "tab" came out as three
/// separate caps reading t · a · b, which "looks like you need to press a
/// combination of 3 different keys at the same time" (Marcello, 2026-08-16).
///
/// A named key is ONE key, so it gets one cap wide enough to hold its name —
/// outlined rather than filled, which is how Raycast draws the same hint and
/// reads as a key rather than as a chip.
struct WordKeycap: View {
    let text: String
    var size: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(DSColor.textPrimary.opacity(0.80))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.dynamicOverlay(light: 0.22, dark: 0.20),
                                  lineWidth: 1)
            )
    }
}

// MARK: - Reusable component: Shortcut hint badge

struct ShortcutHintBadge: View {
    let text: String

    var body: some View {
        // One keycap implementation for the whole app.
        Keycap(text: text, tone: .onDark, size: 9)
    }
}

// MARK: - Reusable component: Combo box row (creation flow)

/// Used for BOTH category and urgency selection in the creation flow.
/// Category swatch is a rounded square; urgency swatch is a circle —
/// this shape difference is intentional, see Section 3.2 of
/// notchsnap_design_reference_prd.md. Do not standardize the two to one shape.
struct ComboBoxRow: View {
    enum SwatchShape { case roundedSquare, circle }

    let label: String
    let swatchColor: Color
    let swatchShape: SwatchShape
    let cycleShortcutHint: String
    /// Urgency/entity PRD §1.4: the creation flow's urgency swatch is 11px —
    /// the one place urgency is the row's primary subject.
    var swatchDiameter: CGFloat = 10

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                swatch
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(DSColor.textPrimaryBright)
            }
            Spacer()
            ShortcutHintBadge(text: cycleShortcutHint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DSColor.fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .stroke(DSColor.panelBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous))
    }

    @ViewBuilder
    private var swatch: some View {
        switch swatchShape {
        case .roundedSquare:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatchColor)
                .frame(width: swatchDiameter, height: swatchDiameter)
        case .circle:
            Circle()
                .fill(swatchColor)
                .frame(width: swatchDiameter, height: swatchDiameter)
        }
    }
}

// MARK: - Reusable component: Primary action button (Create, etc.)

/// A capsule, like every other action in the app and like macOS 26's own push
/// buttons. It used to be a rounded rectangle while Join was a capsule — the
/// same control in two shapes (Marcello, 2026-07-26).
struct PrimaryActionButton: View {
    let title: String
    let shortcutHint: String
    /// Filled by default; `false` gives the outlined secondary treatment, so
    /// Cancel/Snooze pair with a filled primary instead of inventing a style.
    var isProminent: Bool = true
    /// Form buttons span the panel; a button sitting inline next to other
    /// content (Join, on a meeting card) hugs its label instead.
    var fillsWidth: Bool = true
    /// Inline buttons are smaller so they sit inside a card without dominating.
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(isCompact ? .system(size: 11, weight: .medium) : DSFont.buttonLabel)
                .foregroundColor(isProminent ? DSColor.primaryText : DSColor.textSecondary)
            if !shortcutHint.isEmpty {
                // The shortcut lives ON the control, so the keyboard path is
                // discoverable without opening the reference sheet.
                Keycap(text: shortcutHint,
                       tone: isProminent ? .onLight : .onDark,
                       size: isCompact ? 9 : 10)
            }
        }
        .padding(.horizontal, fillsWidth ? 0 : (isCompact ? 12 : 16))
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .padding(.vertical, isCompact ? 5 : 9)
        .background(isProminent ? DSColor.primaryFill : Color.clear)
        .overlay(
            DSShape.action.strokeBorder(isProminent ? .clear : DSColor.panelBorder,
                                        lineWidth: 1)
        )
        .clipShape(DSShape.action)
    }
}

// MARK: - Reusable component: Category color-picker swatch (Section 4 form)

struct ColorSwatchButton: View {
    let color: Color
    let isSelected: Bool
    /// Explicit size: `aspectRatio(.fit)` alone collapsed these to a few
    /// points inside an HStack (nothing proposed a size), which made them
    /// "super small and not selectable" (Marcello, 2026-07-23). A concrete
    /// frame gives both a comfortable hit target and a visible swatch.
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? DSColor.selectionRing : DSColor.panelBorder,
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DSColor.primaryText)
                }
            }
            // Lift the selected swatch slightly so the choice reads at a glance.
            .scaleEffect(isSelected ? 1.0 : 0.92)
            .shadow(color: DSColor.shadowSoft.opacity(isSelected ? 1 : 0), radius: 4, y: 1)
            // Selection is NEVER implied by position alone — always pair
            // the border + checkmark, per CT-6 in notchsnap_todo_pivot_prd.md.
    }
}

// MARK: - Addendum: urgency clarity & inline entity highlighting
// (notchsnap_urgency_entity_prd.md §3 — supplied by Marcello 2026-07-14.
// Adapted in two flagged ways: labels route through L10n/TodoUrgency.fullLabel
// because the app ships EN+IT tables, and the native .help() tooltip was
// replaced by UrgencyTooltip per Marcello's answer to the §4 open question —
// hover AND keyboard focus, immediate, no system delay.)

// MARK: Urgency dot (§1)

enum DSUrgencyDot {
    static let diameter: CGFloat = 9
    static let creationFlowSwatchDiameter: CGFloat = 11
}

struct UrgencyDot: View {
    let urgency: TodoUrgency
    /// Reports hover on the DOT ITSELF. The tooltip used to key off the row's
    /// hover, so pointing anywhere on a to-do popped "Medium priority" — an
    /// explanation nobody asked for (Marcello, 2026-07-26). UG-2 always meant
    /// the dot.
    var onHover: ((Bool) -> Void)? = nil

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: DSUrgencyDot.diameter, height: DSUrgencyDot.diameter)
            // A 9pt circle is a small target; pad the hit area without
            // changing the layout so the tooltip isn't a pixel hunt.
            .contentShape(Circle().inset(by: -4))
            .onHover { onHover?($0) }
    }

    private var color: Color {
        switch urgency {
        case .low: return DSColor.urgencyLow.opacity(0.5) // UG-5: rows skip Low entirely
        case .medium: return DSColor.urgencyMedium
        case .high: return DSColor.urgencyHigh
        }
    }
}

/// §1.4 tooltip: dark bubble with a pointer, shown immediately on row
/// hover/keyboard focus near the dot — never by default (UG-2/UG-3).
struct UrgencyTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(DSColor.textPrimaryBright)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DSColor.divider)   // #2A2A2A per mockup
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DSColor.hairlineOnPanel, lineWidth: 0.5)
            )
            .overlay(alignment: .bottom) {
                // Pointer: the rotated-square trick from the mockup.
                Rectangle()
                    .fill(DSColor.divider)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
                    .offset(y: 3.5)
            }
            .shadow(color: DSColor.shadowStrong, radius: 6, y: 2)
            .fixedSize()
    }
}

// MARK: Inline entity chips (§2)

enum EntityKind {
    case link, date, mention, code, channel
}

enum DSEntityChip {
    static func background(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return Color(hex: "#1A2733")
        case .date: return Color(hex: "#231F14")
        case .mention: return Color(hex: "#2A1F33")
        // Code sits on a warm dark ground rather than neutral grey — the
        // orange-on-dark convention Slack, Jira and every code review tool
        // share, which is what makes a snippet findable by scanning rather
        // than reading (Marcello's tester, 2026-08-10).
        case .code: return Color(hex: "#2A1A14")
        case .channel: return Color(hex: "#14262A")
        }
    }

    static func border(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return Color(hex: "#2F4A5C")
        case .date: return Color(hex: "#4A3F22")
        case .mention: return Color(hex: "#493459")
        case .code: return Color(hex: "#5C3524")
        case .channel: return Color(hex: "#245259")
        }
    }

    static func text(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return DSColor.CategoryPalette.blue
        case .date: return DSColor.CategoryPalette.amber
        case .mention: return DSColor.CategoryPalette.purple
        case .code: return Color(hex: "#E8905C")
        case .channel: return Color(hex: "#5CC5D6")
        }
    }

    static func sfSymbol(for kind: EntityKind) -> String? {
        switch kind {
        case .link: return "link"
        case .date: return "calendar"
        case .mention: return "at"
        case .code: return nil // monospace font is the signal, no icon
        case .channel: return "number"
        }
    }

    /// Code is the one kind whose glyph shapes carry meaning — brackets,
    /// underscores and `l` vs `1` have to be unambiguous — so it renders
    /// monospaced while every other chip stays in the UI face.
    static func isMonospaced(_ kind: EntityKind) -> Bool { kind == .code }
}

// NOTE: this SwiftUI view is a visual reference for a SINGLE chip's styling.
// It cannot be dropped into a Text concatenation to achieve inline flow —
// see §2.3 of the urgency/entity PRD. EntityTitleView's NSTextAttachment
// renderer reproduces these exact metrics.
struct EntityChipReference: View {
    let kind: EntityKind
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = DSEntityChip.sfSymbol(for: kind) {
                Image(systemName: symbol).font(.system(size: 10))
            }
            Text(label)
                .font(kind == .code ? .system(size: 12, design: .monospaced) : .system(size: 12))
        }
        .foregroundColor(DSEntityChip.text(for: kind))
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(DSEntityChip.background(for: kind))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(DSEntityChip.border(for: kind), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Attendee avatars (calendar PRD §3.3, AV-4..6)
//
// Replaces the "with Rose, Wessel" text line and the colored accent stripe —
// the stripe-plus-text layout is exactly what read as generic/AI-templated
// (Marcello, 2026-07-25). A real avatar stack is the product signal.
//
// NOTE on AV-5: profile photos would come from the Google Calendar API. The
// EventKit provider has no access to attendee photos, so this renders the
// initial-based fallback on every avatar today. `imageURL` is the seam for
// photos once a Google OAuth provider exists — never a person-outline glyph.

struct AttendeeAvatar: View {
    let name: String
    /// Used to resolve a real photo from Contacts; nil ⇒ initial only.
    var email: String? = nil
    var diameter: CGFloat = 24
    /// Dim non-urgent rows without changing the layout (Today's later events).
    var isMuted: Bool = false
    /// Ring colour — matches whatever surface the avatar sits on, so an
    /// overlapping stack reads as separate discs.
    var ringColor: Color = DSColor.fieldBackground

    @ObservedObject private var photos = AttendeePhotoStore.shared

    /// Separator width between overlapping discs.
    private var ringWidth: CGFloat { diameter > 20 ? 2 : 1.5 }

    var body: some View {
        Group {
            if let email, let image = photos.photo(for: email) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .opacity(isMuted ? 0.65 : 1)
            } else {
                // Prefer the contact's real name for the initial — an
                // address-only attendee would otherwise read as its domain.
                let display = email.flatMap { photos.name(for: $0) } ?? name
                let tone = Self.tone(for: display)
                Circle()
                    .fill(tone.background.opacity(isMuted ? 0.55 : 1))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        // Proportions from Marcello's spec: a 14pt letter on a
                        // 32pt disc, medium weight, line-height 100%.
                        Text(Self.initial(for: display))
                            .font(.system(size: diameter * 0.4375, weight: .medium))
                            .foregroundStyle(tone.foreground.opacity(isMuted ? 0.7 : 1))
                    )
            }
        }
        // Inside the edge, under the ring: a pale disc or a light photo would
        // otherwise dissolve into whatever sits behind it.
        .overlay(
            Circle().strokeBorder(DSColor.AvatarPalette.innerStroke, lineWidth: 1)
        )
        // The separator sits OUTSIDE the disc rather than on top of it, so it
        // cannot eat into the artwork or hide the hairline above. Drawn as a
        // background it adds no layout size — neighbours still overlap by the
        // stack's own ratio.
        .background(
            Circle()
                .fill(ringColor)
                .frame(width: diameter + ringWidth * 2,
                       height: diameter + ringWidth * 2)
        )
    }

    static func initial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Emails ("rose@x.com") should key off the local part, not the "@".
        let base = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        guard let first = base.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    /// AV-5: stable per-person tone from the pastel avatar family.
    /// Hash is computed by hand — Swift's `hashValue` is randomly seeded per
    /// process, so a person's colour would change on every launch.
    static func tone(for name: String) -> DSColor.AvatarPalette.Tone {
        let palette = DSColor.AvatarPalette.all
        var hash: UInt64 = 5381
        for byte in name.lowercased().utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

/// AV-6: overlapping stack, capped, with a "+N" disc for the remainder.
// MARK: - AccountAvatar — the signed-in user, wherever they are shown
//
// One implementation for the onboarding sign-in screen and the notch's tab
// row, so the face in the corner and the face in onboarding can never be two
// different treatments of the same person.
//
// Falls back to the first letter of the address on the same pastel tones the
// attendee avatars use — a signed-out user gets a neutral glyph rather than a
// stock silhouette.
struct AccountAvatar: View {
    /// nil ⇒ nobody is signed in.
    var email: String?
    var diameter: CGFloat = 20

    @ObservedObject private var photos = AttendeePhotoStore.shared

    var body: some View {
        Group {
            if let email, let image = photos.photo(for: email) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else if let email, !email.isEmpty {
                let tone = AttendeeAvatar.tone(for: email)
                Circle()
                    .fill(tone.background)
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Text(AttendeeAvatar.initial(for: email))
                            .font(.system(size: diameter * 0.4375, weight: .medium))
                            .foregroundStyle(tone.foreground)
                    )
            } else {
                Circle()
                    .fill(DSColor.placeholderFill)
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: diameter * 0.46))
                            .foregroundStyle(DSColor.textSecondary)
                    )
            }
        }
        .overlay(Circle().strokeBorder(DSColor.AvatarPalette.innerStroke, lineWidth: 1))
    }
}

struct AvatarStack: View {
    let names: [String]
    /// Parallel to `names` where known — drives the Contacts photo lookup.
    var emails: [String] = []
    var diameter: CGFloat = 24
    var maxVisible: Int = 3
    var isMuted: Bool = false
    var ringColor: Color = DSColor.fieldBackground

    /// How far each disc slides under the previous one. 0.42 buried the
    /// initial of every avatar but the last — legible only when every
    /// attendee happens to have a Contacts photo.
    var overlapRatio: CGFloat = 0.30
    private var overlap: CGFloat { diameter * overlapRatio }

    var body: some View {
        // Kick off (idempotent) photo resolution for whoever is on screen.
        let _ = AttendeePhotoStore.shared.prefetch(emails: emails)
        let shown = Array(names.prefix(maxVisible))
        let extra = names.count - shown.count
        HStack(spacing: -overlap) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                AttendeeAvatar(name: name,
                               email: index < emails.count ? emails[index] : nil,
                               diameter: diameter,
                               isMuted: isMuted, ringColor: ringColor)
            }
            if extra > 0 {
                // Deliberately NOT pastel: this disc is a count, not a person,
                // and the dark ground is what separates "and 3 more" from the
                // faces beside it.
                Circle()
                    .fill(Color(hex: "#3A3A3A"))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        // Same ratio as an initial — it used to be smaller
                        // (0.34) to make room for two glyphs, which just made
                        // the count unreadable (Marcello, 2026-07-26). A big
                        // overflow ("+57") shrinks to fit instead of forcing
                        // every count to be tiny.
                        Text("+\(extra)")
                            .font(.system(size: diameter * 0.40, weight: .semibold))
                            .foregroundStyle(DSColor.textPrimaryBright)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, diameter * 0.1)
                    )
                    .overlay(
                        Circle().strokeBorder(DSColor.AvatarPalette.innerStroke, lineWidth: 1)
                    )
                    .background(
                        Circle()
                            .fill(ringColor)
                            .frame(width: diameter + (diameter > 20 ? 4 : 3),
                                   height: diameter + (diameter > 20 ? 4 : 3))
                    )
            }
        }
    }
}
