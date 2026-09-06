import SwiftUI
import AppKit

// MARK: - Notes space (design handoff "flusso continuo", 2026-09-06)
//
// One space, not many lists — so it takes the head of the space bar and never
// scrolls with them. Inside, ONE recurring object carries three roles: the
// 76pt rounded field at the top of the panel is the capture field in a list,
// the composer here, and an open note's title bar. It keeps its position and
// its radius in all three, which is why an open note gets no header of its own.
//
// The governing idea: WRITING COMES BEFORE NAMING. The space opens with the
// caret in the composer. The user types the note; on ↩ it drops into the
// stream and the model proposes a name afterwards. The title is a proposal,
// never a gate — people offloading a thought do not want to file it first.

// MARK: Metrics

/// A real NSView that answers the mouse, laid over a SwiftUI row.
///
/// The rows were a `.onTapGesture`, then a `Button`, and neither ever fired.
/// Measured rather than guessed at: an in-process hitTest at each row's screen
/// point returns NotchHostingView with insideShape true, and a dump of the
/// panel's AppKit tree shows nothing at all covering them — so the click
/// reaches the window and is lost inside SwiftUI's own gesture resolution,
/// where the row competes with the composer, the panel catcher and the scroll
/// view for the same point (Marcello, 2026-09-06, three times).
///
/// This stops competing. AppKit hit-testing runs BEFORE SwiftUI gestures and
/// finds real subviews first, which is exactly why the to-do rows have always
/// been clickable — their taps go through EntityTextView, an NSView, not
/// through SwiftUI at all. Same route here.
///
/// It also carries hover, so the row can light up under the pointer.
private struct RowClickCatcher: NSViewRepresentable {
    let onClick: () -> Void
    let onHover: (Bool) -> Void
    /// Screen-space pointer Y and the vertical distance dragged so far.
    let onDrag: (CGFloat, CGFloat) -> Void
    let onDragEnd: () -> Void
    /// This row's rect in SCREEN coordinates, so the drag can work out which
    /// gap the pointer is over.
    let onFrame: (CGRect) -> Void

    final class CatcherView: NSView {
        var onClick: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }
        var onDrag: (CGFloat, CGFloat) -> Void = { _, _ in }
        var onDragEnd: () -> Void = {}
        var onFrame: (CGRect) -> Void = { _ in }

        private var tracking: NSTrackingArea?
        private var downAt: NSPoint?
        private var dragging = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self)
            addTrackingArea(area)
            tracking = area
            reportFrame()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        private func reportFrame() {
            guard let window else { return }
            onFrame(window.convertToScreen(convert(bounds, to: nil)))
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }

        // Click and drag live in the SAME view, and they have to.
        //
        // The catcher takes mouseDown, so a SwiftUI DragGesture underneath it
        // would never begin — putting the click back would have taken the
        // reorder away. AppKit gives both here: a press that barely moves is a
        // click, and one that travels is a drag.
        override func mouseDown(with event: NSEvent) {
            downAt = NSEvent.mouseLocation
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = downAt else { return }
            let now = NSEvent.mouseLocation
            let travelled = now.y - start.y
            // A few points of slop, so a hand that is not quite still while
            // clicking still reads as a click.
            if !dragging, abs(travelled) < 6 { return }
            dragging = true
            onDrag(now.y, travelled)
        }

        override func mouseUp(with event: NSEvent) {
            defer { downAt = nil; dragging = false }
            if dragging { onDragEnd() } else { onClick() }
        }

        /// The panel is a nonactivating panel in an accessory app, so the
        /// first click into it would otherwise be spent activating rather than
        /// acting — the "why does it take two clicks" family of bug.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        /// Let the scroll wheel through to the ScrollView underneath: this
        /// view is here for clicks, and swallowing scrolls would trade one
        /// broken interaction for another.
        override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    }

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
        view.onHover = onHover
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        view.onFrame = onFrame
    }
}

