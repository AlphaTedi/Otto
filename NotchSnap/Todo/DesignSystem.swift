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

enum DSColor {
    // Panel & structure
    static let panelBackground = Color(hex: "#111111")
    static let outerBackground = Color(hex: "#000000")
    static let panelBorder = Color(hex: "#333333")
    static let divider = Color(hex: "#2A2A2A")
    static let dividerSubtle = Color(hex: "#222222")

    // Text
    static let textPrimary = Color(hex: "#E5E5E5")
    static let textPrimaryBright = Color(hex: "#EEEEEE")
    static let textSecondary = Color(hex: "#888888")
    static let textMuted = Color(hex: "#777777")
    static let textFaint = Color(hex: "#666666")
    static let textHint = Color(hex: "#555555")

    // Interactive / focus
    static let focusAccent = Color(hex: "#4A9EFF")
    static let fieldBackground = Color(hex: "#1A1A1A")
    static let focusedRowBackground = Color(hex: "#1C1C1C")

    // Primary action (Create button etc.)
    static let primaryFill = Color(hex: "#EEEEEE")
    static let primaryText = Color(hex: "#111111")

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
    static let todoTitleSize: CGFloat = 13
    static let todoTitle: Font = .system(size: todoTitleSize)
    static let tabLabel: Font = .system(size: 11)
    static let sectionLabel: Font = .system(size: 10, weight: .regular)
    static let hint: Font = .system(size: 9)
    static let checklistItem: Font = .system(size: 11)
    static let buttonLabel: Font = .system(size: 12, weight: .medium)
}

enum DSAnimation {
    // The one primary spring used for height changes, row enter/exit,
    // Completed section expand/collapse, tab switches, and progress-ring
    // fill changes. See notchsnap_todo_pivot_prd.md Section 8.2.
    static let primary: Animation = .interpolatingSpring(mass: 1, stiffness: 170, damping: 20)
    // Rough SwiftUI equivalent of response: 0.45, dampingFraction: 0.60 —
    // tune numerically against a real build rather than trusting this
    // conversion blindly; the important part is reusing ONE spring
    // definition everywhere rather than ad hoc values per view.

    // Secondary, faster transitions: contextual hint fade, modifier-held
    // badge reveal. Never use the primary spring for these.
    static let secondary: Animation = .easeOut(duration: 0.18)
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
    let numberBadge: Int?           // shown only while a modifier key is held

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(DSFont.tabLabel)
                .foregroundColor(isActive ? DSColor.primaryText : DSColor.textSecondary)

            if let remaining {
                if remaining == 0 {
                    // Nothing left — a quiet "all clear", not a zero.
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isActive ? DSColor.primaryText.opacity(0.55)
                                                  : DSColor.textFaint)
                } else {
                    Text("\(remaining)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(isActive ? DSColor.primaryText.opacity(0.75)
                                                  : DSColor.textFaint)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(isActive ? categoryColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let numberBadge {
                Text("\(numberBadge)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(isActive ? DSColor.primaryText : Color(hex: "#AAAAAA"))
                    .padding(.horizontal, 3)
                    .background(isActive ? DSColor.primaryFill : Color(hex: "#333333"))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .offset(x: 6, y: -8)
                    .transition(.opacity)
            }
        }
        .animation(DSAnimation.secondary, value: numberBadge)
    }
}

/// The dedicated "+" creation tab — always present, no category color of
/// its own. See Section 6.1 of notchsnap_todo_pivot_prd.md.
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
        .animation(DSAnimation.primary, value: progress)
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

    private var cap: Color {
        tone == .onLight ? Color.black.opacity(0.10) : Color.white.opacity(0.13)
    }
    private var label: Color {
        tone == .onLight ? DSColor.primaryText : DSColor.textPrimaryBright
    }
    private var topEdge: Color {
        tone == .onLight ? Color.white.opacity(0.85) : Color.white.opacity(0.22)
    }
    private var bottomEdge: Color {
        tone == .onLight ? Color.black.opacity(0.22) : Color.black.opacity(0.55)
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            // Symbol glyphs (⌘ ⇧ ⌥ ↩) have wildly different widths; tabular
            // spacing keeps a row of caps from jittering.
            .monospacedDigit()
            .foregroundStyle(label)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: size + 6)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(cap)
            )
            .overlay(
                // Top highlight + bottom shade, drawn as one stroke gradient:
                // the cheap way to get a lit edge and a grounded one.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [topEdge, bottomEdge],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: bottomEdge.opacity(0.5), radius: 0, y: 0.5)
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
                    .stroke(isSelected ? Color.white : DSColor.panelBorder,
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
            .shadow(color: .black.opacity(isSelected ? 0.35 : 0), radius: 4, y: 1)
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
                    .stroke(Color(hex: "#444444"), lineWidth: 0.5)
            )
            .overlay(alignment: .bottom) {
                // Pointer: the rotated-square trick from the mockup.
                Rectangle()
                    .fill(DSColor.divider)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
                    .offset(y: 3.5)
            }
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .fixedSize()
    }
}

// MARK: Inline entity chips (§2)

enum EntityKind {
    case link, date, mention, code
}

enum DSEntityChip {
    static func background(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return Color(hex: "#1A2733")
        case .date: return Color(hex: "#231F14")
        case .mention: return Color(hex: "#2A1F33")
        case .code: return Color(hex: "#1C1C1C")
        }
    }

    static func border(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return Color(hex: "#2F4A5C")
        case .date: return Color(hex: "#4A3F22")
        case .mention: return Color(hex: "#493459")
        case .code: return Color(hex: "#3A3A3A")
        }
    }

    static func text(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return DSColor.CategoryPalette.blue
        case .date: return DSColor.CategoryPalette.amber
        case .mention: return DSColor.CategoryPalette.purple
        case .code: return Color(hex: "#BBBBBB")
        }
    }

    static func sfSymbol(for kind: EntityKind) -> String? {
        switch kind {
        case .link: return "link"
        case .date: return "calendar"
        case .mention: return "at"
        case .code: return nil // monospace font is the signal, no icon
        }
    }
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
                Circle()
                    .fill(Self.color(for: display).opacity(isMuted ? 0.55 : 1))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Text(Self.initial(for: display))
                            .font(.system(size: diameter * 0.42, weight: .bold))
                            .foregroundStyle(Color(hex: "#111111"))
                    )
            }
        }
        .overlay(
            Circle().strokeBorder(ringColor, lineWidth: diameter > 20 ? 2 : 1.5)
        )
    }

    static func initial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Emails ("rose@x.com") should key off the local part, not the "@".
        let base = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        guard let first = base.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    /// AV-5: stable per-person colour from the category palette family.
    /// Hash is computed by hand — Swift's `hashValue` is randomly seeded per
    /// process, so a person's colour would change on every launch.
    static func color(for name: String) -> Color {
        let palette = DSColor.CategoryPalette.all
        var hash: UInt64 = 5381
        for byte in name.lowercased().utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

/// AV-6: overlapping stack, capped, with a "+N" disc for the remainder.
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
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: diameter > 20 ? 2 : 1.5))
            }
        }
    }
}
