import SwiftUI
import AppKit

// MARK: - The dock's own state: the space menu and the new-space card
//
// Two small surfaces the final flow adds to the B3 dock (OTTO-NOTCH-FINAL-FLOW
// §4.6, §4.7). Both are modal while up — the key router asks them first — and
// both pin the notch open, so a stray pointer move cannot take them away.

@MainActor
final class DockState: ObservableObject {
    static let shared = DockState()

    // The space menu (right-click a dock item)
    @Published var menuSpaceID: UUID?
    /// Keyboard highlight: 0 Rename, 1 Colour, 2 Move left, 3 Move right,
    /// 4 Delete. −1 until an arrow asks, like the gear menu.
    @Published var menuHighlight = -1
    @Published var renaming = false
    @Published var renameText = ""
    @Published var confirmingDelete = false

    // The new-space card (the "+" / ⇧⌘N)
    @Published var isCreatingSpace = false
    @Published var newSpaceName = ""
    @Published var newSpaceTint: SpaceTint = .grocery
    /// The space just made — its empty state says "‹Name› is ready".
    @Published var justCreatedID: UUID?

    static let menuRowCount = 5

    // The note menu (right-click a note in the dock's Notes)
    @Published var noteMenuID: UUID?
    /// 0 Open, 1 Rename, 2 Duplicate, 3 Delete; −1 until an arrow asks.
    @Published var noteMenuHighlight = -1
    static let noteMenuRowCount = 4

    // A note swiped open (two fingers sideways, NoteSwipeDelete)
    @Published var swipedNoteID: UUID?
    /// ≤ 0: how far the row has slid left.
    @Published var swipeOffset: CGFloat = 0
    /// Rest position when open: the 38-pt Delete and its gap.
    static let swipeReveal: CGFloat = 52
    /// Past this, letting go deletes — the full swipe.
    static let swipeCommit: CGFloat = 190

    /// Up, and the notch must not close under it.
    var isBusy: Bool { menuSpaceID != nil || isCreatingSpace || noteMenuID != nil }

    // MARK: Menu

    func openMenu(for id: UUID) {
        BarTipState.shared.dismiss()
        closeNoteMenu()
        cancelNewSpace()
        TodoStore.shared.closeAvatarMenu()
        menuSpaceID = id
        menuHighlight = -1
        renaming = false
        confirmingDelete = false
        renameText = TodoStore.shared.collection(id: id)?.name ?? ""
    }

    func closeMenu() {
        menuSpaceID = nil
        renaming = false
        confirmingDelete = false
        menuHighlight = -1
    }

    func beginRename() {
        guard let id = menuSpaceID else { return }
        renameText = TodoStore.shared.collection(id: id)?.name ?? ""
        renaming = true
    }

    func commitRename() {
        if let id = menuSpaceID { TodoStore.shared.renameCollection(id, to: renameText) }
        closeMenu()
    }

    func setTint(_ tint: SpaceTint) {
        guard let id = menuSpaceID else { return }
        TodoStore.shared.setCollectionTint(id, tint)
    }

    /// ←/→ on the colour row walks the seven swatches.
    func cycleMenuTint(by offset: Int) {
        guard let id = menuSpaceID, let collection = TodoStore.shared.collection(id: id) else { return }
        setTint(Self.step(collection.spaceTint, by: offset))
    }

    func move(by offset: Int) {
        guard let id = menuSpaceID else { return }
        TodoStore.shared.moveCollection(id, by: offset)
    }

    /// The first press asks, the second deletes (final flow 4.6: "with the
    /// existing confirmation" — there was none, so the menu holds it).
    func delete() {
        guard let id = menuSpaceID else { return }
        if confirmingDelete {
            TodoStore.shared.deleteCollection(id)
            closeMenu()
        } else {
            confirmingDelete = true
        }
    }

    func performHighlighted() {
        switch menuHighlight {
        case 0: beginRename()
        case 1: cycleMenuTint(by: 1)
        case 2: move(by: -1)
        case 3: move(by: 1)
        case 4: delete()
        default: closeMenu()
        }
    }

    // MARK: Note menu

    func openNoteMenu(for id: UUID) {
        closeMenu()
        cancelNewSpace()
        TodoStore.shared.closeAvatarMenu()
        NotesStore.shared.selectedNoteID = id
        noteMenuID = id
        noteMenuHighlight = -1
    }

    func closeNoteMenu() {
        noteMenuID = nil
        noteMenuHighlight = -1
    }

    func performNote(_ row: Int) {
        guard let id = noteMenuID else { return }
        let notes = NotesStore.shared
        closeNoteMenu()
        switch row {
        case 0: notes.open(id)
        case 1: notes.open(id); notes.beginRename()
        case 2: notes.duplicate(id)
        case 3: notes.delete(id)       // undoable for five seconds (⌘Z)
        default: break
        }
    }

