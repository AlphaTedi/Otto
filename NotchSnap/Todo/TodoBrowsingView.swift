import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - TodoTabView — the whole to-do panel (design PRD §§1-7)
//
// One surface, four modes (TodoPanelMode): browsing and creation share the
// tab row; category creation and Quick Find replace the content entirely.
// All colors/spacing/radii/fonts come from DesignSystem.swift (DSColor,
// DSSpacing, DSRadius, DSFont) and its reusable components — never inline
// hex values (design PRD §11, drift table §10).
//
// Content sits directly on the notch's black — single background, only
// element-level fills (Marcello's explicit call, 2026-07-13; it overrides
// the #111 panel shown in the PRD §1 markup).
//
// Layout law (pivot PRD §3): fixed width, VARIABLE height. This view
// measures its natural height and publishes it; the notch shape animates to
// match on NotchAnimation.contentHug (the exact response 0.45 / damping 0.60
// spring the PRD §8.2 mandates — DSAnimation.primary is a rough conversion
// of the same spring and its own comment says to prefer tuned values).

// MARK: - Height measurement

private struct TodoContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// How far the capped to-do region has scrolled, in points from the top.
private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Softens whichever edge of a scrolling region has content past it.
///
/// A capped ScrollView crops on a hard line, which reads as "the list ends
/// here" — the reason to-dos below the fold and the whole Completed section
/// looked missing rather than scrolled away. A fade says "this continues"
/// without adding a control or a label to read, and it disappears at each end
/// so a fully-scrolled list still terminates cleanly.
private struct ScrollEdgeFade: ViewModifier {
    let scrollOffset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    private let fade: CGFloat = 22
    /// 2pt of slack: sub-pixel offsets must not leave a permanent haze on a
    /// list that is actually at its end.
    private var hasAbove: Bool { scrollOffset > 2 }
    private var hasBelow: Bool { contentHeight - scrollOffset - viewportHeight > 2 }

    func body(content: Content) -> some View {
        content.mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(hasAbove ? 0 : 1), .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(hasBelow ? 0 : 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
            }
            .animation(NotchAnimation.hintFade, value: hasAbove)
            .animation(NotchAnimation.hintFade, value: hasBelow)
        )
    }
}

/// "More below" — a small floating control at the foot of a list that still
/// overflows once the panel has grown as far as it can.
///
/// The fade tells you the list continues; this tells you what to do about it
/// and does it for you. It only appears while there is genuinely something
/// below, so it is never a permanent piece of furniture.
private struct MoreBelowPill: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                Text(L10n.t("todo.moreBelow"))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(hover ? DSColor.textPrimaryBright : DSColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(DSColor.fieldBackground)
            )
            .overlay(
                Capsule().strokeBorder(DSColor.panelBorder, lineWidth: 0.5)
            )
            // Lifts off the rows sliding underneath it.
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
    }
}

private struct SectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// UG-2 tooltip plumbing: the hovered/focused row's dot reports its anchor;
/// TodoTabView renders the bubble at PANEL level so the list ScrollView's
/// clipping can't cut it off (for the first row it floats over the tabs).
private struct UrgencyTooltipInfo {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct UrgencyTooltipKey: PreferenceKey {
    static let defaultValue: [UrgencyTooltipInfo] = []
    static func reduce(value: inout [UrgencyTooltipInfo],
                       nextValue: () -> [UrgencyTooltipInfo]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func measureHeight<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: proxy.size.height)
            }
        )
    }
}

// MARK: - TodoTabView