/// The composer's drawn height, reported upward so the stream below it knows
/// how much room is actually left.
///
/// Measured, not assumed — the composer is the one piece of this surface whose
/// height genuinely moves (76pt empty, up to 240 with a long draft), and the
/// panel has already been overflowed twice by a budget that subtracted a
/// constant for something that changes size. See PanelChrome.
private struct ComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// This file's own formatter cache. MarkdownVault's is private to that file,
/// and a DateFormatter built per row is an allocation on every redraw of a
/// scrolling list.
private enum NotesFormatters {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    static func cached(_ format: String) -> DateFormatter {
        if let existing = cache[format] { return existing }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(format)
        cache[format] = formatter
        return formatter
    }
}


enum NotesMetrics {
    /// The same field, the same radius, the same place as the capture bar.
    static let composerMinHeight: CGFloat = 76
    static let composerMaxHeight: CGFloat = 240
    static let fieldRadius: CGFloat = LabMetrics.barRadius   // 24
    static let fieldPaddingH: CGFloat = 24
    static let fieldPaddingV: CGFloat = 16
    static let entryGap: CGFloat = 18
    static let entryInset: CGFloat = 12
    static let highlightRadius: CGFloat = 16
    static let bottomBarHeight: CGFloat = 52
    /// Under the notch the height is a cost, not a resource: the composer
    /// stops at two lines and the text scrolls inside it instead of pushing
    /// the silhouette down.
    static let notchComposerMaxHeight: CGFloat = 62
    static let notchStreamMaxHeight: CGFloat = 190
    /// The Notes pill's own colour. A literal, and deliberately so: every
    /// other active pill wears its category's colour, so the one permanent
    /// pill in the bar needs a colour that belongs to no category.
    ///
    /// Outlined rather than filled, and dashed (Marcello, 2026-09-06): a
    /// filled pill says "this list is selected", which is what the lists to
    /// its right say. Notes is a different kind of thing and the broken
    /// outline is what says so without a second shape or an icon.
    static let pillStroke = Color(hex: "#E8C15A")
    /// Kept for the search highlight, which needs a solid ground to sit on.
    static let pillFill = Color(hex: "#A9D8E9")
    static let pillLabel = Color(hex: "#16283A")
}

// MARK: - The space

struct NotesSpaceView: View {
    @ObservedObject private var store = NotesStore.shared
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels

    private var isContainer: Bool { notchLayout == .container }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let open = store.openNote {
                NoteDetailView(note: open, isContainer: isContainer)
                    // Per NOTE, not per surface. Without it SwiftUI reuses the
                    // same view for the next note opened, `onAppear` does not
                    // run again, and the body field still holds the previous
                    // note's text — you open one note and read another.
                    .id(open.id)
                    .transition(.opacity)
            } else {
                StreamView(isContainer: isContainer)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Motion.swap, value: store.openNoteID)
        // The undo window floats over the stream rather than displacing it:
        // a row that vanished and a bar that pushed everything down would be
        // two movements for one event.
        .overlay(alignment: .bottom) {
            if let pending = store.pendingDelete {
                UndoBar(title: pending.title)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
    }
}

// MARK: - Stream level: composer on top, history below

private struct StreamView: View {
    let isContainer: Bool

    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var chrome = PanelChrome.shared
    @FocusState private var composerFocused: Bool
    @State private var composerHeight: CGFloat = NotesMetrics.composerMinHeight
    // Reordering, as a plain drag — the same recipe the to-do list uses, and
    // for the same reason: `.onDrag` rides the system pasteboard, which was
    // never really meant for a non-activating panel and never moved a row.
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var draggedNoteID: UUID?
    @State private var dropBeforeID: UUID?
    @State private var dropAtEnd = false
    @State private var dragOffset: CGFloat = 0


