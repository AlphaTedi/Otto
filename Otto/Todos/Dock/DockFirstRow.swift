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
struct DockFirstRowChrome<Field: View>: View {
    let tint: DockTint
    /// The caret is in it, or it holds text: the box turns solid.
    let isActive: Bool
    let showsReturnKey: Bool
    let onTap: () -> Void
    @ViewBuilder let field: Field

    var body: some View {
        HStack(alignment: .center, spacing: NotchContainerMetrics.rowGap) {
            box
            field.frame(maxWidth: .infinity, alignment: .leading)
            if showsReturnKey {
                Text("\u{21B5}")
                    .font(DSDock.keycap)
                    .foregroundStyle(DSDock.text3)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DSDock.keycapBorder, lineWidth: 1))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, NotchContainerMetrics.firstRowInset)
        .frame(minHeight: NotchContainerMetrics.rowMinHeight)
        // The whole row takes the caret, not just the strip of text in it.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .animation(.easeInOut(duration: 0.3), value: tint)
        .animation(.easeOut(duration: 0.15), value: showsReturnKey)
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: NotchContainerMetrics.boxRadius, style: .continuous)
        return shape
            .fill(isActive ? tint.firstRowFill : .clear)
            .overlay(shape.strokeBorder(
                isActive ? tint.base : tint.firstRowStroke,
                style: StrokeStyle(lineWidth: NotchContainerMetrics.boxStroke,
                                   dash: isActive ? [] : [3, 2.5])))
            .frame(width: NotchContainerMetrics.box, height: NotchContainerMetrics.box)
    }
}

/// The grey placeholder over a field — never tinted (spec §4.2).
struct DockPlaceholder: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DSDock.rowTitle)
            .foregroundStyle(DSDock.placeholder)
            .lineLimit(1)
            .allowsHitTesting(false)
    }
}

private struct DockFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// In a list: the to-do being typed.
struct DockTodoFirstRow: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var fieldWidth: CGFloat = 0

    private static let fontSize: CGFloat = 15
    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }
    private var hasText: Bool { !store.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var tint: DockTint { DockTint(store.draftSpaceTint) }

    /// Measured here, where `draftTitle` is observed, the field's own way
    /// (ChipLineLayout) — an NSViewRepresentable is not re-measured on a pure
    /// content change (see InlineDraftRow).
    private var fieldHeight: CGFloat {
        let width = fieldWidth > 0 ? fieldWidth : 400
        let measured = ChipLineLayout.height(of: store.draftTitle,
                                             font: .systemFont(ofSize: Self.fontSize), width: width)
        return max(HighlightingTitleField.lineHeight(Self.fontSize),
                   min(ceil(measured), HighlightingTitleField.maxHeight))
    }

    private var placeholder: String {
        String(format: L10n.t("dock.addTo"), store.draftDestination?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DockFirstRowChrome(tint: tint,
                               isActive: store.draftFocused || hasText,
                               showsReturnKey: hasText,
                               onTap: { store.draftWantsFocus = true }) {
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
                        allowsImages: true
                    )
                    .frame(height: fieldHeight)
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: DockFieldWidthKey.self, value: proxy.size.width)
                })
                .onPreferenceChange(DockFieldWidthKey.self) { fieldWidth = $0 }
            }
            // NL-3: the resolved date, under the text.
            if let parsed {
                Text("\u{2192} \(parsed.display)")
                    .font(.system(size: 11))
                    .foregroundStyle(DSDock.text3)
                    .padding(.leading, NotchContainerMetrics.firstRowInset
                             + NotchContainerMetrics.box + NotchContainerMetrics.rowGap)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: parsed?.display)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

/// In Notes: the note being written. The same field the Notes composer used —
/// NotesStore.draft, ⏎ files the note, ⇧⏎ breaks the line.
struct DockNoteFirstRow: View {
    @FocusState.Binding var focused: Bool
    @ObservedObject private var store = NotesStore.shared

    private var hasText: Bool { !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        DockFirstRowChrome(tint: DockTint(.notes),
                           isActive: focused || hasText,
                           showsReturnKey: hasText,
                           onTap: { focused = true }) {
            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty { DockPlaceholder(text: L10n.t("dock.newNote")) }
                // The user's text is NEVER reformatted.
                TextField("", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DSDock.rowTitle)
                    .foregroundStyle(DSDock.text)
                    .focused($focused)
                    .lineLimit(3)
                    .onChange(of: store.draft) { _ in store.draftChanged() }
            }
        }
        .accessibilityLabel(L10n.t("dock.newNote"))
    }
}