    // MARK: Swipe

    func swipeNote(_ id: UUID, by delta: CGFloat, ended: Bool) {
        if swipedNoteID != id {
            closeNoteMenu()
            withAnimation(Self.settle) { swipedNoteID = id; swipeOffset = 0 }
        }
        let before = swipeOffset
        // Left only; a little give to the right of rest.
        swipeOffset = min(swipeOffset + delta, 8)
        if (before > -Self.swipeCommit) != (swipeOffset > -Self.swipeCommit) {
            HapticManager.shared.reorderTick()
        }
        guard ended else { return }
        if swipeOffset <= -Self.swipeCommit { return swipeDelete(id) }
        let open = swipeOffset < -Self.swipeReveal * 0.5
        withAnimation(Self.settle) { swipeOffset = open ? -Self.swipeReveal : 0 }
        if !open { swipedNoteID = nil }
    }

    func closeSwipe() {
        withAnimation(Self.settle) { swipeOffset = 0; swipedNoteID = nil }
    }

    func swipeDelete(_ id: UUID) {
        withAnimation(Self.settle) { swipeOffset = 0; swipedNoteID = nil }
        NotesStore.shared.delete(id)   // ⌘Z brings it back for five seconds
    }

    private static var settle: Animation {
        DockMorph.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    // MARK: New space

    func beginNewSpace() {
        closeMenu()
        TodoStore.shared.closeAvatarMenu()
        newSpaceName = ""
        newSpaceTint = TodoStore.shared.nextUnusedTint
        withAnimation(DockMorph.open) { isCreatingSpace = true }
    }

    func cancelNewSpace() {
        guard isCreatingSpace else { return }
        withAnimation(DockMorph.close) { isCreatingSpace = false }
    }

    func cycleNewSpaceTint(by offset: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { newSpaceTint = Self.step(newSpaceTint, by: offset) }
    }

    /// ⏎ or ✓: make it, fold the card back into the dock, land on the new
    /// space with the caret in its first row.
    func createSpace() {
        // Once: ⏎ reaches both the key router and the field's onSubmit.
        guard isCreatingSpace else { return }
        let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tint = newSpaceTint
        let hex = DockTint.swatches[tint.key].map { String(format: "#%06X", $0) } ?? "#9EE0B0"
        // In TWO beats: first the card folds back into the dock as it was,
        // then the new space pops in and takes the highlight. Done at once,
        // the dock was morphing back AND growing a dot AND sliding its
        // highlight, and the whole bar lurched right before settling
        // (Marcello, 2026-10-18).
        withAnimation(DockMorph.close) { isCreatingSpace = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (DockMorph.reduceMotion ? 0.05 : 0.3)) { [weak self] in
            guard let self else { return }
            let collection = TodoStore.shared.addCollection(name: name, colorHex: hex, tint: tint.key)
            self.justCreatedID = collection.id
            TodoStore.shared.selectCollection(collection.id)
            TodoStore.shared.draftWantsFocus = true
        }
    }

    private static func step(_ tint: SpaceTint, by offset: Int) -> SpaceTint {
        let palette = SpaceTint.palette
        let index = palette.firstIndex(where: { $0.key == tint.key }) ?? 0
        return palette[((index + offset) % palette.count + palette.count) % palette.count]
    }

    // MARK: Keys

    enum KeyResult { case consumed, toField, notMine }

    /// Asked first by the key router while the dock is on.
    func handleKey(keyCode: UInt16, shift: Bool, option: Bool, cmd: Bool) -> KeyResult {
        if isCreatingSpace {
            switch keyCode {
            case 53: cancelNewSpace(); return .consumed                         // Esc
            case 48: cycleNewSpaceTint(by: shift ? -1 : 1); return .consumed    // ⇥ / ⇧⇥
            case 36, 76: createSpace(); return .consumed                        // ⏎
            default: return .toField
            }
        }
        if noteMenuID != nil {
            switch keyCode {
            case 53: closeNoteMenu()
            case 125, 126:
                let count = Self.noteMenuRowCount
                noteMenuHighlight = noteMenuHighlight < 0
                    ? (keyCode == 125 ? 0 : count - 1)
                    : ((noteMenuHighlight + (keyCode == 125 ? 1 : -1)) % count + count) % count
            case 36, 76: performNote(max(0, noteMenuHighlight))
            case 51 where cmd: performNote(3)
            default: break
            }
            return .consumed
        }
        if swipedNoteID != nil, keyCode == 53 {
            closeSwipe()
            return .consumed
        }
        guard menuSpaceID != nil else { return .notMine }
        if renaming {
            switch keyCode {
            case 53: renaming = false; return .consumed
            case 36, 76: commitRename(); return .consumed
            default: return .toField
            }
        }
        switch keyCode {
        case 53: closeMenu()
        case 125, 126:
            let count = Self.menuRowCount
            menuHighlight = menuHighlight < 0
                ? (keyCode == 125 ? 0 : count - 1)
                : ((menuHighlight + (keyCode == 125 ? 1 : -1)) % count + count) % count
        case 123, 124:
            if option { move(by: keyCode == 124 ? 1 : -1) }
            else if menuHighlight == 1 { cycleMenuTint(by: keyCode == 124 ? 1 : -1) }
        case 36, 76:
            performHighlighted()
        default: break
        }
        return .consumed
    }
}

// MARK: - The space menu (final flow §4.6, screen 06)
//
// Otto's popover pattern, not a new one: `ottoMenuSurface`, the gear menu's
// rows, padding and highlight, drawn in the container's menu layer so it can
// hang over the list (NotchRootView.ContainerMenuLayer).

struct DockSpaceMenu: View {
    let collection: TodoCollection
    @ObservedObject private var dock = DockState.shared
    @ObservedObject private var store = TodoStore.shared
    @FocusState private var renameFocused: Bool

