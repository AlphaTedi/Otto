import SwiftUI
import AppKit

// MARK: - In-panel surfaces (design PRD §§3-5)
//
// Category creation and Quick Find render INSIDE the panel, replacing the
// browsing content — no floating windows (CT-5/CT-6). Mode swaps animate on
// contentHug so the panel re-hugs each surface's height. Every visual value
// comes from DesignSystem.swift; where a reusable component exists there
// (PrimaryActionButton, ColorSwatchButton, ShortcutHintBadge) it is used
// directly, wrapped in Buttons for behavior.
//
// TO-DO CREATION IS NO LONGER ONE OF THESE. It was `TodoCreateView` — a card
// with a title field, a category combo, an urgency combo and a Create button,
// which replaced the whole panel and so was detached from the section it was
// filing into. It is now a draft row pinned above the list itself (see
// InlineDraftRow in TodoBrowsingView.swift). What survived the deletion is
// HighlightingTitleField below, which the draft row reuses: the inline date
// coloring and the grow-with-your-text behaviour were the parts of that card
// worth keeping.

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
    /// The destination section's color — the caret and the selection wear it,
    /// so "where is my cursor" and "where is this going" are one answer.
    var accent: Color = DSColor.focusAccent
    /// Set by the store when something asks for the caret (⌃⇧N, ⌘N, a click
    /// on the row). Cleared here once taken, so it is a request, not a state.
    var wantsFocus: Bool = false
    /// Reports first-responder changes back to the store. Focus is what pins
    /// the panel open, so it has to be observed rather than assumed.
    var onFocusChange: (Bool) -> Void = { _ in }

    static let lineHeight: CGFloat = 17
    static let maxHeight: CGFloat = 102   // ~6 lines, then it scrolls

    /// Stamped on the text view so the key monitor can ask "is the caret in
    /// the draft row?" rather than "is a draft open?". Those are different
    /// questions once a note or step field can hold focus at the same time,
    /// and ⏎ / ⇥ / Esc belong to whichever field the user is actually in.
    static let fieldIdentifier = NSUserInterfaceItemIdentifier("otto.todo.draftTitleField")

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed

        let view = FocusReportingTextView()
        view.identifier = Self.fieldIdentifier
        view.onFocusChange = { focused in
            // Async: this fires from inside AppKit's responder change, and
            // publishing store state synchronously from there re-enters
            // SwiftUI layout mid-transaction.
            DispatchQueue.main.async { onFocusChange(focused) }
        }
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
        // Deliberately NOT grabbing focus on appear. The draft row is now
        // permanent, so it is built every time the panel opens — and a field
        // that took the caret on sight would pin the notch open forever and
        // swallow every keystroke meant for Quick Find.
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
        }
        view.insertionPointColor = NSColor(accent)
        view.selectedTextAttributes = [
            .backgroundColor: NSColor(accent).withAlphaComponent(0.32),
            .foregroundColor: NSColor(DSColor.textPrimaryBright),
        ]
        context.coordinator.restyle(view, highlight: highlightRange)
        if wantsFocus, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
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

    /// NSTextView tells nobody when it gains or loses the caret, and the
    /// delegate's textDidBegin/EndEditing only fire on an actual edit — so
    /// clicking in and out of an empty field is silent. Overriding the
    /// responder calls is the only account of focus that is always right.
    final class FocusReportingTextView: NSTextView {
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusChange?(true) }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocusChange?(false) }
            return resigned
        }
    }

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