struct TodoTabView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var calendar = CalendarStore.shared

    // FB2: one transition, every direction. A pure in-place crossfade —
    // no y-offset, no edge-move — so switching tabs or modes never "slides
    // in from the top" or bleeds over the tab row, and Work→Today looks
    // identical to Today→Personal (Marcello 2026-07-23).
    private var modeTransition: AnyTransition { .opacity }

    var body: some View {
        // §2.3: the shortcuts overlay sits ON TOP of the live content —
        // dismissing is instant, nothing re-renders underneath.
        ZStack(alignment: .topLeading) {
            // CA-3: while a meeting alert is live it OWNS the panel — the
            // notch opened itself for this, so it shouldn't compete with the
            // to-do list underneath.
            if let alert = calendar.activeAlert {
                MeetingAlertView(meeting: alert)
                    .transition(.opacity)
            } else {
                todoPanelContent
            }
        }
        .padding(EdgeInsets(top: 14, leading: DSSpacing.panelPadding,
                            bottom: DSSpacing.panelPadding, trailing: DSSpacing.panelPadding))
        // UG-2: immediate tooltip near the hovered/focused row's urgency dot,
        // clamped so it can't overflow the panel's edges.
        .overlayPreferenceValue(UrgencyTooltipKey.self) { infos in
            GeometryReader { geo in
                if let info = infos.first {
                    let rect = geo[info.anchor]
                    UrgencyTooltip(text: info.text)
                        .position(x: min(max(rect.midX, 46), geo.size.width - 46),
                                  y: rect.minY - 18)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(NotchAnimation.hintFade, value: infos.first?.text)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Hugging height: the notch shape is a direct animated function of
        // this measurement.
        .measureHeight(TodoContentHeightKey.self)
        .onPreferenceChange(TodoContentHeightKey.self) { height in
            AppState.shared.todoContentHeight = height
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TodoBrowsingKeyHandler())
    }

    /// The normal to-do panel: tab row + the active mode's surface, with the
    /// on-demand shortcuts overlay on top.
    private var todoPanelContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                // The tab row lives OUTSIDE the mode switch: its identity is
                // stable across browsing ↔ create, so toggling "+" swaps only
                // the content below — same motion as switching categories.
                if store.panelMode == .browsing || store.panelMode == .create
                    || store.panelMode == .voice {
                    TodoTabRow()
                        .notchEntry(index: 0)
                }
                // ZStack, not bare switch: during a transition BOTH the
                // outgoing and incoming views exist for a few frames — as
                // VStack siblings they'd stack vertically and the whole
                // panel visibly jumped (Marcello's Work→Today report).
                // Overlapped, the swap reads as one in-place motion.
                ZStack(alignment: .topLeading) {
                    switch store.panelMode {
                    case .browsing:
                        TodoBrowsingView()
                            .transition(modeTransition)
                    case .create:
                        TodoCreateView()
                            .transition(modeTransition)
                    case .newCategory:
                        CategoryFormView()
                            .transition(modeTransition)
                    case .find:
                        QuickFindView()
                            .transition(modeTransition)
                    case .voice:
                        VoiceCaptureView()
                            .transition(modeTransition)
                    }
                }
            }

            if store.showShortcuts {
                ShortcutsOverlay()
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Tab row — CreationTabChip + CategoryTabChips (design PRD §3.1)
//
// Drift table §10: a tab is label + its remaining count, NOTHING else (#4);
// badges exist only while ⌘ is held (#2); the active tab wears its own
// category color at regular weight (#1). The count replaced the progress
// ring on 2026-07-23 — see CategoryTabChip. Tabs drag to reorder; the "+"
// chips are structural and never move.

private struct TodoTabRow: View {
    @ObservedObject private var store = TodoStore.shared
    /// The category tab currently being dragged (nil when idle).
    @State private var draggedCollectionID: UUID?

    var body: some View {
        HStack(spacing: 10) {
            tabScroller
            // Outside the scroller: the account is not a tab.
            AccountButton()
        }
        // No rule under the tab row (Marcello, 2026-07-26). The two paddings
        // stay: they were the breathing room either side of the line, and
        // together they are what now separates the tabs from the list.
        .padding(.bottom, DSSpacing.tabRowBottomPadding)
        .padding(.bottom, DSSpacing.tabRowBottomMargin)
    }

    private var tabScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    if store.panelMode == .create {
                        store.setMode(.browsing)
                    } else {
                        store.presetDraftToActiveCollection()
                        store.setMode(.create)
                        NotchController.shared.focusPanel()
                    }
                } label: {
                    CreationTabChip(isActive: store.panelMode == .create)
                        .contentShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L10n.t("todo.newTodo"))

                ForEach(Array(store.collections.enumerated()), id: \.element.id) { index, collection in
                    Button {
                        store.selectCollection(collection.id)
                    } label: {
                        CategoryTabChip(
                            title: collection.name,
                            categoryColor: collection.color,
                            isActive: store.panelMode == .browsing
                                && collection.id == store.activeCollectionID,
                            remaining: store.remainingCount(for: collection)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    // Drag a tab onto another to swap places. Only category
                    // chips participate — the "+" chips are structural, never
                    // movable (Marcello, 2026-07-23).
                    .opacity(draggedCollectionID == collection.id ? 0.4 : 1)
                    .onDrag {
                        draggedCollectionID = collection.id
                        return .notchSnapInternal(collection.id)
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
                    .onDrop(of: [.notchSnapInternalItem], delegate: CollectionReorderDropDelegate(
                        targetID: collection.id,
                        draggedID: $draggedCollectionID
                    ))
                    .contextMenu {
                        // FB8: explicit default for new to-dos (checkmark on
                        // the current default). Today can't be a default —
                        // it's a smart view, not a home.
                        if !collection.isSystemToday {
                            Button {
                                store.setDefaultCollection(collection.id)
                            } label: {
                                let isDefault = store.defaultCreationCollectionID == collection.id
                                Text((isDefault ? "\u{2713}  " : "") + L10n.t("todo.setDefault"))
                            }
                            Divider()
                        }
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
                        .disabled(index == store.collections.count - 1)
                        if !collection.isSystemToday {
                            Divider()
                            Button(L10n.t("action.delete"), role: .destructive) {
                                store.deleteCollection(collection.id)
                            }
                        }
                    }
                }

                // Voice brain-dump entry point (VC-1). Sits beside the "+"
                // creation chip: same family of "start something" controls.
                // SHELVED 2026-07-25 — hidden behind VoiceFeature.isEnabled;
                // the implementation stays intact, just unreachable.
                if VoiceFeature.isEnabled {
                    VoiceChip(isActive: store.panelMode == .voice) {
                        if store.panelMode == .voice {
                            VoiceCaptureController.shared.toggle()
                        } else {
                            store.setMode(.voice)
                            NotchController.shared.focusPanel()
                            VoiceCaptureController.shared.start()
                        }
                    }
                }

                // CT-5: exactly ONE "+" in the tab row, and it always means
                // "create a to-do". Category management lives behind this
                // overflow control instead of a second plus, which read as
                // ambiguous. Trailing-aligned per the mockup.
                Spacer(minLength: 8)
                CategoryOverflowMenu()
            }
            // No top padding here. It used to reserve headroom for the
            // ⌘-held index badges (offset y:-8) drawn above each chip; the
            // badges are gone, but the padding stayed and pushed every chip
            // 8pt below AccountButton, which sits in the outer row with no
            // matching offset — the avatar visibly floating above the tabs'
            // midline (Marcello, 2026-08-09).
        }
    }
}

// MARK: - Category tab drag-to-reorder

private struct CollectionReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID, dragged != targetID else { return }
        // Live re-slotting: the row reorders as the drag passes over it, so
        // the drop itself is just "let go".
        TodoStore.shared.moveCollection(dragged, before: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

// MARK: - VoiceChip — voice brain-dump entry (VC-1)

private struct VoiceChip: View {
    let isActive: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "waveform" : "mic.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? DSColor.primaryText : DSColor.textPrimaryBright)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous)
                        .fill(isActive ? DSColor.focusAccent
                                       : Color(hex: "#333333").opacity(hover ? 1 : 0.85))
                )
                .contentShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L10n.t("voice.start") + "  \u{2318}\u{21E7}V")
    }
}

