import SwiftUI
import AppKit

// MARK: - In-panel surfaces (design PRD §§3-5)
//
// Creation, category creation, and Quick Find all render INSIDE the panel,
// replacing the browsing content — no floating windows (CT-5/CT-6). Mode
// swaps animate on contentHug so the panel re-hugs each surface's height.
// Every visual value comes from DesignSystem.swift; where a reusable
// component exists there (ComboBoxRow, PrimaryActionButton, ColorSwatchButton,
// ShortcutHintBadge) it is used directly, wrapped in Buttons for behavior.

// MARK: - TodoCreateView — the "+" tab (§3.2)

struct TodoCreateView: View {
    @ObservedObject private var store = TodoStore.shared

    /// Combo boxes are closed by default; tapping one expands its options
    /// INLINE (the panel hugs the extra height) — SwiftUI's Menu can't
    /// present from a non-activating panel, and a popup window would leave
    /// the notch anyway.
    private enum PickerKind { case category, urgency }
    @State private var openPicker: PickerKind?

    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }

    private var selectedCollection: TodoCollection? {
        store.collections.first { $0.id == store.draftCollectionID }
    }

    private var assignable: [TodoCollection] {
        // FB8: the user's default category appears FIRST in the picker; the
        // rest follow tab order.
        let all = store.collections.filter { !$0.isSystemToday }
        guard let def = store.defaultCreationCollectionID else { return all }
        return all.sorted { a, b in
            (a.id == def ? 0 : 1, a.sortOrder) < (b.id == def ? 0 : 1, b.sortOrder)
        }
    }

    private var canCreate: Bool {
        let title = parsed?.cleanedTitle ?? store.draftTitle
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.draftCollectionID != nil
    }

    /// FB5: the field's height, recomputed from the draft on every keystroke.
    /// Width is estimated slightly narrow (panel width minus paddings) so we
    /// round UP the line count and never clip the last line; beyond the max
    /// the field scrolls internally.
    private var titleFieldHeight: CGFloat {
        let panelWidth = CGFloat(NotchController.shared.expandedWidth)
        let width = max(120, panelWidth - CGFloat(DSSpacing.panelPadding) * 2 - 24 - 24)
        let text = store.draftTitle.isEmpty ? " " : store.draftTitle
        let measured = NSAttributedString(
            string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]
        ).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return max(HighlightingTitleField.lineHeight,
                   min(ceil(measured), HighlightingTitleField.maxHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("todo.newTodo").uppercased())
                .font(DSFont.sectionLabel)
                .tracking(0.4)
                .foregroundStyle(DSColor.textFaint)
                .padding(.bottom, 10)

            // STEP 1 — Type. NL-2: a recognized date phrase colors inline,
            // inside the same field, and is stripped only on Create.
            HighlightingTitleField(
                text: $store.draftTitle,
                highlightRange: parsed?.nsRange,
                placeholder: L10n.t("todo.titlePlaceholder")
            )
            // FB5: height is driven from SwiftUI (where draftTitle is
            // observed) so it recomputes on every keystroke and the panel
            // hugs it — an NSViewRepresentable's own sizeThatFits is NOT
            // re-invoked on a pure content change, so relying on it left the
            // field stuck at one line.
            .frame(height: titleFieldHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                    .fill(DSColor.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                    .stroke(DSColor.focusAccent, lineWidth: 0.5)
            )
            .padding(.bottom, parsed == nil ? 14 : 4)

            // NL-3: live resolved-date caption.
            if let parsed {
                Text("\u{2192} \(parsed.display)")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textFaint)
                    .padding(.leading, 2)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

            // STEP 2 — Category (rounded-square swatch; the square-vs-circle
            // distinction is deliberate, DesignSystem ComboBoxRow enforces it).
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    togglePicker(.category)
                } label: {
                    ComboBoxRow(
                        label: selectedCollection?.name ?? L10n.t("todo.noCollection"),
                        swatchColor: selectedCollection?.color ?? .gray,
                        swatchShape: .roundedSquare,
                        cycleShortcutHint: "\u{2303}\u{21E5}"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if openPicker == .category {
                    optionList {
                        ForEach(assignable) { c in
                            OptionRow(
                                swatch: AnyView(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(c.color).frame(width: 10, height: 10)),
                                label: c.name,
                                selected: c.id == store.draftCollectionID
                            ) {
                                store.draftCollectionID = c.id
                                togglePicker(nil)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)

            // STEP 3 — Urgency (circle swatch).
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    togglePicker(.urgency)
                } label: {
                    ComboBoxRow(
                        label: store.draftUrgency.fullLabel,
                        swatchColor: store.draftUrgency.color,
                        swatchShape: .circle,
                        cycleShortcutHint: "\u{2303}\u{21E7}\u{21E5}",
                        swatchDiameter: DSUrgencyDot.creationFlowSwatchDiameter
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if openPicker == .urgency {
                    optionList {
                        ForEach(TodoUrgency.allCases) { u in
                            OptionRow(
                                swatch: AnyView(Circle()
                                    .fill(u.color).frame(width: 10, height: 10)),
                                label: u.fullLabel,
                                selected: u == store.draftUrgency
                            ) {
                                store.draftUrgency = u
                                togglePicker(nil)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 14)

            // STEP 4 — Send: explicit, never implicit (⏎ chip inline per §3.2).
            Button(action: create) {
                PrimaryActionButton(title: L10n.t("todo.create"), shortcutHint: "\u{21A9}")
                    .opacity(canCreate ? 1 : 0.35)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(NotchAnimation.hintFade, value: parsed?.display)
    }

    private func togglePicker(_ kind: PickerKind?) {
        withAnimation(NotchAnimation.contentHug) {
            openPicker = (openPicker == kind) ? nil : kind
        }
    }

    /// KB-3/KB-4: cycle without opening — called from the key handler.
    static func cycleCollection(store: TodoStore) {
        let assignable = store.collections.filter { !$0.isSystemToday }
        guard !assignable.isEmpty else { return }
        let idx = assignable.firstIndex { $0.id == store.draftCollectionID } ?? -1
        store.draftCollectionID = assignable[(idx + 1) % assignable.count].id
    }

    static func submit(store: TodoStore) {
        let parsed = NLDateParser.parse(store.draftTitle)
        let title = parsed?.cleanedTitle ?? store.draftTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cid = store.draftCollectionID else { return }
        // NL-4: the phrase leaves the title and becomes a real due date.
        guard store.addItem(title: title, collectionID: cid,
                            urgency: store.draftUrgency, dueDate: parsed?.date) != nil else { return }
        store.draftTitle = ""
        store.draftUrgency = .low
        store.setMode(.browsing)
    }

    private func create() { Self.submit(store: store) }

    // MARK: Inline option list (the opened state of a combo box)

    @ViewBuilder
    private func optionList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .fill(DSColor.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .stroke(DSColor.panelBorder, lineWidth: 0.5)
        )
        .padding(.top, 4)
        .transition(.opacity.combined(with: .offset(y: -4)))
    }
}

private struct OptionRow: View {
    let swatch: AnyView
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                swatch
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textPrimaryBright)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DSColor.textFaint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hover ? Color.white.opacity(0.05) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - HighlightingTitleField — auto-growing NSTextView w/ inline NL coloring
//
// TextField can't color a substring while editing; an NSTextView can. The
// field GROWS with its content (FB5): one line by default, wrapping and
// getting taller as you type, up to `maxHeight`, then scrolling. Height is
// always clamped to [lineHeight, maxHeight] and the field NEVER accepts the
// panel's proposed height — that feedback loop is what made it balloon a
// little more on every visit in the previous build. Return/Esc are consumed
// by the mode-aware key monitor before they reach the view, so newlines only
// ever arrive via paste (collapsed to spaces).

struct HighlightingTitleField: NSViewRepresentable {
    @Binding var text: String
    let highlightRange: NSRange?
    let placeholder: String

    static let lineHeight: CGFloat = 17
    static let maxHeight: CGFloat = 102   // ~6 lines, then it scrolls

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed

        let view = NSTextView()
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.font = .systemFont(ofSize: 13)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.autoresizingMask = [.width]
        view.string = text
        context.coordinator.restyle(view, highlight: highlightRange)

        scroll.documentView = view
        // The creation surface exists to be typed into — grab focus once
        // the panel has become key.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
        }
        context.coordinator.restyle(view, highlight: highlightRange)
    }

    /// FB5: report the wrapped content height for the proposed width, clamped
    /// so the field hugs its text and never stretches to the panel.
    ///
    /// Measures the CURRENT `text` directly with boundingRect rather than
    /// reading the live text view's layout manager — the latter goes stale
    /// (an updateNSView that just changed the string may not have re-laid-out
    /// yet when SwiftUI asks for the size), so the field failed to grow.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView,
                      context: Context) -> CGSize? {
        let width = (proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }) ?? 200
        let measured = NSAttributedString(
            string: text.isEmpty ? " " : text,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        ).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let clamped = max(Self.lineHeight, min(ceil(measured), Self.maxHeight))
        return CGSize(width: width, height: clamped)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTitleField
        init(_ parent: HighlightingTitleField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            // Newlines only arrive via paste — collapse them (single logical
            // line of title text, even though it wraps visually).
            if view.string.contains("\n") {
                view.string = view.string.replacingOccurrences(of: "\n", with: " ")
            }
            parent.text = view.string
        }

        func restyle(_ view: NSTextView, highlight: NSRange?) {
            let full = NSRange(location: 0, length: (view.string as NSString).length)
            guard let storage = view.textStorage else { return }
            storage.beginEditing()
            storage.setAttributes([
                .foregroundColor: NSColor(DSColor.textPrimaryBright),
                .font: NSFont.systemFont(ofSize: 13),
            ], range: full)
            if let highlight, NSMaxRange(highlight) <= full.length {
                storage.addAttribute(.foregroundColor,
                                     value: NSColor(DSColor.focusAccent), range: highlight)
            }
            storage.endEditing()
            view.typingAttributes = [
                .foregroundColor: NSColor(DSColor.textPrimaryBright),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        }
    }
}

// MARK: - CategoryFormView — inline "New category" (§4, CT-5/CT-6)

struct CategoryFormView: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var name = ""
    @State private var colorHex = Self.paletteHex[0]
    @FocusState private var nameFocused: Bool

    /// Hex strings behind DSColor.CategoryPalette (TodoCollection persists
    /// hex, the DS palette only exposes Color values).
    private static let paletteHex = ["#7FB8E0", "#C99EE0", "#E8C15A", "#8FBF7A", "#E07A5F"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("todo.newCollection").uppercased())
                .font(DSFont.sectionLabel)
                .tracking(0.4)
                .foregroundStyle(DSColor.textFaint)
                .padding(.bottom, 10)

            Text(L10n.t("todo.categoryName"))
                .font(.system(size: 10))
                .foregroundStyle(DSColor.textFaint)
                .padding(.bottom, 6)

            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DSColor.textPrimaryBright)
                .focused($nameFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                        .fill(DSColor.fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                        .stroke(nameFocused ? DSColor.focusAccent : DSColor.panelBorder, lineWidth: 0.5)
                )
                .onSubmit(create)
                .padding(.bottom, 16)

            Text(L10n.t("todo.categoryColor"))
                .font(.system(size: 10))
                .foregroundStyle(DSColor.textFaint)
                .padding(.bottom, 8)

            // 5 swatches; selection is a white border + check, never implied
            // by position alone (CT-6, enforced by ColorSwatchButton). Each is
            // an explicit 34pt square — big enough to see and to click.
            HStack(spacing: 12) {
                ForEach(Self.paletteHex, id: \.self) { hex in
                    Button {
                        withAnimation(NotchAnimation.hintFade) { colorHex = hex }
                    } label: {
                        ColorSwatchButton(color: Color(hex: hex), isSelected: colorHex == hex)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                Button {
                    store.setMode(.browsing)
                } label: {
                    Text(L10n.t("snippet.cancel"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#999999"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                                .stroke(DSColor.panelBorder, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: create) {
                    Text(L10n.t("todo.create"))
                        .font(DSFont.buttonLabel)
                        .foregroundStyle(DSColor.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                                .fill(DSColor.primaryFill)
                        )
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let collection = store.addCollection(name: trimmed, colorHex: colorHex)
        store.selectCollection(collection.id)
    }
}

// MARK: - QuickFindView — cross-category search (§5, QF-1..4)

struct QuickFindView: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var caretVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // QF-2 "type anywhere": the query is fed by the key monitor, not
            // a focused TextField — a real field grabbed mid-word would
            // select-all and eat the seeding character. The caret is ours.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textSecondary)
                Text(store.findQuery)
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .lineLimit(1)
                Rectangle()
                    .fill(DSColor.textHint)
                    .frame(width: 1, height: 14)
                    .opacity(caretVisible ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                    .fill(DSColor.focusedRowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                    .stroke(DSColor.focusAccent, lineWidth: 0.5)
            )
            .padding(.bottom, 14)

            let matches = store.findMatches
            if !matches.isEmpty {
                Text(L10n.t("todo.matches").uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(DSColor.textFaint)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                        matchRow(item, selected: index == store.findSelection)
                    }
                }
            } else if !store.findQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(L10n.t("todo.noMatches"))
                    .font(DSFont.checklistItem)
                    .foregroundStyle(DSColor.textHint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                caretVisible = false
            }
        }
    }

    @ViewBuilder
    private func matchRow(_ item: TodoItem, selected: Bool) -> some View {
        let collection = store.collection(id: item.collectionID)
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(NotchAnimation.contentHug) {
                    store.panelMode = .browsing
                    store.activeCollectionID = item.collectionID
                    store.focusedItemID = item.id
                }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(collection?.color ?? .gray)
                        .frame(width: 8, height: 8)
                    Text(highlightedTitle(item.title))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous)
                        .fill(selected ? DSColor.fieldBackground : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // QF-4: say where the match lives.
            if let collection {
                Text("\(L10n.t("todo.inCategory")) \(collection.name)")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textHint)
                    .padding(.leading, 16)
            }
        }
    }

    /// Matched substring bolded in the focus accent, rest stays bright (§5).
    private func highlightedTitle(_ title: String) -> AttributedString {
        var attributed = AttributedString(title)
        attributed.foregroundColor = DSColor.textPrimaryBright
        let query = store.findQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty, let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = DSColor.focusAccent
            attributed[range].font = .system(size: 12, weight: .semibold)
        }
        return attributed
    }
}
