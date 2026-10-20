import SwiftUI
import AppKit

// MARK: - The first row — the B3 dock's input (spec §5.1)
//
// No input card: the list's first row IS where you type, drawn like a to-do
// row so it reads as part of the list. A dashed box in the space colour and a
// grey placeholder at rest; a solid box with a faint fill once it has the
// caret or holds text; a ↵ key while there is something to file.
//
// The field underneath is the same one the container's draft row used
// (HighlightingTitleField): the same store, the same keys (⏎ files, ⇥ walks
// the spaces, Esc clears then closes), inline dates, image chips and drops.

/// The row's chrome, shared by the to-do and the note flavours.
struct DockFirstRowChrome<Leading: View, Field: View>: View {
    /// The caret is in it, or it holds text.
    let isActive: Bool
    /// Something to file: the white ↵ key shows.
    let canSave: Bool
    let onTap: () -> Void
    let onSave: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let field: Field

    var body: some View {
        HStack(alignment: .center, spacing: NotchContainerMetrics.rowGap) {
            leading
            field.frame(maxWidth: .infinity, alignment: .leading)
            if canSave {
                // Just the key, no "Save": the word read as a form's button
                // in a surface that has none (Marcello, 2026-10-17). Clicking
                // it is ⏎.
                DockReturnKey(action: onSave)
                    // The same air on both sides of the key: from the text's
                    // end to the key as from the key to the silhouette's edge
                    // (content inset = frame inset + this row's padding).
                    .padding(.leading, NotchContainerMetrics.contentInset - NotchContainerMetrics.rowGap)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        // The content column (30 from the silhouette): no highlight around
        // the first row, so its box sits where the rows' checkboxes do.
        .padding(.horizontal, NotchContainerMetrics.contentInFrame)
        .frame(minHeight: NotchContainerMetrics.rowMinHeight)
        // The whole row takes the caret, not just the strip of text in it.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.easeOut(duration: 0.15), value: canSave)
    }
}

/// The to-do flavour's box: ALWAYS dashed in the space colour — the mark of
/// the row you type into, at rest and while typing (Marcello, 2026-10-17) —
/// with a faint fill and a fuller stroke once it has the caret or holds text.
struct DockFirstRowBox: View {
    let tint: DockTint
    let isActive: Bool

    var body: some View {
        let side = NotchContainerMetrics.box
        let stroke = NotchContainerMetrics.boxStroke
        let shape = RoundedRectangle(cornerRadius: NotchContainerMetrics.boxRadius, style: .continuous)
        return shape
            .fill(isActive ? tint.firstRowFill : .clear)
            .overlay(EvenDashBox(cornerRadius: NotchContainerMetrics.boxRadius - stroke / 2)
                .stroke(isActive ? tint.base : tint.firstRowStroke,
                        style: EvenDashBox.style(side: side - stroke, radius: NotchContainerMetrics.boxRadius - stroke / 2,
                                                 lineWidth: stroke))
                .padding(stroke / 2))
            .frame(width: side, height: side)
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .animation(.easeInOut(duration: 0.3), value: tint)
    }
}

/// A rounded square drawn from the middle of its top edge, so a dash pattern
/// can be laid on it evenly.
///
/// The old box dashed a stock RoundedRectangle with a fixed [4, 3.2]: the
/// pattern did not divide the perimeter, so the last dash came out short,
/// the gaps differed and the dashes on one side looked longer than on the
/// other (Marcello, 2026-10-17). Here the period divides each QUARTER of the
/// perimeter exactly, and the path starts at a side's middle with the first
/// dash centred on it — so every side and every corner gets the same dashes.
struct EvenDashBox: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }

    /// Two dashes per quarter — one centred on each side, one on each
    /// corner — dash and gap about equal.
    static func style(side: CGFloat, radius: CGFloat, lineWidth: CGFloat) -> StrokeStyle {
        let quarter = (side - 2 * radius) + .pi * radius / 2
        let period = quarter / 2
        let dash = period * 0.52
        return StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                           dash: [dash, period - dash], dashPhase: dash / 2)
    }
}