    /// What is left of the panel once the composer and the space bar have
    /// taken theirs.
    ///
    /// This has to be a NUMBER, and that is the whole of the first bug in this
    /// surface. `maxHeight: .infinity` on a ScrollView means "grow to what you
    /// are offered", and in a VStack whose other flexible child is a Spacer
    /// the offer is the content's own ideal height — so twenty notes laid out
    /// 1180pt tall inside a 556pt panel. They drew past the bottom of the
    /// panel and, in the floating layout, past `visibleShapeScreenRect` as
    /// well: outside that rect the hosting view returns nil from hitTest, so
    /// the rows were not merely overflowing, they were unclickable
    /// (Marcello, 2026-09-06). Under the notch the same overflow is what ran
    /// them out of the silhouette.
    private var streamBudget: CGFloat {
        if isContainer { return NotesMetrics.notchStreamMaxHeight }
        return max(120, LabMetrics.todoBlockMaxHeight
                   - LabMetrics.panelTopPadding
                   - composerHeight
                   - chrome.tabRow
                   - (store.searchActive ? 46 : 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Composer(focused: $composerFocused, isContainer: isContainer)
                .padding(.horizontal, LabMetrics.barOuterInset)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ComposerHeightKey.self, value: geo.size.height)
                })
                .onPreferenceChange(ComposerHeightKey.self) { composerHeight = $0 }

            if store.searchActive {
                SearchRow()
                    .padding(.horizontal, LabMetrics.barOuterInset)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            streamBody
                // Dimmed while something is BEING WRITTEN, not merely while
                // the field has focus.
                //
                // The composer takes the caret on appear and keeps it, so
                // "focused" is permanently true and the whole history sat at
                // half opacity for ever — every note read as disabled, which
                // is exactly what it looked like (Marcello, 2026-09-06). The
                // design's intent was the composing state, and the honest
                // test for that is whether there is a draft in the field.
                .opacity(store.draft.isEmpty ? 1 : 0.55)
                .animation(Motion.hintFade, value: store.draft.isEmpty)
        }
        .onAppear {
            // The space opens ready to write. Nothing to read first, nothing
            // to click.
            DispatchQueue.main.async { composerFocused = true }
        }
        .onReceive(store.$composerFocusRequest) { _ in
            DispatchQueue.main.async { composerFocused = true }
        }
    }

