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
            .shadow(color: DSColor.shadowSoft, radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
    }
}

/// Width of the tab row's content, and of the window it sits in. The two
/// together answer the only question the scroller has: does it need to scroll
/// at all?
private struct TabsContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TabsViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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

/// A transparent layer that means "you clicked nothing" — it ends whatever
/// edit or selection is live.
///
/// Always used as a `.background`, deliberately: a background only receives a
/// click where nothing in front of it handled one, so rows, checkboxes,
/// buttons, the tab strip and drag-to-reorder all still get theirs first. It
/// is a fallback, never an interceptor.
private struct DeselectCatcher: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { TodoStore.shared.endEditing() }
    }
}

/// Opacity plus a few points of blur, in and out. SwiftUI ships no blur
/// transition, so it is a modifier pair; the radius is small enough that
/// nothing reads as an effect — the content just softens on its way out.
private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// Zero LAYOUT height, full drawing. The content overflows its frame (SwiftUI
/// does not clip by default), so it is still painted while it fades — it just
/// no longer has a say in how tall its parent is.
private struct ZeroLayoutHeight: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.frame(height: active ? 0 : nil, alignment: .top)
    }
}

private extension AnyTransition {
    // Computed, not stored: AnyTransition isn't Sendable, so a static let
    // fails Swift 6's isolation check.
    static var crossfadeBlur: AnyTransition {
        .opacity.combined(
            with: .modifier(active: BlurModifier(radius: 4), identity: BlurModifier(radius: 0))
        )
    }

    /// The section / mode swap: crossfade in, crossfade out — and the
    /// outgoing view drops out of LAYOUT the moment it starts leaving.
    ///
    /// Both views overlap in a ZStack during the crossfade, and a ZStack is
    /// as tall as its tallest child. So Work (12 rows) → Personal (2 rows)
    /// kept the panel at twelve rows' height until the old list had fully
    /// faded, then snapped to two — outside any animation, because a
    /// transition's removal is discrete — and the tab row snapped with it
    /// (Thomas, 2026-09-01). With the outgoing view at zero layout height
    /// the ZStack is the incoming list's height from the first frame, the
    /// change happens inside the withAnimation that switched sections, and
    /// the panel, the scroll region and the tabs all ride one spring.
    static var sectionSwap: AnyTransition {
        .asymmetric(
            insertion: crossfadeBlur,
            removal: crossfadeBlur.combined(with: .modifier(
                active: ZeroLayoutHeight(active: true),
                identity: ZeroLayoutHeight(active: false)))
        )
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
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels

    // FB2: one transition, every direction. A pure in-place crossfade —
    // no y-offset, no edge-move — so switching tabs or modes never "slides
    // in from the top" or bleeds over the tab row, and Work→Today looks
    // identical to Today→Personal (Marcello 2026-07-23). A touch of blur
    // rides on the fade (Thomas, 2026-09-01) so the outgoing content
    // dissolves rather than ghosting over the incoming one mid-hug.
    private var modeTransition: AnyTransition { .sectionSwap }

    var body: some View {
        // §2.3: the shortcuts overlay sits ON TOP of the live content —
        // dismissing is instant, nothing re-renders underneath.
        ZStack(alignment: .topLeading) {
            // Who draws the live meeting alert depends on the layout.
            //
            // In `.panels` nobody draws it here: the meeting card is its own
            // block above, and a copy in here put the same meeting on screen
            // twice, one above the other. The column hides this whole panel
            // while an alert is live — see LabPanelsView.
            //
            // In `.container` there is no block above, so the panel carries
            // the alert again as it did before the split, and it OWNS the
            // panel while it is up: the notch opened itself for this, so it
            // must not compete with the list underneath (CA-3).
            if notchLayout == .container, let alert = calendar.activeAlert {
                MeetingAlertView(meeting: alert)
                    .transition(.opacity)
            } else {
                todoPanelContent
            }
        }
        .padding(.top, LabMetrics.panelTopPadding)
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
        // Width only — NOT maxHeight: .infinity. That frame took whatever
        // height was proposed, and in the panels layout the column proposes
        // its 556 cap, so the glass block drew 556 tall with the tabs
        // floating a third of the way down it while the measurement above
        // (which sits inside this frame) dutifully reported the hugged
        // height. The silhouette hugged; the block the user looks at did
        // not (Thomas, 2026-09-01, screenshot). The view is its content's
        // height, full stop; whoever draws around it hugs for free.
        .frame(maxWidth: .infinity, alignment: .top)
        // Click anywhere the panel isn't otherwise using — the empty band
        // beside the tabs, the gaps between rows, the padding — and whatever
        // is being edited commits and gives up the caret.
        //
        // This is the ordinary text-field contract everywhere else on the
        // Mac: clicking off a focused field ends the edit. SwiftUI does not
        // give it to you for free on macOS, because nothing else claims focus
        // when you click a non-interactive area, so the field simply keeps it
        // and typing carries on into a row the user has visually left
        // (Marcello, 2026-08-10).
        //
        // Sits in `.background`, deliberately: a background only receives a
        // click where no real control was hit, so rows, buttons, the tab
        // strip and drag-to-reorder all still get theirs first. It is a
        // fallback, not an interceptor.
        .background(DeselectCatcher())
        .background(TodoBrowsingKeyHandler())
    }

    /// The normal to-do panel: tab row + the active mode's surface, with the
    /// on-demand shortcuts overlay on top.
    private var todoPanelContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                // The order is now bar, list, TABS AT THE BOTTOM.
                //
                // The sections were demoted deliberately: the point of the
                // panel is the to-do being typed, and a row of section chips
                // sitting between the field and the list kept pulling the eye
                // to switching rather than to writing. At the foot they are
                // still one click away and no longer compete.
                //
                // The draft row stays hoisted out of TodoBrowsingView, which
                // also keeps it clear of the `.id(collection.id)` subtree that
                // is rebuilt on every ⇥ — the reason its caret survives.
                if store.panelMode == .browsing || store.panelMode == .voice {
                    InlineDraftRow(accent: store.draftDestination?.color ?? LabMetrics.accent)
                        .padding(.horizontal, LabMetrics.barOuterInset)
                        .notchEntry(index: 0)
                        .padding(.bottom, LabMetrics.sectionGap)
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

                // No Spacer here. With the panel hugging its content again
                // (Thomas, 2026-09-01) there is no slack to absorb: the tabs
                // sit directly under the list and ride with it. A Spacer in a
                // definite-height proposal is also what closed the container
                // layout's measurement loop — the content stretched to
                // whatever height it was handed, so the measured "natural"
                // height was just the proposal echoed back and the hug could
                // never converge.

                if store.panelMode == .browsing || store.panelMode == .voice {
                    TodoTabRow()
                        .notchEntry(index: 1)
                }
            }

            if store.showShortcuts {
                ShortcutsOverlay()
                    .transition(.opacity)
            }
        }
    }
}

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

