import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tab row — CategoryTabChips + NewSectionButton (design PRD §3.1)
//
// Drift table §10: a tab is label + its remaining count, NOTHING else (#4);
// badges exist only while ⌘ is held (#2); the active tab wears its own
// category color at regular weight (#1). The count replaced the progress
// ring on 2026-07-23 — see CategoryTabChip. Tabs drag to reorder; the "+"
// is structural and never moves.
//
// The "+" changed both position and meaning on 2026-08-16. It used to lead
// the row as a filled chip meaning "new to-do", which was the most prominent
// thing in the panel; now that a to-do is made by typing into the list
// itself, the only thing left for a button to create is a SECTION. So it
// moved to the end of the tabs and lost its fill — it is ordinary chrome
// now, not the primary action. The "•••" overflow went with it: everything
// it held (set default, reorder, delete) is already on each tab's own
// context menu, so it was a second door to one room.

struct TodoTabRow: View {
    /// Which side of the row the gap to the list is on.
    ///
    /// It is a parameter and not a nudge because the gap's placement is
    /// load-bearing: the pills sit on whichever side the list is NOT, so the
    /// breathing room has to be on the side facing the rows. Getting this
    /// wrong is what once drew the old divider inside the list's own area and
    /// made the last row appear to continue past the panel's edge.
    enum RulePosition { case above, below }

    var rulePosition: RulePosition = .above

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ObservedObject private var store = TodoStore.shared
    /// The category tab currently being dragged (nil when idle).
    @State private var draggedCollectionID: UUID?
    /// The tab the dragged one would land in FRONT of. Arc's model, the same
    /// one the to-do list uses: dragging only ever moves the indicator, and
    /// the row itself is left alone until the drop lands.
    ///
    /// It used to reorder live inside `dropEntered`, which on a horizontal
    /// row is worse than on a vertical one — re-slotting shifts every tab
    /// sideways under the cursor, which immediately fires the next
    /// `dropEntered`, and the tabs flip back and forth for as long as you hold
    /// the drag (Marcello: "we need to implement the possibility to swap the
    /// ordering by dragging" — it was implemented, it just never settled).
    @State private var dropBeforeCollectionID: UUID?
    /// True when the drop would land past the last tab.
    @State private var dropCollectionAtEnd = false
    @State private var tabsContentWidth: CGFloat = 0
    @State private var tabsViewportWidth: CGFloat = 0

    /// Only scroll if there is genuinely something off the edge. A horizontal
    /// ScrollView and a sideways drag compete for the same gesture and the
    /// ScrollView wins, so an always-on scroller costs the drag and buys
    /// nothing while every tab is already visible.
    private var tabsOverflow: Bool {
        tabsViewportWidth > 0 && tabsContentWidth > tabsViewportWidth + 1
    }

    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels
    private var isContainerLayout: Bool { notchLayout == .container }

