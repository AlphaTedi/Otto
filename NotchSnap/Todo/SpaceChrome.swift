import AppKit
import SwiftUI

// MARK: - Space chrome — the capture header, the context bar and the gear
//
// Everything in here is FURNITURE around the list: the light behind it, the
// field above it, the rim and the settings button. Rows, checkboxes and steps
// are not touched by any of it (U5 §8) — colour is ambient, never on content.

// MARK: Ink

/// The reference is drawn on the dark panel, in white at fixed strengths. The
/// floating panel follows the system appearance, so the same strengths are
/// taken from black in light mode — otherwise the field would go invisible.
enum SpaceInk {
    static func a(_ alpha: Double) -> Color { Color.dynamicOverlay(light: alpha, dark: alpha) }
}

// MARK: Corner geometry

enum SpaceChrome {
    /// Everything in a corner — the Back key, the gear, the note's toolbar —
    /// sits this far from BOTH edges it is near (Marcello, 2026-09-25).
    static let cornerInset: CGFloat = 16
    /// Radius for corner furniture: the window's minus the inset.
    static var cornerRadius: CGFloat { LabMetrics.blockRadius - cornerInset }
    /// The leading slot (dot or Back): 16 + 30 puts its centre on the
    /// checkbox column (22 + 9) and, with the 7 gap, the text at 53 — where
    /// every to-do title starts.
    static let slotWidth: CGFloat = 30
    static let slotGap: CGFloat = 7
    /// THE list column: every row container — a to-do, a note — starts this
    /// far from the window's edge, and its content 12 further in (22), on the
    /// checkbox column. One token, so no list corrects itself with its own
    /// offset (2026-09-25 spec).
    static let columnInset: CGFloat = 10
    /// Where text starts after the leading slot — the capture field's text,
    /// a page title after Back, a note's body and meeting metadata: 53.
    static var textColumn: CGFloat { cornerInset + slotWidth + slotGap }
}

// MARK: Capture header (U5 §4) — floating panels only

/// The borderless, Raycast-style capture field: a space dot, the text, and a
/// trailing "Save to <Space> ↵" once something is typed. Nothing trails the
/// empty field any more: ⇥ still switches space, it just is not spelled out
/// (Notes/Meetings dropdown PRD, 2026-09-26). 60 pt tall whatever state it is in, with a
/// hairline under it across the whole panel.
///
/// Shared by the to-do field and the Notes composer; each brings its own text
/// view, since one is an NSTextView with inline date colouring and the other
/// a multi-line TextField.
struct CaptureHeader<Field: View>: View {
    let tint: SpaceTint
    let placeholder: String
    /// Nothing at all in the field — the placeholder shows.
    let showsPlaceholder: Bool
    /// Something other than whitespace — "Save to …" appears.
    let isTyping: Bool
    /// "Save to Work" — nil when the space has nothing to save (Calendar).
    let saveLabel: String?
    let onSave: () -> Void
    let onDot: () -> Void
    /// A control that belongs to the space (the Notes · Meetings dropdown),
    /// trailing the field.
    var accessory: AnyView? = nil
    @ViewBuilder let field: Field

    static var height: CGFloat { 60 }

    var body: some View {
        HStack(alignment: .center, spacing: SpaceChrome.slotGap) {
            SpaceDot(tint: tint, action: onDot)
            ZStack(alignment: .leading) {
                if showsPlaceholder {
                    Text(placeholder)
                        .font(.system(size: 18))
                        .foregroundStyle(SpaceInk.a(0.40))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                field
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let accessory { accessory }
            trailing
        }
        .padding(.horizontal, SpaceChrome.cornerInset)
        .padding(.vertical, 8)
        .frame(minHeight: Self.height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpaceInk.a(0.08)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        ZStack(alignment: .trailing) {
            if isTyping, let saveLabel {
                SaveButton(label: saveLabel, action: onSave)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isTyping)
    }
}

/// The 9-pt space dot in an 18-pt slot — the checkbox column's width, so its
/// centre lines up with every checkbox below it.
private struct SpaceDot: View {
    let tint: SpaceTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The destination, in the section colour — the same colour as the
            // active pill and this section's checkboxes.
            Circle()
                .fill(tint.sectionColor)
                .frame(width: 9, height: 9)
                .shadow(color: tint.base.color.opacity(0.6), radius: 4)
                // The same slot the Back key takes one level in, so the dot
                // sits on the checkbox column and the bar does not move.
                .frame(width: SpaceChrome.slotWidth, height: 28)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.2), value: tint)
        }
        .buttonStyle(.plain)
        .help(L10n.t("todo.switchSpace"))
        .accessibilityLabel(L10n.t("todo.switchSpace"))
    }
}

/// The generic key hint: 1-pt border at 22%, 10.5 pt at 60% (U5 §4.1).
struct CaptureKeyHint: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 10.5))
            .foregroundStyle(SpaceInk.a(0.6))
            // Content-box, as the reference renders it: 18 of content, 5 of
            // padding each side, then the border.
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 5)
            .padding(1)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(SpaceInk.a(0.22), lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// "Save to Work" + a filled white ↵ cap; on hover the label brightens and the
/// cap takes a soft violet glow (U5 §4.2, `02b`).
private struct SaveButton: View {
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SpaceInk.a(hover ? 1 : 0.72))
                    .lineLimit(1)
                Text("\u{21B5}")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(hex: "#111111"))
                    .frame(minWidth: 22, minHeight: 20)
                    .padding(.horizontal, 5)
                    .padding(1)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hover ? Color.white : Color(hex: "#F2F1F5")))
                    .shadow(color: Color(hex: "#B69CFF").opacity(hover ? 0.55 : 0), radius: 6)
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.2)) { hover = hovering } }
        .accessibilityLabel(label + ", Return")
    }
}