private struct TodoTabRow: View {
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

    var body: some View {
        HStack(spacing: LabMetrics.tabsGap) {
            tabScroller

            // OUTSIDE the scroller, like the account button beside it.
            //
            // The "+" used to be the last thing INSIDE the scrolling strip, so
            // at five sections it scrolled off the end and there was no way
            // left to make a new one (Marcello, 2026-08-23: "I have lost the
            // plus"). The sole entry point for creating something cannot be
            // allowed to leave the screen.
            NewSectionButton()

            Spacer(minLength: LabMetrics.tabsGap)
            // Outside the scroller: the account is not a tab.
            AccountButton()
        }
        // No rule under the tab row (Marcello, 2026-07-26). The two paddings
        // stay: they were the breathing room either side of the line, and
        // together they are what now separates the tabs from the list.
        .padding(.horizontal, LabMetrics.tabsInset)
        // The rule is part of the tab row's own LAYOUT now, not an overlay
        // pushed up out of it.
        //
        // It used to be drawn at `-tabsDividerPaddingV`, 12pt above this row's
        // top edge — which is inside the area the list occupies. So the last
        // row and the rule were painted over each other and the list appeared
        // to continue past its own boundary (Marcello, 2026-08-22). In the
        // flow it cannot overlap anything, and the list is clipped to stop at
        // it. See `.clipped()` on the scroll region.
        .padding(.top, LabMetrics.tabsDividerPaddingV)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DSColor.hairlineOnPanel)
                .frame(height: 1)
        }
        .padding(.top, LabMetrics.tabsTopPadding)
        .padding(.bottom, LabMetrics.tabsBottomPadding)
    }

    private var tabScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LabMetrics.tabsGap) {
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
                        categoryColor: collection.color,
                        isActive: store.panelMode == .browsing
                            && collection.id == store.activeCollectionID,
                        remaining: store.remainingCount(for: collection)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: DSRadius.chipCorner, style: .continuous))
                    .onTapGesture { store.selectCollection(collection.id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(collection.name)
                    // Drag a tab onto another to change the order. Only
                    // category chips participate — the "+" is structural and
                    // never moves (Marcello, 2026-07-23).
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
                    // Drawn in the gap BEFORE this tab so it never displaces
                    // anything — an inserted view would make the row jump
                    // under the cursor, which is the whole bug being fixed.
                    .overlay(alignment: .leading) {
                        if dropBeforeCollectionID == collection.id {
                            TabDropIndicator().offset(x: -5)
                        }
                    }
                    .onDrop(of: [.notchSnapInternalItem], delegate: CollectionReorderDropDelegate(
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
                        .onDrop(of: [.notchSnapInternalItem], delegate: CollectionEndDropDelegate(
                            draggedID: $draggedCollectionID,
                            dropBeforeID: $dropBeforeCollectionID,
                            dropAtEnd: $dropCollectionAtEnd
                        ))
                }

            }
            .animation(NotchAnimation.hintFade, value: dropBeforeCollectionID)
            .animation(NotchAnimation.hintFade, value: dropCollectionAtEnd)
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
        .onPreferenceChange(TabsContentWidthKey.self) { tabsContentWidth = $0 }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TabsViewportWidthKey.self,
                                       value: proxy.size.width)
            }
        )
        .onPreferenceChange(TabsViewportWidthKey.self) { tabsViewportWidth = $0 }
    }
}

