import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - TodoTabView — the whole to-do panel (design PRD §§1-7)
//
// One surface, four modes (TodoPanelMode): browsing and creation share the
// tab row; category creation and Quick Find replace the content entirely.
// All colors/spacing/radii/fonts come from DesignTokens.swift (DSColor,
// DSSpacing, DSRadius, DSFont) and its reusable components — never inline
// hex values (design PRD §11, drift table §10).
//
// Content sits directly on the notch's black — single background, only
// element-level fills (Marcello's explicit call, 2026-07-13; it overrides
// the #111 panel shown in the PRD §1 markup).
//
// Layout law (pivot PRD §3): fixed width, VARIABLE height. This view
// measures its natural height and publishes it; the notch shape animates to
// match on NotchAnimation.contentHug — retuned since to 0.38 / 0.82, because
// at 0.60 the overshoot read as the whole panel bouncing rather than settling.
// DSAnimation, the second near-duplicate token set, is gone; NotchAnimation
// with Motion in front of it is the only vocabulary now.

struct TodoTabView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var calendar = CalendarStore.shared
    /// Observed so the space bar disappears the moment a note opens —
    /// `showsSpaceBar` reads NotesStore, and a value this view does not watch
    /// is a value this view will not redraw for.
    @ObservedObject private var notes = NotesStore.shared
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels
    @State private var footBlurVisible = false
    /// Where the controls the panel menus open from are (MenuAnchor).
    @State private var menuAnchors: [MenuAnchor: CGRect] = [:]
    /// Where this view sits inside the notch's root (container layout), so
    /// its menu anchors can be handed to NotchRootView, which draws the menus
    /// above the silhouette.
    @State private var originInRoot: CGPoint = .zero

    /// The notch silhouette hugs its content, so its height moves with the
    /// section; the floating panels are a fixed 556 and do not.
    private var isContainerLayout: Bool { notchLayout == .container }
    /// Spaces whose scroll runs UNDER the floating pills, with the
    /// progressive blur between them. Lists and the Notes/Meetings stream.
    private var hasFloatingFooter: Bool {
        [.browsing, .notes, .calendar].contains(store.panelMode)
    }

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
            // while an alert is live — see FloatingPanelsView.
            //
            // In `.container` it is not drawn here either any more: the
            // meeting is a detached card under the notch (ContainerMeetingCard,
            // 2026-10-04), like the floating panels' block.
            todoPanelContent
        }
        // The floating panels' capture header starts at the very top edge
        // (U5 §2: top padding 0); the container keeps its 16.
        .padding(.top, isContainerLayout ? PanelMetrics.panelTopPadding : 0)
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
        // Not in the Notes space. "Click the empty panel to deselect a to-do"
        // has no meaning there, and a full-width tap gesture under the stream
        // is one more peer competing with every row for the same click.
        .background((store.panelMode == .notes || store.panelMode == .calendar) ? nil : DeselectCatcher())
        .background(TodoBrowsingKeyHandler())
        // The catcher goes UNDER the menu, which is the whole reason it is a
        // separate overlay: a click-anywhere-else dismisser stacked on top
        // would eat the menu's own clicks and nothing in it would ever fire.
        .overlay {
            if store.showsAvatarMenu {
                MenuDismissCatcher { store.closeAvatarMenu() }
            } else if notes.kindMenuOpen {
                MenuDismissCatcher { notes.closeKindMenu() }
            }
        }
        // The avatar menu, over everything and inside the panel.
        //
        // Aligned to the avatar's own corner, and on the side the space bar is
        // NOT: in the container the bar is at the top so the menu drops below
        // it, in the floating panels it is at the foot so the menu rises. A
        // menu that opens off the edge of its own panel is a menu you cannot
        // read.
        //
        // Both panel menus are placed the same way (2026-09-27): against the
        // control that opened them, trailing edges flush, `anchorGap` away.
        // The Notes · Meetings menu lives up here too rather than inside its
        // header — at this level its rows are hit before anything under them.
        .overlay {
            GeometryReader { proxy in
                ZStack {
                    // The container draws its menus in NotchRootView instead:
                    // in here the silhouette clips them (2026-10-03).
                    if !isContainerLayout, store.showsAvatarMenu, let gear = menuAnchors[.gear] {
                        AvatarMenu()
                            .anchoredMenu(to: gear, in: proxy.size, opensUpward: !isContainerLayout)
                            .transition(.opacity.combined(
                                with: .offset(y: isContainerLayout ? -4 : 4)))
                    }
                    if !isContainerLayout, notes.kindMenuOpen, let trigger = menuAnchors[.notesKind] {
                        NotesKindMenuList(meetings: store.panelMode == .calendar)
                            .anchoredMenu(to: trigger, in: proxy.size, opensUpward: false)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
            }
        }
        .animation(NotchAnimation.hintFade, value: notes.kindMenuOpen)

        .onPreferenceChange(MenuAnchorKey.self) { anchors in
            menuAnchors = anchors
            publishContainerAnchors()
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { originInRoot = proxy.frame(in: .named("notchPanelContent")).origin; publishContainerAnchors() }
                .onChange(of: proxy.frame(in: .named("notchPanelContent")).origin) { origin in
                    originInRoot = origin
                    publishContainerAnchors()
                }
        })
        .coordinateSpace(name: OttoMenuStyle.space)
    }

    /// The container's menu anchors, moved into the notch root's space.
    private func publishContainerAnchors() {
        guard isContainerLayout else { return }
        NotchController.shared.containerMenuAnchors = menuAnchors.mapValues {
            $0.offsetBy(dx: originInRoot.x, dy: originInRoot.y)
        }
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
                // U5 capture header — FLOATING PANELS ONLY. The notch
                // container keeps its own field exactly as it is (Marcello,
                // 2026-09-25).
                if !isContainerLayout, store.panelMode == .browsing {
                    TodoCaptureHeader()
                        .notchEntry(index: 0)
                        // The first checkbox sits as far below the bar as it
                        // sits from the window's left edge (22). The gap
                        // measured 10.5 with nothing added (settled), so 11.5 more.
                        .padding(.bottom, 11.5)
                        .measureHeight(DraftBlockKey.self)
                }
                if isContainerLayout, store.panelMode == .browsing {
                    InlineDraftRow(accent: store.draftDestination?.color ?? PanelMetrics.accent)
                        .padding(.horizontal, PanelMetrics.barOuterInset)
                        .notchEntry(index: 0)
                        .padding(.bottom, PanelMetrics.fieldToTabsGap)
                        // Reported, not assumed — see PanelChrome. The bar
                        // grew 10pt when it became a recessed well and the
                        // list's budget went on subtracting the old number,
                        // so the panel overran its own block by exactly that.
                        .measureHeight(DraftBlockKey.self)
                }

                // In the NOTCH CONTAINER the sections sit at the top instead.
                //
                // The reasoning above holds for the floating panels, where the
                // block is a fixed 556 and the tabs never move. Inside the
                // notch the silhouette hugs its content, so the panel's height
                // follows how many to-dos the current section happens to hold
                // — which puts the row you click to CHANGE section at a
                // different place for every section. Aiming at a target that
                // moves because of what you are aiming away from is the
                // problem (Marcello, 2026-09-05).
                //
                // Anchoring them under the field fixes their position for good:
                // the field is always the same height, so everything above the
                // list stops moving.
                //
                // NOT in the Notes space, which places the same row itself.
                // The rule the container follows is FIELD FIRST, SECTIONS
                // UNDER IT: in a list that falls out for free, because the
                // draft row above is a sibling here. Notes brings its own
                // field — the composer, inside NotesSpaceView — so drawing the
                // row at this level put the sections ABOVE the thing you type
                // into, and Notes became the one space in the app with its
                // furniture in the other order (Marcello, 2026-09-06). It is
                // handed to StreamView instead, which owns the composer and
                // can put it on the right side of it.
                if isContainerLayout, store.showsSpaceBar,
                   store.panelMode != .notes, store.panelMode != .calendar,
                   store.panelMode != .insights {
                    // No extra gap under it. The row already carries its own
                    // breathing room plus the rule's — measured, the added
                    // sectionGap made the panel 16pt taller than the same
                    // content was at the bottom, which is a change nobody
                    // asked for on a panel whose height is the complaint.
                    TodoTabRow(rulePosition: .below)
                        .notchEntry(index: 1)
                        .measureHeight(TabRowHeightKey.self)
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
                    case .notes:
                        // The Notes space brings its own field — the composer
                        // stands exactly where the capture bar stands in a
                        // list, same position, same radius. That is why the
                        // draft row above is suppressed in this mode rather
                        // than the composer being tucked under it.
                        NotesSpaceView()
                            .transition(modeTransition)
                    case .calendar:
                        NotesSpaceView()
                            .transition(modeTransition)
                    case .insights:
                        // Like Notes, a SPACE: it brings its own header and
                        // suppresses the draft row, because there is nothing
                        // to capture on a page you only read.
                        InsightsView()
                            .transition(modeTransition)
                    }
                }

                // A Spacer, but ONLY in the floating panels.
                //
                // That block is a definite 556 again, so the tabs have to be
                // pushed to its foot or they ride up under the list and sit
                // wherever the content happens to end — floating in the middle
                // of the card on a short section, and jumping every time you
                // switch (Marcello, 2026-09-05: "fanno un floating continuo").
                //
                // It must NOT appear in the notch container. There the panel
                // measures its own natural height and the silhouette animates
                // to match; a Spacer inside a definite-height proposal stretches
                // the content to whatever it was handed, so the measurement is
                // just the proposal echoed back and the hug never converges.
                // That is the loop this comment used to warn about — it is real,
                // and it is the reason this is conditional rather than simply
                // restored.
                if !isContainerLayout {
                    Spacer(minLength: 0)
                }

                if !isContainerLayout, store.showsSpaceBar, !hasFloatingFooter {
                    TodoTabRow(rulePosition: .above)
                        .notchEntry(index: 1)
                        .measureHeight(TabRowHeightKey.self)
                }
            }
            // The two pieces of furniture report upward; the list's budget
            // reads them back down through PanelChrome. onPreferenceChange
            // rather than a write from inside the geometry reader: this fires
            // after the update, so it cannot mutate state mid-layout.
            .onPreferenceChange(DraftBlockKey.self) { h in
                if h > 0 { PanelChrome.shared.draftBlock = h }
            }
            .onPreferenceChange(TabRowHeightKey.self) { h in
                if h > 0 { PanelChrome.shared.tabRow = h }
            }
            .onPreferenceChange(FootBlurVisibleKey.self) { footBlurVisible = $0 }
            .overlay(alignment: .bottom) {
                if !isContainerLayout, store.showsSpaceBar, hasFloatingFooter {
                    ZStack(alignment: .bottom) {
                        if footBlurVisible {
                            ProgressiveBlur(cornerRadius: PanelMetrics.blockRadius)
                                .frame(height: PanelMetrics.floatingFooterBlurDepth)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TodoTabRow(rulePosition: .above)
                            .notchEntry(index: 1)
                            .measureHeight(TabRowHeightKey.self)
                    }
                    .zIndex(10)
                }
            }

            if store.showShortcuts {
                ShortcutsOverlay()
                    .transition(.opacity)
            }
        }
    }
}
