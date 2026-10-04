import SwiftUI

// MARK: - NotchRootView — Connects NotchShapeView with gallery content
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

    var body: some View {
        ZStack(alignment: .top) {
            if notchLayout == .panels, controller.state == .expanded {
                LabPanelsView()
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
            screenshotJustArrived: controller.screenshotJustArrived,
            contentVisible: controller.contentVisible,
            notificationContentVisible: controller.notificationContentVisible,
            notificationWide: controller.notificationWide,
            content: AnyView(expandedContent),
            notificationContent: AnyView(
                NotchNotificationContent(controller: controller)
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if notchLayout == .container {
            NotchExpandedView()
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if store.showsAvatarMenu, let gear = controller.containerMenuAnchors[.gear] {
                    AvatarMenu()
                        .background(frameReporter)
                        .anchoredMenu(to: gear, in: proxy.size, opensUpward: false)
                        .transition(.opacity.combined(with: .offset(y: -4)))
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
        .onChange(of: store.showsAvatarMenu || notes.kindMenuOpen) { open in
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
                LabMeetingCard(meeting: meeting, isNext: true)
                    .padding(LabMetrics.blockPadding)
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
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(NotchAnimation.contentHug, value: appState.notchExtraHeight)
        .animation(NotchAnimation.contentHug, value: meeting?.id)
        .onChange(of: meeting == nil) { gone in if gone { controller.setContainerCardFrame(nil) } }
        .onDisappear { controller.setContainerCardFrame(nil) }
    }
}
