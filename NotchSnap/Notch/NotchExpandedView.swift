import SwiftUI

// MARK: - Content filter

// Shared with NotchRootView, which needs to know whether the filter bar is
// visible so the notch shape can grow to make room for it.
extension AppState {
    var notchAvailableFilters: [NotchContentFilter] {
        // Pivot PRD: the notch is a to-do app. Everything else exists only
        // when "Show legacy panels" is re-enabled from Settings.
        guard showLegacyPanels else { return [.todos] }
        var result: [NotchContentFilter] = []
        // To-dos lead — they're the product; Tray and Notes are legacy tools.
        result.append(.todos)
        result.append(.tray)
        result.append(.notes)
        if !screenshots.isEmpty
            || clipboardItems.contains(where: { $0.type == .screenshot || $0.type == .image }) {
            result.append(.screenshots)
        }
        if !snippets.isEmpty {
            result.append(.snippets)
        }
        if clipboardItems.contains(where: { $0.type == .url }) {
            result.append(.links)
        }
        if clipboardItems.contains(where: {
            $0.type != .url && $0.type != .screenshot && $0.type != .image
        }) {
            result.append(.text)
        }
        return result
    }

    /// Only show the bar when there's more than one category to switch between.
    var showsNotchFilterBar: Bool {
        notchAvailableFilters.count >= 2
    }
}

enum NotchContentFilter: String, CaseIterable, Identifiable {
    case all, tray, screenshots, snippets, links, text, notes, todos
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:         return L10n.t("filter.all")
        case .tray:        return L10n.t("filter.tray")
        case .screenshots: return L10n.t("filter.shots")
        case .snippets:    return L10n.t("filter.snippets")
        case .links:       return L10n.t("filter.links")
        case .text:        return L10n.t("filter.text")
        case .notes:       return L10n.t("filter.notes")
        case .todos:       return L10n.t("filter.todos")
        }
    }

    var icon: String {
        switch self {
        case .all:         return "square.grid.2x2"
        case .tray:        return "tray.full"
        case .screenshots: return "camera.viewfinder"
        case .snippets:    return "text.badge.star"
        case .links:       return "link"
        case .text:        return "text.alignleft"
        case .notes:       return "note.text"
        case .todos:       return "checkmark.square"
        }
    }
}

// MARK: - Expanded Notch View — Gallery with screenshots + clipboard items

struct NotchExpandedView: View {
    @EnvironmentObject var appState: AppState
    // Re-render when the language override changes.
    @AppStorage(L10n.storageKey) private var appLanguage = "system"
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var appeared = false
    // The app opens directly into the to-do experience (pivot PRD §11).
    @State private var filter: NotchContentFilter = .todos
    @State private var shelfDropTargeted = false
    @AppStorage("showLegacyPanels") private var showLegacyPanels = false

    private var hasContent: Bool {
        !appState.screenshots.isEmpty || !appState.clipboardItems.isEmpty
            || !shelf.items.isEmpty || !appState.snippets.isEmpty
            || !appState.pinnedItems.isEmpty
    }

    // MARK: - Filtered collections

    private var filteredScreenshots: [ScreenshotItem] {
        switch filter {
        case .all, .screenshots: return appState.screenshots
        default:                 return []
        }
    }

    private var filteredClipboardItems: [ClipboardItem] {
        switch filter {
        case .all:
            return appState.clipboardItems
        case .screenshots:
            return appState.clipboardItems.filter { $0.type == .screenshot || $0.type == .image }
        case .links:
            return appState.clipboardItems.filter { $0.type == .url }
        case .text:
            return appState.clipboardItems.filter {
                $0.type != .url && $0.type != .screenshot && $0.type != .image
            }
        case .tray, .snippets, .notes, .todos:
            return []
        }
    }

    private var showsTraySection: Bool { filter == .all || filter == .tray }
    private var showsSnippetSection: Bool { filter == .all || filter == .snippets }

    private var availableFilters: [NotchContentFilter] { appState.notchAvailableFilters }
    private var showsFilterBar: Bool { appState.showsNotchFilterBar }

