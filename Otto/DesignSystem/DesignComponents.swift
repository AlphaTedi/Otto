import SwiftUI

// Reusable SwiftUI components built on the tokens in DesignTokens.swift.
// Use these rather than re-specifying a chip, keycap or button inline.

// MARK: - Reusable component: Category tab chip

/// A single tab in the browsing view's tab row. Only the ACTIVE tab is
/// rendered in its category color — inactive tabs are always neutral.
/// See TD-9 / TD-2 in the to-do pivot PRD — this is not optional
/// styling, it's a functional requirement.
struct CategoryTabChip: View {
    let title: String
    /// The space's tint: the selected fill is its LIGHT colour, the shadow its
    /// base (U5 §5.1, §7).
    let tint: SpaceTint
    let isActive: Bool
    /// How many to-dos are still OPEN in this category. nil = the category is
    /// empty (no indicator at all); 0 = everything done (checkmark).
    ///
    /// This replaces the circular progress ring: a 14pt arc couldn't tell you
    /// how much was left — "I don't understand from that view how much I am
    /// still missing" (Marcello, 2026-07-23). A remaining COUNT answers that
    /// directly, the way Reminders/Things do.
    let remaining: Int?

    /// Whether the pointer is on this chip. The lists had NO hover state at
    /// all, so the only chip in the bar that answered the pointer was the one
    /// already selected — a row of controls that looked inert until clicked
    /// (Marcello, 2026-09-06).
    @State private var hover = false

    /// Text on the section-coloured fill: dark on the light tone (dark mode),
    /// white on the deepened one (light mode).
    private static let onFill = Color.dynamic(light: .white,
                                              dark: NSColor(srgbRed: 0x16 / 255, green: 0x1A / 255,
                                                            blue: 0x24 / 255, alpha: 1))

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isActive ? Self.onFill : DSColor.textPrimary)

            if let remaining {
                if remaining == 0 {
                    // Nothing left — a quiet "all clear", not a zero.
                    OttoIcon("checkmark", pointSize: 9)
                        .foregroundColor(isActive ? Self.onFill : DSColor.textPrimary)
                        .opacity(0.5)
                } else {
                    Text("\(remaining)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(isActive ? Self.onFill : DSColor.textPrimary)
                        .opacity(0.5)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        // ONE shape, in every state — a capsule; selection is a fill, not a
        // silhouette (Marcello, 2026-09-06). Still no matchedGeometryEffect:
        // it resolved frames outside the scroller and cut the first chip.
        .background(
            Capsule(style: .continuous)
                .fill(isActive ? tint.sectionColor
                      : (hover ? DSColor.fieldBackground : Color.clear))
        )
        .clipShape(Capsule(style: .continuous))
        // No glow: the strip scrolls, and a scroller clips whatever reaches
        // past it — the shadow was being cut off square (2026-09-25).
        .contentShape(Capsule(style: .continuous))
        .onHover { hover = $0 }
        // No implicit animation on selection: a click animates it (180 ms,
        // at the call site), the keyboard switches instantly (U5 §5.1).
        .animation(Motion.hoverFade, value: hover)
    }
}

// MARK: - Reusable component: Progress ring (Section 9.2)
//
// RETIRED from the tab row (2026-07-23): at 14pt the arc was unreadable —
// it couldn't answer "how much is left in this category?". CategoryTabChip
// now shows a remaining COUNT instead. Kept here because the type is still
// referenced by the design PRD; use it only where an arc is genuinely legible
// (i.e. considerably larger than the tab chip).

// MARK: - Reusable component: To-do row

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

// MARK: - Reusable component: Shortcut hint badge

struct ShortcutHintBadge: View {
    let text: String

    var body: some View {
        // One keycap implementation for the whole app.
        Keycap(text: text, tone: .onDark, size: 9)
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

// MARK: - Addendum: inline entity highlighting
// (urgency & entity PRD §3 — supplied by Marcello 2026-07-14.
// The urgency half of that PRD is gone — priority was removed entirely on
// 2026-09-14, dot, tooltip, model field and all. What remains is the entity
// half: links, dates, @mentions and code chips.)

// MARK: Inline entity chips (§2)

enum EntityKind {
    case link, date, mention, code, channel
}

enum DSEntityChip {
    /// Light and dark pairs. The chips were dark-only, so on a light panel
    /// every date, link and @name was a near-black lozenge — far louder than
    /// the words around it (Marcello, 2026-10-02). Light mode: a pale wash
    /// of the same hue, a soft edge, and the hue darkened for the text.
    private static func pair(_ light: String, _ dark: String) -> Color {
        .dynamic(light: NSColor(Color(hex: light)), dark: NSColor(Color(hex: dark)))
    }

    static func background(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return pair("#E5EFF8", "#1A2733")
        case .date: return pair("#F7EED5", "#231F14")
        case .mention: return pair("#F1E6F8", "#2A1F33")
        // Code sits on a warm ground rather than neutral grey — the
        // orange-on-dark convention Slack, Jira and every code review tool
        // share, which is what makes a snippet findable by scanning rather
        // than reading (Marcello's tester, 2026-08-10).
        case .code: return pair("#FBE9DE", "#2A1A14")
        case .channel: return pair("#DFF2F4", "#14262A")
        }
    }

    static func border(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return pair("#BDD4E8", "#2F4A5C")
        case .date: return pair("#E5D29A", "#4A3F22")
        case .mention: return pair("#D9C2E9", "#493459")
        case .code: return pair("#EEC3AA", "#5C3524")
        case .channel: return pair("#A8D8DE", "#245259")
        }
    }

    static func text(for kind: EntityKind) -> Color {
        switch kind {
        case .link: return pair("#2B6A9A", "#7FB8E0")
        case .date: return pair("#8A6A0E", "#E8C15A")
        case .mention: return pair("#7A479B", "#C99EE0")
        case .code: return pair("#AD5326", "#E8905C")
        case .channel: return pair("#1F7F8C", "#5CC5D6")
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