// MARK: Context bar — the same bar, one level in (top-navigation spec)

/// The top bar inside a page: Back where the destination circle was, then the
/// page's title, on the capture header's exact geometry (60 pt, 22 at the
/// sides, hairline under it) so moving between levels never moves the bar.
struct ContextBar<Title: View, Trailing: View>: View {
    /// Where Back goes — spoken, since the button itself is an arrow.
    let parentTitle: String
    let onBack: () -> Void
    @ViewBuilder let title: Title
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: SpaceChrome.slotGap) {
            BackChip(parentTitle: parentTitle, action: onBack)
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            trailing
        }
        .padding(.horizontal, SpaceChrome.cornerInset)
        .padding(.vertical, 8)
        .frame(minHeight: CaptureHeader<EmptyView>.height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpaceInk.a(0.08)).frame(height: 1)
        }
    }
}

extension ContextBar where Title == Text, Trailing == EmptyView {
    /// A read-only page title.
    init(parentTitle: String, title: String, onBack: @escaping () -> Void) {
        self.init(parentTitle: parentTitle, onBack: onBack,
                  title: { Text(title).font(.system(size: 18, weight: .medium))
                                .foregroundColor(SpaceInk.a(1)) },
                  trailing: { EmptyView() })
    }
}

/// Raycast's back control: a small rounded key with an arrow.
private struct BackChip: View {
    let parentTitle: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpaceInk.a(0.85))
                .frame(width: SpaceChrome.slotWidth, height: 28)
                // 24 − 16: concentric with the window's corner.
                .background(RoundedRectangle(cornerRadius: SpaceChrome.cornerRadius, style: .continuous)
                    .fill(SpaceInk.a(hover ? 0.14 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hoverFade) { hover = hovering } }
        .help(String(format: L10n.t("nav.backTo"), parentTitle) + "  (Esc)")
        .accessibilityLabel(String(format: L10n.t("nav.backTo"), parentTitle))
    }
}

/// The page title as the bar shows it.
extension Text {
    func contextTitleStyle() -> some View {
        font(.system(size: 18, weight: .medium))
            .foregroundStyle(SpaceInk.a(1))
            .lineLimit(1)
    }
}

// MARK: Settings (U5 §5.2)

/// A 34-pt gear circle where the avatar was. No shortcut is printed; ⌘, still
/// opens Settings. It opens the same menu the avatar did — Preferences,
/// Insights, the shortcuts, the notes folder and Quit all live there.
struct SettingsGearButton: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    var body: some View {
        Button {
            if store.showsAvatarMenu { store.closeAvatarMenu() } else { store.openAvatarMenu() }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SpaceInk.a(0.75))
                .frame(width: 34, height: 34)
                .background(Circle().fill(SpaceInk.a(hover || store.showsAvatarMenu ? 0.12 : 0.07)))
                .overlay(Circle().strokeBorder(SpaceInk.a(0.10), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hoverFade) { hover = hovering } }
        .help(L10n.t("settings.open"))
        .accessibilityLabel(L10n.t("settings.open"))
    }
}

// MARK: The to-do capture header (floating panels)

private struct CaptureFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The floating panels' to-do field. Same store, same keys and the same
/// NSTextView (with its inline date colouring) as the container's draft row;
/// only the chrome is U5's.
struct TodoCaptureHeader: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var fieldWidth: CGFloat = 0

    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }
    private var isTyping: Bool {
        !store.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Driven from here, where `draftTitle` is observed: an NSViewRepresentable
    /// is not re-measured on a pure content change (see InlineDraftRow).
    private var fieldHeight: CGFloat {
        let width = fieldWidth > 0 ? fieldWidth : 360
        let text = store.draftTitle.isEmpty ? " " : store.draftTitle
        let measured = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        return max(HighlightingTitleField.lineHeight(18),
                   min(ceil(measured), HighlightingTitleField.maxHeight))
    }

    var body: some View {
        CaptureHeader(
            tint: store.draftSpaceTint,
            placeholder: L10n.t("capture.placeholder"),
            showsPlaceholder: store.draftTitle.isEmpty,
            isTyping: isTyping,
            saveLabel: String(format: L10n.t("capture.saveTo"), store.draftDestination?.name ?? ""),
            onSave: { store.commitDraft() },
            onDot: { store.cycleCollection() }
        ) {
            HighlightingTitleField(
                text: $store.draftTitle,
                highlightRange: parsed?.nsRange,
                // Caret and selection in the destination's section colour.
                accent: store.draftSpaceTint.sectionColor,
                wantsFocus: store.draftWantsFocus,
                onFocusChange: { focused in
                    store.draftFocused = focused
                    if focused { store.draftWantsFocus = false }
                },
                fontSize: 18
            )
            .frame(height: fieldHeight)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CaptureFieldWidthKey.self, value: proxy.size.width)
            })
            .onPreferenceChange(CaptureFieldWidthKey.self) { fieldWidth = $0 }
        }
        // The resolved date sits in the header's own foot room, so typing
        // "tomorrow" never changes the header's 60 pt.
        .overlay(alignment: .bottomLeading) {
            if let parsed {
                Text("\u{2192} \(parsed.display)")
                    .font(.system(size: 10))
                    .foregroundStyle(SpaceInk.a(0.45))
                    .padding(.leading, SpaceChrome.cornerInset + SpaceChrome.slotWidth + SpaceChrome.slotGap)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.draftWantsFocus = true }
    }
}
