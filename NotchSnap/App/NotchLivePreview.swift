import SwiftUI

// MARK: - NotchLivePreview — Real-time miniature notch preview in Settings
//
// Shows a scaled-down simulation of the notch that updates instantly
// as the user moves sliders. Uses the REAL NotchShape for accuracy.

struct NotchLivePreview: View {
    let cornerRadius: Double
    let width: Double
    let height: Double

    // Scale the preview to fit inside the form (max ~480pt -> ~240pt = scale 0.4)
    private let previewScale: CGFloat = 0.4

    var body: some View {
        ZStack {
            // Simulated wallpaper background
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.18),
                    Color(red: 0.09, green: 0.13, blue: 0.24),
                    Color(red: 0.06, green: 0.20, blue: 0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Simulated menu bar
            Rectangle()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 28 * previewScale)
                .frame(maxHeight: .infinity, alignment: .top)

            // Simulated notch — uses REAL NotchShape scaled down
            VStack(spacing: 0) {
                NotchShape(
                    bottomRadius: CGFloat(cornerRadius) * previewScale,
                    filletRadius: 12 * previewScale
                )
                .fill(Color.black)
                .frame(
                    width: CGFloat(width) * previewScale,
                    height: CGFloat(height) * previewScale
                )
                .overlay(
                    // Mini thumbnail placeholders to show the content area
                    HStack(spacing: 6 * previewScale) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4 * previewScale, style: .continuous)
                                .fill(Color.white.opacity(0.15))
                                .frame(
                                    width: 48 * previewScale,
                                    height: (CGFloat(height) - 48) * previewScale
                                )
                        }
                    }
                    .padding(.top, 24 * previewScale)
                )

                Spacer()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cornerRadius)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: width)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipped()
    }
}