// MARK: - Category tab drag-to-reorder

private struct CollectionReorderDropDelegate: DropDelegate {
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
private struct CollectionEndDropDelegate: DropDelegate {
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
private struct TabDropIndicator: View {
    var body: some View {
        Capsule()
            .fill(DSColor.textPrimaryBright.opacity(0.85))
            .frame(width: 2, height: 18)
            .transition(.opacity)
    }
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

// MARK: - NewSectionButton — the "+" at the end of the tabs
//
// A plain glyph at the same weight as any other piece of chrome, not a filled
// chip. Creating a section is a rare, structural act; it should be findable
// and never louder than the tabs it sits beside. Everything ELSE about a
// section — default, reorder, delete — is on that section's own right-click
// menu, where it applies to the tab you are pointing at rather than to
// whichever one happened to be active.

private struct NewSectionButton: View {
    @State private var hover = false

    var body: some View {
        Button {
            TodoStore.shared.setMode(.newCategory)
            NotchController.shared.focusPanel()
        } label: {
            // Two bare crossing lines in a 24pt box — no glyph weight, no
            // background, no border. Drawn rather than set, because an SF
            // "plus" carries its own optical padding and metrics that will
            // not match a 12pt/1pt cross.
            ZStack {
                Rectangle().frame(width: 12, height: 1)
                Rectangle().frame(width: 1, height: 12)
            }
            .foregroundStyle(hover ? DSColor.glyphStrong : DSColor.glyph)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        .help(L10n.t("todo.newCollection"))
        .accessibilityLabel(L10n.t("todo.newCollection"))
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
    ///
    /// `draftInset` is the space the pinned draft row takes above the list.
    /// It has to come out of the same budget: the draft is chrome from the
    /// scroll region's point of view, and a region that ignored it would lay
    /// out rows in the strip the draft is standing on.
    private static func maxRegion(draftInset: CGFloat) -> CGFloat {
        // The panel's ceiling minus its furniture, computed once in
        // LabMetrics. It used to be derived from the SCREEN, which is why an
        // unbounded list grew until it covered one.
        // 556 total, less the creation-bar block and the tab bar that now
        // sits under the list. Derived so changing either end carries.
        LabMetrics.todoBlockMaxHeight
            - (LabMetrics.panelTopPadding + LabMetrics.barHeight + LabMetrics.sectionGap)
            - (LabMetrics.tabsDividerPaddingV + LabMetrics.tabsTopPadding
               + 31 + LabMetrics.tabsBottomPadding)
    }

    /// One line of draft plus its padding and the gap under it. An estimate,
    /// not a measurement: a draft that has wrapped to three lines is both rare
    /// and short-lived, and the cost of being a little conservative here is
    /// one row of scroll, while the cost of measuring is a layout round-trip
    /// on every keystroke.
    private static let draftRowAllowance: CGFloat = 54
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
    @State private var draggedItemID: UUID?
    /// Which edge `scrollTo` aims at. Walking down, keep the focused row at
    /// the bottom; walking up, at the top. One fixed anchor makes the list
    /// leap a whole viewport the moment the user reverses direction.
    @State private var scrollAnchor: UnitPoint = .bottom
    @State private var lastFocusedIndex: Int?
    /// Where each row sits, in `rowSpace`. Published by the rows themselves so
    /// the gesture can resolve a pointer position to a gap.
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
                        .transition(.sectionSwap)   // FB2: same in-place crossfade
                }
            }
        }
    }

