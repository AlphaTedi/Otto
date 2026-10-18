import SwiftUI

// MARK: - NotchRootView — the notch panel's root: silhouette plus content
//
// TWO expanded designs live here, chosen by `notchLayout` in Settings.
//
// `.panels` (current): the notch draws itself and nothing else. The panels
// are siblings BELOW it with real gaps between, so the desktop shows through
// and they read as separate objects rather than as the inside of a container
// that grew.
//
// `.container` (the design that preceded it, kept as an option): the notch IS
// the container — it grows downward and the content is drawn inside the
// silhouette, clipped to its shape.
//
// The branch is only ever about WHERE the content is drawn. Everything the
// content itself does — the to-do panel, its measurement, its key handling —
// is the same code in both.

struct NotchRootView: View {
    @ObservedObject var controller: NotchController
    @EnvironmentObject var appState: AppState
    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels
    @AppStorage(DockExperiment.key) private var containerDock = false

    var body: some View {
        ZStack(alignment: .top) {
            if notchLayout == .panels, controller.state == .expanded {
                FloatingPanelsView()
                    .environmentObject(appState)
                    // The staggered entry (`notchEntry`) reads this. Inside
                    // the silhouette NotchShapeView sets it; out here the
                    // column is a sibling and inherited the default (true),
                    // so in the panels layout the rows never staggered at
                    // all — they were simply there when the fade ended.
                    .environment(\.notchContentAppeared, controller.contentVisible)
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
            notchShape
            // The container's menus, OVER the silhouette rather than inside
            // its clip: on a short list the gear's menu was cut off, and
            // growing the notch to fit it was not the fix (Marcello,
            // 2026-10-03) — the menu hangs past the edge instead.
            if notchLayout == .container, controller.state == .expanded {
                ContainerMeetingCard(controller: controller)
                    .transition(.opacity.animation(NotchAnimation.contentOut))
                // The B3 dock's glass bar, OUTSIDE the silhouette's mask so
                // the glass can see what is behind it (DockBarLayer).
                if DockExperiment.isOn(layout: notchLayout, flag: containerDock) {
                    // Leaves at once on collapse: it is outside the clip
                    // (glass must see the desktop), so it may not linger
                    // over a closing notch. It enters on its own, late.
                    DockBarLayer(controller: controller)
                        .transition(.asymmetric(insertion: .identity,
                                                removal: .opacity.animation(.easeOut(duration: 0.08))))
                }
                ContainerMenuLayer(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "notchPanelContent")
        .animation(NotchAnimation.contentHug, value: controller.state)
    }

    /// In `.panels` the silhouette never grows to `.expanded` any more —
    /// while the panels are open it wears its hover size, which is the only
    /// state change the notch itself has left. In `.container` it goes back
    /// to being driven by the real state, because growing IS the design.
    private var notchShape: some View {
        NotchShapeView(
            state: notchLayout == .container
                ? $controller.state
                : .constant(controller.state == .expanded ? .hovering : controller.state),
            notchSize: controller.notchSize,
            expandedSize: controller.expandedSize,
            // VW-1/VW-2: width fixed, height varies by tab AND by how much
            // content the tab is showing.
            extraExpandedHeight: appState.notchExtraHeight,
            hasPhysicalNotch: controller.hasPhysicalNotch,
            contentVisible: controller.contentVisible,
            content: AnyView(expandedContent)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if notchLayout == .container {
            TodoTabView()
                // TOP-aligned, explicitly. The default alignment of a max
                // frame is centre, and the silhouette proposes an ANIMATING
                // height: for the duration of a big-to-small section switch
                // the proposal is taller than the content, so the content sat
                // centred in the slack and the draft row slid up and down
                // with every switch (Thomas, 2026-09-01). The input must stay
                // put; only the bottom edge moves.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environmentObject(appState)
                // The container has no gap between the notch and its content,
                // so the pointer moving from one into the other must not read
                // as leaving. The panels layout gets the same guarantee from
                // the widened hover rect instead.
                .onHover { hovering in
                    if hovering {
                        controller.cancelCollapse()
                    } else {
                        controller.triggerCollapse()
                    }
                }
        } else {
            EmptyView()
        }
    }
}

/// The gear and Notes · Meetings menus of the notch container, drawn at the
/// root so they can extend below the silhouette. Their frame is reported to
/// the controller: that part of the screen still counts as the panel.
private struct ContainerMenuLayer: View {
    @ObservedObject var controller: NotchController
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var dock = DockState.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if store.showsAvatarMenu, let gear = controller.dockBarAnchors[.gear] ?? controller.containerMenuAnchors[.gear] {
                    // The B3 dock's gear sits at the foot: its menu rises.
                    let rises = DockExperiment.isOn
                    AvatarMenu()
                        .background(frameReporter)
                        .anchoredMenu(to: gear, in: proxy.size, opensUpward: rises)
                        .transition(.opacity.combined(with: .offset(y: rises ? 4 : -4)))
                } else if let id = dock.menuSpaceID, let collection = store.collection(id: id),
                          let item = controller.dockBarAnchors[.dockItem] ?? controller.containerMenuAnchors[.dockItem] {
                    // The B3 dock's space menu: centred over its dot, opening up.
                    DockSpaceMenu(collection: collection)
                        .background(frameReporter)
                        .fixedSize()
                        .padding(.bottom, max(0, proxy.size.height - item.minY + OttoMenuStyle.anchorGap))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .offset(x: item.midX - proxy.size.width / 2)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                } else if let id = dock.noteMenuID, let note = notes.notes.first(where: { $0.id == id }),
                          let row = controller.containerMenuAnchors[.noteRow] {
                    // The dock's note menu: at the note's trailing edge,
                    // below it — or above it in the list's lower half.
                    let rises = row.midY > proxy.size.height * 0.55
                    DockNoteMenu(note: note)
                        .background(frameReporter)
                        .fixedSize()
                        .anchoredMenu(to: row.insetBy(dx: 8, dy: 0), in: proxy.size, opensUpward: rises)
                        .transition(.opacity.combined(with: .offset(y: rises ? 4 : -4)))
                } else if notes.kindMenuOpen, let trigger = controller.containerMenuAnchors[.notesKind] {
                    NotesKindMenuList(meetings: store.panelMode == .calendar)
                        .background(frameReporter)
                        .anchoredMenu(to: trigger, in: proxy.size, opensUpward: false)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
        }
        .environment(\.ottoMenuGlass, true)
        .animation(NotchAnimation.hintFade, value: store.showsAvatarMenu)
        .animation(NotchAnimation.hintFade, value: notes.kindMenuOpen)
        .animation(NotchAnimation.hintFade, value: dock.menuSpaceID)
        .animation(NotchAnimation.hintFade, value: dock.noteMenuID)
        .onChange(of: store.showsAvatarMenu || notes.kindMenuOpen || dock.menuSpaceID != nil
                      || dock.noteMenuID != nil) { open in
            if !open { controller.setOverflowMenuFrame(nil) }
        }
        .onDisappear { controller.setOverflowMenuFrame(nil) }
    }

    private var frameReporter: some View {
        GeometryReader { menu in
            Color.clear
                .onAppear { controller.setOverflowMenuFrame(menu.frame(in: .named("notchPanelContent"))) }
                .onChange(of: menu.frame(in: .named("notchPanelContent"))) { controller.setOverflowMenuFrame($0) }
        }
    }
}

/// The notch container's meeting: a detached black card hanging under the
/// silhouette, the container's version of the floating panels' meeting block
/// (Marcello, 2026-10-04). Before, the container showed a meeting only as an
/// alert that took over the whole panel, so an upcoming one was invisible.
private struct ContainerMeetingCard: View {
    @ObservedObject var controller: NotchController
    @ObservedObject private var calendar = CalendarStore.shared
    @ObservedObject private var store = TodoStore.shared
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the entrance: the card drops out of the notch just behind it,
    /// on the notch's own expand spring (Marcello, 2026-10-04: it was simply
    /// there when the notch opened).
    @State private var entered = false

    /// Same rule as the floating panels: at the root only, never over a page.
    private var meeting: DetectedMeeting? {
        guard store.panelPath.count == 1 else { return nil }
        return calendar.activeAlert ?? calendar.upcomingToday.first
    }

    var body: some View {
        // Exactly the notch's body width and corner, whatever the size preset
        // (Marcello, 2026-10-04: the card was wider than the notch).
        let shape = RoundedRectangle(cornerRadius: controller.containerBottomRadius, style: .continuous)
        VStack(spacing: 0) {
            Color.clear.frame(height: controller.containerSilhouetteHeight + 12)
            if let meeting {
                PanelMeetingCard(meeting: meeting, isNext: true)
                    .padding(PanelMetrics.blockPadding)
                    .frame(width: controller.containerBodyWidth, alignment: .leading)
                    .background(shape.fill(Color.black))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .background(GeometryReader { card in
                        Color.clear
                            .onAppear { controller.setContainerCardFrame(card.frame(in: .named("notchPanelContent"))) }
                            .onChange(of: card.frame(in: .named("notchPanelContent"))) { controller.setContainerCardFrame($0) }
                    })
                    .environment(\.colorScheme, .dark)
                    .opacity(entered ? 1 : 0)
                    .scaleEffect(entered || reduceMotion ? 1 : 0.94, anchor: .top)
                    .offset(y: entered || reduceMotion ? 0 : -28)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(NotchAnimation.contentHug, value: appState.notchExtraHeight)
        .animation(NotchAnimation.contentHug, value: meeting?.id)
        .onChange(of: meeting == nil) { gone in if gone { controller.setContainerCardFrame(nil) } }
        .onAppear {
            // A beat after the notch starts growing, so the card reads as
            // coming out of it rather than arriving alongside.
            withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                                       : NotchAnimation.expand.delay(0.08)) { entered = true }
        }
        .onDisappear {
            entered = false
            controller.setContainerCardFrame(nil)
        }
    }
}

/// The B3 dock's bar — Notes, the dock, Settings, or the note editor's back ·
/// tools · export — drawn at the ROOT, over the silhouette, rather than
/// inside it.
///
/// Inside, it was not glass. NotchShapeView renders its content through a
/// mask and the open animation's opacity and blur, and each of those draws
/// the content in a layer of its own: Liquid Glass inside one cannot sample
/// what lies behind it, so macOS drew it flat and grey (Marcello,
/// 2026-10-17, beside the space menu — which was real glass, because it
/// already lived up here). Out here it refracts the list scrolling under it.
private struct DockBarLayer: View {
    @ObservedObject var controller: NotchController
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var dock = DockState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var editingNote: Bool {
        (store.panelMode == .notes || store.panelMode == .calendar) && notes.openNoteID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if editingNote {
                    DockEditorBar()
                        .transition(.opacity)
                } else if store.showsSpaceBar || dock.isCreatingSpace {
                    DockBottomBar()
                        .transition(.opacity)
                }
            }
            // The bar's one gliding tooltip, over Notes, the dock, Settings
            // and the note's tools alike.
            .barTipHost()
            .padding(.horizontal, NotchContainerMetrics.barInset)
            .padding(.bottom, NotchContainerMetrics.barBottom)
            .frame(width: controller.containerBodyWidth)
            .onHover { if $0 { controller.cancelCollapse() } }
        }
        .frame(height: controller.containerSilhouetteHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The menus measure their anchors in this space; here it IS the root's.
        .coordinateSpace(name: OttoMenuStyle.space)
        .onPreferenceChange(MenuAnchorKey.self) { controller.dockBarAnchors = $0 }
        .opacity(appeared && controller.state == .expanded ? 1 : 0)
        .animation(.easeOut(duration: 0.08), value: controller.state)
        .offset(y: appeared || reduceMotion ? 0 : 6)
        .animation(NotchAnimation.hintFade, value: editingNote)
        .animation(NotchAnimation.hintFade, value: store.showsSpaceBar)
        .onAppear {
            // Only once the silhouette has reached the foot under it — the
            // bar is outside the clip, so earlier it floated over the desktop
            // ahead of the black (Marcello, 2026-10-18).
            withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                                       : .easeOut(duration: 0.22).delay(0.26)) { appeared = true }
        }
        .onDisappear {
            appeared = false
            controller.dockBarAnchors = [:]
        }
    }
}

