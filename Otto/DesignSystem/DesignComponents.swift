import SwiftUI

// Reusable SwiftUI components built on the tokens in DesignTokens.swift.
// Use these rather than re-specifying a chip, keycap or button inline.

// MARK: - Reusable component: Space pill

/// A space in the floating panels' tab row — a section, or Notes. Only the
/// ACTIVE pill is drawn in its colour; inactive pills are always neutral, with
/// the shared hover wash (TD-9 / TD-2 in the to-do pivot PRD — this is not
/// optional styling, it's a functional requirement).
///
/// One component for every space (2026-11-08): Notes had its own copy with a
/// different text colour on the fill.
struct SpacePill: View {
    let title: String
    /// The fill while active: the space's own colour.
    let fill: Color
    let isActive: Bool
    /// The number after the title. nil = no number at all.
    let count: Int?
    /// A count of 0 reads as "all clear" — a quiet ✓ — for a to-do section.
    /// Notes show their 0 as a number.
    var zeroIsDone = true
    /// The tab row uses `.sm` (28). Bigger pills are for roomier pickers.
    var size: DSControlSize = .sm

    /// The lists had NO hover state at all, so the only chip in the bar that
    /// answered the pointer was the one already selected (Marcello, 2026-09-06).
    @State private var hover = false
    @Environment(\.dsPalette) private var palette

    /// Text on the space-coloured fill: dark on the light tone (dark mode),
    /// white on the deepened one (light mode).
    private static let onFill = Color.dynamic(light: .white,
                                              dark: NSColor(srgbRed: 0x16 / 255, green: 0x1A / 255,
                                                            blue: 0x24 / 255, alpha: 1))

    private var ink: Color { isActive ? Self.onFill : palette.textPrimary }