    @ViewBuilder
    private func browsingBody(for collection: TodoCollection) -> some View {
        let open = store.openItems(in: collection)
        let openCount = open.count
        let completedCount = store.completedItems(in: collection).count
        // Steps are real rows on screen now, so they have to count toward the
        // budget. Three to-dos with five steps each is eighteen rows, not
        // three — and a region that only counted parents would lay them out
        // past what the notch can display, which is exactly the bug the cap
        // exists to prevent (2026-08-05).
        // +1 per checklist for the trailing draft row, which is now on screen
        // in the list as well.
        let stepCount = open.reduce(0) { $0 + $1.checklist.count + ($1.checklist.isEmpty ? 0 : 1) }
        let visibleRows = openCount + stepCount + (store.completedExpanded ? completedCount : 0)

        let content = VStack(alignment: .leading, spacing: 0) {
            // CT-1/CT-6: meetings (or the connect nudge) sit above the
            // to-dos, in the Today tab only.
            if collection.isSystemToday {
                UpNextSection()
            }
            todoList(for: collection)
            completedSection(for: collection)
        }
        .padding(.horizontal, LabMetrics.listInset)
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
            let budget = Self.maxRegion(draftInset: 0)
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
            let hasBelow = natural - scrollOffset - viewport > 2
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
                // Arrow keys move a focus ring the list was not following, so
                // past the fold you were selecting rows you could not see —
                // still moving, still invisible (Marcello, 2026-08-23). The
                // region now brings the focused row into view.
                //
                // `.bottom` going down and `.top` going up, rather than one
                // anchor for both: aiming at the same edge in both directions
                // makes the list jump a whole viewport the moment you reverse.
                .onChange(of: store.focusedItemID) { focused in
                    guard let focused else { return }
                    let index = store.visibleFocusIndex(of: focused)
                    if let index, let last = lastFocusedIndex {
                        scrollAnchor = index >= last ? .bottom : .top
                    }
                    lastFocusedIndex = index
                    withAnimation(NotchAnimation.hintFade) {
                        proxy.scrollTo(focused, anchor: scrollAnchor)
                    }
                }
                .onPreferenceChange(SectionHeightKey.self) { height in
                    regionNaturalHeights[collection.id] = height
                    lastRegionNaturalHeight = height
                }
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
                .frame(height: viewport)
                // The list ENDS at its own bottom edge. Without this a row
                // that overran the viewport kept drawing into the band the
                // divider and the tabs live in, so the two overlapped and it
                // read as a rendering fault rather than as a list continuing.
                .clipped()
                // The edge that is cut off softens, so the list visibly
                // continues past it instead of ending on a hard crop.
                .modifier(ScrollEdgeFade(scrollOffset: scrollOffset,
                                         contentHeight: natural,
                                         viewportHeight: viewport))
                // A fade says "there is more"; this says how to get there, and
                // takes you. Even at full height a long enough list still
                // overflows, and the fade alone is easy to miss on a first run.
                // No bottom fade. Its 54pt of transparent-to-black was meant
                // to soften a half-cut row against the divider, but it painted
                // whether or not anything was being cut — so an empty or short
                // list wore a dark band across nothing (Marcello, 2026-08-22).
                // The rule above the tabs already does the separating.
                // No "More below" pill. The 54pt fade already says the list
                // continues; a floating label over the last row was a second
                // device carrying one message.
                .animation(NotchAnimation.hintFade, value: hasBelow)
            }
            // The panel must animate every viewport change — opening
            // Completed, adding a row, switching to a shorter section — or
            // the hug snaps instead of growing. Keyed on the viewport itself
            // so any route into a new height takes the same spring.
            .animation(NotchAnimation.contentHug, value: viewport)
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
        // 6, per the export — 37pt rows on a 43pt pitch. This was the
        // generic 10pt row gap, which is why the rhythm never matched the mock.
        VStack(alignment: .leading, spacing: LabMetrics.listRowGap) {
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
                            .offset(y: -(LabMetrics.listRowGap / 2 + 3))
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
                    isExpanded: false
                )
                .transition(rowTransition)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - InlineDraftRow — the to-do being typed
//
// The replacement for the creation card, and the panel's only visible way to
// make a to-do — so it is ALWAYS here, at the top of the list, whether or not
// anyone asked for it. Summoning it with ⌃⇧N was not enough: a user who opens
// the notch and looks at it has to be able to see how to add something.
//
// It is deliberately built out of the SAME parts as a real row — checkbox at
// 14pt, the same leading gap, the same title type — because the point of
// typing in place is that you can see the thing you are making take its final
// shape. It also spans the FULL panel width; a short box floating in the
// middle of a wide notch reads as a stray control rather than as the first
// row of the list.
//
// Four states, and they have to be told apart at a glance:
//
//   1. Idle + empty     neutral fill, muted placeholder — an invitation
//   2. Focused + empty  destination tint + border, caret blinking
//   3. Idle + typed     neutral fill, full-brightness text
//   4. Focused + typing tint + border, accent caret and selection
//
// The tint and the caret both take the DESTINATION section's color, so "where
// is my cursor" and "where is this going" have one answer. That also makes ⇥
// legible in the row itself, not only up in the tab bar — and it is what
// makes an honest job of Today, which cannot hold to-dos: aim at Today and
// the row quietly wears the section it will actually file into.

private struct InlineDraftRow: View {
    /// The destination section's color.
    let accent: Color

    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    /// The well is BLACK in both appearances, at different strengths, so it
    /// cannot be written with `dynamicOverlay` — that flips to white in the
    /// dark, which is the grey this is trying to stop being.
    @Environment(\.colorScheme) private var colorScheme

