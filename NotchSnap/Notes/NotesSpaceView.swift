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
// caret in the composer. The user types the note; on ⌘S it drops into the
// stream and the model proposes a name afterwards. The title is a proposal,
// never a gate — people offloading a thought do not want to file it first.

// MARK: Metrics

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
                // While the composer holds the caret the entry being written is
                // the only thing in focus; the history steps back rather than
                // competing with it.
                .opacity(composerFocused ? 0.5 : 1)
                .animation(Motion.hintFade, value: composerFocused)
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
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: NotesMetrics.entryGap) {
                    ForEach(entries) { note in
                        NoteEntryRow(note: note)
                            .id(note.id)
                    }
                }
                .padding(.horizontal, LabMetrics.barOuterInset + 10)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .frame(height: min(naturalHeight(of: entries), streamBudget), alignment: .top)
            // The stream ENDS at its own bottom edge. Without this a run of
            // notes taller than the budget kept drawing into the space bar and
            // past the panel, which is how they became unclickable.
            .clipped()
        }
    }

    /// Roughly how tall the entries want to be, so a short stream hugs instead
    /// of reserving the whole budget — the panel's second principle. An
    /// estimate on purpose: measuring would cost a layout round-trip on every
    /// keystroke, and being a row out costs one row of scroll.
    private func naturalHeight(of entries: [QuickNote]) -> CGFloat {
        28 + CGFloat(entries.count) * 59
    }
}

// MARK: The composer

private struct Composer: View {
    @FocusState.Binding var focused: Bool
    let isContainer: Bool

    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty {
                    Text(L10n.t("notes.composerPlaceholder"))
                        .font(.system(size: 16))
                        .foregroundStyle(DSColor.textHint)
                        .allowsHitTesting(false)
                }
                // The user's text is NEVER reformatted — lowercase, missing
                // punctuation and typos are preserved exactly. This field
                // stores what was typed and shows what was stored.
                TextField("", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .focused($focused)
                    .lineLimit(isContainer ? 2 : 10)
                    .onChange(of: store.draft) { _ in store.draftChanged() }
            }
            .frame(maxHeight: isContainer ? NotesMetrics.notchComposerMaxHeight
                                          : NotesMetrics.composerMaxHeight,
                   alignment: .topLeading)

            footer
        }
        .padding(.horizontal, NotesMetrics.fieldPaddingH)
        .padding(.vertical, NotesMetrics.fieldPaddingV)
        .frame(minHeight: NotesMetrics.composerMinHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: NotesMetrics.fieldRadius, style: .continuous)
                .fill(DSColor.fieldWell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotesMetrics.fieldRadius, style: .continuous)
                .strokeBorder(focused ? LabMetrics.accent.opacity(0.45) : DSColor.panelBorder,
                              lineWidth: focused ? 1 : 0.5)
        )
        .animation(Motion.hoverFade, value: focused)
        .contentShape(RoundedRectangle(cornerRadius: NotesMetrics.fieldRadius, style: .continuous))
        .onTapGesture { focused = true }
    }

    /// One word for the status, and the keystroke shown the way the capture
    /// field already shows ⇥. No Save button — saving is continuous, and ⌘S
    /// means "close this entry", not "persist it".
    private var footer: some View {
        HStack(spacing: 8) {
            if !store.draft.isEmpty {
                Text(store.isWriting ? L10n.t("notes.saving") : L10n.t("notes.saved"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(LabMetrics.accent.opacity(0.85))
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            Text(L10n.t("notes.save"))
                .font(.system(size: 13))
                .foregroundStyle(DSColor.textHint)
            Keycap(text: "\u{2318}S", tone: .onDark, size: 9)
        }
    }
}

// MARK: One entry in the stream

private struct NoteEntryRow: View {
    let note: QuickNote

    @ObservedObject private var store = NotesStore.shared
    @State private var hover = false

    private var isLanding: Bool { store.landingNoteID == note.id }
    private var isSelected: Bool { store.selectedNoteID == note.id }

    var body: some View {
        // A Button, not a bare `.onTapGesture`.
        //
        // The panel carries a full-width DeselectCatcher and the composer
        // carries its own tap, so a plain tap gesture on a row is one of
        // several peers over the same point — and SwiftUI resolves peers
        // unpredictably. That is the same fault that made Snooze take the
        // second or third click while Join, a Button beside it, always worked
        // (2026-09-06). The to-do rows are not a counter-example: their clicks
        // are handled by EntityTextView, a real NSView, not by SwiftUI
        // gesture resolution at all.
        Button(action: { store.open(note.id) }) { rowContent }
            .buttonStyle(.plain)
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(note.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .lineLimit(1)

                // Disclosure, not decoration: while the name is the model's,
                // the row says so and ⌘⇧R is available. It disappears the
                // moment the user types their own.
                if note.titleSource == .generated {
                    Text(L10n.t("notes.generatedBadge"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(LabMetrics.accent.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DSColor.fieldBackground))
                        .overlay(Capsule().strokeBorder(DSColor.panelBorder, lineWidth: 0.5))
                        // Late on purpose: a title that changes while the row
                        // is still moving reads as a glitch.
                        .transition(.opacity)
                }

                Text(Self.stamp(note.updatedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DSColor.textHint)
                Spacer(minLength: 0)
            }

            HighlightedPreview(text: note.previewLine, query: store.searchActive ? store.searchQuery : "")
        }
        .padding(.horizontal, NotesMetrics.entryInset)
        .padding(.vertical, isLanding || isSelected ? NotesMetrics.entryInset : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotesMetrics.highlightRadius, style: .continuous)
                .fill(isLanding ? LabMetrics.accent.opacity(0.10)
                      : (isSelected ? DSColor.focusedRowBackground
                         : (hover ? DSColor.fieldBackground : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotesMetrics.highlightRadius, style: .continuous)
                .strokeBorder(isLanding ? LabMetrics.accent.opacity(0.24) : Color.clear,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
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
            .font(.system(size: 14))
            .lineSpacing(3)
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
                    .font(.system(size: 15.5))
                    .lineSpacing(6)
                    .foregroundStyle(DSColor.textPrimaryBright)
                    .focused($bodyFocused)
                    .onChange(of: body_) { store.setBody($0, for: note.id) }
                    .padding(.horizontal, NotesMetrics.fieldPaddingH)
                    .padding(.top, 22)
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
        .onReceive(store.$renameRequest) { _ in
            guard store.openNoteID == note.id else { return }
            DispatchQueue.main.async { titleFocused = true }
        }
    }

    /// The same 76pt field at the same radius in the same place — which is
    /// exactly why an open note needs no header bar of its own.
    private var header: some View {
        HStack(spacing: 16) {
            BackButton { store.closeNote() }

            TextField("", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DSColor.textPrimaryBright)
                .focused($titleFocused)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocused) { if !$0 { commitTitle() } }

            Text(store.isWriting ? L10n.t("notes.saving") : L10n.t("notes.saved"))
                .font(.system(size: 12.5))
                .foregroundStyle(DSColor.textHint)
            Keycap(text: "\u{2318}[", tone: .onDark, size: 9)
        }
        .padding(.horizontal, NotesMetrics.fieldPaddingH)
        .frame(minHeight: NotesMetrics.composerMinHeight)
        .background(
            RoundedRectangle(cornerRadius: NotesMetrics.fieldRadius, style: .continuous)
                .fill(DSColor.fieldWell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotesMetrics.fieldRadius, style: .continuous)
                .strokeBorder(DSColor.panelBorder, lineWidth: 0.5)
        )
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