/// The ↵ keycap that files the first row: white, the glyph in full black.
struct DockReturnKey: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text("\u{21B5}")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(width: 30, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hover ? Color.white : Color(hex: "#F2F1F5")))
                .contentShape(Rectangle())
        }
        .buttonStyle(DockPressStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { hover = hovering } }
        .accessibilityLabel(L10n.t("dock.save") + ", Return")
    }
}

/// The grey placeholder over a field — never tinted.
struct DockPlaceholder: View {
    let text: String
    var font: Font = DSDock.rowTitle
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(DSDock.placeholder)
            .lineLimit(1)
            .allowsHitTesting(false)
    }
}

/// In a list: the to-do being typed.
struct DockTodoFirstRow: View {
    @ObservedObject private var store = TodoStore.shared

    private static let fontSize: CGFloat = 15
    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }
    private var hasText: Bool { !store.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var tint: DockTint { DockTint(store.draftSpaceTint) }

    /// ONE line, always: a long to-do runs on under the caret and the field
    /// scrolls sideways, the floating capture header's way (Marcello,
    /// 2026-10-20: wrapping to a second line pushed the list down).
    private var fieldHeight: CGFloat { HighlightingTitleField.lineHeight(Self.fontSize) }

    private var placeholder: String {
        String(format: L10n.t("dock.addTo"), store.draftDestination?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DockFirstRowChrome(isActive: store.draftFocused || hasText,
                               canSave: hasText,
                               onTap: { store.draftWantsFocus = true },
                               onSave: { store.commitDraft() }) {
                DockFirstRowBox(tint: tint, isActive: store.draftFocused || hasText)
            } field: {
                ZStack(alignment: .leading) {
                    if store.draftTitle.isEmpty { DockPlaceholder(text: placeholder) }
                    HighlightingTitleField(
                        text: $store.draftTitle,
                        highlightRange: parsed?.nsRange,
                        accent: tint.base,
                        wantsFocus: store.draftWantsFocus,
                        onFocusChange: { focused in
                            store.draftFocused = focused
                            if focused { store.draftWantsFocus = false }
                        },
                        fontSize: Self.fontSize,
                        singleLine: true,
                        allowsImages: true
                    )
                    .frame(height: fieldHeight)
                }
            }
            // NL-3: the resolved date follows the caret in grey now
            // (DateCompletion), not on a line under the text.
        }
        .animation(.easeOut(duration: 0.15), value: parsed?.display)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

/// In Notes: a new note's TITLE (final flow 4.9–4.10). A gold dashed box
/// where a checkbox would be, the to-do row's own 15-pt regular; ⏎ or Save makes the note and opens
/// it with the caret in the body (NotesStore.commitTitleDraft).
struct DockNoteFirstRow: View {
    @FocusState.Binding var focused: Bool
    @ObservedObject private var store = NotesStore.shared

    private var hasText: Bool { !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        DockFirstRowChrome(isActive: focused || hasText,
                           canSave: hasText,
                           onTap: { focused = true },
                           onSave: { store.commitTitleDraft() }) {
            // The to-do row's dashed box, in Notes' gold: the same mark
            // for "type here" in every space. The pencil was too big and
            // too loud (Marcello, 2026-10-17).
            DockFirstRowBox(tint: DockTint(.notes), isActive: focused || hasText)
        } field: {
            ZStack(alignment: .leading) {
                if store.draft.isEmpty {
                    DockPlaceholder(text: L10n.t("dock.newNoteTitle"), font: DSDock.noteTitle)
                }
                // The user's text is NEVER reformatted. One line: a title.
                TextField("", text: $store.draft)
                    .textFieldStyle(.plain)
                    .font(DSDock.noteTitle)
                    .foregroundStyle(DSDock.text)
                    .tint(DSDock.notes)
                    .focused($focused)
                    .onChange(of: store.draft) { _ in store.draftChanged() }
            }
        }
        .accessibilityLabel(L10n.t("dock.newNoteTitle"))
    }
}