    var body: some View {
        HStack(spacing: DSSpace.s) {
            Text(title)
                .font(size == .sm ? DSType.label : size.font.weight(.semibold))
                .foregroundColor(ink)

            if let count {
                if count == 0 && zeroIsDone {
                    // Nothing left — a quiet "all clear", not a zero.
                    OttoIcon("checkmark", pointSize: 9)
                        .foregroundColor(ink)
                        .opacity(0.5)
                } else {
                    Text("\(count)")
                        .font(size == .sm ? DSType.label : size.font.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(ink)
                        .opacity(0.5)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, size == .sm ? DSSpace.xl : size.padding + DSSpace.xxs)
        .frame(height: size.height)
        // Never squeezed: when the lists overflow, the scroller gives way.
        .fixedSize()
        // ONE shape, in every state — a capsule; selection is a fill, not a
        // silhouette (Marcello, 2026-09-06). No glow: the strip scrolls and
        // a scroller clips whatever reaches past it.
        .background(DSShape.action.fill(isActive ? fill : (hover ? palette.controlHover : .clear)))
        .contentShape(DSShape.action)
        .onHover { hover = $0 }
        // No implicit animation on selection: a click animates it (180 ms,
        // at the call site), the keyboard switches instantly (U5 §5.1).
        .animation(Motion.hoverFade, value: hover)
    }
}

// MARK: - Reusable component: Section label

/// A label that heads a group, never a control.
///
///   .caps   — "NEW SECTION", "MOVE TO": 10 pt medium caps, tracked, tertiary
///             ink. Heads a form or a picker.
///   .quiet  — "Completed · 2": 12.5 pt semibold, tertiary. Heads a group
///             INSIDE a list.
struct DSSectionLabel: View {
    enum Style { case caps, quiet }
    let text: String
    var style: Style = .caps
    @Environment(\.dsPalette) private var palette

    var body: some View {
        switch style {
        case .caps:
            Text(text.uppercased())
                .font(DSType.sectionCaps)
                .tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .accessibilityAddTraits(.isHeader)
        case .quiet:
            Text(text)
                .font(DSType.quiet)
                .foregroundStyle(palette.textTertiary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - Reusable component: Field well

extension View {
    /// A text field sunk into the panel: the creation bar's well, one shape
    /// for every field the notch draws (new section, rename, composers).
    /// Padding is the caller's — fields differ in size, not in look.
    func dsFieldWell(radius: CGFloat = DSRadius.bar) -> some View {
        modifier(DSFieldWell(radius: radius))
    }
}

private struct DSFieldWell: ViewModifier {
    let radius: CGFloat
    @Environment(\.dsPalette) private var palette
    func body(content: Content) -> some View {
        content.background(DSShape.squircle(radius).fill(palette.fieldWell))
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

/// `.horizontal` — between two rows (to-dos, notes): a line with a dot on
/// its leading end. `.vertical` — between two pills or dock items: an 18-pt
/// upright capsule.
struct DropIndicator: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal
    var tint: Color = DSColor.textPrimaryBright

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                HStack(spacing: 0) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(tint)
                        .frame(height: 1.5)
                }
                .frame(height: 6)
            case .vertical:
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: 2, height: 18)
            }
        }
        .transition(DSTransition.fade)
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

// MARK: - Reusable component: Key badge (outlined)
//
// The other half of the key vocabulary. `Keycap` is FILLED and sits on a
// control (a button's own shortcut). `KeyBadge` is OUTLINED and sits on the
// panel as a quiet hint beside words: "Switch space  Tab", the ⌘⏎ at the end
// of a focused row, "esc" in a header. There were six hand-drawn copies of
// it (2026-11-08); every outlined key is this one now.
//
//   .row   — 10 pt semibold, text and border one colour (row affordances,
//            footer hints). Fixed 32-pt width for a word key, min 23 for a
//            glyph.
//   .hint  — 10.5 pt regular at 60%, border at 22% (U5 §4.1, the capture
//            header and menus).

struct KeyBadge: View {
    enum Style { case row, hint }
    let text: String
    var style: Style = .row
    /// The ink for `.row`. Ignored by `.hint`, which takes the panel's ink.
    var color: Color = DSColor.textFaint
    var minWidth: CGFloat = 23
    var height: CGFloat = 18

    var body: some View {
        switch style {
        case .row:
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, text.count > 1 ? 5 : 0) // ds-allow: optical key padding
                .frame(minWidth: minWidth, minHeight: height)
                .fixedSize()
                .overlay(DSShape.squircle(DSRadius.keycap).strokeBorder(color, lineWidth: 1))
        case .hint:
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(SpaceInk.a(0.6))
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 5) // ds-allow: content-box, as the reference renders it
                .padding(1)
                .overlay(DSShape.squircle(5).strokeBorder(SpaceInk.a(0.22), lineWidth: 1))
                .fixedSize()
                .accessibilityHidden(true)
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

// MARK: - Progress bar

/// How far a long job has got — an update downloading. `value` 0…1, or nil
/// when it cannot be known: a segment then sweeps across (`Motion.sweep`).
struct DSProgressBar: View {
    var value: Double?
    var tint: Color? = nil
    @State private var sweeping = false
    @Environment(\.dsPalette) private var palette

    var body: some View { inspectedBody }

    private var inspectedBody: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DSColor.divider)
                if let value {
                    Capsule().fill(tint ?? palette.textPrimary)
                        .frame(width: max(DSSpace.xs, width * min(max(value, 0), 1)))
                        .animation(Motion.contentHug, value: value)
                } else {
                    Capsule().fill(tint ?? palette.textPrimary)
                        .frame(width: width * 0.35)
                        .offset(x: Motion.sweep == nil ? width * 0.325 : (sweeping ? width : -width * 0.35))
                        .onAppear {
                            guard let sweep = Motion.sweep else { return }
                            withAnimation(sweep) { sweeping = true }
                        }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: DSSpace.xs)
        .accessibilityElement()
        .accessibilityValue(value.map { "\(Int($0 * 100)) %" } ?? "")
    }
}
