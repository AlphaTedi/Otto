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
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
            notchShape
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