    private var index: Int { store.visibleCollections.firstIndex { $0.id == collection.id } ?? 0 }

    var body: some View {
        let tint = DockTint(collection.spaceTint)
        VStack(alignment: .leading, spacing: 1) {
            // Header: dot + name, quiet.
            HStack(spacing: 9) {
                Circle().fill(tint.base).frame(width: 8, height: 8)
                Text(collection.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSDock.text2)
                    .lineLimit(1)
            }
            .padding(.horizontal, OttoMenuStyle.rowPaddingH)
            .padding(.top, 6)
            .padding(.bottom, 4)

            if dock.renaming {
                TextField("", text: $dock.renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: OttoMenuStyle.rowFont))
                    .foregroundStyle(DSDock.text)
                    .focused($renameFocused)
                    .onSubmit { dock.commitRename() }
                    .padding(.horizontal, OttoMenuStyle.rowPaddingH)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous)
                        .fill(Color.white.opacity(0.10)))
                    .onAppear { DispatchQueue.main.async { renameFocused = true } }
            } else {
                row(0, label: L10n.t("dock.rename"), shortcut: "\u{21B5}") { dock.beginRename() }
            }

            // Colour: the nine swatches, the current one ringed. More than
            // the row holds, so they SLIDE — a two-finger swipe, or ←/→ on
            // the row, which keeps the current one in view. Wider than the
            // menu, they had pushed it off-centre and its rows to the edge
            // (Marcello, 2026-10-17).
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SpaceTint.palette, id: \.key) { swatch in
                            let color = DockTint(swatch).base
                            let current = swatch.key == collection.spaceTint.key
                            Button { dock.setTint(swatch) } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 17, height: 17)
                                    .padding(2.5)
                                    .overlay(Circle().strokeBorder(current ? color : .clear, lineWidth: 1.5))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .id(swatch.key)
                            .accessibilityLabel(swatch.key)
                            .accessibilityAddTraits(current ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, OttoMenuStyle.rowPaddingH - 2.5)
                    .padding(.vertical, 6)
                }
                .mask(swatchFades)
                .onAppear { proxy.scrollTo(collection.spaceTint.key, anchor: .center) }
                .onChange(of: collection.spaceTint.key) { key in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(key, anchor: .center) }
                }
            }
            .background(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous)
                .fill(dock.menuHighlight == 1 ? Color.white.opacity(0.12) : .clear))

            row(2, label: L10n.t("action.moveLeft"), shortcut: "\u{2325}\u{2190}") { dock.move(by: -1) }
                .disabled(index == 0)
            row(3, label: L10n.t("action.moveRight"), shortcut: "\u{2325}\u{2192}") { dock.move(by: 1) }
                .disabled(index == store.visibleCollections.count - 1)

            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
                .padding(.horizontal, 10).padding(.vertical, 5)

            // Hold to delete (dqnamo's hold-to-confirm): the red fills the
            // row while the pointer holds it, and the space goes when it is
            // full. From the keyboard, ⏎ asks and a second ⏎ deletes.
            HoldToDeleteRow(label: dock.confirmingDelete
                                ? String(format: L10n.t("dock.deleteConfirm"), collection.name)
                                : L10n.t("dock.holdToDelete"),
                            isHighlighted: dock.menuHighlight == 4) {
                TodoStore.shared.deleteCollection(collection.id)
                dock.closeMenu()
            }
        }
        .padding(OttoMenuStyle.padding)
        .frame(width: 248)
        .ottoMenuSurface()
        .animation(.easeOut(duration: 0.15), value: dock.renaming)
        .animation(.easeOut(duration: 0.15), value: dock.confirmingDelete)
    }

    private var swatchFades: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.06),
            .init(color: .black, location: 0.9),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    private func row(_ index: Int, label: String, shortcut: String?, destructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        DockMenuRow(label: label, shortcut: shortcut, destructive: destructive,
                    isHighlighted: dock.menuHighlight == index, action: action)
    }
}