// MARK: - CategoryOverflowMenu — the "..." control (CT-5)
//
// Everything category-level lives here: creating one, reordering, choosing the
// default, deleting. Keeping it out of the tab row means the row has exactly
// one "+", which unambiguously means "new to-do".

private struct CategoryOverflowMenu: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    var body: some View {
        Menu {
            Button(L10n.t("todo.newCollection") + "\u{2026}") {
                store.setMode(.newCategory)
                NotchController.shared.focusPanel()
            }
            if let active = store.activeCollection {
                Divider()
                Text(active.name)
                if !active.isSystemToday {
                    Button(L10n.t("todo.setDefault")) {
                        store.setDefaultCollection(active.id)
                    }
                }
                let index = store.collections.firstIndex { $0.id == active.id } ?? 0
                Button(L10n.t("action.moveLeft")) {
                    store.moveCollection(active.id, by: -1)
                }
                .disabled(index == 0)
                Button(L10n.t("action.moveRight")) {
                    store.moveCollection(active.id, by: 1)
                }
                .disabled(index == store.collections.count - 1)
                if !active.isSystemToday {
                    Divider()
                    Button(L10n.t("action.delete"), role: .destructive) {
                        store.deleteCollection(active.id)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? DSColor.textPrimary : DSColor.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
        .help(L10n.t("todo.manageCategories"))
    }
}

// MARK: - SettingsButton — the visible way into Settings
//
// Until now the ONLY route was right-clicking the collapsed notch, which
// testers simply never found: "people don't really understand that they have to
// double-click on the notch" (Marcello, 2026-08-06). An app with no Dock icon
// and no menu-bar item has no other affordance, so a hidden context menu was
// the whole discovery story.
//
// It sits at the trailing edge of the tab row beside the overflow control, and
// borrows that control's exact metrics — 12pt glyph in a 20x20 box, same two
// foreground tones — so the two read as a pair of row-level actions rather than
// one chip and one afterthought. The context menu stays for anyone who learned
// it.
private struct AccountButton: View {
    @State private var hover = false

    /// Read at render time rather than observed: sign-in state changes only
    /// through onboarding or Settings, both of which rebuild this row.
    /// Google is checked first only because it was wired first — nothing
    /// stops both being signed in, the row just shows whichever exists.
    private var account: String? { GoogleOAuth.shared.account ?? AppleSignIn.shared.account }

    var body: some View {
        Button {
            SettingsWindowController.show()
        } label: {
            AccountAvatar(email: account, diameter: 22)
                .opacity(hover ? 0.82 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        .help(account ?? L10n.t("settings.open"))
        .accessibilityLabel(L10n.t("settings.open"))
    }
}

// MARK: - TodoBrowsingView — the list + Completed (browsing mode content)

struct TodoBrowsingView: View {
    @ObservedObject private var store = TodoStore.shared

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
    private static var maxRegion: CGFloat {
        // Panel top inset + tab row + its top padding + the two paddings under
        // it + the panel's bottom inset.
        let chrome: CGFloat = 14 + 34 + 8
            + DSSpacing.tabRowBottomPadding + DSSpacing.tabRowBottomMargin
            + DSSpacing.panelPadding
        return max(240, AppState.shared.maxTodoContentHeight - chrome)
    }
    private static let inlineRowThreshold = 8
    private static let scrollSpace = "todoScrollRegion"
    private static let bottomAnchor = "todoScrollBottom"

    @State private var regionNaturalHeight: CGFloat = 0
    /// How far the capped region has been scrolled. Drives the edge fades.
    @State private var scrollOffset: CGFloat = 0
    @State private var draggedItemID: UUID?
    /// The row the dragged item would land ABOVE. Arc-style: nothing moves
    /// until the drop, we just draw the slot.
    @State private var dropBeforeID: UUID?
    /// True when the drop would land past the last row.
    @State private var dropAtEnd = false

    var body: some View {
        // §8.3 category switch: the id() swap transitions the whole block
        // while the panel height animates — content and container together.
        if let collection = store.activeCollection {
            // Same jump guard as the mode switch: the id() swap keeps two
            // copies alive mid-transition; overlap them instead of stacking.
            ZStack(alignment: .topLeading) {
                browsingBody(for: collection)
                    .id(collection.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)   // FB2: same in-place crossfade
            }
        }
    }

    @ViewBuilder
    private func browsingBody(for collection: TodoCollection) -> some View {
        let openCount = store.openItems(in: collection).count
        let completedCount = store.completedItems(in: collection).count
        let visibleRows = openCount + (store.completedExpanded ? completedCount : 0)

        let content = VStack(alignment: .leading, spacing: 0) {
            // CT-1/CT-6: meetings (or the connect nudge) sit above the
            // to-dos, in the Today tab only.
            if collection.isSystemToday {
                UpNextSection()
            }
            todoList(for: collection)
            completedSection(for: collection)
        }

        if visibleRows <= Self.inlineRowThreshold {
            // Fits comfortably: hug it, no scroll, no measurement round-trip.
            content
        } else {
            // Tall: one capped ScrollView so list + Completed scroll as a
            // single unit and the panel height stops at the budget.
            let viewport = min(regionNaturalHeight, Self.maxRegion)
            let hasBelow = regionNaturalHeight - scrollOffset - viewport > 2
            // Indicators ON. They were hidden, so a capped region gave the eye
            // nothing at all to say "there is more" — rows below the fold and
            // the entire Completed section read as missing rather than
            // scrolled away (Marcello, 2026-08-05).
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
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
                    // Anchor for the "more below" pill to jump to.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .coordinateSpace(name: Self.scrollSpace)
                .onPreferenceChange(SectionHeightKey.self) { regionNaturalHeight = $0 }
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
                .frame(height: viewport)
                // The edge that is cut off softens, so the list visibly
                // continues past it instead of ending on a hard crop.
                .modifier(ScrollEdgeFade(scrollOffset: scrollOffset,
                                         contentHeight: regionNaturalHeight,
                                         viewportHeight: viewport))
                // A fade says "there is more"; this says how to get there, and
                // takes you. Even at full height a long enough list still
                // overflows, and the fade alone is easy to miss on a first run.
                .overlay(alignment: .bottom) {
                    if hasBelow {
                        MoreBelowPill {
                            withAnimation(NotchAnimation.contentHug) {
                                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                            }
                        }
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(NotchAnimation.hintFade, value: hasBelow)
            }
            // The panel must animate to the new budget, or opening Completed
            // snaps instead of growing.
            .animation(NotchAnimation.contentHug, value: store.completedExpanded)
        }
    }

    // MARK: Open list

    @ViewBuilder
    private func todoList(for collection: TodoCollection) -> some View {
        let rows = store.openItems(in: collection)
        if rows.isEmpty {
            // Today says nothing when it is empty — an empty Today already
            // means "you're done", and a sentence restating that is one more
            // thing to read (Marcello, 2026-07-26). A user category still gets
            // a line, because an empty one there looks broken rather than done.
            if !collection.isSystemToday {
                Text(L10n.t("todo.empty"))
                    .font(DSFont.checklistItem)
                    .foregroundStyle(DSColor.textHint)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            openRows(rows)
        }
    }

    private func openRows(_ rows: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.rowInternalGap) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, item in
                TodoItemRow(
                    item: item,
                    accent: store.collection(id: item.collectionID)?.color ?? .accentColor,
                    isFocused: store.focusedItemID == item.id,
                    isExpanded: store.expandedItemID == item.id,
                    draggedItemID: $draggedItemID
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
                            .offset(y: -(DSSpacing.rowInternalGap / 2 + 3))
                    }
                }
                .onDrop(of: [.notchSnapInternalItem], delegate: TodoReorderDropDelegate(
                    targetID: item.id,
                    draggedID: $draggedItemID,
                    dropBeforeID: $dropBeforeID,
                    dropAtEnd: $dropAtEnd
                ))
            }

            // Landing strip for the bottom slot. `reorder(_:before:)` can only
            // insert in FRONT of a row, so without this the last position is
            // unreachable by drag.
            if draggedItemID != nil {
                Color.clear
                    .frame(height: 14)
                    .overlay(alignment: .top) {
                        if dropAtEnd { DropIndicator().offset(y: 3) }
                    }
                    .onDrop(of: [.notchSnapInternalItem], delegate: TodoEndDropDelegate(
                        draggedID: $draggedItemID,
                        dropBeforeID: $dropBeforeID,
                        dropAtEnd: $dropAtEnd
                    ))
            }
        }
        .animation(NotchAnimation.hintFade, value: dropBeforeID)
        .animation(NotchAnimation.hintFade, value: dropAtEnd)
    }

    private var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(x: 24))
        )
    }