    private var focused: Bool { store.draftFocused }
    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }

    /// How far the well sits below the panel. Deeper in the dark, where there
    /// is more room beneath the panel before a well turns into a hole.
    private var wellOpacity: Double {
        if colorScheme == .dark {
            return focused ? 0.14 : (hover ? 0.18 : 0.22)
        }
        return focused ? 0.03 : (hover ? 0.04 : 0.05)
    }

    /// FB5, inherited from the creation card: an NSViewRepresentable's own
    /// sizeThatFits is NOT re-invoked on a pure content change, so the height
    /// has to be computed here — where `draftTitle` is observed — or the field
    /// stays stuck at one line while the text wraps out of sight.
    private var fieldHeight: CGFloat {
        let panelWidth = CGFloat(NotchController.shared.expandedWidth)
        // Panel padding ×2, the row's own inset ×2, the checkbox and its gap,
        // and the ⇥ badge. Estimated slightly narrow so the line count rounds
        // up rather than clipping the last line.
        let width = max(120, panelWidth - CGFloat(DSSpacing.panelPadding) * 2 - 20 - 24 - 112)
        let text = store.draftTitle.isEmpty ? " " : store.draftTitle
        let measured = NSAttributedString(
            string: text, attributes: [.font: NSFont.systemFont(ofSize: DSFont.todoTitleSize)]
        ).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return max(HighlightingTitleField.lineHeight,
                   min(ceil(measured), HighlightingTitleField.maxHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // CENTER, per the export's `align-items: center`. Top-aligning while
        // the label carries its own 8pt box is what left every checkbox
        // sitting visibly above the text it belongs to.
        HStack(alignment: .center, spacing: LabMetrics.rowInnerGap) {
                // Back to a checkbox, and the SAME one the rows use: 18pt,
                // 2pt cyan, 6pt corner. The export draws the bar and the list
                // with one component, so the bar reads as the row you are
                // about to make rather than as a search field.
                // The DESTINATION's colour, so the bar says where the thing
                // being typed will land — the same pairing the rows use.
                RoundedRectangle(cornerRadius: LabMetrics.checkboxRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: LabMetrics.checkboxStroke)
                    .frame(width: LabMetrics.checkboxSize, height: LabMetrics.checkboxSize)

                ZStack(alignment: .topLeading) {
                    // Stays until the first character, the way every other
                    // Mac text field behaves — it brightens on focus instead
                    // of vanishing, so an empty focused field still says what
                    // it is for.
                    if store.draftTitle.isEmpty {
                        Text(L10n.t("todo.titlePlaceholder"))
                            .font(DSFont.todoTitle)
                            .foregroundStyle(focused ? DSColor.textFaint : DSColor.textHint)
                            .allowsHitTesting(false)
                    }
                    HighlightingTitleField(
                        text: $store.draftTitle,
                        // NL-2: a recognized date phrase colors inline, in
                        // place, and is stripped from the title only on commit.
                        highlightRange: parsed?.nsRange,
                        accent: accent,
                        wantsFocus: store.draftWantsFocus,
                        onFocusChange: { isFocused in
                            store.draftFocused = isFocused
                            if isFocused { store.draftWantsFocus = false }
                        }
                    )
                    .frame(height: fieldHeight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Spelled out, not a bare ⇥. The glyph alone was "not really
                // clear enough, and it's really hard to understand what you
                // can do with it" (Marcello, 2026-08-16) — a keyboard hint
                // that has to be decoded is not a hint. The word plus what it
                // does needs no decoding, and there is room for it now that
                // the row spans the panel.
                //
                // Always present, just quieter when idle: this is the only
                // thing telling you the row has a destination at all, so
                // hiding it until hover hid the whole feature.
                // Two keys, no prose.
                //
                // "Switch section" spelled it out because the ⇥ glyph alone
                // was undecodable — but the words were only ever scaffolding
                // for one key, and now there are two to show. Raycast puts the
                // keys bare at the right edge and lets them be keys; the
                // tooltips still carry the words for anyone who wants them.
                // "Switch space", per the export — and always visible at the
                // stated 35%, not fading in on hover.
                HStack(spacing: 8) {
                    Text(L10n.t("todo.switchSpace"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DSColor.textFaint)
                        .fixedSize()
                    Text(L10n.t("key.tab"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DSColor.textFaint)
                        .frame(width: 32, height: 19)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(DSColor.textFaint, lineWidth: 1)
                        )
                }
            }

            // NL-3: live resolved-date caption, aligned with the title.
            if let parsed {
                Text("\u{2192} \(parsed.display)")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textFaint)
                    .padding(.leading, 14 + DSSpacing.rowInternalGap)
                    .transition(.opacity)
            }
        }
        // 24 / 16, as specified.
        .padding(.horizontal, LabMetrics.barPaddingH)
        .padding(.vertical, LabMetrics.barPaddingV)
        // Spans the notch. Without this the field reports its own ideal width
        // and the box floated mid-panel, detached from the list it belongs to.
        .frame(maxWidth: .infinity, alignment: .leading)
        // NOT a second sheet of glass. That is what made it disappear.
        //
        // Glass over glass means both layers sample the same desktop, so the
        // bar's colour was decided by the WALLPAPER — and over a dark one it
        // and the panel converged until the placeholder and the key hints were
        // barely legible (Marcello, Tahoe, 2026-08-22).
        //
        // Its contrast is now defined against the PANEL instead: a fixed step
        // away from whatever the panel resolved to, which cannot collapse no
        // matter what is behind the window. Plus a hairline that is always
        // drawn, so the bar has an edge even when the fills are close.
        .frame(minHeight: LabMetrics.barHeight)
        // A WELL: darker than the panel, with the edge doing the finding.
        //
        // Two wrong answers came first. The export's flat black wash gave the
        // bar no edge at all, so on a dark desktop it vanished into the panel.
        // Lifting it with white made it findable and GREY — a filled slab, and
        // the brightest thing on a panel whose job is to be calm (Marcello,
        // 2026-08-24: "too grayish and too prominent").
        //
        // A recessed well is the third answer and the ordinary one: the fill
        // goes slightly DARKER than what surrounds it and a hairline draws the
        // boundary. Depth is what marks a field, not brightness — text goes
        // into an input, and it should look like somewhere text can go.
        //
        // Not glass, deliberately. The material is right for inputs in the
        // NAVIGATION layer — that is what `.searchable()` gets on macOS 26,
        // placed by the system in a toolbar. This one sits inside a panel that
        // is itself glass, and glass cannot sample glass; the prescribed
        // remedy is a shared container for NEARBY elements, which has no
        // answer for a child nested in a glass parent.
        .background(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .fill(Color.black.opacity(wellOpacity))
        )
        // Soft. It only has to separate the well from the panel, and the well
        // already sits a shade below it.
        .overlay(
            RoundedRectangle(cornerRadius: LabMetrics.barRadius, style: .continuous)
                .strokeBorder(focused ? accent.opacity(0.7)
                                      : Color.dynamicOverlay(light: 0.07, dark: 0.08),
                              lineWidth: 1)
        )
        .animation(NotchAnimation.hintFade, value: focused)

        // Clicking anywhere in the box takes the caret, not just the ~17pt
        // strip of text view inside it.
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous))
        .onTapGesture { store.draftWantsFocus = true }
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        // Detachment is whitespace, not a rule: the fill already says "this is
        // not one of the list items", so a divider would be two devices doing
        // one job.
        .padding(.bottom, 10)
        .animation(NotchAnimation.hintFade, value: focused)
        .animation(NotchAnimation.hintFade, value: parsed?.display)
        .animation(NotchAnimation.contentHug, value: accent)
    }
}

// MARK: - Drag-to-reorder (TD-5)

/// Arc's model: dragging only ever MOVES THE INDICATOR. The list itself is
/// left alone until the drop lands, so rows never shuffle under the cursor
/// mid-drag (the previous delegate reordered live inside `dropEntered`).
/// Every row's rectangle, collected into one dictionary.
private struct RowFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
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
    /// Hover on the urgency dot alone — drives the priority tooltip.
    @State private var urgencyHover = false
    @State private var hover = false
    /// Title editing. `nil` = not editing; a String = the live draft.
    /// Held separately from the item so an abandoned edit (Escape, clicking
    /// away) never touches the stored title.
    @State private var titleDraft: String?
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow

