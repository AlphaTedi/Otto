import AVKit
import SwiftUI

// MARK: - Media banner: a release worth showing, not just announcing
//
// The plain update banner (UpdateAlertCard) says "a new version is ready".
// This one is for the releases Marcello wants to advertise: a picture that
// moves on the left — a short looping clip or a live SwiftUI scene — and the
// headline, one line and the two actions on the right (sketch, 2026-11-15).
//
// Anatomy and sizes follow the "benefits modal / spotlight card" pattern of
// Atlassian, Polaris's MediaCard and Material's banner (media · heading ·
// body · actions), on Otto's 4-pt grid:
//
//   • height 144; media 192 wide (4:3), bleeding to the card's left edge and
//     clipped by its corners — the picture is the card's left half, not a
//     thumbnail inside it;
//   • the text column inset 16 on every side, title `cardTitle`, body
//     `meta`, 4 between them;
//   • actions bottom-left on the text's edge, `sm` (28), 8 apart: primary
//     filled first, then the ghost secondary; 16 from the bottom;
//   • radius `menu` (20) and the dock's Liquid Glass, like the plain banner.

struct DSMediaBanner<Media: View>: View {
    let title: String
    var subtitle: String = ""
    var secondaryTitle: String? = nil
    var primaryTitle: String
    var onSecondary: () -> Void = {}
    let onPrimary: () -> Void
    /// False when a parent draws the card (glass and clip) itself — so it
    /// can morph one card between this and another layout.
    var chrome = true
    @ViewBuilder let media: Media
    @Environment(\.dsPalette) private var palette

    static var height: CGFloat { DSMediaBannerMetrics.height }
    static var mediaWidth: CGFloat { DSMediaBannerMetrics.mediaWidth }

    var body: some View { inspectedBody }

    private var inspectedBody: some View {
        let shape = DSShape.squircle(DSRadius.menu)
        return HStack(spacing: 0) {
            media
                .frame(width: Self.mediaWidth, height: Self.height)
                .clipped()
            VStack(alignment: .leading, spacing: DSSpace.xs) {
                Text(title)
                    .font(DSType.cardTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DSType.meta)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: DSSpace.m)
                // On the text's left edge (2026-11-15). The filled primary
                // leads, so its edge — not a ghost's invisible one — is the
                // one that lines up with the words above.
                HStack(spacing: DSSpace.m) {
                    PrimaryActionButton(title: primaryTitle, size: .sm, action: onPrimary)
                    if let secondaryTitle {
                        PrimaryActionButton(title: secondaryTitle, variant: .ghost, size: .sm, action: onSecondary)
                    }
                }
            }
            .padding(DSSpace.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .modifier(DSMediaBannerChrome(on: chrome, shape: shape))
    }
}

enum DSMediaBannerMetrics {
    static var height: CGFloat { DSSize.controlXL * 3 + DSSpace.xl * 2 }   // 144
    static var mediaWidth: CGFloat { height * 4 / 3 }                       // 192
}

private struct DSMediaBannerChrome: ViewModifier {
    let on: Bool
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if on {
            content.background(Color.clear.notchGlass(in: shape)).clipShape(shape)
        } else {
            content
        }
    }
}

/// A short clip for the media slot: muted, looping, filling its frame.
/// Pass a file inside the app bundle or one Otto downloaded with the update
/// notes; nothing streams while the banner is off screen.
struct DSLoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }
}
