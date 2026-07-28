import SwiftUI

// MARK: - ClipboardTile — Visual card for clipboard items in the notch gallery

struct ClipboardTile: View {
    let item: ClipboardItem
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var justCopied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isImageCard: Bool {
        item.type == .screenshot || item.type == .image
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Card background — image items fill the whole card edge to edge,
            // with a scrim so the header/button stay readable on top.
            Group {
                if isImageCard, let img = item.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 130, height: 100)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.45), location: 0),
                                    .init(color: .clear, location: 0.32),
                                    .init(color: .clear, location: 0.6),
                                    .init(color: .black.opacity(0.5), location: 1),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 0) {
                // Header: type icon + (snippet label | timestamp) + kind badge
                HStack(spacing: 4) {
                    Image(systemName: item.kind == .snippet ? "text.badge.star" : item.iconName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.kind == .snippet ? Color.yellow : .secondary)

                    if item.kind == .snippet, let label = item.label {
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }

                    Spacer()

                    if item.kind == .pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.accentColor)
                    } else if item.kind == .history {
                        Text(item.relativeTime)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Type-specific preview
                previewContent
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                Spacer(minLength: 4)

                // Quick Copy button
                Button(action: quickCopy) {
                    Text(justCopied ? L10n.t("tile.copied") : L10n.t("tile.quickCopy"))
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(justCopied ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
                        )
                        .foregroundStyle(justCopied ? .green : .primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 130, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1.0)
        .shadow(
            color: .black.opacity(isHovered ? 0.35 : 0.15),
            radius: isHovered ? 10 : 4,
            y: isHovered ? 4 : 2
        )
        // Same spring as screenshot thumbnails so all tiles hover alike.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : NotchAnimation.thumbnailHover,
            value: isHovered
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                appState.hoveredQuickLookItem = .clipboard(item)
            } else if case .clipboard(let c) = appState.hoveredQuickLookItem, c.id == item.id {
                appState.hoveredQuickLookItem = nil
            }
        }
        .contextMenu {
            switch item.kind {
            case .history:
                Button(L10n.t("action.pin")) { appState.pinClipboardItem(item) }
                Button(L10n.t("action.copy")) { quickCopy() }
                Divider()
                Button(L10n.t("action.delete"), role: .destructive) {
                    appState.removeClipboardItem(id: item.id)
                }
            case .pinned:
                Button(L10n.t("action.unpin")) { appState.unpinClipboardItem(id: item.id) }
                Button(L10n.t("action.copy")) { quickCopy() }
                Divider()
                Button(L10n.t("action.moveLeft"))  { appState.moveClipboardEntry(id: item.id, direction: -1) }
                Button(L10n.t("action.moveRight")) { appState.moveClipboardEntry(id: item.id, direction: 1) }
            case .snippet:
                Button(L10n.t("action.edit")) { SnippetEditorController.shared.show(editing: item) }
                Button(L10n.t("action.copy")) { quickCopy() }
                Divider()
                Button(L10n.t("action.moveLeft"))  { appState.moveClipboardEntry(id: item.id, direction: -1) }
                Button(L10n.t("action.moveRight")) { appState.moveClipboardEntry(id: item.id, direction: 1) }
                Divider()
                Button(L10n.t("action.delete"), role: .destructive) {
                    appState.removeSnippet(id: item.id)
                }
            }
        }
    }

    // MARK: - Type-Specific Preview

    @ViewBuilder
    var previewContent: some View {
        switch item.type {
        case .screenshot, .image:
            // The image already fills the whole card as its background —
            // the middle of the tile stays clear so it shows through.
            Color.clear.frame(height: 42)

        case .color:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colorFromItem)
                    .frame(width: 32, height: 32)
                Text(item.previewText ?? "")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(height: 42)

        case .code:
            Text(item.previewText ?? "")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Color.green.opacity(0.9))
                .lineLimit(3)
                .frame(height: 42, alignment: .topLeading)

        case .url:
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                Text(item.sourceURL?.host ?? item.previewText ?? "")
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            .frame(height: 42, alignment: .leading)

        case .number:
            Text(item.previewText ?? "")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 42)

        default:
            Text(item.previewText ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(height: 42, alignment: .topLeading)
        }
    }

    // MARK: - Helpers

    private var colorFromItem: Color {
        if let nsColor = item.previewColor {
            return Color(nsColor)
        }
        if let hex = item.previewText {
            return Color(nsColor: NSColor.fromHex(hex) ?? .gray)
        }
        return .gray
    }

    private func quickCopy() {
        // Skip next clipboard change so we don't add a duplicate
        ClipboardMonitor.shared.skipNextChange()
        item.recopyToPasteboard()

        withAnimation(.spring(duration: 0.2, bounce: 0.2)) { justCopied = true }
        HapticManager.shared.copyConfirmed()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.25, bounce: 0.0)) { justCopied = false }
        }
    }
}
