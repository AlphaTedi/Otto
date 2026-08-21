import SwiftUI

// MARK: - NotchRootView — Connects NotchShapeView with gallery content

struct NotchRootView: View {
    @ObservedObject var controller: NotchController
    @EnvironmentObject var appState: AppState

    var body: some View {
        // LAB: the notch draws itself and nothing else. The panels are
        // siblings BELOW it with real gaps between, so the desktop shows
        // through and they read as separate objects rather than as the inside
        // of a container that grew.
        ZStack(alignment: .top) {
            if controller.state == .expanded {
                LabPanelsView()
                    .environmentObject(appState)
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
            notchOnly
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimation.contentHug, value: controller.state)
    }

    /// The silhouette alone. It never grows to `.expanded` any more — while
    /// the panels are open it wears its hover size, which is the only state
    /// change the notch itself has left.
    private var notchOnly: some View {
        NotchShapeView(
            state: .constant(controller.state == .expanded ? .hovering : controller.state),
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
            content: AnyView(EmptyView()),
            notificationContent: AnyView(
                NotchNotificationContent(controller: controller)
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