    @ViewBuilder
    private var streamBody: some View {
        let entries = store.stream
        if entries.isEmpty {
            EmptyStreamState(searching: store.searchActive && !store.searchQuery.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: NotesMetrics.entryGap) {
                        ForEach(entries) { note in
                            NoteEntryRow(
                                note: note,
                                isDragged: draggedNoteID == note.id,
                                showsDropIndicator: dropBeforeID == note.id,
                                dragOffset: draggedNoteID == note.id ? dragOffset : 0,
                                onDrag: { pointerY, travelled in
                                    if draggedNoteID != note.id {
                                        draggedNoteID = note.id
                                        HapticManager.shared.dragBegan()
                                    }
                                    // Screen y grows UPWARD; the row follows
                                    // the pointer, so the offset is negated.
                                    dragOffset = -travelled
                                    updateDropTarget(pointerY: pointerY,
                                                     dragged: note.id, rows: entries)
                                },
                                onDragEnd: { commitReorder(dragged: note.id) },
                                onFrame: { rowFrames[note.id] = $0 }
                            )
                            .id(note.id)
                        }
                    }
                    .padding(.horizontal, LabMetrics.barOuterInset + 10)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                // The arrows moved a selection the list was not following, so
                // past the sixth note you were selecting rows you could not
                // see — still moving, still invisible. The same fault the
                // to-do list had, and the same fix.
                .onChange(of: store.selectedNoteID) { selected in
                    guard let selected else { return }
                    withAnimation(Motion.hintFade) {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }
            .frame(height: min(naturalHeight(of: entries), streamBudget), alignment: .top)
            // The stream ENDS at its own bottom edge. Without this a run of
            // notes taller than the budget kept drawing into the space bar and
            // past the panel, which is how they became unclickable.
            .clipped()
        }
    }

    /// Insert before the first row the pointer has dropped past the middle of.
    ///
    /// Screen coordinates, reported by the rows' own catchers: the drag is
    /// handled in AppKit (see RowClickCatcher), and screen y grows UPWARD, so
    /// "further down the list" means a SMALLER y — hence `>` where the to-do
    /// list, working in flipped SwiftUI space, uses `<`.
    private func updateDropTarget(pointerY: CGFloat, dragged: UUID, rows: [QuickNote]) {
        let landing = rows.first { row in
            guard let frame = rowFrames[row.id] else { return false }
            return pointerY > frame.midY
        }
        guard let landing else {
            let toEnd = rows.last?.id != dragged
            if toEnd && !dropAtEnd { HapticManager.shared.reorderTick() }
            dropBeforeID = nil
            dropAtEnd = toEnd
            return
        }
        let landingIndex = rows.firstIndex { $0.id == landing.id }
        let draggedIndex = rows.firstIndex { $0.id == dragged }
        // Landing on itself, or in the gap directly above itself, is where it
        // already is — say nothing rather than promise a move that won't happen.
        if landing.id == dragged || landingIndex.map({ $0 - 1 }) == draggedIndex {
            dropBeforeID = nil
            dropAtEnd = false
            return
        }
        if dropBeforeID != landing.id { HapticManager.shared.reorderTick() }
        dropBeforeID = landing.id
        dropAtEnd = false
    }

    private func commitReorder(dragged: UUID) {
        if let before = dropBeforeID, before != dragged {
            store.reorder(dragged, before: before)
        } else if dropAtEnd {
            store.moveToEnd(dragged)
        }
        draggedNoteID = nil
        dropBeforeID = nil
        dropAtEnd = false
        dragOffset = 0
    }

    /// Roughly how tall the entries want to be, so a short stream hugs instead
    /// of reserving the whole budget — the panel's second principle. An
    /// estimate on purpose: measuring would cost a layout round-trip on every
    /// keystroke, and being a row out costs one row of scroll.
    private func naturalHeight(of entries: [QuickNote]) -> CGFloat {
        24 + CGFloat(entries.count) * 62
    }
}

// MARK: The composer

private struct Composer: View {
    @FocusState.Binding var focused: Bool
    let isContainer: Bool

    @ObservedObject private var store = NotesStore.shared
    @State private var hover = false
    @Environment(\.colorScheme) private var colorScheme

