import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - TodoBrowsingView — the list + Completed (browsing mode content)

struct TodoBrowsingView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var archive = CompletedArchive.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels

    /// The container is a hole in the hardware and keeps its black ground; the
    /// floating panels are a card over the desktop and keep their material.
    private var isContainerLayout: Bool { notchLayout == .container }

    /// FB3+4: ONE scroll region for the whole browsing body (open list +
    /// Completed together), capped to the panel's budget. Two independent
    /// caps (a 300px list + a 120px completed) could sum past the panel and
    /// overflow — that's what pushed the tabs off the top and squeezed
    /// Completed into a tiny window. Below the threshold everything renders
    /// inline (natural height, no scroll, no switch-lag flash).
    /// Height budget for the scrolling region.
    ///
    /// This was a flat 400. With a long list the frame was already pinned at
    /// the cap, so opening Completed grew the CONTENT but not the panel — the
    /// notch did not move and the completed rows appeared only if you thought
    /// to scroll (Marcello, 2026-08-04). Opening a section has to be visible.
    ///
    /// So: derived from the actual screen rather than a magic number, and
    /// allowed to grow when Completed is open. It stays bounded — the panel
    /// hangs from the top of the display and must not run off the bottom.
    /// The scroll region's ceiling, derived from the notch's OWN budget minus
    /// the chrome above and below it. It used to be an independent screen
    /// fraction capped at 720, while the silhouette could only show ~539pt of
    /// content — so the region cheerfully laid out rows the notch could never
    /// display (Marcello, 2026-08-05). One source now, two consumers.
    ///
    /// Everything that is not the list comes out of the same budget: the
    /// creation bar, the section row, the pinned Completed section. A region
    /// that ignored any of them would lay out rows in the strip that thing is
    /// standing on — which is precisely what it did, three times, each time
    /// with a different piece of furniture (see `PanelChrome`).
    private static func maxRegion(chrome: PanelChrome, completedInset: CGFloat,
                                  isContainer: Bool) -> CGFloat {
        // The panel's ceiling, 556, minus its furniture — MEASURED, so
        // restyling any of it carries through here without a second edit.
        PanelMetrics.todoBlockMaxHeight
            - (isContainer ? PanelMetrics.panelTopPadding : 0)
            - chrome.draftBlock
            - (isContainer ? chrome.tabRow : 0)
            // The pinned Completed section, which sits BELOW the scroll
            // region — MEASURED, not assumed.
            //
            // Adding it without subtracting it at all is what pushed the panel
            // past the block's fixed 556 the first time; subtracting a 24pt
            // constant left half of it still unaccounted for, because the
            // header also carries 24pt of top padding and grows to 160 when
            // the section is open. Both times the tab row was shoved through
            // the bottom edge and the first chip, being the filled one, was
            // the one you could see was cut (Marcello, 2026-09-05, 2026-09-06).
            // A budget that does not count everything competing for the space
            // is not a budget — and a constant standing in for something that
            // changes size is not counting it.
            //
            // No feedback loop: what Completed draws does not depend on the
            // viewport it is shrinking, so this settles in one pass.
            - (isContainer ? completedInset : 0)
    }

    /// Negative on purpose: the capped, scrolling path is now the ONLY path.
    /// The inline path had no ceiling, so a list that grew past the panel's
    /// height simply kept going. `viewport = min(natural, cap)` still hugs a
    /// short list, so nothing is lost but the overflow.
    private static let inlineRowThreshold = -1
    private static let scrollSpace = "todoScrollRegion"
    private static let bottomAnchor = "todoScrollBottom"

    /// Natural (unclipped) height of each section's scroll content, keyed by
    /// section. PER SECTION, not one shared number: the old and new list
    /// overlap during a switch, and `onPreferenceChange` only fires on a
    /// CHANGE — so when SwiftUI revived the outgoing Work list because the
    /// user switched back mid-crossfade, its measurement was unchanged,
    /// nothing fired, and the shared value stayed at Personal's two rows.
    /// Work then rendered twelve rows into a two-row viewport and the panel
    /// "kept the same height" (Thomas, 2026-09-01; reproduced with rapid
    /// switch 1/0/1/0 → Work at 205 instead of 334). Each section reading
    /// its own entry makes a revived view correct by construction.
    @State private var regionNaturalHeights: [UUID: CGFloat] = [:]
    /// The most recent measurement of any section — the seed for a section
    /// seen for the first time, so its first frame starts from a plausible
    /// height rather than jumping to the full budget and shrinking back.
    @State private var lastRegionNaturalHeight: CGFloat = 0
    /// How far the capped region has been scrolled. Drives the edge fades.
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject private var chrome = PanelChrome.shared
    /// Measured height of the pinned Completed section. Seeded at the
    /// collapsed size so the first frame — before any measurement exists — is
    /// approximately right rather than a full-budget overshoot that then
    /// snaps back.
    @State private var completedInsetHeight: CGFloat = PanelMetrics.completedHeaderHeight
        + DSSpacing.tabRowBottomMargin + 10
    @State private var draggedItemID: UUID?
    /// Where each row sits, in `rowSpace`. Published by the rows themselves so
    /// the gesture can resolve a pointer position to a gap, and so keyboard
    /// focus only scrolls when its row has actually left the viewport.
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var dragOffset: CGFloat = 0
    /// The row the dragged item would land ABOVE. Arc-style: nothing moves
    /// until the drop, we just draw the slot.
    @State private var dropBeforeID: UUID?
    /// True when the drop would land past the last row.
    @State private var dropAtEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // §8.3 category switch: the id() swap transitions the whole block
            // while the panel height animates — content and container together.
            if let collection = store.activeCollection {
                // Same jump guard as the mode switch: the id() swap keeps two
                // copies alive mid-transition; overlap them instead of stacking.
                ZStack(alignment: .topLeading) {
                    browsingBody(for: collection)
                        .id(collection.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // FB2's in-place crossfade in the container; U5's
                        // 6-pt rise in the floating panels.
                        .transition(isContainerLayout ? .sectionSwap
                                                      : .spaceSwap(reduceMotion: reduceMotion))
                }
            }
        }
        // Read the archive HERE, not while drawing.
        //
        // Whether the Completed section exists at all now depends on what is
        // on disk, and that question is asked during body evaluation — so the
        // answer has to be in memory before the body runs. Reading from inside
        // the body would be a file system call in the middle of layout, on
        // every redraw.
        .onAppear { archive.reloadIfNeeded() }
        .onReceive(store.$archiveRevision) { _ in archive.reload() }
    }

    @ViewBuilder
    private func browsingBody(for collection: TodoCollection) -> some View {
        let open = store.openItems(in: collection)
        let openCount = open.count
        // The rows Completed would put on screen — live AND archived.
        //
        // Counting only the live ones is what pushed the section row out
        // through the bottom of the panel the moment history arrived: the
        // section was DRAWN because the archive had entries, and MEASURED as
        // though it were not there at all, so the list kept a budget that
        // already belonged to something else (Marcello, 2026-09-07).
        let completedCount = store.completedItems(in: collection).count
            + archive.historyCount(section: collection.isSystemToday ? nil : collection.name,
                                   excluding: liveCompletedIDs(in: collection))
        // Closed rows preview at most two checklist entries and add one quiet
        // disclosure row when more are hidden. Only the opened row renders
        // every entry plus its trailing draft. Count exactly that furniture
        // here so the inline-vs-scroll decision matches what is on screen.
        let stepCount = open.reduce(0) { count, item in
            let expanded = store.expandedItemID == item.id
            let visible = ChecklistDisclosure.visibleCount(total: item.checklist.count,
                                                            expanded: expanded)
            let hidden = ChecklistDisclosure.hiddenCount(total: item.checklist.count,
                                                          expanded: expanded)
            let disclosure = hidden > 0 ? 1 : 0
            let draft = expanded ? 1 : 0
            return count + visible + disclosure + draft
        }
        let visibleRows = openCount + stepCount + (store.completedExpanded ? completedCount : 0)

        let completedInset = hasAnyCompleted(in: collection)
            ? min(completedInsetHeight, PanelMetrics.completedExpandedMaxHeight)
            : 0
        let budget = Self.maxRegion(chrome: chrome, completedInset: completedInset,
                                    isContainer: isContainerLayout)

        let content = VStack(alignment: .leading, spacing: 0) {
            // CT-1/CT-6: meetings (or the connect nudge) sit above the
            // to-dos, in the Today tab only.
            if collection.isSystemToday {
                UpNextSection()
            }
            todoList(for: collection, room: budget)
            if !isContainerLayout, hasAnyCompleted(in: collection) {
                completedSection(for: collection)
            }
        }
        .padding(.horizontal, isContainerLayout ? PanelMetrics.listInset : SpaceChrome.columnInset)
        // The container's list ended flush on the panel's rounded foot: a
        // multi-line last to-do sat against the edge (Marcello, 2026-09-27).
        // Inside the content, so the hugging height includes it and a
        // scrolled list ends with the same air.
        .padding(.bottom, isContainerLayout ? 16 : 0)
        // A second catcher, INSIDE what will become the scroll region.
        //
        // The panel already had one at its root, but an NSScrollView is opaque
        // to hit testing: once the list is long enough to scroll, a click in
        // the gaps between rows lands on the scroller and is consumed there,
        // and never reaches anything behind it. So the panel-root catcher
        // worked on a short list and silently stopped working on a long one —
        // which is the list you are most likely to be clicking around in.
        .background(DeselectCatcher())

        if visibleRows <= Self.inlineRowThreshold {
            // Fits comfortably: hug it, no scroll, no measurement round-trip.
            content
        } else {
            // Tall: one capped ScrollView so list + Completed scroll as a
            // single unit and the panel height stops at the budget.
            // draftInset 0: the typing bar lives above the sections now, in
            // TodoTabView, not inside this scrolling column.
            // The SAME question the safeAreaInset asks before drawing it.
            // Two predicates for one section is how the panel ends up
            // budgeting for a section it is not showing, or showing one it has
            // not budgeted for — and the second is the one you can see,
            // because the tab row goes out through the bottom edge.
            // min(natural, budget): the region hugs its content again.
            //
            // This was the full budget for a while — the export pinned the
            // block at 556 so the tab row never moved between sections
            // (Marcello, 2026-08-22). That traded the app's own second
            // product principle away: a panel that is 556 with three to-dos
            // in it is mostly empty glass. Hugging is back by explicit call
            // (Thomas, 2026-09-01) — the panel is a function of what is in
            // it, and the tabs riding up and down with the content is the
            // accepted cost, animated on the same contentHug spring as the
            // silhouette so the two move as one.
            //
            // First pass after a cold mount measures 0; fall back to the
            // budget for that frame rather than collapsing to nothing.
            let natural = regionNaturalHeights[collection.id] ?? lastRegionNaturalHeight
            let viewport = natural > 0 ? min(natural, budget) : budget
            // The footer overlays the bottom of the panel. Rows can reach it
            // before they exceed the panel's full budget, as in Work with nine
            // items. Start the material and add scroll travel at that point.
            let overlapsFooter = !isContainerLayout &&
                natural > budget - PanelMetrics.floatingFooterBlurDepth
            let hasBelow = natural > viewport + max(scrollOffset, 0) + 2
            // Indicators ON. They were hidden, so a capped region gave the eye
            // nothing at all to say "there is more" — rows below the fold and
            // the entire Completed section read as missing rather than
            // scrolled away (Marcello, 2026-08-05).
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    content
                        .measureHeight(SectionHeightKey.self)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: -geo.frame(in: .named(Self.scrollSpace)).minY
                                )
                            }
                        )
                    // The footer overlays this scroll view. Leave enough travel
                    // at the end that the last thing — usually Completed —
                    // clears the whole blur band, not just the pills: at one
                    // footer (95) its header still sat 24pt inside the blur,
                    // squeezed against the bar (Marcello, 2026-09-30).
                    if overlapsFooter {
                        Color.clear.frame(height: PanelMetrics.floatingFooterBlurDepth + 16)
                    }
                    // Anchor for the "more below" pill to jump to.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .coordinateSpace(name: Self.scrollSpace)
                // Keep keyboard focus visible, but preserve the user's scroll
                // position whenever the row already fits. The old unconditional
                // `scrollTo(anchor:)` snapped every clicked row to an edge,
                // even in the middle of the viewport, so opening neighbouring
                // to-dos made the whole list appear to jump at random.
                .onChange(of: store.focusedItemID) { focused in
                    guard let focused else { return }
                    revealRowIfNeeded(focused,
                                      viewport: viewport,
                                      footer: isContainerLayout ? 0 : PanelMetrics.floatingFooterDepth,
                                      proxy: proxy)
                }
                // Expanding changes the row's height after the click. Wait for
                // that layout to settle, then reveal only the overflow. A row
                // that still fits produces no scroll at all.
                .onChange(of: store.expandedItemID) { expanded in
                    guard let expanded else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guard store.expandedItemID == expanded else { return }
                        revealRowIfNeeded(expanded,
                                          viewport: viewport,
                                          footer: isContainerLayout ? 0 : PanelMetrics.floatingFooterDepth,
                                          proxy: proxy)
                    }
                }
                .onPreferenceChange(SectionHeightKey.self) { height in
                    regionNaturalHeights[collection.id] = height
                    lastRegionNaturalHeight = height
                }
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
                .frame(height: viewport)
                // The list still ENDS at its own bottom edge — a row that
                // overran the viewport must not draw into the band the pills
                // live in. But the edge is a gradient mask now rather than
                // `.clipped()`: same guarantee, no straight cut. It has to
                // come AFTER the frame, or the ramp is positioned against the
                // content's natural height instead of the viewport's bottom.
                .modifier(TodoScrollEdgeEffect(isScrollable: natural > budget,
                                               scrollOffset: scrollOffset,
                                               hasBelow: hasBelow,
                                               isContainer: isContainerLayout,
                                               showsFootBlur: !isContainerLayout))
                // Completed sits BELOW the scroll region, not inside it.
                //
                // It was the last thing in the scrolling content, so on any
                // list long enough to scroll it was under the fold — and a
                // section you have to go hunting for reads as a section that
                // was removed (Marcello, 2026-09-05: "è sparita"). Pinned to
                // the foot it is always one glance away, and the count in its
                // header answers "what did I finish" without opening it.
                //
                // Capped and scrolling when expanded, so opening a long
                // archive cannot push the open list off its own panel.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Nothing at all when nothing is finished.
                    //
                    // The open/closed flag is global, not per-section, so an
                    // empty section visited while Completed happened to be
                    // open was handing 160pt of its list budget to a section
                    // with no rows in it.
                    // The archive counts as content. Gating on the live store
                    // alone is what made the whole section disappear a day
                    // after finishing anything — "i completed sono spariti"
                    // (Marcello, 2026-09-07) — because completions leave the
                    // store for Archive/<day>.md and the section then had
                    // nothing to draw.
                    if isContainerLayout, hasAnyCompleted(in: collection) {
                        ScrollView(.vertical, showsIndicators: false) {
                            completedSection(for: collection)
                                .padding(.horizontal, isContainerLayout ? PanelMetrics.listInset : SpaceChrome.columnInset)
                                .measureHeight(CompletedInsetKey.self)
                        }
                        // Hugs its content up to the cap, rather than taking
                        // the cap whether it needs it or not: a ScrollView
                        // given `maxHeight` claims all of it, so two finished
                        // to-dos cost the open list the same 160pt as twenty.
                        .frame(height: min(completedInsetHeight,
                                           PanelMetrics.completedExpandedMaxHeight))
                    }
                }
                .onPreferenceChange(CompletedInsetKey.self) { completedInsetHeight = $0 }
            }
            // The panel must animate every viewport change — opening
            // Completed, adding a row, switching to a shorter section — or
            // the hug snaps instead of growing. Keyed on the viewport itself
            // so any route into a new height takes the same spring.
            .animation(NotchAnimation.contentHug, value: viewport)
            .preference(key: FootBlurVisibleKey.self,
                        value: overlapsFooter)
        }
    }

    /// Scroll the least possible amount, and only when the complete row is
    /// outside the visible list region. Row frames are in content coordinates;
    /// adding `scrollOffset` gives the current viewport in that same space.
    ///
    /// `footer` is how much of the viewport's foot the floating pills cover.
    /// The visible region stops above it — and so must the scroll: anchoring
    /// a row at `.bottom` lined it up with the viewport's real bottom, under
    /// the pills, so ↓ onto the last to-do selected something you could not
    /// see (Marcello, 2026-10-01).
    private func revealRowIfNeeded(_ id: UUID,
                                   viewport fullViewport: CGFloat,
                                   footer: CGFloat,
                                   proxy: ScrollViewProxy) {
        guard let frame = rowFrames[id] else { return }
        let margin: CGFloat = 8
        let viewport = fullViewport - footer
        let visibleTop = max(0, scrollOffset) + margin
        let visibleBottom = max(0, scrollOffset) + viewport - margin

        if frame.minY < visibleTop {
            withAnimation(NotchAnimation.hintFade) {
                proxy.scrollTo(id, anchor: .top)
            }
        } else if frame.maxY > visibleBottom,
                  let collection = store.activeCollection,
                  store.openItems(in: collection).last?.id == id {
            // The last to-do: go all the way to the end, so it is out of the
            // soft foot too, not just above the pills.
            withAnimation(NotchAnimation.hintFade) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        } else if frame.maxY > visibleBottom {
            // A row taller than the viewport cannot fit in full; anchoring its
            // top keeps the title and collapse control available.
            //
            // scrollTo lines the row's point at `y` up with the viewport's
            // point at `y`. For the row's foot to land `footer + margin` above
            // the viewport's foot: y = 1 − (footer + margin) / (V − h).
            let room = fullViewport - frame.height
            let anchor: UnitPoint = frame.height >= viewport - margin * 2 || room <= 0
                ? .top
                : UnitPoint(x: 0.5, y: max(0, 1 - (footer + margin) / room))
            withAnimation(NotchAnimation.hintFade) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    // MARK: Open list

    /// `room` is the scroll region's budget: the container drops the empty
    /// state's subtitle when it has less than 180pt to give.
    @ViewBuilder
    private func todoList(for collection: TodoCollection, room: CGFloat) -> some View {
        let rows = store.openItems(in: collection)
        if rows.isEmpty {
            // Today says nothing when it is empty — an empty Today already
            // means "you're done", and a sentence restating that is one more
            // thing to read (Marcello, 2026-07-26). A user list gets the
            // peeking Otto (empty state, 2026-10-04), because an empty one
            // there looks broken rather than done.
            if !collection.isSystemToday {
                EmptyListView(compact: isContainerLayout,
                              showsSubtitle: !isContainerLayout || room >= 180,
                              fillHeight: isContainerLayout ? nil : room)
                    .transition(EmptyListView.transition)
            }
        } else {
            openRows(rows)
        }
    }

    private func openRows(_ rows: [TodoItem]) -> some View {
        // 6, per the export — 37pt rows on a 43pt pitch. This was the
        // generic 10pt row gap, which is why the rhythm never matched the mock.
        VStack(alignment: .leading, spacing: PanelMetrics.listRowGap) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, item in
                TodoItemRow(
                    item: item,
                    accent: store.collection(id: item.collectionID)?.color ?? .accentColor,
                    isFocused: store.focusedItemID == item.id,
                    isExpanded: store.expandedItemID == item.id
                )
                .transition(rowTransition)
                // Rows come in behind the tab row and the meeting cards, so
                // the panel assembles top-down as the silhouette opens.
                .notchEntry(index: rowIndex + 2)
                // The dragged row dims in place while its copy travels.
                .opacity(draggedItemID == item.id ? 0.4 : 1)
                // The landing slot, drawn in the gap ABOVE this row so it
                // never displaces anything — an inserted view would make the
                // list jump under the cursor while dragging.
                .overlay(alignment: .top) {
                    if dropBeforeID == item.id {
                        DropIndicator()
                            .offset(y: -(PanelMetrics.listRowGap / 2 + 3))
                    }
                }
                // Where this row IS, so the gesture can tell which gap the
                // pointer is over without any of the rows having to move.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RowFrameKey.self,
                            value: [item.id: geo.frame(in: .named(Self.rowSpace))]
                        )
                    }
                )
                // The dragged row travels with the pointer and floats over
                // its neighbours.
                .offset(y: draggedItemID == item.id ? dragOffset : 0)
                .zIndex(draggedItemID == item.id ? 1 : 0)
                .gesture(reorderGesture(for: item, in: rows))
                // The target `scrollTo` aims at when the arrow keys walk the
                // focus past the fold.
                .id(item.id)
            }

            // No landing strip. Inserting a view when the drag began moved
            // every row below it at the exact moment the pointer needed them
            // to hold still; the bottom slot is reached now by the pointer
            // simply being past the last row's middle.
        }
        .coordinateSpace(name: Self.rowSpace)
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
        .animation(NotchAnimation.hintFade, value: dropBeforeID)
        .animation(NotchAnimation.hintFade, value: dropAtEnd)
    }

    fileprivate static let rowSpace = "todoRowSpace"

    /// Reordering, as a plain drag gesture.
    ///
    /// This used to be `.onDrag` + `DropDelegate`, riding the system
    /// pasteboard. Every piece of it was correct — the exported UTType, the
    /// providers, the delegates — and it still never moved a row, twice, on a
    /// non-activating panel that the drag machinery was never really meant to
    /// start a session from. A gesture needs none of that: no pasteboard, no
    /// item provider, no window activation. It is all in-process, which is all
    /// this ever was, since a reorder drag cannot leave the list it started in.
    private func reorderGesture(for item: TodoItem, in rows: [TodoItem]) -> some Gesture {
        // A few points of slop so a click still reads as a click; the row's
        // own tap gesture keeps working underneath.
        DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.rowSpace))
            .onChanged { value in
                if draggedItemID != item.id {
                    draggedItemID = item.id
                    TodoStore.shared.expandedItemID = nil
                    // The row leaving the list, felt at the moment it lifts.
                    HapticManager.shared.dragBegan()
                }
                dragOffset = value.translation.height
                updateDropTarget(pointerY: value.location.y, dragged: item.id, rows: rows)
            }
            .onEnded { _ in
                commitReorder(dragged: item.id)
            }
    }

    /// Insert before the first row whose middle the pointer is above; past
    /// them all means the bottom.
    private func updateDropTarget(pointerY: CGFloat, dragged: UUID, rows: [TodoItem]) {
        let landing = rows.first { row in
            guard let frame = rowFrames[row.id] else { return false }
            return pointerY < frame.midY
        }

        guard let landing else {
            // Below every row. Nothing to mark if it is already last.
            let toEnd = rows.last?.id != dragged
            if toEnd && !dropAtEnd { HapticManager.shared.reorderTick() }
            dropBeforeID = nil
            dropAtEnd = toEnd
            return
        }

        // Landing on itself, or in the gap directly above itself, is where it
        // already is — say nothing rather than promise a move that won't
        // happen.
        let landingIndex = rows.firstIndex { $0.id == landing.id }
        let draggedIndex = rows.firstIndex { $0.id == dragged }
        if landing.id == dragged || landingIndex.map({ $0 - 1 }) == draggedIndex {
            dropBeforeID = nil
            dropAtEnd = false
            return
        }

        // One tick per slot ENTERED. `updateDropTarget` runs on every
        // pointer move, so tapping unconditionally here would be a continuous
        // buzz rather than a sequence of snaps — the difference between
        // feeling the row click into place and feeling the trackpad vibrate.
        if dropBeforeID != landing.id { HapticManager.shared.reorderTick() }
        dropBeforeID = landing.id
        dropAtEnd = false
    }

    private func commitReorder(dragged: UUID) {
        if let before = dropBeforeID, before != dragged {
            TodoStore.shared.reorder(dragged, before: before)
            HapticManager.shared.reorderCommitted()
        } else if dropAtEnd {
            TodoStore.shared.moveToEnd(dragged)
            HapticManager.shared.reorderCommitted()
        }
        draggedItemID = nil
        dropBeforeID = nil
        dropAtEnd = false
        dragOffset = 0
    }

    private var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(x: 24))
        )
    }

    // MARK: Completed (TD-3, per-category)

    /// The live completions, keyed the way the archive keys them — so history
    /// can drop the entries the store is still showing.
    private func liveCompletedIDs(in collection: TodoCollection) -> Set<String> {
        Set(store.completedItems(in: collection).flatMap {
            [$0.id.uuidString, CompletedArchive.identity(title: $0.title, at: $0.completedAt ?? .distantPast)]
        })
    }

    /// Whether there is anything to show at all — live rows OR history.
    private func hasAnyCompleted(in collection: TodoCollection) -> Bool {
        if !store.completedItems(in: collection).isEmpty { return true }
        return archive.historyCount(section: collection.isSystemToday ? nil : collection.name,
                                    excluding: []) > 0
    }

    /// Today's live completions and the archived history behind them, as one
    /// list. The live rows are real to-dos and can be un-ticked; the history is
    /// a record and is read-only, because those items have left the store.
    @ViewBuilder
    private func completedSection(for collection: TodoCollection) -> some View {
        let completed = store.completedItems(in: collection)
        let liveIDs = liveCompletedIDs(in: collection)
        let section = collection.isSystemToday ? nil : collection.name
        // COUNTED while closed, GROUPED only once open. The header needs a
        // number on every redraw; the day groups are needed only when someone
        // is actually looking at them.
        let historyCount = archive.historyCount(section: section, excluding: liveIDs)
        if !completed.isEmpty || historyCount > 0 {
            // No rule above Completed (Marcello, 2026-07-26) — the gap and the
            // dimmer label already separate it from the open list.
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(NotchAnimation.contentHug) { store.completedExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        OttoIcon("chevron.right", pointSize: 9)
                            .foregroundStyle(DSColor.textFaint)
                            .rotationEffect(.degrees(store.completedExpanded ? 90 : 0))
                        Text(L10n.t("todo.completed"))
                            .font(DSFont.checklistItem)
                            .foregroundStyle(DSColor.textMuted)
                        // Everything the section holds, history included —
                        // the count in a closed header is the answer to "what
                        // did I finish", and one that stopped at yesterday
                        // would be the same lie the empty section told.
                        Text("\(completed.count + historyCount)")
                            .font(.system(size: 10))
                            .foregroundStyle(DSColor.textHint)
                            .contentTransition(.numericText())
                        Spacer()
                        // Seven days of volume, in the header itself. It
                        // answers "am I still moving" while the section is
                        // CLOSED, which is the state it is in almost always —
                        // a count says how much, never when.
                        CompletionSparkline(
                            counts: CompletionStats.dailyCounts(
                                section: section, days: 7, store: store, archive: archive))
                            .padding(.trailing, store.completedExpanded ? 4 : 0)
                        // Sweep: clear the completed pile in one go. Only
                        // offered while the section is open — clearing a list
                        // you cannot see is not something to make easy.
                        if store.completedExpanded {
                            SweepButton {
                                withAnimation(NotchAnimation.contentHug) {
                                    store.clearCompleted(in: collection.id)
                                }
                            }
                        }
                    }
                    // The sparkline ends on the rows' hint line, not the
                    // slab's edge (Marcello, 2026-10-01: "più allineate").
                    .padding(.trailing, PanelMetrics.rowPaddingH)
                    // Carries the separation the rule used to provide.
                    .padding(.top, DSSpacing.tabRowBottomMargin + 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if store.completedExpanded {
                    // Inline at natural height — the outer browsingBody region
                    // provides scrolling when the combined content is tall, so
                    // Completed opens fully instead of into a cramped window.
                    CompletedDayList(
                        days: CompletionStats.days(section: section, store: store, archive: archive))
                        .transition(.opacity)
                }
            }
            .transition(.opacity)
        }
    }

}

// MARK: - SweepButton — clear the completed pile (Marcello, 2026-08-04)
//
// Sits at the right of the Completed header. Deliberately quiet: it only
// appears while the section is open, and it fades up on hover rather than
// advertising itself, because it throws work away and should not be the most
// obvious thing in the row.

struct SweepButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            OttoIcon("wind", pointSize: 11)
                .foregroundStyle(hover ? DSColor.textPrimaryBright : DSColor.textHint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    DSShape.squircle(DSRadius.chipCorner)
                        .fill(hover ? DSColor.fieldBackground : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        .help(L10n.t("todo.clearCompleted"))
    }
}