    // MARK: Completed (TD-3, per-category)

    @ViewBuilder
    private func completedSection(for collection: TodoCollection) -> some View {
        let completed = store.completedItems(in: collection)
        if !completed.isEmpty {
            // No rule above Completed (Marcello, 2026-07-26) — the gap and the
            // dimmer label already separate it from the open list.
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(NotchAnimation.contentHug) { store.completedExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DSColor.textFaint)
                            .rotationEffect(.degrees(store.completedExpanded ? 90 : 0))
                        Text(L10n.t("todo.completed"))
                            .font(DSFont.checklistItem)
                            .foregroundStyle(DSColor.textMuted)
                        Text("\(completed.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(DSColor.textHint)
                            .contentTransition(.numericText())
                        Spacer()
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
                    // Carries the separation the rule used to provide.
                    .padding(.top, DSSpacing.tabRowBottomMargin + 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if store.completedExpanded {
                    // Inline at natural height — the outer browsingBody region
                    // provides scrolling when the combined content is tall, so
                    // Completed opens fully instead of into a cramped window.
                    completedRows(completed)
                        .transition(.opacity)
                }
            }
            .transition(.opacity)
        }
    }

    private func completedRows(_ completed: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(completed) { item in
                TodoItemRow(
                    item: item,
                    accent: store.collection(id: item.collectionID)?.color ?? .gray,
                    isFocused: false,
                    isExpanded: false,
                    // Completed rows aren't reorderable — the grip stays hidden.
                    draggedItemID: .constant(nil)
                )
                .transition(rowTransition)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Drag-to-reorder (TD-5)

/// Arc's model: dragging only ever MOVES THE INDICATOR. The list itself is
/// left alone until the drop lands, so rows never shuffle under the cursor
/// mid-drag (the previous delegate reordered live inside `dropEntered`).
private struct TodoReorderDropDelegate: DropDelegate {
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
        TodoStore.shared.reorder(dragged, before: targetID)
        return true
    }

    func dropExited(info: DropInfo) {
        // Only retract the indicator if it is still ours — the next row's
        // dropEntered may already have claimed it.
        if dropBeforeID == targetID { dropBeforeID = nil }
    }

    private func clear() {
        draggedID = nil
        dropBeforeID = nil
        dropAtEnd = false
    }
}

/// The strip below the last row: drops here send the item to the bottom.
private struct TodoEndDropDelegate: DropDelegate {
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
        TodoStore.shared.moveToEnd(dragged)
        return true
    }

    func dropExited(info: DropInfo) { dropAtEnd = false }
}

// MARK: - TodoItemRow — live row (collapsed + NC expanded states)
//
// DesignSystem.swift's `TodoRow` is the static visual reference for this
// row's collapsed look; the live app row additionally needs completion
// state, urgency dot, the NC-2 details indicator, and the expanded
// note/checklist editor — so this view exists, styled EXCLUSIVELY from the
// same DS tokens so the two can't drift apart.

private struct TodoItemRow: View {
    let item: TodoItem
    let accent: Color
    let isFocused: Bool
    let isExpanded: Bool
    /// Shared with the list so the dragged row can dim itself.
    @Binding var draggedItemID: UUID?
    /// Hover on the urgency dot alone — drives the priority tooltip.
    @State private var urgencyHover = false
    @State private var hover = false
    @State private var newStep = ""
    /// Title editing. `nil` = not editing; a String = the live draft.
    /// Held separately from the item so an abandoned edit (Escape, clicking
    /// away) never touches the stored title.
    @State private var titleDraft: String?
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow

            if isExpanded {
                expandedDetails
            }
        }
        .padding(.horizontal, isExpanded ? 12 : 8)
        .padding(.vertical, isExpanded ? 10 : 7)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .fill(isExpanded ? DSColor.fieldBackground
                                 : (isFocused ? DSColor.focusedRowBackground
                                              : (hover ? Color.white.opacity(0.04) : .clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .stroke((isFocused || isExpanded) ? DSColor.focusAccent : .clear, lineWidth: 0.5)
        )
        .animation(NotchAnimation.hintFade, value: isFocused)
        .onHover { hover = $0 }
        // A row can also be closed from outside this view — clicking a
        // different row, Escape, the whole panel collapsing. Any of those
        // while mid-edit would otherwise strand the draft in view state and
        // silently lose it, so they save on the way out too.
        .onChange(of: isExpanded) { expanded in
            if !expanded { commitTitle() }
        }
        .contextMenu { contextMenuItems }
    }

    // The first text line is ~17pt tall; the 14pt checkbox and the trailing
    // indicators sit on THAT line via a small top inset, so a title that
    // wraps to several lines keeps the checkbox pinned to the top-left
    // instead of floating to the vertical middle (FB1, Marcello 2026-07-23).
    private static let firstLineInset: CGFloat = 1.5

    private var titleRow: some View {
        HStack(alignment: .top, spacing: DSSpacing.rowInternalGap) {
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
                    RoundedRectangle(cornerRadius: DSRadius.checkboxCorner, style: .continuous)
                        .strokeBorder(accent, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if item.isCompleted {
                        RoundedRectangle(cornerRadius: DSRadius.checkboxCorner, style: .continuous)
                            .fill(accent)
                            .frame(width: 14, height: 14)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(DSColor.primaryText.opacity(0.8))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, Self.firstLineInset)
            // §8.3: near-instant fill; row exit + shrink follow on contentHug.
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: item.isCompleted)

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
                    .focused($titleFieldFocused)
                    .onSubmit { commitTitle() }
                    // Losing focus commits too — clicking away is a save
                    // everywhere else in this app, so it is here as well.
                    .onChange(of: titleFieldFocused) { focused in
                        if !focused { commitTitle() }
                    }
                    .onExitCommand { titleDraft = nil }   // Escape discards
            } else {
                // EH-1..6: links/dates/mentions/code render as inline chips
                // in the flowing, wrapping title.
                EntityTitleView(
                    title: item.title,
                    isBright: isFocused || isExpanded,
                    onTap: activateRow
                )
            }

            Spacer(minLength: 6)

            // Trailing indicators ride the first line too.
            Group {
                // No pencil. Opening a row puts the caret straight in the
                // title, so a button to do the same thing was an extra step
                // for something that should just be click-and-type
                // (Marcello, 2026-08-10).

                // NC-2: collapsed rows with details wear a subtle indicator.
                if item.hasDetails && !isExpanded {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 8))
                        .foregroundStyle(DSColor.textHint)
                }

                // UG-1/UG-5: 9px dot, Medium/High only — Low (the default)
                // stays visually silent, so a dot always means "raised".
                if item.urgency != .low && !item.isCompleted {
                    UrgencyDot(urgency: item.urgency) { hovering in
                        withAnimation(NotchAnimation.hintFade) { urgencyHover = hovering }
                    }
                    .anchorPreference(key: UrgencyTooltipKey.self, value: .bounds) { anchor in
                        // The DOT's own hover, not the row's.
                        urgencyHover
                            ? [UrgencyTooltipInfo(text: item.urgency.fullLabel, anchor: anchor)]
                            : []
                    }
                }

                // §7.1: only the focused row shows its one relevant shortcut.
                if isFocused && !item.isCompleted && !isExpanded {
                    ShortcutHintBadge(text: "\u{21A9}")
                        .transition(.opacity)
                }
            }
            .padding(.top, Self.firstLineInset + 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: activateRow)
        // Reordering starts from anywhere on the row. Completed rows are
        // fixed, so they stay undraggable.
        .onDrag {
            draggedItemID = item.id
            return .notchSnapInternal(item.id)
        } preview: {
            Text(item.title)
                .font(DSFont.todoTitle)
                .foregroundStyle(DSColor.textPrimaryBright)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DSShape.squircle(DSRadius.controlCorner).fill(DSColor.fieldBackground))
        }
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
    }

    /// Save and leave edit mode. An empty title is refused by the store, so
    /// clearing the field and pressing Return keeps the original rather than
    /// leaving an unidentifiable blank row.
    private func commitTitle() {
        guard let draft = titleDraft else { return }
        TodoStore.shared.rename(item.id, to: draft)
        titleDraft = nil
    }

    // MARK: NC expanded details — note with left rule, sub-checklist (§7)

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DSColor.panelBorder)
                    .frame(width: 0.5)
                    .padding(.leading, 6)
                TextField(L10n.t("todo.notePlaceholder"),
                          text: noteBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DSFont.checklistItem)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1...4)
                    .padding(.leading, 17)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.checklist) { step in
                    HStack(spacing: 6) {
                        Button {
                            TodoStore.shared.toggleChecklistItem(step.id, in: item.id)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: DSRadius.checklistCheckboxCorner,
                                                 style: .continuous)
                                    .strokeBorder(DSColor.textFaint, lineWidth: 1)
                                    .frame(width: 10, height: 10)
                                if step.isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Text(step.title)
                            .font(DSFont.checklistItem)
                            .strikethrough(step.isDone)
                            .foregroundStyle(step.isDone ? DSColor.textFaint : Color(hex: "#AAAAAA"))
                        Spacer(minLength: 0)
                    }
                    .contextMenu {
                        Button(L10n.t("action.delete"), role: .destructive) {
                            TodoStore.shared.deleteChecklistItem(step.id, in: item.id)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 7))
                        .foregroundStyle(DSColor.textHint)
                        .frame(width: 10, height: 10)
                    TextField(L10n.t("todo.addStep"), text: $newStep)
                        .textFieldStyle(.plain)
                        .font(DSFont.checklistItem)
                        .foregroundStyle(DSColor.textSecondary)
                        .onSubmit {
                            TodoStore.shared.addChecklistItem(newStep, to: item.id)
                            newStep = ""
                        }
                }
            }
            .padding(.leading, DSSpacing.checklistIndent)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(L10n.t("todo.editTitle")) { beginEditingTitle() }
        Divider()
        ForEach(TodoUrgency.allCases) { u in
            Button(u.label) { TodoStore.shared.setUrgency(u, for: item.id) }
        }
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