    var body: some View {
        HStack(spacing: 6) {
            // Notes is the ONLY permanent pill here now.
            //
            // Insights had one beside it, which made the two the same rank —
            // and they are not: Notes is a space you work in every day,
            // Insights is a page you read once a week. It has moved into the
            // avatar menu, where per-user, non-daily things belong, and the
            // lists row gets back the ~100pt the pill was taking.
            //
            // FIRST, and outside the scroller.
            //
            // A user can have ten or fifteen lists; there is exactly one Notes
            // space. Inside the scrolling strip it would leave the screen the
            // moment the lists overflowed — the same way the "+" once did —
            // and the one space that is always there must always be reachable.
            // First claim on the row's width: when the lists overflow, the
            // scroller gives way, not these two (their ends were being cut).
            NotesPill().layoutPriority(1)
            // No Calendar pill: meeting notes are a view inside Notes now
            // (NotesKindMenu), not a third global section.

            // A rule, because the two sides of it are different kinds of
            // thing. Notes is one permanent space; the lists are many and they
            // scroll. Without it the bar read as one row of equals in which
            // the first item simply refused to move (Marcello, 2026-09-06).
            Rectangle()
                // Dark ink in light mode: white at 12% vanished there.
                .fill(Color.dynamicOverlay(light: 0.15, dark: 0.12))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            tabScroller

            // OUTSIDE the scroller, like the account button beside it.
            //
            // "New section" lives INSIDE the scroller now, after the last tab.
            //
            // It was pulled out on 2026-08-23 for a good reason — at five
            // sections it scrolled off the end and there was no way left to
            // make one ("I have lost the plus"). That objection is answered
            // rather than ignored: the act has a key now, ⇧⌘N, so it can no
            // longer become unreachable by scrolling, and pinned to the right
            // edge it had stopped reading as a member of the row and started
            // reading as chrome bolted to the panel (Marcello, 2026-09-20).
            //
            // If it ever loses the shortcut, it has to come back out here.

            Spacer(minLength: PanelMetrics.tabsGap)
            // Outside the scroller: settings is not a tab. The gear replaced
            // the avatar (U5 §5.2); it opens the same menu.
            SettingsGearButton()
        }
        // Floating chrome, not a container divider — the Notes bottom bar set
        // this precedent (§9). No static strip behind the pills and no hairline
        // rule any more: the row is glass pills over the panel, grouped so the
        // material samples them together on macOS 26. What separates the
        // scrolling rows from the pills is the shared fade + frosted material.
        .glassGroup(spacing: 6)
        // No rule under the tab row (Marcello, 2026-07-26). The two paddings
        // stay: they were the breathing room either side of the line, and
        // together they are what now separates the tabs from the list.
        // U5's footer in the floating panels: 16 at the sides, 12 above and
        // 14 below, replacing the paddings further down.
        .padding(.horizontal, isContainerLayout ? PanelMetrics.tabsInset : 16)
        .padding(.top, isContainerLayout ? 0 : 12)
        // 16: the gear sits in the corner 16 from both edges, like every
        // other corner element (SpaceChrome.cornerInset).
        .padding(.bottom, isContainerLayout ? 0 : SpaceChrome.cornerInset)
        // The gap that used to hold the rule stays a gap — the pills still
        // need breathing room from the list, just with nothing drawn in it.
        // It is part of the row's own LAYOUT, not an overlay pushed out of
        // it: the old rule was once drawn 12pt above this row's top edge,
        // inside the area the list occupies, and the last row and the rule
        // painted over each other (Marcello, 2026-08-22).
        .padding(.top, isContainerLayout && rulePosition == .above ? PanelMetrics.tabsDividerPaddingV : 0)
        .padding(.bottom, isContainerLayout && rulePosition == .below ? PanelMetrics.tabsDividerPaddingV : 0)
        // The outer breathing room mirrors as well, so the row keeps the same
        // distance from the panel edge whichever end it sits at.
        .padding(.top, !isContainerLayout ? 0 : (rulePosition == .above ? PanelMetrics.tabsTopPadding
                                                                         : PanelMetrics.tabsBottomPadding))
        .padding(.bottom, !isContainerLayout ? 0 : (rulePosition == .above ? PanelMetrics.tabsBottomPadding
                                                                            : PanelMetrics.tabsTopPadding))

        // No background here. A frosted band behind the pills was the second
        // of two surfaces in this panel, and its top edge was the hard line
        // under the list — see TodoScrollEdgeEffect for the whole story.
        .zIndex(1)

    }

