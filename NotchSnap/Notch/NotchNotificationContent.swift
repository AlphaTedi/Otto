import SwiftUI

// MARK: - Environment key for wing width (space outside the physical notch)

private struct NotchWingWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 40
}

extension EnvironmentValues {
    var notchWingWidth: CGFloat {
        get { self[NotchWingWidthKey.self] }
        set { self[NotchWingWidthKey.self] = newValue }
    }
}

// MARK: - NotchNotificationContent — Dynamic Island style notification inside the pill
//
// Layout: [icon]  ···notch safe area···  [text]
// Icon sits in the left wing, text in the right wing.
// Both stay outside the physical notch safe area.

struct NotchNotificationContent: View {
    @ObservedObject var controller: NotchController
    @Environment(\.notchWingWidth) private var wingWidth

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: icon anchored to left edge
            leftContent
                .frame(width: 16, height: 16)
                .padding(.leading, 2)

            Spacer(minLength: 0)

            // Right wing: text label — constrained to wing width so it never
            // enters the physical notch safe area
            rightContent
                .frame(maxWidth: wingWidth, alignment: .trailing)
                .padding(.trailing, 2)
        }
        .offset(x: controller.notificationContentVisible ? 0 : -20)
        .opacity(controller.notificationContentVisible ? 1 : 0)
        .animation(
            .spring(response: 0.32, dampingFraction: 0.72),
            value: controller.notificationContentVisible
        )
        .clipped()
    }

    // MARK: - Left Content

    @ViewBuilder
    private var leftContent: some View {
        if let thumbnail = controller.notificationThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if let iconName = controller.notificationIcon {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(controller.notificationIconColor)
        }
    }

    // MARK: - Right Content

    @ViewBuilder
    private var rightContent: some View {
        if controller.notificationShowCheckmark {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0.196, green: 0.843, blue: 0.294))
        } else if let text = controller.notificationRightText {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                // On the silhouette — see DSColor.onNotchSurface.
                .foregroundColor(DSColor.onNotchSurface.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