// MARK: - ShortcutsOverlay — in-panel `?` reference (§2.3)

private struct ShortcutsOverlay: View {
    private let rows: [(String, String)] = [
        ("\u{2191} \u{2193}", "todo.sc.moveFocus"),
        ("\u{21A9}", "todo.sc.toggleComplete"),
        ("\u{2192} \u{2190}", "todo.sc.expandRow"),
        ("\u{2318}N", "todo.sc.newTodo"),
        ("\u{2318}1\u{2013}9 / \u{2318}", "todo.sc.switchCollection"),
        ("\u{2325}\u{2191}\u{2193}", "todo.sc.reorder"),
        ("\u{21E7}\u{2318}M", "todo.sc.moveItem"),
        ("a\u{2026}z", "todo.sc.quickFind"),
        ("\u{2325}\u{2318}N", "todo.sc.quickEntry"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.t("todo.shortcuts").uppercased())
                    .font(DSFont.sectionLabel)
                    .tracking(0.4)
                    .foregroundStyle(DSColor.textMuted)
                Spacer()
                Text(L10n.t("todo.sc.closeHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textHint)
            }
            .padding(.bottom, 4)

            ForEach(rows, id: \.0) { keys, labelKey in
                HStack {
                    Text(L10n.t(labelKey))
                        .font(DSFont.checklistItem)
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    ShortcutHintBadge(text: keys)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#0A0A0A").opacity(0.94))
        )
    }
}

// MARK: - Internal drag payload

private extension NSItemProvider {
    /// A reorder drag that never leaves the process, carrying a type nothing
    /// else in the app (or the system) accepts — see UTType.notchSnapInternalItem.
    static func notchSnapInternal(_ id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.notchSnapInternalItem.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

// MARK: - SweepButton — clear the completed pile (Marcello, 2026-08-04)
//
// Sits at the right of the Completed header. Deliberately quiet: it only
// appears while the section is open, and it fades up on hover rather than
// advertising itself, because it throws work away and should not be the most
// obvious thing in the row.

private struct SweepButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "wind")
                .font(.system(size: 11, weight: .medium))
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