/// Press and hold: the red sweeps across the row from the left over
/// `duration`; let go early and it drains back. Full, it fires once.
private struct HoldToDeleteRow: View {
    let label: String
    let isHighlighted: Bool
    let onComplete: () -> Void

    static let duration: TimeInterval = 1.2
    private static let red = Color(hex: "#FF6961")

    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var hover = false
    @State private var finish: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(Self.red.opacity(hover || isHighlighted || holding ? 0.12 : 0))
            text(Self.red)
            // The fill and its white label, revealed left to right.
            ZStack(alignment: .leading) {
                shape.fill(Self.red)
                text(.white)
            }
            .mask(Rectangle().scaleEffect(x: progress, y: 1, anchor: .leading))
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { hovering in withAnimation(NotchAnimation.hoverFade) { hover = hovering } }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !holding { begin() } }
            .onEnded { _ in cancel() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onComplete() }
    }

    private func text(_ color: Color) -> some View {
        Text(label)
            .font(.system(size: OttoMenuStyle.rowFont, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, OttoMenuStyle.rowPaddingH)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func begin() {
        holding = true
        withAnimation(.linear(duration: Self.duration)) { progress = 1 }
        let work = DispatchWorkItem {
            guard holding else { return }
            holding = false
            HapticManager.shared.itemDeleted()
            onComplete()
        }
        finish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    private func cancel() {
        finish?.cancel()
        guard holding else { return }
        holding = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3)) { progress = 0 }
    }
}

// MARK: - The note menu (right-click a note, Marcello 2026-10-17)
//
// The space menu's surface and rows for a note: Open, Rename, Duplicate,
// Delete. Delete needs no hold — a note comes back with ⌘Z for five seconds.
// The row also swipes (NoteSwipe) to reach Delete without a menu.

struct DockNoteMenu: View {
    let note: QuickNote
    @ObservedObject private var dock = DockState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(note.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSDock.text2)
                .lineLimit(1)
                .padding(.horizontal, OttoMenuStyle.rowPaddingH)
                .padding(.top, 6)
                .padding(.bottom, 4)
            row(0, label: L10n.t("dock.openNote"), shortcut: "\u{21B5}")
            row(1, label: L10n.t("notes.rename"), shortcut: nil)
            row(2, label: L10n.t("notes.duplicate"), shortcut: nil)
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
                .padding(.horizontal, 10).padding(.vertical, 5)
            row(3, label: L10n.t("action.delete"), shortcut: "\u{2318}\u{232B}", destructive: true)
        }
        .padding(OttoMenuStyle.padding)
        .frame(width: 220)
        .ottoMenuSurface()
    }

    private func row(_ index: Int, label: String, shortcut: String?, destructive: Bool = false) -> some View {
        DockMenuRow(label: label, shortcut: shortcut, destructive: destructive,
                    isHighlighted: dock.noteMenuHighlight == index) { dock.performNote(index) }
    }
}

private struct DockMenuRow: View {
    let label: String
    let shortcut: String?
    let destructive: Bool
    let isHighlighted: Bool
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: OttoMenuStyle.rowFont))
                    .foregroundStyle(destructive ? Color(hex: "#FF6961") : DSDock.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: OttoMenuStyle.shortcutFont))
                        .foregroundStyle(DSDock.text3)
                }
            }
            .padding(.horizontal, OttoMenuStyle.rowPaddingH)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous)
                .fill(hover || isHighlighted ? Color.white.opacity(0.12) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering in withAnimation(NotchAnimation.hoverFade) { hover = hovering } }
    }
}

// MARK: - Right-click, without stealing left clicks
//
// SwiftUI on macOS 13 has no right-click gesture, and `.contextMenu` is the
// system menu, not Otto's popover. This AppKit view answers hit tests only
// while a right-button event is being delivered, so a left click, a hover and
// a drag go straight through to the dock item underneath.

struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    final class CatcherView: NSView {
        var onRightClick: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type,
                  type == .rightMouseDown || type == .rightMouseUp else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) {
            // Claimed, so the panel's native Settings / Quit menu stays shut.
            NotchController.shared.rightClickClaimedAt = event.timestamp
            onRightClick()
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onRightClick = onRightClick }
}

// MARK: - Morph timing (final flow §7.3)

enum DockMorph {
    /// Dock → card. A smooth deceleration, no overshoot: the slight overshoot
    /// of the first version moved the bar's side columns right and back.
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    }
    /// Card → dock: the same curve, a little quicker.
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.34)
    }
    /// Notes and Settings stepping aside and back.
    static var side: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.3)
    }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