            // Notes stay behind the click. Steps do not.
            //
            // A step used to be invisible until you opened the to-do, which
            // meant you had to click into every item to find out whether it
            // had any — so a checklist you had written was, during ordinary
            // browsing, simply not there (Marcello's spec, 2026-08-18). Steps
            // now render inline, always, and stay tickable from the list.
            //
            // The draft row comes with them. It was held back to the opened
            // to-do at first, which left the list showing a checklist with no
            // hint that it could be added to — "you don't have anything that
            // shows you how you can add a new step" (Marcello, 2026-08-19).
            // The empty row IS the affordance, so keeping it hidden was
            // keeping the feature hidden.
            //
            // It appears under a to-do that HAS steps, not under every to-do:
            // an empty "Type to add a step" line beneath all twenty rows of a
            // list would be a lot of furniture to advertise one gesture.
            if isExpanded {
                noteBlock
            }
            if !item.checklist.isEmpty || isExpanded {
                stepsBlock()
            }
        }
        // 12pt horizontal, always. That puts a row's checkbox at
        // listInset 24 + 12 = 36 — the same offset the creation bar's sits at
        // (barOuterInset 16 + barPaddingH 20), so every checkbox in the panel
        // finally shares one vertical line. They were apart because this line
        // was lost when an earlier script aborted before writing.
        .padding(.horizontal, LabMetrics.rowPaddingH)
        .padding(.vertical, isExpanded ? 8 : 0)
        // A floor, not a fixed height: a title that wraps still grows. Without
        // it the row was exactly as tall as its content, so the checkbox had
        // 12pt either side and nothing above or below.
        .frame(minHeight: isExpanded ? 0 : LabMetrics.rowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: LabMetrics.rowRadius, style: .continuous)
                .fill(isExpanded ? DSColor.fieldBackground
                                 : (isFocused ? DSColor.focusedRowBackground
                                              : (hover ? Color.dynamicOverlay(light: 0.04, dark: 0.04)
                                                       : .clear)))
        )
        // No ring on a focused row. The system accent drew a blue outline that
        // belonged to no other surface in the panel; the slab behind the row
        // says "focused" on its own, which is what the export does.
        .overlay(
            RoundedRectangle(cornerRadius: LabMetrics.rowRadius, style: .continuous)
                .stroke(isExpanded ? DSColor.focusAccent : .clear, lineWidth: 0.5)
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

    // The first text line is ~17pt tall; the 14pt checkbox and the trailing
    // indicators sit on THAT line via a small top inset, so a title that
    // wraps to several lines keeps the checkbox pinned to the top-left
    // instead of floating to the vertical middle (FB1, Marcello 2026-07-23).
    fileprivate static let firstLineInset: CGFloat = 1.5

    private var titleRow: some View {
        // CENTER, per the export's `align-items: center`. Top-aligning while
        // the label carries its own 8pt box is what left every checkbox
        // sitting visibly above the text it belongs to.
        HStack(alignment: .center, spacing: LabMetrics.rowInnerGap) {
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
                    RoundedRectangle(cornerRadius: LabMetrics.checkboxRadius, style: .continuous)
                        .strokeBorder(accent, lineWidth: LabMetrics.checkboxStroke)
                        .frame(width: LabMetrics.checkboxSize, height: LabMetrics.checkboxSize)
                    if item.isCompleted {
                        RoundedRectangle(cornerRadius: LabMetrics.checkboxRadius, style: .continuous)
                            .fill(accent)
                            .frame(width: LabMetrics.checkboxSize, height: LabMetrics.checkboxSize)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            // On the category's own fill, which is light in
                            // both appearances — see DSColor.onAccentFill.
                            .foregroundStyle(DSColor.onAccentFill.opacity(0.85))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                // The export wraps the label in its own 8pt box, which is what
                // gives a single-line row 33pt and lets a wrapped one grow to
                // 50 instead of being clipped to a fixed height.
                .padding(.vertical, LabMetrics.rowTextInset)
            }

            Spacer(minLength: 6)

            // Trailing indicators ride the first line too.
            Group {
                // No pencil. Opening a row puts the caret straight in the
                // title, so a button to do the same thing was an extra step
                // for something that should just be click-and-type
                // (Marcello, 2026-08-10).

                // NC-2, narrowed: the indicator means "there is something here
                // you cannot see". Steps are visible now, so only a note
                // still qualifies — leaving it on `hasDetails` would have it
                // pointing at a checklist already on screen.
                if !item.note.isEmpty && !isExpanded {
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

            }
            // Glyphs align to the FIRST line of the title, not to the centre
            // of a title that has wrapped to three lines.
            .padding(.top, Self.firstLineInset + 1)

            // Each affordance answers the input that can actually reach it.
            //
            // ⏎ is a KEYBOARD act, so it appears when the row has keyboard
            // focus — you arrowed here, and ⏎ is what to press next. The grip
            // is a MOUSE act, so it appears under the pointer. Showing both to
            // whichever input arrived first advertised a key to someone
            // holding a mouse and a handle to someone who had let go of it
            // (Marcello, 2026-08-22).
            //
            // Hovering the focused row is the one moment both are true, and
            // then the hairline earns its place by separating them — which is
            // exactly the state the export draws.
            // The gutter is ALWAYS here; only its contents come and go.
            //
            // Letting the cluster into the layout on hover took width away
            // from the title, so a title that only just fit on one line
            // re-wrapped to two and the row grew — under the pointer, and
            // under the arrow keys, which made the whole list lurch
            // (Marcello, 2026-08-22). Holding the width open means the title
            // measures the same whether or not anything is drawn beside it,
            // so nothing reflows and there is nothing to truncate.
            //
            // Centred in the row, like the export. The first-line inset the
            // other glyphs use is for aligning to a title that wraps; this
            // cluster belongs to the row, not to the title.
            ZStack(alignment: .trailing) {
                Color.clear.frame(width: LabMetrics.rowActionsWidth, height: 1)
                if !item.isCompleted && !isExpanded && (hover || isFocused) {
                    RowActions(showEnter: isFocused, showGrip: hover)
                        .transition(.opacity)
                }
            }
            .frame(width: LabMetrics.rowActionsWidth, alignment: .trailing)
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
        }
        .padding(.top, 2)
    }

    /// The steps checklist. Same indent and connector rule in the list as in
    /// the opened row — deliberately the identical treatment, because they are
    /// the identical rows; only where you can reach them has changed.
    private func stepsBlock() -> some View {
        indented {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(item.checklist) { step in
                    StepRow(step: step, parentID: item.id, accent: accent)
                }
                // Always present, always last, styled exactly like a real
                // step. There is no "add step" button because there is nothing
                // to press: the empty row IS the affordance, and committing one
                // leaves you sitting on the next.
                StepDraftRow(parentID: item.id, accent: accent)
            }
        }
        .padding(.top, 2)
    }

    /// The connector rule + indent shared by notes and steps.
    private func indented<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(DSColor.panelBorder)
                .frame(width: 0.5)
                .padding(.leading, 6)
            content()
                .padding(.leading, 17)   // 6 + 0.5 + 17 ≈ DSSpacing.checklistIndent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
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

/// The trailing cluster on a hovered or focused row.
///
/// Geometry is the export's: a 23x18 badge with a 1pt border at radius 6, an
/// 18pt hairline, and six 3pt dots 2pt apart inside a 16pt box.
private struct RowActions: View {
    let showEnter: Bool
    let showGrip: Bool

    var body: some View {
        HStack(spacing: LabMetrics.rowActionGap) {
            if showEnter {
                Text("\u{21B5}")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.rowAffordance)
                    .frame(width: LabMetrics.enterBadgeWidth,
                           height: LabMetrics.enterBadgeHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: LabMetrics.enterBadgeRadius,
                                         style: .continuous)
                            .strokeBorder(DSColor.rowAffordance, lineWidth: 1)
                    )
            }

            // Only when both are up does a separator have two things to
            // separate.
            if showEnter && showGrip {
                Rectangle()
                    .fill(DSColor.rowAffordance)
                    .frame(width: 1, height: LabMetrics.enterBadgeHeight)
            }

            if showGrip { DragGrip() }
        }
        .allowsHitTesting(false)
    }
}

