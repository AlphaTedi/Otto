import Foundation
import AppKit
import SwiftUI

// MARK: - QuickLookItem — Hovered gallery item for Spacebar Quick Look
//
// Defined here (rather than in QuickLookPreview.swift) so AppState can
// reference it without depending on file target-membership ordering.

enum QuickLookItem: Equatable {
    case screenshot(ScreenshotItem)
    case clipboard(ClipboardItem)

    var trackingID: UUID {
        switch self {
        case .screenshot(let s): return s.id
        case .clipboard(let c):  return c.id
        }
    }

    static func == (lhs: QuickLookItem, rhs: QuickLookItem) -> Bool {
        lhs.trackingID == rhs.trackingID
    }
}

// MARK: - AppState — Source of truth

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var screenshots: [ScreenshotItem] = []
    @Published var clipboardItems: [ClipboardItem] = []

    // Persistent clipboard: pinned favorites + user-authored snippets.
    // Both survive restarts (JSON in Application Support) and never expire.
    @Published var pinnedItems: [ClipboardItem] = []
    @Published var snippets: [ClipboardItem] = []
    @Published var isNotchExpanded: Bool = false
    @Published var selectedScreenshotID: UUID? = nil
    @Published var settings: AppSettings = AppSettings.load()
    @Published var lastCaptureMode: CaptureMode = .area

    /// Currently-hovered gallery item — drives the Spacebar Quick Look preview.
    /// Set by ScreenshotThumbnailView and ClipboardTile in their .onHover.
    @Published var hoveredQuickLookItem: QuickLookItem? = nil

    /// Filter currently shown in the expanded notch — lets the shape grow
    /// for tabs that need more room (e.g. Notes).
    @Published var activeNotchFilter: NotchContentFilter = .todos

    /// Pivot PRD: the notch is a to-do app first. The Shelf/Clipboard/Notes
    /// panels stay in the codebase but are hidden unless re-enabled from
    /// Settings ("Show legacy panels").
    var showLegacyPanels: Bool {
        UserDefaults.standard.bool(forKey: "showLegacyPanels")
    }

    /// Hugging height (pivot PRD §3): the to-do view MEASURES its natural
    /// content height and publishes it here; the panel is a direct animated
    /// function of this value — never a fixed container that scrolls.
    /// Published so the notch shape re-renders the moment content changes.
    @Published var todoContentHeight: CGFloat = 0

    /// Menu-bar/notch strip height, pushed in by NotchController on setup and
    /// screen changes — the hugging math needs it to convert "content height"
    /// into "total shape height".
    @Published var notchBarHeight: CGFloat = 38

    /// Headroom available inside the pre-sized panel window — the hugging
    /// height is clamped to this so the shape never outgrows its NSPanel
    /// (NotchController sizes the window to expandedSize.height + 380).
    static let maxExtraHeight: CGFloat = 372

    /// The user's gallery height preset — the baseline `extraHeight` is
    /// measured against. Same key as NotchController's @AppStorage.
    private var expandedBaseHeight: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "notchExpandedHeight")
        return stored > 0 ? CGFloat(stored) : 200
    }

    /// VW-2: extra HEIGHT (never width) for the expanded panel.
    ///
    /// For the to-do view this is the hugging-height core: total shape height
    /// = notch strip + chrome + measured content, expressed relative to the
    /// gallery baseline — so it's NEGATIVE when a short list needs less room
    /// than the gallery preset. The shape animates every change of this value
    /// on the shared contentHug spring.
    var notchExtraHeight: CGFloat {
        let filterBar: CGFloat = showsNotchFilterBar ? 34 : 0
        switch activeNotchFilter {
        case .todos:
            // notch strip + 8 (top gap) + measured panel (its own paddings
            // and bezel margins are inside the measurement) + filter bar
            // when legacy panels are shown.
            let desiredTotal = notchBarHeight + 8 + todoContentHeight + filterBar
            let cappedTotal = min(desiredTotal, expandedBaseHeight + Self.maxExtraHeight)
            return cappedTotal - expandedBaseHeight
        case .notes:
            return filterBar + 44   // composer layout, stable height — no jumping
        default:
            return filterBar
        }
    }

    /// One-shot request to focus the Notes composer (set by the ⌃⇧N hotkey
    /// so the user can type immediately). Consumed by NotesTabView.
    @Published var focusNotesComposer = false

    /// One-shot request to open Settings on a specific section (used by the
    /// calendar nudge card). Consumed by SettingsView.
    @Published var pendingSettingsSection: SettingsSection? = nil

    /// One-shot request to open the notch gallery on a specific filter —
    /// e.g. a file drag touching the notch opens straight onto the Tray.
    /// Consumed (reset to nil) by NotchExpandedView.
    @Published var pendingNotchFilter: NotchContentFilter? = nil

    private let maxClipboardItems = 30

    // MARK: - Screenshot Management

    func addScreenshot(_ item: ScreenshotItem) {
        // 1. Insert immediately — UI updates instantly
        screenshots.insert(item, at: 0)

        // FIFO removal
        if screenshots.count > settings.maxSessionScreenshots {
            let removed = screenshots.removeLast()
            TempFileManager.shared.cleanupFile(for: removed.id)
        }

        // 2. Haptic + sound feedback (non-blocking)
        HapticManager.shared.screenshotCaptured()

        // 3. Everything else happens in background — ZERO main thread blocking
        let itemID = item.id
        let originalImage = item.originalImage
        let autoCopy = settings.autoCopyToClipboard
        let autoSave = settings.autoSaveFile

        Task.detached(priority: .userInitiated) {
            // Pre-write temp file for drag-and-drop
            let nsImage = NSImage(cgImage: originalImage, size: NSSize(
                width: originalImage.width, height: originalImage.height
            ))
            TempFileManager.shared.prewriteFile(image: nsImage, id: itemID)

            // Auto-copy to clipboard (on main thread since NSPasteboard requires it)
            if autoCopy {
                await MainActor.run {
                    ClipboardMonitor.shared.skipNextChange()
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([nsImage])
                }
            }

            // Auto-save to file
            if autoSave {
                await MainActor.run {
                    try? AppState.shared.saveToFile(item)
                }
            }
        }
    }

    func removeScreenshot(id: UUID) {
        HapticManager.shared.itemDeleted()
        screenshots.removeAll { $0.id == id }
        TempFileManager.shared.cleanupFile(for: id)
    }

    func clearSession() {
        for item in screenshots {
            TempFileManager.shared.cleanupFile(for: item.id)
        }
        screenshots.removeAll()
    }

    // MARK: - Clipboard

    func copyToClipboard(_ item: ScreenshotItem) {
        ClipboardMonitor.shared.skipNextChange()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.flattenedImage])

        // Mark as copied — DON'T remove from gallery
        if let index = screenshots.firstIndex(where: { $0.id == item.id }) {
            screenshots[index].wasCopied = true
            screenshots[index].copiedAt = Date()
        }

        HapticManager.shared.copyConfirmed()
    }

    // MARK: - Save to File

    @discardableResult
    func saveToFile(_ item: ScreenshotItem) throws -> URL {
        let dir = settings.saveDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let timestamp = formatter.string(from: item.capturedAt)
        let ext = settings.fileFormat == .png ? "png" : "jpg"
        let filename = "NotchSnap-\(timestamp).\(ext)"
        let fileURL = dir.appendingPathComponent(filename)

        let image = item.flattenedImage
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            throw NSError(domain: "NotchSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }

        let data: Data?
        switch settings.fileFormat {
        case .png:
            data = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: settings.jpegQuality])
        }

        guard let imageData = data else {
            throw NSError(domain: "NotchSnap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }

        try imageData.write(to: fileURL)

        // Update item
        if let index = screenshots.firstIndex(where: { $0.id == item.id }) {
            screenshots[index].savedFileURL = fileURL
        }

        return fileURL
    }

    // MARK: - Clipboard History

    func addClipboardItem(_ item: ClipboardItem) {
        // Avoid consecutive duplicates
        if let last = clipboardItems.first,
           last.previewText == item.previewText && last.type == item.type { return }

        pruneStaleClipboardItems()

        withAnimation(.spring(duration: 0.42, bounce: 0.25)) {
            clipboardItems.insert(item, at: 0)
            if clipboardItems.count > maxClipboardItems {
                clipboardItems.removeLast()
            }
        }
        HapticManager.shared.clipboardItemAdded()
    }

    /// PERF: an all-day session accumulates stale history that makes the
    /// gallery long and scrolling laggy. Rolling history older than 8 hours
    /// quietly drops off (pinned items and snippets are untouched — they
    /// live in their own arrays).
    func pruneStaleClipboardItems() {
        let cutoff = Date().addingTimeInterval(-8 * 3600)
        clipboardItems.removeAll { $0.capturedAt < cutoff }
    }

    func removeClipboardItem(id: UUID) {
        clipboardItems.removeAll { $0.id == id }
    }

    // MARK: - Pinned items & Snippets

    /// Pin a history item: copies it into the persistent Pinned section.
    /// The original stays in rolling history until it scrolls off naturally.
    func pinClipboardItem(_ item: ClipboardItem) {
        guard !pinnedItems.contains(where: {
            $0.previewText == item.previewText && $0.type == item.type
        }) else { return }
        let pinned = ClipboardItem(
            id: UUID(), capturedAt: item.capturedAt, type: item.type,
            rawData: item.rawData, pasteboardTypes: item.pasteboardTypes,
            previewText: item.previewText, previewImage: item.previewImage,
            previewColor: item.previewColor, sourceURL: item.sourceURL,
            fileName: item.fileName,
            kind: .pinned, label: nil, sortOrder: pinnedItems.count
        )
        withAnimation(NotchAnimation.newScreenshot) {
            pinnedItems.append(pinned)
        }
        HapticManager.shared.thumbnailSelect()
        persistClipboardArchive()
    }

    /// Un-pinning removes it from Pinned; it does NOT return to history (CB-9).
    func unpinClipboardItem(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pinnedItems.removeAll { $0.id == id }
        }
        persistClipboardArchive()
    }

    func addSnippet(label: String, content: String) {
        let item = ClipboardItem(
            id: UUID(), capturedAt: Date(),
            type: .plainText, rawData: content.data(using: .utf8),
            pasteboardTypes: [.string],
            previewText: content,
            kind: .snippet, label: label, sortOrder: snippets.count
        )
        withAnimation(NotchAnimation.newScreenshot) {
            snippets.append(item)
        }
        persistClipboardArchive()
    }

    func updateSnippet(id: UUID, label: String, content: String) {
        guard let idx = snippets.firstIndex(where: { $0.id == id }) else { return }
        let updated = snippets[idx]
        snippets[idx] = ClipboardItem(
            id: updated.id, capturedAt: updated.capturedAt,
            type: .plainText, rawData: content.data(using: .utf8),
            pasteboardTypes: [.string],
            previewText: content,
            kind: .snippet, label: label, sortOrder: updated.sortOrder
        )
        persistClipboardArchive()
    }

    func removeSnippet(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            snippets.removeAll { $0.id == id }
        }
        persistClipboardArchive()
    }

    /// Reorder within the Pinned or Snippets section (CB-8).
    func moveClipboardEntry(id: UUID, direction: Int) {
        func move(in array: inout [ClipboardItem]) -> Bool {
            guard let idx = array.firstIndex(where: { $0.id == id }) else { return false }
            let newIdx = idx + direction
            guard newIdx >= 0, newIdx < array.count else { return true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                array.swapAt(idx, newIdx)
            }
            return true
        }
        if !move(in: &pinnedItems) { _ = move(in: &snippets) }
        persistClipboardArchive()
    }

    // MARK: - Clipboard archive persistence (pinned + snippets)
    //
    // Same lightweight pattern as the Shelf: one JSON file, image payloads
    // as PNGs next to it, debounced writes.

    private struct PersistedEntry: Codable {
        let id: UUID
        let kind: ClipboardItemKind
        let createdAt: Date
        let label: String?
        let typeKey: String
        let text: String?
        let hasImage: Bool
        let sortOrder: Int
    }

    private static var clipboardArchiveDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchSnap/Clipboard", isDirectory: true)
    }

    private var archiveSaveWork: Task<Void, Never>?

    func persistClipboardArchive() {
        archiveSaveWork?.cancel()
        archiveSaveWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let dir = Self.clipboardArchiveDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var entries: [PersistedEntry] = []
            for item in self.pinnedItems + self.snippets {
                var hasImage = false
                if (item.type == .image || item.type == .screenshot),
                   let data = item.rawData {
                    let imgURL = dir.appendingPathComponent("\(item.id.uuidString).tiff")
                    try? data.write(to: imgURL)
                    hasImage = true
                }
                entries.append(PersistedEntry(
                    id: item.id, kind: item.kind, createdAt: item.capturedAt,
                    label: item.label, typeKey: item.type.persistenceKey,
                    text: item.previewText, hasImage: hasImage,
                    sortOrder: item.sortOrder
                ))
            }
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: dir.appendingPathComponent("clipboard.json"))
            }
        }
    }

    func loadClipboardArchive() {
        let dir = Self.clipboardArchiveDir
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("clipboard.json")),
              let entries = try? JSONDecoder().decode([PersistedEntry].self, from: data) else { return }

        var pinned: [ClipboardItem] = []
        var snips: [ClipboardItem] = []
        for e in entries {
            var rawData: Data? = e.text?.data(using: .utf8)
            var previewImage: NSImage? = nil
            if e.hasImage {
                let imgURL = dir.appendingPathComponent("\(e.id.uuidString).tiff")
                if let d = try? Data(contentsOf: imgURL) {
                    rawData = d
                    previewImage = NSImage(data: d)
                }
            }
            let type = ClipboardItem.ClipboardItemType.from(persistenceKey: e.typeKey)
            let item = ClipboardItem(
                id: e.id, capturedAt: e.createdAt, type: type,
                rawData: rawData, pasteboardTypes: [.string],
                previewText: e.text, previewImage: previewImage,
                previewColor: type == .color ? e.text.flatMap { NSColor.fromHex($0) } : nil,
                sourceURL: type == .url ? e.text.flatMap { URL(string: $0) } : nil,
                kind: e.kind, label: e.label, sortOrder: e.sortOrder
            )
            if e.kind == .snippet { snips.append(item) } else { pinned.append(item) }
        }
        pinnedItems = pinned.sorted { $0.sortOrder < $1.sortOrder }
        snippets = snips.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Settings

    func updateSettings(_ block: (inout AppSettings) -> Void) {
        block(&settings)
        settings.save()
        applyTheme()
    }

    /// Applies the selected app theme. Called on launch and after any settings change.
    func applyTheme() {
        switch settings.appTheme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