    /// The same well the to-do capture field sits in, at the same depths.
    ///
    /// It was a flat `fieldWell` fill with a 24pt radius and a 16pt font, and
    /// beside the list's own field it read as another product: different type,
    /// different depth, different key hints (Marcello, 2026-09-06 — "sembrano
    /// veramente due prodotti diversi"). One bar, three roles, was the
    /// handoff's own rule; three roles cannot mean three appearances.
    private var wellOpacity: Double {
        if colorScheme == .dark {
            return focused ? 0.14 : (hover ? 0.18 : 0.22)
        }
        return focused ? 0.03 : (hover ? 0.04 : 0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: LabMetrics.rowInnerGap) {
                ZStack(alignment: .topLeading) {
                    if store.draft.isEmpty {
                        Text(L10n.t("notes.composerPlaceholder"))
                            .font(DSFont.todoTitle)
                            .foregroundStyle(focused ? DSColor.textFaint : DSColor.textHint)
                            .allowsHitTesting(false)
                    }
                    // The user's text is NEVER reformatted — lowercase,
                    // missing punctuation and typos are preserved exactly.
                    TextField("", text: $store.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DSFont.todoTitle)
                        .foregroundStyle(DSColor.textPrimaryBright)
                        .focused($focused)
                        .lineLimit(isContainer ? 2 : 10)
                        .onChange(of: store.draft) { _ in store.draftChanged() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                hint
            }
        }
        // 20 / 12, the creation bar's own insets.
        .padding(.horizontal, LabMetrics.barPaddingH)
        .padding(.vertical, LabMetrics.barPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: LabMetrics.barHeight)
        // A WELL: darker than the panel, with the edge doing the finding —
        // the same reasoning, and the same numbers, as InlineDraftRow.
        .background(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .fill(Color.black.opacity(wellOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .strokeBorder(focused ? NotesMetrics.pillStroke.opacity(0.7)
                                      : Color.dynamicOverlay(light: 0.07, dark: 0.08),
                              lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous))
        .onTapGesture { focused = true }
        .onHover { hovering in
            withAnimation(Motion.hintFade) { hover = hovering }
        }
        .animation(Motion.hintFade, value: focused)
    }

    /// Two keys at the right edge, drawn the way the creation bar draws its
    /// own — a word and a bordered cap at 10pt, not a pair of filled Keycaps.
    private var hint: some View {
        HStack(spacing: 8) {
            if !store.draft.isEmpty {
                Text(store.isWriting ? L10n.t("notes.saving") : L10n.t("notes.saved"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotesMetrics.pillStroke.opacity(0.8))
                    .fixedSize()
                    .transition(.opacity)
            }
            Text(L10n.t("notes.save"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DSColor.textFaint)
                .fixedSize()
            // ⏎, not ⌘S. Return is the confirm key everywhere else in the
            // app — it files a to-do, it commits a step — and Notes was the
            // one surface asking for a modifier to do the same thing.
            // ⇧⏎ still puts in a line break.
            Text("\u{21A9}")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DSColor.textFaint)
                .frame(width: 32, height: 19)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DSColor.textFaint, lineWidth: 1)
                )
        }
        .animation(Motion.hintFade, value: store.draft.isEmpty)
    }
}

// MARK: One entry in the stream

private struct NoteEntryRow: View {
    let note: QuickNote
    /// Where the drop indicator goes, and whether this row is the one moving.
    let isDragged: Bool
    let showsDropIndicator: Bool
    let dragOffset: CGFloat
    let onDrag: (CGFloat, CGFloat) -> Void
    let onDragEnd: () -> Void
    let onFrame: (CGRect) -> Void

    @ObservedObject private var store = NotesStore.shared
    @State private var hover = false

    private var isLanding: Bool { store.landingNoteID == note.id }
    private var isSelected: Bool { store.selectedNoteID == note.id }

    var body: some View {
        rowContent
            // On TOP, not behind: AppKit hit-tests the frontmost subview
            // first, and behind the content it would never be reached.
            .overlay(RowClickCatcher(
                onClick: { store.open(note.id) },
                onHover: { hover = $0 },
                onDrag: onDrag,
                onDragEnd: onDragEnd,
                onFrame: onFrame
            ))
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The to-do list's own title type — 14/medium — not a 15pt
                // semibold of its own. Notes was styled as a separate surface
                // and read as a separate product beside it.
                Text(note.title)
                    .font(DSFont.todoTitle)
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .lineLimit(1)

                // No "generated title" badge (Marcello, 2026-09-06). The
                // stored `titleSource` stays and still does its work — ⌘⇧R
                // regenerates a proposed title, and a hand-typed one locks the
                // model out of that note permanently. It is simply not
                // announced on the row any more: every title here is drawn
                // from the note's own words by an on-device pass, so the badge
                // was labelling the user's own sentence as machine output.

                // A COLUMN, not a tail on the title. Sitting immediately after
                // the title put every timestamp at a different x depending on
                // how long the name happened to be, so a list of times could
                // not be read as a list of times.
                Spacer(minLength: 12)
                Text(Self.stamp(note.updatedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DSColor.textHint)
                    .fixedSize()
            }

            HighlightedPreview(text: note.previewLine,
                               query: store.searchActive ? store.searchQuery : "")
        }
        // The trailing gutter is RESERVED whether anything is drawn in it or
        // not, exactly as the to-do rows reserve theirs — so revealing the
        // affordances cannot reflow the text beside them.
        .padding(.trailing, LabMetrics.rowActionsWidth)
        .overlay(alignment: .trailing) {
            RowActions(showEnter: isSelected, showGrip: hover && !isSelected)
                .opacity(hover || isSelected ? 1 : 0)
        }
        // Padding that does NOT change with state.
        //
        // It used to be applied only while highlighted, so the hover
        // background hugged the text on all sides and the row jumped by 24pt
        // the moment the pointer arrived (Marcello, 2026-09-06). A hover state
        // that resizes the thing being hovered is a hover state that fights
        // the pointer.
        .padding(.horizontal, NotesMetrics.entryInset)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotesMetrics.highlightRadius, style: .continuous)
                .fill(isLanding ? NotesMetrics.pillStroke.opacity(0.12)
                      : (isSelected ? DSColor.focusedRowBackground
                         : (hover ? DSColor.fieldBackground : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotesMetrics.highlightRadius, style: .continuous)
                .strokeBorder(isLanding ? NotesMetrics.pillStroke.opacity(0.3) : Color.clear,
                              lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if showsDropIndicator {
                Capsule()
                    .fill(DSColor.textPrimaryBright)
                    .frame(height: 2)
                    .offset(y: -(NotesMetrics.entryGap / 2 + 1))
            }
        }
        .offset(y: dragOffset)
        .zIndex(isDragged ? 1 : 0)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.t("notes.rename")) { store.open(note.id); store.beginRename() }
            Button(L10n.t("notes.duplicate")) { store.duplicate(note.id) }
            Divider()
            Button(L10n.t("action.delete"), role: .destructive) { store.delete(note.id) }
        }
        .animation(Motion.hoverFade, value: hover)
        .animation(Motion.contentHug, value: isLanding)
    }

