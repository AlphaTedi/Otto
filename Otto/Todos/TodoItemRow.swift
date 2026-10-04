import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drag-to-reorder (TD-5)

/// Arc's model: dragging only ever MOVES THE INDICATOR. The list itself is
/// left alone until the drop lands, so rows never shuffle under the cursor
/// mid-drag (the previous delegate reordered live inside `dropEntered`).
/// Every row's rectangle, collected into one dictionary.
struct RowFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - TodoItemRow — live row (collapsed + NC expanded states)
//
// The live row: collapsed look, completion state, the NC-2 details
// indicator and the expanded note/checklist editor — styled EXCLUSIVELY
// from the DS tokens (DesignTokens.swift) so it cannot drift from the design.

struct TodoItemRow: View {
    let item: TodoItem
    let accent: Color
    let isFocused: Bool
    let isExpanded: Bool
    /// Shared with the list so the dragged row can dim itself.
    @State private var hover = false
    /// Title editing. `nil` = not editing; a String = the live draft.
    /// Held separately from the item so an abandoned edit (Escape, clicking
    /// away) never touches the stored title.
    @State private var titleDraft: String?
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var noteFocused: Bool
    @ObservedObject private var store = TodoStore.shared
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels

    /// Whether the row draws anything under its title — the note editor, the
    /// inline steps, or the trailing step-draft row an expanded row always
    /// carries. Only then does the slab need vertical air of its own; plain
    /// rows are inset by their 37pt floor instead.
    private var carriesDetails: Bool { isExpanded || !item.checklist.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow

            // Notes stay behind the click. A closed row keeps only a compact
            // checklist preview; opening it reveals the whole checklist and
            // the draft row. This keeps one detailed to-do useful without
            // leaving every previous to-do fully expanded in the list.
            //
            // A step used to be invisible until you opened the to-do, which
            // meant you had to click into every item to find out whether it
            // had any — so a checklist you had written was, during ordinary
            // browsing, simply not there (Marcello's spec, 2026-08-18). Steps
            // now preview inline and stay tickable from the list. Two entries
            // are enough to show that the checklist exists; the count below
            // them says exactly how much remains hidden.
            //
            // The draft row belongs only to the opened form. Repeating "Type
            // to add a step" beneath every closed parent was the largest part
            // of the clutter this disclosure is meant to remove.
            if isExpanded {
                noteBlock
            }
            if !item.checklist.isEmpty || isExpanded {
                stepsBlock(expanded: isExpanded)
            }
        }
        // 12pt horizontal, always. That puts a row's checkbox at
        // listInset 24 + 12 = 36 — the same offset the creation bar's sits at
        // (barOuterInset 16 + barPaddingH 20), so every checkbox in the panel
        // finally shares one vertical line. They were apart because this line
        // was lost when an earlier script aborted before writing.
        //
        // The SAME air vertically as between rows — but only when the row
        // carries content below its title. Steps render inline now whether
        // or not the row is expanded, and with no vertical air at all a
        // stepped-but-never-opened row's hover/focus slab touched the
        // checkbox on top and the last step at the bottom (Marcello,
        // 2026-09-14).
        //
        // The value is the inter-row gap, not the 12pt side inset, and that
        // is the whole point: a plain row already insets its content by
        // ~5.5pt inside its 37pt floor, so content-to-content down the list
        // runs ~17pt everywhere — 5.5 + 6 + 5.5 between plain rows, 6 + 6 +
        // 5.5 after a stepped one. At 12 the stepped rows floated visibly
        // looser than the rest of the list (Marcello, 2026-09-14).
        // Plain rows keep no padding and their 37pt floor, which already
        // insets them.
        // The container's slab now starts at the field's edge, so its content
        // keeps the field's own inner inset (20) — checkboxes still line up
        // with the field's.
        .padding(.horizontal, notchLayout == .container ? PanelMetrics.barPaddingH : PanelMetrics.rowPaddingH)
        // Plain rows get the same 6 top and bottom. A one-line row is still
        // exactly its 37pt floor (6 + 4 + 17 + 4 + 6); a WRAPPED one now keeps
        // the side inset's air above its first line and below its last
        // instead of touching the slab — visible only on hover and focus,
        // which is exactly when it was (Marcello, 2026-10-01).
        .padding(.vertical, carriesDetails ? 0 : PanelMetrics.listRowGap)
        .padding(.top, carriesDetails ? PanelMetrics.listRowGap : 0)
        // The title row is visually taller than the 10pt step draft because
        // its text carries `rowTextInset` above and below. Adding that inset
        // at the foot makes the visible air above the main checkbox and below
        // “Type to add a step” equal inside an opened card.
        .padding(.bottom, carriesDetails
                 ? PanelMetrics.listRowGap + (isExpanded ? PanelMetrics.rowTextInset : 0)
                 : 0)
        // A floor, not a fixed height: a title that wraps still grows. Without
        // it the row was exactly as tall as its content, so the checkbox had
        // 12pt either side and nothing above or below.
        .frame(minHeight: carriesDetails ? 0 : PanelMetrics.rowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                .fill(isExpanded ? Self.openedRowFill
                                 : (isFocused ? DSColor.focusedRowBackground
                                              : (hover ? DSColor.rowHover(container: notchLayout == .container)
                                                       : .clear)))
        )
        // An opened to-do is a well sunk into the panel: darker than the
        // list, and no outline at all — not the lighter card with a
        // section-coloured stroke it was (Marcello, 2026-10-03).
        .animation(Motion.hintFade, value: isFocused)
        // Was a bare assignment. The row's own background snapped, and so did
        // the hover half of the RowActions reveal — its condition includes
        // `hover`, so with nothing animating that value there was no
        // transaction for `.transition(.opacity)` to attach to. One line fixes
        // both.
        .animation(Motion.hoverFade, value: hover)
        .onHover { hover = $0 }
        // A row can also be closed from outside this view — clicking a
        // different row, Escape, the whole panel collapsing. Any of those
        // while mid-edit would otherwise strand the draft in view state and
        // silently lose it, so they save on the way out too.
        .onChange(of: isExpanded) { expanded in
            if !expanded { commitTitle() }
        }
        // ⏎ on the focused row: the key router can't reach this view's
        // private edit machinery, so it raises a one-shot request on the
        // store and the row consumes it here — same flag pattern as
        // draftWantsFocus, and it funnels into the exact code path a click
        // takes, so the two inputs can never diverge.
        .onReceive(TodoStore.shared.$titleEditRequestID) { requested in
            guard requested == item.id else { return }
            TodoStore.shared.titleEditRequestID = nil
            beginEditingTitle()
        }
        // The title is the first link in the chain, so ↓ from it reaches the
        // note and the steps below without the caret ever leaving the keyboard.
        .onReceive(store.$detailFocusRequest) { _ in
            let wanted = store.focusedDetail?.item == item.id
                && store.focusedDetail?.target == .title
            guard wanted else { return }
            beginEditingTitle()
        }
        // Escape while this row's title editor holds the caret: DISCARD.
        // The key router consumes Esc itself (it must — loose, the key
        // would close the whole notch) and announces the cancel instead;
        // clearing the draft before the blur lands means the commit-on-blur
        // that follows finds nothing to save.
        .onReceive(NotificationCenter.default.publisher(for: .todoEditorEscape)) { _ in
            if titleFieldFocused { titleDraft = nil }
        }
        .contextMenu { contextMenuItems }
    }


    /// The note glyph at rest; the ⌘↵ / grip cluster on hover or focus,
    /// in the same slot.
    ///
    /// Each affordance answers the input that can actually reach it: ⏎ is a
    /// KEYBOARD act, so it appears when the row has keyboard focus; the grip
    /// is a MOUSE act, so it appears under the pointer (Marcello, 2026-08-22).
    /// NC-2: the note glyph means "there is something here you cannot see",
    /// so it shows only for a note on a closed row.
    private var trailingHints: some View {
        let showsActions = !item.isCompleted && !isExpanded && (hover || isFocused)
        return ZStack(alignment: .trailing) {
            Color.clear.frame(width: PanelMetrics.rowActionsWidth, height: 1)
            if showsActions {
                RowActions(showEnter: isFocused, showGrip: hover, enterLabel: "\u{2318}\u{21B5}")
                    .transition(.opacity)
            } else if !item.note.isEmpty && !isExpanded {
                OttoIcon("text.alignleft", pointSize: 8)
                    .foregroundStyle(DSColor.textHint)
            }
        }
        .frame(width: PanelMetrics.rowActionsWidth, alignment: .trailing)
    }

    /// The opened to-do's ground: darker than the panel in dark mode, a
    /// faint grey well in light.
    private static let openedRowFill = Color.dynamic(light: NSColor.black.withAlphaComponent(0.05),
                                                     dark: NSColor.black.withAlphaComponent(0.30))

    private var titleRow: some View {
        // CENTER, per the export's `align-items: center`. Top-aligning while
        // the label carries its own 8pt box is what left every checkbox
        // sitting visibly above the text it belongs to.
        // 13 in the floating panels so a title starts exactly under the
        // capture field's text (U5 §3); the container keeps its 12.
        HStack(alignment: .center, spacing: notchLayout == .container ? PanelMetrics.rowInnerGap : 13) {
            // No grip handle. The row IS the drag handle now — see
            // EntityTextView.hitTest, which makes the title transparent to the
            // mouse everywhere except a link chip. The old six-dot grip had to
            // reserve leading space on every row whether shown or not, which is
            // what made the list "float in the middle, too distanced from the
            // left side" (Marcello, 2026-07-26).
            Button {
                TodoStore.shared.toggleComplete(item.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: PanelMetrics.checkboxRadius, style: .continuous)
                        .strokeBorder(accent, lineWidth: PanelMetrics.checkboxStroke)
                        .frame(width: PanelMetrics.checkboxSize, height: PanelMetrics.checkboxSize)
                    if item.isCompleted {
                        RoundedRectangle(cornerRadius: PanelMetrics.checkboxRadius, style: .continuous)
                            .fill(accent)
                            .frame(width: PanelMetrics.checkboxSize, height: PanelMetrics.checkboxSize)
                        OttoIcon("checkmark", pointSize: 10)
                            // On the category's own fill, which is light in
                            // both appearances — see DSColor.onAccentFill.
                            .foregroundStyle(DSColor.onAccentFill.opacity(0.85))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // §8.3: near-instant fill; row exit + shrink follow on contentHug.
            .animation(Motion.complete, value: item.isCompleted)

            if item.isCompleted {
                Text(item.title)
                    .font(DSFont.todoTitle)
                    .strikethrough(true)
                    .foregroundStyle(DSColor.textHint)
                    .lineLimit(1)
            } else if let draft = titleDraft {
                // Editing. A plain TextField, deliberately NOT the entity
                // renderer: chips are a read view built from NSTextAttachments,
                // and you cannot put a caret inside one. Editing shows the raw
                // source — `code`, @name, the full URL — which is also the only
                // way to see and fix the markup that produced a chip.
                TextField("", text: Binding(
                    get: { draft },
                    set: { titleDraft = $0 }
                ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DSFont.todoTitle)
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .lineLimit(1...5)
                    // The SAME vertical box the read view carries below.
                    //
                    // Without it the row was one height while the caret was in
                    // the title and another the instant the caret moved to the
                    // note, so walking the fields with ↑/↓ made the whole
                    // panel breathe under the text you were trying to read
                    // (Marcello, 2026-09-06). Two renderers for one line of
                    // text have to agree on its box.
                    //
                    // Measured both ways: without it the row is 305pt with the
                    // caret in the title and 312pt the moment the caret moves
                    // to the note. With it, 312 throughout.
                    .padding(.vertical, PanelMetrics.rowTextInset)
                    .focused($titleFieldFocused)
                    .onSubmit { commitTitle() }
                    // Losing focus commits too — clicking away is a save
                    // everywhere else in this app, so it is here as well.
                    .onChange(of: titleFieldFocused) { focused in
                        // Register with the store. Without this line the whole
                        // arrow chain was dead on arrival: opening a to-do put
                        // the caret in the title but left `focusedDetail` nil,
                        // and the router's ↑/↓ branch is gated on knowing which
                        // field holds it. The model walked correctly in
                        // isolation — the keys just never reached it
                        // (Marcello, 2026-09-05, second report).
                        if focused { store.focusedDetail = (item.id, .title) }
                        if !focused { commitTitle() }
                    }
                    .onExitCommand { titleDraft = nil }   // Escape discards
            } else {
                // EH-1..6: links/dates/mentions/code render as inline chips
                // in the flowing, wrapping title.
                VStack(alignment: .leading, spacing: 0) {
                    EntityTitleView(
                        title: item.title,
                        isBright: isFocused || isExpanded,
                        onTap: activateRow,
                        onRemoveImage: { path in
                            store.rename(item.id, to: AttachmentStore.removingToken(path, from: item.title))
                        }
                    )
                    // The export wraps the label in its own 8pt box, which is what
                    // gives a single-line row 33pt and lets a wrapped one grow to
                    // 50 instead of being clipped to a fixed height.
                    .padding(.vertical, PanelMetrics.rowTextInset)
                    // Its images, as chips under the title (Attachments.swift).
                    if !item.attachments.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(item.attachments, id: \.self) { path in
                                AttachmentChip(path: path) { store.removeAttachment(path, from: item.id) }
                            }
                        }
                        .padding(.bottom, PanelMetrics.rowTextInset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The hint gutter, on EVERY line and always reserved: no text
            // ever runs under ⌘↵ or the grip, and a hint appearing on hover
            // or focus reflows nothing (Marcello, 2026-10-01, the red band
            // in his mock-up; the 2026-08-22 reflow rule). Centred in the
            // row like the checkbox opposite it, its right edge on the same
            // line as the capture field's keycap.
            trailingHints
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: activateRow)
        // Reordering is NOT attached here. It is a plain drag gesture owned by
        // the list, which is the only place that knows where the other rows
        // are — see `reorderGesture`.
    }

    /// NC-1: deliberate open — clicking the row body (not the checkbox)
    /// toggles the note/checklist details. Non-link clicks inside the
    /// entity title view route here too.
    /// Clicking a to-do opens it AND drops the caret in its text.
    ///
    /// Editing used to be a separate act behind a pencil; selecting a row and
    /// then aiming at a small button is two steps for what should be one.
    /// Opening a row is already the gesture that means "I want to work on
    /// this one", so it now hands over a caret as well — you click, you type
    /// (Marcello, 2026-08-10).
    ///
    /// A caret is unobtrusive enough to carry both meanings: someone who only
    /// wanted to read the note or tick a step just ignores it, and nothing is
    /// written unless they actually type.
    private func activateRow() {
        let store = TodoStore.shared
        store.focusedItemID = item.id
        guard !item.isCompleted else { return }
        let willExpand = store.expandedItemID != item.id
        withAnimation(NotchAnimation.contentHug) {
            store.expandedItemID = willExpand ? item.id : nil
        }
        if willExpand {
            beginEditingTitle()
        } else {
            // Collapsing while mid-edit saves rather than silently dropping
            // the change — closing a row is not a cancel.
            commitTitle()
        }
    }

    /// Enter edit mode with the caret in the title.
    private func beginEditingTitle() {
        guard !item.isCompleted else { return }
        titleDraft = item.title
        // The field has to exist before it can take focus.
        DispatchQueue.main.async { titleFieldFocused = true }
        // Caret, not a selection — see FieldCaret. The title is a read view
        // until this moment, so there is no click position to preserve and
        // every route in wants the same thing.
        FieldCaret.collapseToEnd()
    }

    /// Save and leave edit mode. An empty title is refused by the store, so
    /// clearing the field and pressing Return keeps the original rather than
    /// leaving an unidentifiable blank row.
    private func commitTitle() {
        guard let draft = titleDraft else { return }
        TodoStore.shared.rename(item.id, to: draft)
        titleDraft = nil
    }

    // MARK: NC expanded details — note, then steps (§7)
    //
    // Notes and steps used to share one block: a note field, then a checklist
    // hanging off the same indent with no separation, so a to-do's prose and
    // its sub-tasks read as one undifferentiated column. They are two
    // different kinds of thing — one is a paragraph, the other is a list you
    // tick off — and each now gets its own connector rule with real air
    // between them.

    private var noteBlock: some View {
        indented {
            TextField(L10n.t("todo.notePlaceholder"),
                      text: noteBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DSFont.checklistItem)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1...8)
                // Without this the field is handed its ideal (single-line)
                // width and the rest of the note is simply cropped off the
                // right edge — text that was typed and then silently
                // disappeared (Marcello, 2026-08-16).
                .fixedSize(horizontal: false, vertical: true)
                .focused($noteFocused)
                // The note is a link in the arrow chain like any other field.
                .onReceive(store.$detailFocusRequest) { _ in
                    let wanted = store.focusedDetail?.item == item.id
                        && store.focusedDetail?.target == .note
                    guard wanted else { return }
                    DispatchQueue.main.async { noteFocused = true }
                    FieldCaret.collapseToEnd()
                }
                .onChange(of: noteFocused) { isFocused in
                    if isFocused { store.focusedDetail = (item.id, .note) }
                }
        }
        .padding(.top, 2)
    }

    /// The steps checklist. Same indent and connector rule in the list as in
    /// the opened row — deliberately the identical treatment, because they are
    /// the identical rows; only where you can reach them has changed.
    private func stepsBlock(expanded: Bool) -> some View {
        let visibleCount = ChecklistDisclosure.visibleCount(total: item.checklist.count,
                                                             expanded: expanded)
        let hiddenCount = ChecklistDisclosure.hiddenCount(total: item.checklist.count,
                                                           expanded: expanded)
        return indented {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(item.checklist.prefix(visibleCount))) { step in
                    StepRow(step: step, parentID: item.id, accent: accent)
                }

                if hiddenCount > 0 {
                    Button {
                        store.focusedItemID = item.id
                        withAnimation(NotchAnimation.contentHug) {
                            store.expandedItemID = item.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            OttoIcon("ellipsis", pointSize: 8)
                            Text(moreStepsLabel(hiddenCount))
                                .font(DSFont.checklistItem)
                        }
                        .foregroundStyle(DSColor.textHint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("todo.sc.expandRow"))
                    .accessibilityLabel(moreStepsLabel(hiddenCount))
                }

                if expanded {
                    // Always last in an opened row, styled exactly like a real
                    // step. The empty row is the add affordance and committing
                    // one leaves the caret on the next empty row.
                    StepDraftRow(parentID: item.id, accent: accent)
                }
            }
        }
        .padding(.top, 2)
    }

    private func moreStepsLabel(_ count: Int) -> String {
        if count == 1 { return L10n.t("todo.oneMoreStep") }
        return String(format: L10n.t("todo.moreSteps"), "\(count)")
    }

    /// The connector rule + indent shared by notes and steps.
    private func indented<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let connectorWidth: CGFloat = 0.5
        // Centre the connector on the parent checkbox's vertical axis while
        // keeping the child content on the existing checklist indent.
        let connectorLeading = (PanelMetrics.checkboxSize - connectorWidth) / 2
        let contentLeading = DSSpacing.checklistIndent - connectorLeading - connectorWidth

        return HStack(spacing: 0) {
            Rectangle()
                .fill(DSColor.panelBorder)
                .frame(width: connectorWidth)
                .padding(.leading, connectorLeading)
            content()
                .padding(.leading, contentLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(L10n.t("todo.editTitle")) { beginEditingTitle() }
        Divider()
        Button(L10n.t("todo.moveTo")) { TodoMovePicker.shared.show(itemID: item.id) }
        Divider()
        Button(L10n.t("action.delete"), role: .destructive) {
            TodoStore.shared.delete(item.id)
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { TodoStore.shared.items.first { $0.id == item.id }?.note ?? "" },
            set: { TodoStore.shared.setNote($0, for: item.id) }
        )
    }
}

/// The trailing cluster on a hovered or focused row.
///
/// Geometry is the export's: a 23x18 badge with a 1pt border at radius 6, an
/// 18pt hairline, and six 3pt dots 2pt apart inside a 16pt box.
/// Shared with the Notes stream, which reuses the same affordances for
/// the same reason the rows share their type: they are the same row.
struct RowActions: View {
    let showEnter: Bool
    let showGrip: Bool
    /// The key the badge names. A to-do row shows ⌘⏎ — what completes it —
    /// because a bare ⏎ badge read as "Return ticks this off", when ⏎ opens
    /// the row for editing (Marcello, 2026-09-27). Notes keep ⏎: it opens
    /// the note, and that is what it says.
    var enterLabel = "\u{21B5}"

    var body: some View {
        HStack(spacing: PanelMetrics.rowActionGap) {
            if showEnter {
                Text(enterLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.rowAffordance)
                    .padding(.horizontal, enterLabel.count > 1 ? 5 : 0)
                    .frame(minWidth: PanelMetrics.enterBadgeWidth,
                           minHeight: PanelMetrics.enterBadgeHeight)
                    .fixedSize()
                    .overlay(
                        RoundedRectangle(cornerRadius: PanelMetrics.enterBadgeRadius,
                                         style: .continuous)
                            .strokeBorder(DSColor.rowAffordance, lineWidth: 1)
                    )
            }

            // No separator between the two (Marcello, 2026-10-02): the gap
            // separates them, and the gutter gets narrower for the title.
            if showGrip { DragGrip() }
        }
        .allowsHitTesting(false)
    }
}

/// Six dots. Decorative on purpose — the WHOLE row is the drag handle (see
/// EntityTextView.hitTest, which makes the title transparent to the mouse), so
/// this says "draggable" without claiming a target of its own and without
/// reserving leading space on every row the way the old grip did.
struct DragGrip: View {
    var body: some View {
        VStack(spacing: PanelMetrics.gripGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: PanelMetrics.gripGap) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(DSColor.rowAffordance)
                            .frame(width: PanelMetrics.gripDot, height: PanelMetrics.gripDot)
                    }
                }
            }
        }
        .frame(width: PanelMetrics.gripBox, height: PanelMetrics.gripBox)
    }
}