    private var tabScroller: some View {
        // ScrollViewReader so the KEYBOARD can drag the strip.
        //
        // ←/→ walk the sections, and past the fourth or fifth the selected one
        // was simply off-screen: the highlight moved somewhere you could not
        // see, so the bar said nothing about which section you were now in
        // (Marcello, 2026-09-20). The same fix the Notes stream already uses
        // for its own rows.
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.visibleCollections.enumerated()), id: \.element.id) { index, collection in
                    // NOT a Button, deliberately — and this is the whole
                    // reason tabs could not be dragged at all.
                    //
                    // A SwiftUI Button on macOS installs its own press gesture
                    // that claims the mouse-down and everything after it, so an
                    // `.onDrag` attached alongside never gets to begin a drag
                    // session. The chip was a Button; the to-do row, which has
                    // always dragged fine, is a plain view with
                    // `.contentShape` + `.onTapGesture` + `.onDrag`. Same
                    // recipe here now.
                    //
                    // Tapping still selects, and the semantics are restored
                    // explicitly below so VoiceOver still calls it a button.
                    CategoryTabChip(
                        title: collection.name,
                        tint: collection.spaceTint,
                        isActive: store.panelMode == .browsing
                            && collection.id == store.activeCollectionID,
                        remaining: store.remainingCount(for: collection)
                    )
                    .id(collection.id)
                    .contentShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
                    // 180 ms on a click; the keyboard path switches instantly
                    // (U5 §5.1).
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { store.selectCollection(collection.id) }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(collection.name)
                    // Drag a tab onto another to change the order. Only
                    // category chips participate — the "+" is structural and
                    // never moves (Marcello, 2026-07-23).
                    .opacity(draggedCollectionID == collection.id ? 0.4 : 1)
                    .onDrag {
                        draggedCollectionID = collection.id
                        return .ottoInternal(collection.id)
                    } preview: {
                        // Without an explicit preview SwiftUI snapshots the
                        // chip itself — and an INACTIVE chip has a clear
                        // background, so the dragged tab was a few floating
                        // words with nothing behind them and read as a glitch
                        // (Marcello, 2026-08-04). Give it a surface.
                        HStack(spacing: 5) {
                            Circle()
                                .fill(collection.color)
                                .frame(width: 7, height: 7)
                            Text(collection.name)
                                .font(DSFont.tabLabel)
                                .foregroundStyle(DSColor.textPrimaryBright)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            DSShape.squircle(DSRadius.chipCorner)
                                .fill(DSColor.fieldBackground)
                        )
                        .overlay(
                            DSShape.squircle(DSRadius.chipCorner)
                                .strokeBorder(DSColor.panelBorder, lineWidth: 0.5)
                        )
                    }
                    // Drawn in the gap BEFORE this tab so it never displaces
                    // anything — an inserted view would make the row jump
                    // under the cursor, which is the whole bug being fixed.
                    .overlay(alignment: .leading) {
                        if dropBeforeCollectionID == collection.id {
                            TabDropIndicator().offset(x: -5)
                        }
                    }
                    .onDrop(of: [.ottoInternalItem], delegate: CollectionReorderDropDelegate(
                        targetID: collection.id,
                        draggedID: $draggedCollectionID,
                        dropBeforeID: $dropBeforeCollectionID,
                        dropAtEnd: $dropCollectionAtEnd
                    ))
                    .contextMenu {
                        // No "set as default" item any more. Where ⌃⇧N files
                        // is decided by tab ORDER — drag the section you use
                        // most to the front — so a second, invisible way to
                        // set the same thing could only contradict it.
                        Button(L10n.t("todo.newCollection") + "\u{2026}") {
                            store.setMode(.newCategory)
                            NotchController.shared.focusPanel()
                        }
                        Divider()
                        Button(L10n.t("action.moveLeft")) {
                            store.moveCollection(collection.id, by: -1)
                        }
                        .disabled(index == 0)
                        Button(L10n.t("action.moveRight")) {
                            store.moveCollection(collection.id, by: 1)
                        }
                        .disabled(index == store.visibleCollections.count - 1)
                        if !collection.isSystemToday {
                            Divider()
                            Button(L10n.t("action.delete"), role: .destructive) {
                                store.deleteCollection(collection.id)
                            }
                        }
                    }
                }

                // CT-5 still holds — exactly ONE "+" in the row — but it now
                // means "new section", and sits after the last tab rather
                // than in front of the first. The extra 4pt is deliberate: at
                // the tabs' own 8pt spacing it read as a fourth tab rather
                // than an action, which is the one risk of putting it here.
                // Landing strip for the last slot: `moveCollection(_:before:)`
                // can only insert in front of a tab, so without this the
                // trailing position cannot be reached by dragging.
                if draggedCollectionID != nil {
                    Color.clear
                        .frame(width: 18, height: 22)
                        .overlay(alignment: .leading) {
                            if dropCollectionAtEnd { TabDropIndicator() }
                        }
                        .onDrop(of: [.ottoInternalItem], delegate: CollectionEndDropDelegate(
                            draggedID: $draggedCollectionID,
                            dropBeforeID: $dropBeforeCollectionID,
                            dropAtEnd: $dropCollectionAtEnd
                        ))
                }

                // Last in the strip, after the tabs it creates siblings for.
                // It scrolls with them: it is a member of the row, not chrome
                // bolted to the panel's right edge.
                NewSectionButton()

            }
            .animation(NotchAnimation.hintFade, value: dropBeforeCollectionID)
            .animation(NotchAnimation.hintFade, value: dropCollectionAtEnd)
            // Two points of slack inside the scroller, given back outside it.
            //
            // THE FIRST TAB IS CUT, and this is the third attempt at it, so
            // the cause is worth writing down. A ScrollView clips to its own
            // bounds. The first chip's capsule starts at exactly x = 0 of the
            // content, so the clip edge and the leftmost column of the
            // capsule's curve are the same column — and an antialiased curve
            // has nothing to spare there. The left cap loses its softest pixels
            // and the chip reads as sliced off, most visibly on the ACTIVE tab
            // because that one is filled (Marcello: "la prima section rimane
            // sempre tagliata", 2026-09-05 and again 2026-09-06).
            //
            // Removing `matchedGeometryEffect` was the previous fix; it was a
            // real bug and a different one. This is the boundary itself.
            //
            // The negative padding on the ScrollView below widens the clip by
            // the same 2pt, so nothing MOVES: the chips keep their positions
            // and only the edge they are measured against steps outward.
            .padding(.horizontal, 2)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TabsContentWidthKey.self,
                                           value: proxy.size.width)
                }
            )
            // No top padding here. It used to reserve headroom for the
            // ⌘-held index badges (offset y:-8) drawn above each chip; the
            // badges are gone, but the padding stayed and pushed every chip
            // 8pt below AccountButton, which sits in the outer row with no
            // matching offset — the avatar visibly floating above the tabs'
            // midline (Marcello, 2026-08-09).
        }
        .scrollDisabled(!tabsOverflow)
        // A soft trailing edge when, and only when, there is more to reach.
        //
        // Chosen over a literal "…" or a "More" label: both are controls the
        // reader has to interpret, and a chip half-dissolved at the edge says
        // "this continues" in the language the panel already speaks — the
        // to-do list fades at its own bottom edge for the same reason. It
        // disappears at rest so a bar that fits shows no decoration at all.
        .mask(
            LinearGradient(
                stops: tabsOverflow
                    ? [.init(color: .black, location: 0),
                       .init(color: .black, location: 0.88),
                       .init(color: .black.opacity(0), location: 1)]
                    : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                startPoint: .leading, endPoint: .trailing)
        )
        .animation(NotchAnimation.hintFade, value: tabsOverflow)
        .padding(.horizontal, -2)          // see the slack above
        .onPreferenceChange(TabsContentWidthKey.self) { tabsContentWidth = $0 }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TabsViewportWidthKey.self,
                                       value: proxy.size.width)
            }
        )
        .onPreferenceChange(TabsViewportWidthKey.self) { tabsViewportWidth = $0 }
        // Keep the ACTIVE section in view whenever it changes, however it
        // changed — arrows, ⌘1-9, or a click on a half-visible chip.
        //
        // `.center` rather than `.leading`: entering from either side lands
        // the same way, so walking right and walking back left do not scroll
        // by different amounts. Animated with the panel's own content curve so
        // the strip slides rather than jumping.
        .onChange(of: store.activeCollectionID) { active in
            guard let active, tabsOverflow else { return }
            withAnimation(NotchAnimation.contentHug) {
                proxy.scrollTo(active, anchor: .center)
            }
        }
        // …and when this row is NEW. The bar is drawn in one of two places
        // (in the column, or over the list's foot once the list is long), so
        // walking from a short section to a long one builds a fresh row
        // scrolled to its start — the change above never fires for it and
        // the selected section sat off-screen (Marcello, 2026-09-30). The
        // width is only known a pass later, hence also on the overflow flag.
        .onAppear {
            DispatchQueue.main.async {
                if let active = store.activeCollectionID { proxy.scrollTo(active, anchor: .center) }
            }
        }
        .onChange(of: tabsOverflow) { overflow in
            guard overflow, let active = store.activeCollectionID else { return }
            proxy.scrollTo(active, anchor: .center)
        }
        }
    }
}

