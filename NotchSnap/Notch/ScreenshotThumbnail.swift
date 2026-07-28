import SwiftUI

// MARK: - Screenshot Thumbnail View (single card in gallery)
// Iteration 5: copied badge, hover action overlay (Edit/Delete)

struct ScreenshotThumbnailView: View {
    let item: ScreenshotItem
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The screenshot IS the card: image fills the whole tile edge to
        // edge (aspect-fill, cropped as needed — even very tall captures),
        // with metadata overlaid on a bottom gradient scrim for contrast.
        ZStack(alignment: .topTrailing) {
            DraggableThumbnail(item: item) {
                HapticManager.shared.thumbnailSelect()
                openEditor(for: item)
            }
            .frame(width: 120, height: 100)

            // Bottom scrim + metadata — readable over any screenshot.
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(item.relativeTime)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Spacer(minLength: 2)
                    Text(item.dimensions)
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 5)
                .padding(.top, 14)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            .frame(width: 120, height: 100)
            .allowsHitTesting(false)
            // Hide the scrim while the hover actions (with their own darker
            // gradient) are showing, so the two don't stack.
            .opacity(isHovered ? 0 : 1)

            // Hover action overlay (Edit / Delete) — driven by parent's hover state
            ThumbnailActionOverlay(
                onEdit: { openEditor(for: item) },
                onDelete: { deleteItem(item) },
                isVisible: isHovered
            )
            .frame(width: 120, height: 100)

            // Badge: copied checkmark (green) or annotation indicator (pencil)
            if item.wasCopied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, Color.green)
                    .background(Circle().fill(Color.black.opacity(0.4)).padding(-2))
                    .offset(x: -4, y: 4)
                    .transition(.scale.combined(with: .opacity))
            } else if item.hasAnnotations {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                    .padding(4)
            }
        }
        .frame(width: 120, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: item.wasCopied)
        // Premium hover effect
        .scaleEffect(isHovered && !reduceMotion ? 1.07 : 1.0)
        .brightness(isHovered ? 0.04 : 0)
        .shadow(
            color: .black.opacity(isHovered ? 0.40 : 0.18),
            radius: isHovered ? 14 : 6,
            y: isHovered ? 5 : 2
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : NotchAnimation.thumbnailHover,
            value: isHovered
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
                appState.hoveredQuickLookItem = .screenshot(item)
            } else {
                NSCursor.pop()
                if case .screenshot(let s) = appState.hoveredQuickLookItem, s.id == item.id {
                    appState.hoveredQuickLookItem = nil
                }
            }
        }
        .contextMenu {
            Button(L10n.t("action.copy")) {
                appState.copyToClipboard(item)
            }
            Button(L10n.t("action.save")) {
                try? appState.saveToFile(item)
            }
            Divider()
            Button(L10n.t("action.delete"), role: .destructive) {
                deleteItem(item)
            }
        }
        // NOTE: No .onTapGesture here — tap is handled by DraggableImageView.mouseUp()
        // Adding .onTapGesture would intercept mouseDown and break drag-and-drop
    }

    private func openEditor(for item: ScreenshotItem) {
        EditorWindowController.shared.open(item: item)
    }

    private func deleteItem(_ item: ScreenshotItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            appState.removeScreenshot(id: item.id)
        }
    }
}

// MARK: - Thumbnail Action Overlay (Edit + Delete buttons on hover)

struct ThumbnailActionOverlay: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isVisible: Bool  // Driven by parent's hover state

    var body: some View {
        ZStack {
            if isVisible {
                // Gradient scuro in basso per leggibilita' bottoni
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Action buttons at bottom corners
                HStack {
                    // EDIT — bottom left
                    ThumbnailActionButton(icon: "pencil", color: .white, action: onEdit)

                    Spacer()

                    // DELETE — bottom right, red
                    ThumbnailActionButton(
                        icon: "trash",
                        color: Color(red: 1, green: 0.23, blue: 0.19),
                        action: onDelete
                    )
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 5)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // No hit testing when buttons are hidden — mouse clicks pass through to DraggableImageView
        .allowsHitTesting(isVisible)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isVisible)
    }
}

// MARK: - Thumbnail Action Button

struct ThumbnailActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
