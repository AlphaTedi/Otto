import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Steps
//
// A step is a real checklist entry with its own checkbox, independent of the
// parent to-do's — ticking a step never completes the task, and completing
// the task never ticks its steps. Checked state matches the parent's exactly:
// filled box, strikethrough, dimmed label.

struct StepRow: View {
    let step: ChecklistItem
    let parentID: UUID
    @ObservedObject private var store = TodoStore.shared
    /// The section's own colour, the same one the parent to-do's checkbox
    /// wears. A step's box was a flat grey, which made a checklist look like
    /// it belonged to no list in particular (Marcello, 2026-08-19).
    let accent: Color
    @State private var hover = false
    /// `nil` = not editing; a String = the live draft. Held apart from the
    /// step so an abandoned edit never touches what is stored — the same
    /// arrangement TodoItemRow uses for a to-do's title.
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                TodoStore.shared.toggleChecklistItem(step.id, in: parentID)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.checklistCheckboxCorner,
                                     style: .continuous)
                        .strokeBorder(accent, lineWidth: 1)
                        .frame(width: 10, height: 10)
                    if step.isDone {
                        RoundedRectangle(cornerRadius: DSRadius.checklistCheckboxCorner,
                                         style: .continuous)
                            .fill(accent)
                            .frame(width: 10, height: 10)
                        OttoIcon("checkmark", pointSize: 6)
                            .foregroundStyle(DSColor.primaryText.opacity(0.85))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1.5)

            // Click the words to change them. No pencil, for the reason the
            // to-do row has none: opening a thing to work on it and putting a
            // caret in it are one gesture, not two.
            if let draft {
                TextField("", text: Binding(get: { draft }, set: { self.draft = $0 }))
                    .textFieldStyle(.plain)
                    .font(DSFont.checklistItem)
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .focused($focused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Return confirms and moves ON, the same rhythm as the
                    // draft slot below: a checklist is written in one pass, so
                    // finishing a step should land you in the next one rather
                    // than back in the list.
                    .onSubmit {
                        commit()
                        // A closed to-do shows its first steps only and no
                        // draft slot, so the step after this one did not exist
                        // to take the caret and ⏎ just ended the edit
                        // (Marcello, 2026-09-30). Open the to-do first, then
                        // move once its rows are there.
                        let moveOn = { [store, parentID, step] in
                            store.focusedDetail = (parentID, .step(step.id))
                            if !store.moveDetailFocus(1, in: parentID) {
                                store.focusStepDraft(in: parentID)
                            }
                        }
                        if store.expandedItemID == parentID {
                            moveOn()
                        } else {
                            withAnimation(Motion.contentHug) { store.expandedItemID = parentID }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: moveOn)
                        }
                    }
                    // Clicking away is a save everywhere else in this app.
                    .onChange(of: focused) { isFocused in
                        if isFocused { store.focusedDetail = (parentID, .step(step.id)) }
                        if !isFocused { commit() }
                    }
                    .onExitCommand { self.draft = nil }   // Escape discards
            } else {
                Text(step.title)
                    .font(DSFont.checklistItem)
                    .strikethrough(step.isDone)
                    .foregroundStyle(step.isDone ? DSColor.textFaint : DSColor.textSecondary)
                    // Same crop as the note field had: an HStack proposes a Text
                    // its ideal width, so a long step lost its tail off the right
                    // edge instead of running onto a second line.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
            }

            // Deleting a step was right-click only, which is not a thing
            // anyone finds. The gutter is always reserved and only the glyph
            // fades in, so revealing it can't reflow the text beside it.
            Button {
                TodoStore.shared.deleteChecklistItem(step.id, in: parentID)
            } label: {
                OttoIcon("xmark", pointSize: 7)
                    .foregroundStyle(DSColor.textFaint)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
            .padding(.top, 1)
            .help(L10n.t("action.delete"))
        }
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        // The whole row can be closed from outside this view — the parent
        // to-do collapsing, Escape, the panel shutting. Any of those mid-edit
        // would stranded the draft in view state and silently lose it, so
        // leaving the screen saves too.
        .onDisappear { commit() }
        // Escape while this step's editor holds the caret: DISCARD — same
        // announcement TodoItemRow listens for, for the same reason (the key
        // router consumes Esc before .onExitCommand can ever run).
        // The store decides which step holds the caret; this row answers when
        // it is the one named. Same reasoning as StepDraftRow: a request
        // answered after the redraw, not a value the redraw can eat.
        .onReceive(store.$detailFocusRequest) { _ in
            let wanted = store.focusedDetail?.item == parentID
                && store.focusedDetail?.target == .step(step.id)
            guard wanted else { return }
            if draft == nil { draft = step.title }
            DispatchQueue.main.async { focused = true }
            FieldCaret.collapseToEnd()
        }
        .onReceive(NotificationCenter.default.publisher(for: .todoEditorEscape)) { _ in
            if focused { draft = nil }
        }
        .contextMenu {
            Button(L10n.t("todo.editTitle")) { beginEditing() }
            Divider()
            Button(L10n.t("action.delete"), role: .destructive) {
                TodoStore.shared.deleteChecklistItem(step.id, in: parentID)
            }
        }
    }

    /// A ticked step is history; editing it would be rewriting what happened.
    /// Untick it first, exactly as a completed to-do's title is not editable.
    private func beginEditing() {
        guard !step.isDone else { return }
        draft = step.title
        // The field has to exist before it can take focus.
        DispatchQueue.main.async { focused = true }
    }

    /// Save and leave edit mode. An empty title is refused by the store, so
    /// clearing the field and pressing Return keeps the original rather than
    /// leaving an unreadable blank row.
    private func commit() {
        guard let draft else { return }
        TodoStore.shared.renameChecklistItem(step.id, in: parentID, to: draft)
        self.draft = nil
    }
}