// MARK: - Category tab drag-to-reorder

struct CollectionReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var dropBeforeID: UUID?
    @Binding var dropAtEnd: Bool

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID, dragged != targetID else { return }
        dropBeforeID = targetID
        dropAtEnd = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggedID == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { clear() }
        guard let dragged = draggedID, dragged != targetID else { return false }
        TodoStore.shared.moveCollection(dragged, before: targetID)
        return true
    }

    func dropExited(info: DropInfo) {
        // Only retract the indicator if it is still ours — the next tab's
        // dropEntered may already have claimed it.
        if dropBeforeID == targetID { dropBeforeID = nil }
    }

    private func clear() {
        draggedID = nil
        dropBeforeID = nil
        dropAtEnd = false
    }
}

/// The strip after the last tab: drops here send the section to the end.
struct CollectionEndDropDelegate: DropDelegate {
    @Binding var draggedID: UUID?
    @Binding var dropBeforeID: UUID?
    @Binding var dropAtEnd: Bool

    func dropEntered(info: DropInfo) {
        guard draggedID != nil else { return }
        dropBeforeID = nil
        dropAtEnd = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggedID == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedID = nil; dropBeforeID = nil; dropAtEnd = false }
        guard let dragged = draggedID else { return false }
        TodoStore.shared.moveCollectionToEnd(dragged)
        return true
    }

    func dropExited(info: DropInfo) { dropAtEnd = false }
}

