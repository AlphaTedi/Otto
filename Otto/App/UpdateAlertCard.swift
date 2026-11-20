import AppKit
import SwiftUI

// MARK: - The update banner, over the dock's section bar
//
// A new version used to be visible only in Settings › About, so nobody saw
// it (Marcello, 2026-11-13). When Sparkle finds one, opening the notch shows
// this card just above the sections: Dismiss or Update. After Update it stays
// and follows the download and the install with a bar, until Otto relaunches.
//
// After reui's alert (c-alert-3: icon, title, line, actions), with Otto's
// rounder corners and more air inside, Otto's app icon on the left,
// on the dock's Liquid Glass.

struct UpdateAlertCard: View {
    @ObservedObject private var updates = UpdateController.shared
    @Environment(\.dsPalette) private var palette

    /// The plain card's height: the 40-pt icon and its padding.
    private var plainHeight: CGFloat { DSSize.controlXL + DSSpace.l * 2 }

    /// The featured release is still on offer: the tall card with media.
    private var showsFeatured: Bool {
        if case .available = updates.phase { return updates.featured != nil }
        return false
    }

    /// ONE card that changes shape: Update on the featured banner shrinks it
    /// into the progress card on a spring, the media fading as the card
    /// closes over it, instead of one banner vanishing and another appearing
    /// (Marcello, 2026-11-15: "abrupt"). The card's height is explicit, so
    /// the outgoing content cannot hold it open until it has gone.
    var body: some View {
        if updates.showsBanner {
            let shape = DSShape.squircle(DSRadius.menu)
            Color.clear
                .frame(height: showsFeatured ? DSMediaBannerMetrics.height : plainHeight)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        if showsFeatured, let featured = updates.featured {
                            // A release worth showing (Marcello, 2026-11-15).
                            DSMediaBanner(title: featured.title, subtitle: featured.subtitle,
                                          secondaryTitle: L10n.t("update.dismiss"),
                                          primaryTitle: L10n.t("update.install"),
                                          onSecondary: { updates.dismissBanner() },
                                          onPrimary: { updates.installUpdate() },
                                          chrome: false) {
                                if let video = featured.video {
                                    DSLoopingVideo(url: video)
                                } else {
                                    // No clip for this release: the app icon.
                                    Image(nsImage: NSApp.applicationIconImage)
                                        .resizable()
                                        .frame(width: DSSize.controlXL * 2, height: DSSize.controlXL * 2)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .transition(.opacity)
                        } else {
                            plainCard
                                .frame(height: plainHeight)
                                .transition(.opacity)
                        }
                    }
                }
                .background(Color.clear.notchGlass(in: shape))
                .clipShape(shape)
                .transition(DSTransition.rise())
                .animation(Motion.contentHug, value: showsFeatured)
                .animation(Motion.contentHug, value: updates.phase)
        }
    }

    /// The offer (a line and two buttons) or the progress (a bar and the
    /// percentage): the two faces of the plain card.
    private var isOffer: Bool {
        if case .available = updates.phase { return true }
        return false
    }

    private var progressValue: Double? {
        switch updates.phase {
        case .downloading(let progress): return progress
        case .installing: return 1
        default: return nil
        }
    }

    /// Every part keeps its place while the phase changes: the title
    /// cross-fades, the second line swaps text for bar in a fixed-height
    /// slot, the buttons fade out where the percentage fades in — so nothing
    /// in the card jumps (Marcello, 2026-11-15).
    private var plainCard: some View {
        HStack(alignment: .center, spacing: DSSpace.l) {
            // Otto's own icon: whose update this is (2026-11-15).
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: DSSize.controlXL, height: DSSize.controlXL)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpace.xs) {
                Text(title)
                    .font(DSType.label)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                ZStack(alignment: .leading) {
                    if isOffer {
                        Text(L10n.t("update.readyBody"))
                            .font(DSType.meta)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    } else {
                        DSProgressBar(value: progressValue)
                            .transition(.opacity)
                    }
                }
                .frame(height: DSSpace.xxl, alignment: .leading)
            }
            Spacer(minLength: DSSpace.m)
            ZStack(alignment: .trailing) {
                if isOffer {
                    HStack(spacing: DSSpace.s) {
                        PrimaryActionButton(title: L10n.t("update.dismiss"), variant: .ghost, size: .xs) {
                            updates.dismissBanner()
                        }
                        .ottoTooltip(L10n.t("update.dismiss"))
                        PrimaryActionButton(title: L10n.t("update.install"), size: .xs) {
                            updates.installUpdate()
                        }
                        .ottoTooltip(L10n.t("update.check"))
                    }
                    .transition(.opacity)
                } else if case .downloading(let progress?) = updates.phase {
                    Text("\(Int(progress * 100)) %")
                        .font(DSType.meta)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, DSSpace.l)
        .padding(.leading, DSSpace.l)
        // The buttons as far from the right edge as from the top and
        // bottom: the card is the 40-pt icon tall, they are 24.
        .padding(.trailing, DSSpace.l + (DSSize.controlXL - DSSize.controlXS) / 2)
    }

    private var title: String {
        switch updates.phase {
        case .available(let version): return String(format: L10n.t("update.ready"), version)
        case .downloading: return L10n.t("update.downloading")
        case .installing: return L10n.t("update.installing")
        case .idle: return ""
        }
    }
}