/// The always-open trailing row.
///
/// Not a button, not a dashed box, not a "+ Add step" link — an ordinary step
/// row that happens to be empty. Typing in it and pressing Return files it and
/// leaves the caret in the fresh empty row underneath, so a list of five steps
/// is five lines and five Returns with nothing else to aim at in between.
struct StepDraftRow: View {
    let parentID: UUID
    let accent: Color
    @ObservedObject private var store = TodoStore.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            // DASHED, and that is the whole point of it.
            //
            // This box was made identical to a real step's for fidelity to
            // "styled identically to a real step row" — which turned out to be
            // the wrong reading. On a real display the two were
            // indistinguishable, so an empty box that does nothing when you
            // click it sat directly under boxes that tick (Marcello,
            // 2026-08-19). Identical ROW — same size, same indent, same
            // baseline — but the box has to say it is not a step yet.
            //
            // A dashed outline is the ordinary way to draw a slot rather than
            // a thing, and it keeps the section's colour so the row still
            // reads as part of this checklist.
            RoundedRectangle(cornerRadius: DSRadius.checklistCheckboxCorner, style: .continuous)
                .strokeBorder(accent.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 10, height: 10)
                .padding(.top, 1.5)

            // Single-line deliberately: on a vertical-axis field Return
            // inserts a newline instead of submitting, and Return is the
            // entire interaction here.
            TextField(L10n.t("todo.stepPlaceholder"), text: $text)
                .textFieldStyle(.plain)
                .font(DSFont.checklistItem)
                .foregroundStyle(DSColor.textSecondary)
                .focused($focused)
                .onSubmit {
                    TodoStore.shared.addChecklistItem(text, to: parentID)
                    text = ""
                    // Ask the store to put the caret back, rather than
                    // assigning it here.
                    //
                    // The commit mutates `items`, which rebuilds this row's
                    // parent; a synchronous `focused = true` could be lost in
                    // that rebuild, and whether it survived came down to
                    // timing — which is why Return chained here and stopped
                    // after one step on another Mac (Marcello, 2026-09-05).
                    // As a request, it is answered after the redraw instead of
                    // racing it.
                    TodoStore.shared.focusStepDraft(in: parentID)
                }
                // The store is the one that knows where the caret should be,
                // including when it should come back to a slot it never left.
                .onReceive(store.$detailFocusRequest) { _ in
                    let wanted = store.focusedDetail?.item == parentID
                        && store.focusedDetail?.target == .stepDraft
                    guard wanted else {
                        if focused { focused = false }
                        return
                    }
                    // One runloop hop: SwiftUI is mid-update when the store
                    // publishes, and focus asked for inside that pass is
                    // exactly what used to get dropped.
                    DispatchQueue.main.async { focused = true }
                    FieldCaret.collapseToEnd()
                }
                // Clicking straight into the field is still a way in, so the
                // store has to learn about it too or the arrow keys would move
                // from a stale position.
                .onChange(of: focused) { isFocused in
                    if isFocused { store.focusedDetail = (parentID, .stepDraft) }
                }

            // Matches StepRow's delete gutter so the two align.
            Color.clear.frame(width: 12, height: 12)
        }
    }
}