/// The landing slot between two tabs — a vertical bar, since the tab row runs
/// horizontally. `DropIndicator` is the list's horizontal equivalent.
struct TabDropIndicator: View {
    var body: some View {
        Capsule()
            .fill(DSColor.textPrimaryBright.opacity(0.85))
            .frame(width: 2, height: 18)
            .transition(.opacity)
    }
}

// MARK: - NewSectionButton — "New section" at the end of the tabs
//
// A WORD, not a glyph. The "+" was two crossing lines with no label, which
// makes the one structural act in this bar the only thing in it you have to
// already know (Marcello, 2026-09-20). It reads as a normal member of the row
// now — same type, same weight as an inactive tab — and it says what it does.
//
// Creating a section is rare, so it is never louder than the tabs beside it.
// Everything ELSE about a section — default, reorder, delete — is on that
// section's own right-click menu, where it applies to the tab you are pointing
// at rather than to whichever one happened to be active.
//
// ⇧⌘N does the same thing from the keyboard. ⌘N was already the new TO-DO, and
// the two are close enough on purpose: same verb, one level apart.

struct NewSectionButton: View {
    @State private var hover = false

    var body: some View {
        Button {
            TodoStore.shared.setMode(.newCategory)
            NotchController.shared.focusPanel()
        } label: {
            // A pill of its own after the last section, the tabs' size and
            // shape (Marcello, 2026-09-30: "a pill next to the last
            // section"). Dashed, like the empty step slot: a place for a
            // section rather than a section.
            HStack(spacing: 5) {
                OttoIcon("plus", pointSize: 11)
                Text(L10n.t("todo.newSection"))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hover ? DSColor.textPrimary : DSColor.textSecondary)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(hover ? DSColor.fieldBackground : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(DSColor.textSecondary.opacity(hover ? 0.45 : 0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        .help(L10n.t("todo.newCollection"))
        .accessibilityLabel(L10n.t("todo.newCollection"))
    }
}