/// Six dots. Decorative on purpose — the WHOLE row is the drag handle (see
/// EntityTextView.hitTest, which makes the title transparent to the mouse), so
/// this says "draggable" without claiming a target of its own and without
/// reserving leading space on every row the way the old grip did.
private struct DragGrip: View {
    var body: some View {
        VStack(spacing: LabMetrics.gripGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: LabMetrics.gripGap) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(DSColor.rowAffordance)
                            .frame(width: LabMetrics.gripDot, height: LabMetrics.gripDot)
                    }
                }
            }
        }
        .frame(width: LabMetrics.gripBox, height: LabMetrics.gripBox)
    }
}

// MARK: - Steps
//
// A step is a real checklist entry with its own checkbox, independent of the
// parent to-do's — ticking a step never completes the task, and completing
// the task never ticks its steps. Checked state matches the parent's exactly:
// filled box, strikethrough, dimmed label.

private struct StepRow: View {
    let step: ChecklistItem
    let parentID: UUID
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 6, weight: .black))
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
                    .onSubmit { commit() }
                    // Clicking away is a save everywhere else in this app.
                    .onChange(of: focused) { isFocused in
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
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .semibold))
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
private struct StepDraftRow: View {
    let parentID: UUID
    let accent: Color
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
                    // Stay put. Losing focus after each step would make the
                    // second one cost a click.
                    focused = true
                }

            // Matches StepRow's delete gutter so the two align.
            Color.clear.frame(width: 12, height: 12)
        }
    }
}

// MARK: - ShortcutsOverlay — in-panel `?` reference (§2.3)

private struct ShortcutsOverlay: View {
    private let rows: [(String, String)] = [
        ("\u{2191} \u{2193}", "todo.sc.moveFocus"),
        ("\u{2423}", "todo.sc.toggleComplete"),
        ("\u{21A9}", "todo.sc.editTitle"),
        ("\u{2192} \u{2190}", "todo.sc.expandRow"),
        ("\u{2318}N", "todo.sc.newTodo"),
        ("\u{21E5}", "todo.switchSection"),
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