    /// Relative while it still means something, absolute once it does not.
    private static func stamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if abs(date.timeIntervalSinceNow) < 120 { return L10n.t("notes.justNow") }
        if calendar.isDateInToday(date) {
            return NotesFormatters.cached("HH:mm").string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return L10n.t("notes.yesterday") + " " + NotesFormatters.cached("HH:mm").string(from: date)
        }
        return NotesFormatters.cached("d MMM").string(from: date)
    }
}

/// The preview line, with search matches picked out in it.
private struct HighlightedPreview: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributed)
            .font(DSFont.checklistItem)
            .lineSpacing(2)
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(2)
    }

    /// AttributedString rather than a row of Texts: the preview has to wrap as
    /// ONE paragraph, and separate views would break it into fragments that
    /// each wrap on their own.
    private var attributed: AttributedString {
        var result = AttributedString(text)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return result }
        var search = result.startIndex
        while let range = result[search...].range(of: trimmed, options: .caseInsensitive) {
            result[range].backgroundColor = NotesMetrics.pillFill
            result[range].foregroundColor = NotesMetrics.pillLabel
            search = range.upperBound
        }
        return result
    }
}

// MARK: Empty state

private struct EmptyStreamState: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(searching ? L10n.t("notes.noMatches") : L10n.t("notes.emptyTitle"))
                .font(.system(size: 16))
                .foregroundStyle(DSColor.textSecondary)
            // No illustration, no icon, no button: the composer above IS the
            // call to action, and anything here would compete with it.
            Text(searching ? L10n.t("notes.noMatchesBody") : L10n.t("notes.emptyBody"))
                .font(.system(size: 13.5))
                .foregroundStyle(DSColor.textHint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }
}

// MARK: Search

private struct SearchRow: View {
    @ObservedObject private var store = NotesStore.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DSColor.textHint)
            TextField(L10n.t("notes.searchPlaceholder"), text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DSColor.textPrimaryBright)
                .focused($focused)
            Keycap(text: "\u{238B}", tone: .onDark, size: 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(DSColor.fieldBackground))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