    var body: some View {
        VStack(spacing: 0) {
            // The bar always shows — Tray and Notes are tools that must stay
            // reachable even before any content exists.
            if showsFilterBar {
                filterBar
            }
            if filter == .todos {
                TodoTabView()
            } else if filter == .notes {
                NotesTabView()
            } else if filter == .tray && shelf.items.isEmpty {
                TrayEmptyState()
            } else if hasContent {
                galleryView
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The expanded notch is the tray's drop target: files, images, text
        // and links dragged here fall into the Tray section.
        .onDrop(of: ShelfDropHandler.acceptedTypes, isTargeted: $shelfDropTargeted) { providers in
            // The Tray is a legacy panel — don't swallow drops into UI the
            // user can't see.
            guard showLegacyPanels else { return false }
            let handled = ShelfDropHandler.handle(providers: providers)
            if handled {
                // Stay on the Tray so the user sees the item fall in.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    filter = .tray
                }
            }
            return handled
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(6)
                .opacity(shelfDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.15), value: shelfDropTargeted)
        )
        .onAppear {
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appeared = true
            }
            consumePendingFilter()
            // Keep the gallery lean — drop rolling history older than 8h.
            appState.pruneStaleClipboardItems()
        }
        .onChange(of: appState.pendingNotchFilter) { _ in
            consumePendingFilter()
        }
        .onDisappear {
            appeared = false
        }
        .onChange(of: filter) { f in
            appState.activeNotchFilter = f
        }
        .onChange(of: showsFilterBar) { shows in
            // With the bar gone (legacy panels hidden or content shrank to a
            // single category), land on To-dos — the product's home view.
            if !shows { filter = .todos }
        }
    }

    /// Apply a one-shot filter request (e.g. drag-to-notch opens the Tray).
    private func consumePendingFilter() {
        guard let requested = appState.pendingNotchFilter else { return }
        // Never route to a panel that's hidden behind the legacy toggle.
        guard requested == .todos || showLegacyPanels else {
            appState.pendingNotchFilter = nil
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            filter = requested
        }
        appState.pendingNotchFilter = nil
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        // PF-9 root cause: chips and the Clear control shared one unbounded
        // HStack, so once enough category chips existed the Clear chip was
        // pushed past the notch edge. The chips now live in their own
        // horizontal ScrollView while Clear is pinned OUTSIDE the scrollable
        // area — reachable at any item/chip count.
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach([NotchContentFilter.all] + availableFilters) { f in
                        FilterChip(filter: f, isActive: filter == f) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                filter = f
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            // "Clean up the tray" — clears everything unpinned.
            if !shelf.items.isEmpty && (filter == .all || filter == .tray) {
                ClearTrayChip {
                    ShelfStore.shared.clearUnpinned()
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .offset(y: 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.5))
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0.0)
                .animation(.spring(response: 0.38, dampingFraction: 0.62), value: appeared)

            Text(L10n.t("notch.empty"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1.0 : 0.0)
                .animation(.spring(response: 0.38, dampingFraction: 0.62).delay(0.04), value: appeared)
        }
        .padding()
    }

    private var sectionDivider: some View {
        Divider()
            .frame(height: 60)
            .opacity(0.3)
            .padding(.horizontal, 4)
    }

    private var galleryTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.72, anchor: .trailing)),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Gallery — screenshots first, then clipboard items

    private var galleryView: some View {
        // PERF: dropped per-card staggered cardEntry animations and `.map(\.id)`
        // dependency arrays. With many items they were O(N) every body rebuild
        // and every appeared toggle would fire N stacked springs simultaneously.
        // Lazy stack diffing + transition() handle insert/remove animation cleanly.
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 10) {
                // 1. SNIPPETS — always the front spot: the things you reuse
                //    every day should be one glance away.
                if showsSnippetSection {
                    ForEach(appState.snippets) { item in
                        ClipboardTile(item: item)
                            .transition(galleryTransition)
                    }
                    NewSnippetTile()
                    if filter == .all { sectionDivider }
                }

                // 2. TRAY — files in transit; they "fall in" when dropped.
                if showsTraySection {
                    ForEach(shelf.items) { item in
                        TrayCard(item: item)
                            .transition(galleryTransition)
                    }
                    if filter == .all && !shelf.items.isEmpty { sectionDivider }
                }

                // 3. SHOTS
                ForEach(filteredScreenshots) { item in
                    ScreenshotThumbnailView(item: item)
                        .transition(galleryTransition)
                }

                // 4. PINNED + RECENT clipboard
                if filter == .all {
                    ForEach(appState.pinnedItems) { item in
                        ClipboardTile(item: item)
                            .transition(galleryTransition)
                    }
                    if (!filteredScreenshots.isEmpty || !appState.pinnedItems.isEmpty)
                        && !filteredClipboardItems.isEmpty {
                        sectionDivider
                    }
                } else if !filteredScreenshots.isEmpty && !filteredClipboardItems.isEmpty {
                    sectionDivider
                }

                ForEach(filteredClipboardItems) { item in
                    ClipboardTile(item: item)
                        .transition(galleryTransition)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // Clear gap between the chips and the previews below them.
        .padding(.top, showsFilterBar ? 4 : 0)
        .animation(NotchAnimation.newScreenshot, value: appState.screenshots.count)
        .animation(NotchAnimation.newScreenshot, value: appState.clipboardItems.count)
        // Bouncier spring for the tray so drops visibly "land"
        .animation(.spring(response: 0.42, dampingFraction: 0.6), value: shelf.items.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: filter)
        // PF-10: bulk-clear must never depend on one button's layout —
        // right-clicking anywhere in the gallery always offers it.
        .contextMenu {
            if !shelf.items.isEmpty {
                Button(L10n.t("menu.clearTray")) { ShelfStore.shared.clearUnpinned() }
            }
            if !appState.screenshots.isEmpty {
                Button(L10n.t("menu.clearShots"), role: .destructive) {
                    appState.clearSession()
                }
            }
            if !appState.clipboardItems.isEmpty {
                Button(L10n.t("menu.clearHistory"), role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        appState.clipboardItems.removeAll()
                    }
                }
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }
}

// MARK: - Clear Tray Chip

private struct ClearTrayChip: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n.t("tray.clear"))
                    .font(.system(size: 10, weight: .medium))
            }
            // Destructive styling — this deletes tray content.
            .foregroundStyle(hover ? Color.white : Color.red.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(hover ? Color.red.opacity(0.85) : Color.red.opacity(0.15))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let filter: NotchContentFilter
    let isActive: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            // Design system: quiet text tabs — active is near-white with an
            // underline, inactive muted gray. No pill fills, no icons.
            Text(filter.label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.white.opacity(0.93)
                                          : Color.white.opacity(hover ? 0.75 : 0.47))
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? Color.white.opacity(0.93) : .clear)
                        .frame(height: 1.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isActive)
    }
}

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    /// Pin the material's appearance instead of inheriting the system's.
    ///
    /// Materials resolve light or dark from the effective appearance, so on a
    /// light desktop `.hudWindow` came back LIGHT — and every panel in this
    /// app draws white text on it. nil keeps the old inherited behaviour for
    /// the callers that want it.
    var appearance: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        if let appearance { view.appearance = NSAppearance(named: appearance) }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = appearance.flatMap { NSAppearance(named: $0) }
    }
}