// MARK: - Note level: the field becomes the title

private struct NoteDetailView: View {
    let note: QuickNote
    let isContainer: Bool

    @ObservedObject private var store = NotesStore.shared
    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool
    @State private var titleDraft = ""
    @State private var body_ = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, LabMetrics.barOuterInset)

            // Editable in place — no separate edit mode, no Save button. The
            // note is the editor.
            ScrollView(.vertical, showsIndicators: true) {
                TextField("", text: $body_, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DSFont.todoTitle)
                    .lineSpacing(5)
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .focused($bodyFocused)
                    .onChange(of: body_) { store.setBody($0, for: note.id) }
                    // Lined up with the text inside the field above it, so
                    // the note reads as one column rather than as a header
                    // and a separate document.
                    .padding(.horizontal, LabMetrics.barPaddingH + LabMetrics.rowInnerGap + 30)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }
            .frame(height: isContainer
                   ? NotesMetrics.notchStreamMaxHeight
                   : max(120, LabMetrics.todoBlockMaxHeight
                         - LabMetrics.panelTopPadding
                         - NotesMetrics.composerMinHeight
                         - NotesMetrics.bottomBarHeight),
                   alignment: .top)
            .clipped()

            bottomBar
        }
        .onAppear {
            body_ = note.content
            titleDraft = note.title
        }
        // Opening a note puts the caret in the CONTENT.
        //
        // It used to land in the title with the title SELECTED, so the first
        // key you pressed after opening a note replaced its name — a rename
        // offered to someone who asked to read (Marcello, 2026-09-06). The
        // caret goes to the end of the body instead, and the title is reached
        // by clicking it or by Rename.
        .onReceive(store.$bodyFocusRequest) { _ in
            guard store.openNoteID == note.id else { return }
            DispatchQueue.main.async { bodyFocused = true }
            FieldCaret.collapseToEnd()
        }
        .onReceive(store.$renameRequest) { _ in
            guard store.openNoteID == note.id else { return }
            DispatchQueue.main.async { titleFocused = true }
            FieldCaret.collapseToEnd()
        }
    }

    /// The SAME field as the composer — same box, same insets, same type.
    ///
    /// One bar in three roles was the handoff's own rule, and three roles
    /// cannot mean three appearances: the composer was 14/medium in a 59pt
    /// well, this was 17/semibold in a 76pt one, and the body below was a
    /// third size again (Marcello, 2026-09-06). They are one input now,
    /// wearing whatever the role needs inside it.
    private var header: some View {
        HStack(spacing: LabMetrics.rowInnerGap) {
            BackButton { store.closeNote() }

            TextField("", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(DSFont.todoTitle)
                .foregroundStyle(DSColor.textPrimaryBright)
                .focused($titleFocused)
                .onSubmit { commitTitle(); store.focusBody() }
                .onChange(of: titleFocused) { if !$0 { commitTitle() } }

            HStack(spacing: 8) {
                Text(store.isWriting ? L10n.t("notes.saving") : L10n.t("notes.saved"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DSColor.textFaint)
                    .fixedSize()
                Text("\u{2318}[")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.textFaint)
                    .frame(width: 32, height: 19)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(DSColor.textFaint, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, LabMetrics.barPaddingH)
        .padding(.vertical, LabMetrics.barPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: LabMetrics.barHeight)
        .background(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .fill(Color.black.opacity(titleFocused ? 0.14 : 0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .strokeBorder(titleFocused ? NotesMetrics.pillStroke.opacity(0.7)
                                           : Color.dynamicOverlay(light: 0.07, dark: 0.08),
                              lineWidth: 1)
        )
        .animation(Motion.hintFade, value: titleFocused)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("\(note.wordCount) " + L10n.t("notes.wordsSuffix"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DSColor.textHint)
            Spacer(minLength: 8)

            Button { store.exportOpenNote() } label: {
                HStack(spacing: 7) {
                    Text(L10n.t("notes.download"))
                        .font(.system(size: 13))
                        .foregroundStyle(DSColor.textPrimaryBright)
                    Keycap(text: "\u{2318}\u{21E7}S", tone: .onDark, size: 9)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
                .background(Capsule().fill(DSColor.fieldBackground))
                .overlay(Capsule().strokeBorder(DSColor.panelBorder, lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { titleFocused = true } label: {
                Text(L10n.t("notes.rename"))
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LabMetrics.barOuterInset + 10)
        .frame(height: NotesMetrics.bottomBarHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(DSColor.hairlineOnPanel).frame(height: 1)
        }
    }

    private func commitTitle() {
        let clean = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != note.title else {
            titleDraft = note.title
            return
        }
        store.rename(note.id, to: clean)
    }
}

/// The way back to the stream.
///
/// It carries a hover state because it is the only way out of an open note
/// that is visible on screen — the space bar belongs to the stream level and
/// is not drawn here — and a control you must find without being told about
/// has to answer the pointer when it arrives.
private struct BackButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hover ? DSColor.textPrimaryBright : LabMetrics.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(hover ? DSColor.fieldBackground : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.hoverFade, value: hover)
        .help(L10n.t("notes.back"))
    }
}

// MARK: - Undo

private struct UndoBar: View {
    let title: String
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text("\u{00AB}\(title)\u{00BB} " + L10n.t("notes.deletedSuffix"))
                .font(.system(size: 12.5))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            Button { store.undoDelete() } label: {
                HStack(spacing: 6) {
                    Text(L10n.t("notes.undo"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(DSColor.textPrimaryBright)
                    Keycap(text: "\u{2318}Z", tone: .onDark, size: 9)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(DSColor.fieldBackground))
        .overlay(Capsule().strokeBorder(DSColor.panelBorder, lineWidth: 0.5))
        .shadow(color: DSColor.shadowSoft, radius: 10, y: 4)
    }
}

// MARK: - The Notes pill in the space bar

/// Always first, never scrolls, no icon.
///
/// The icon was removed rather than redrawn: in this interface a small rounded
/// square with a stroke means one thing, a CHECKBOX, so a three-line glyph in
/// that shape read as something to tick off. Distinction comes from position
/// and state — permanently first, permanently active-styled — not from a new
/// shape (handoff, decision 3).
struct NotesPill: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var notes = NotesStore.shared
    @State private var hover = false

    private var isActive: Bool { store.panelMode == .notes }

    var body: some View {
        HStack(spacing: 5) {
            Text(L10n.t("filter.notes"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? NotesMetrics.pillStroke : DSColor.textPrimary)
            Text("\(notes.notes.count)")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundColor(isActive ? NotesMetrics.pillStroke.opacity(0.65)
                                          : DSColor.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, LabMetrics.tabPaddingH)
        .padding(.vertical, LabMetrics.tabPaddingV)
        // ONE shape in every state.
        //
        // The fill used to interpolate its radius between 48 active and 8
        // resting, so hovering an inactive pill drew a rounded RECTANGLE and
        // clicking it snapped to a capsule — two different objects for one
        // control (Marcello, 2026-09-06: "sembra weird"). The state is the
        // fill and the stroke; the shape does not move.
        .background(Capsule(style: .continuous).fill(
            isActive ? NotesMetrics.pillStroke.opacity(0.16)
                     : (hover ? NotesMetrics.pillStroke.opacity(0.08) : Color.clear)
        ))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    NotesMetrics.pillStroke.opacity(isActive ? 1 : (hover ? 0.7 : 0.45)),
                    style: StrokeStyle(lineWidth: isActive ? 1.5 : 1, dash: [4, 3])
                )
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { NotesStore.shared.enterSpace() }
        .onHover { hover = $0 }
        .animation(Motion.swap, value: isActive)
        .animation(Motion.hoverFade, value: hover)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L10n.t("filter.notes"))
    }
}






