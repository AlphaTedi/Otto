import Foundation
import AppKit
import SwiftUI

// MARK: - ShelfStore — source of truth for the universal Shelf
//
// Persistence follows the app's existing lightweight pattern (JSON on
// disk, no Core Data): metadata in shelf.json, payloads as real files in
// the same folder. Writes are debounced; expiry is swept once a minute
// and on load. Oldest unpinned item is evicted past capacity.

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [ShelfItem] = []

    // Tray rules: items are "in transit", so cleanup is aggressive —
    // 10 minutes unless pinned. Capacity keeps the notch tidy.
    private let defaultExpiry: TimeInterval = 600    // 10 minutes
    private let capacity = 12

    private var saveWork: Task<Void, Never>?
    private var sweepTimer: Timer?

    // MARK: - Storage locations

    static var shelfDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("\(AppBuild.supportRoot)/Shelf", isDirectory: true)
    }

    private var indexURL: URL { Self.shelfDirectory.appendingPathComponent("shelf.json") }

    private init() {
        try? FileManager.default.createDirectory(at: Self.shelfDirectory, withIntermediateDirectories: true)
        load()
        sweepExpired()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in ShelfStore.shared.sweepExpired() }
        }
    }

    // MARK: - Adds

    /// Copy a dragged-in file into shelf storage and add it.
    @discardableResult
    func addFile(from sourceURL: URL) -> ShelfItem? {
        let id = UUID()
        // Per-item subfolder preserves the original filename for drag-out.
        let itemDir = Self.shelfDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let dest = itemDir.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            print("[Shelf] copy failed: \(error)")
            return nil
        }

        let isImage = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp"]
            .contains(sourceURL.pathExtension.lowercased())

        let item = ShelfItem(
            id: id,
            type: isImage ? .image : .file,
            createdAt: Date(),
            isPinned: false,
            expiresAt: Date().addingTimeInterval(defaultExpiry),
            displayName: sourceURL.lastPathComponent,
            payloadPath: dest.path,
            textContent: nil
        )
        insert(item)
        return item
    }

    /// Add raw image data (e.g. an image dragged from a browser).
    @discardableResult
    func addImageData(_ data: Data, suggestedName: String = "Image") -> ShelfItem? {
        let id = UUID()
        let itemDir = Self.shelfDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let dest = itemDir.appendingPathComponent("\(suggestedName).png")
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try png.write(to: dest)
        } catch {
            print("[Shelf] image write failed: \(error)")
            return nil
        }

        let item = ShelfItem(
            id: id, type: .image, createdAt: Date(), isPinned: false,
            expiresAt: Date().addingTimeInterval(defaultExpiry),
            displayName: suggestedName, payloadPath: dest.path, textContent: nil
        )
        insert(item)
        return item
    }

    /// Add dragged-in text or a URL.
    @discardableResult
    func addText(_ text: String) -> ShelfItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isURL = URL(string: trimmed).map { $0.scheme?.hasPrefix("http") == true } ?? false
        let item = ShelfItem(
            id: UUID(),
            type: isURL ? .url : .text,
            createdAt: Date(),
            isPinned: false,
            expiresAt: Date().addingTimeInterval(defaultExpiry),
            displayName: String(trimmed.prefix(60)),
            payloadPath: nil,
            textContent: trimmed
        )
        insert(item)
        return item
    }

    /// Screenshots land on the Shelf automatically (unified under the
    /// Shelf model, per PRD) — payload is a PNG written to shelf storage.
    @discardableResult
    func addScreenshot(_ screenshot: ScreenshotItem) -> ShelfItem? {
        let id = UUID()
        let itemDir = Self.shelfDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm.ss"
        let name = "Screenshot \(formatter.string(from: screenshot.capturedAt)).jpg"
        let dest = itemDir.appendingPathComponent(name)

        // PF-1: JPEG 85% — screen content compresses 70-85% smaller than PNG
        // with no visible loss at normal viewing sizes.
        guard let tiff = screenshot.flattenedImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try jpeg.write(to: dest)
        } catch {
            print("[Shelf] screenshot write failed: \(error)")
            return nil
        }

        let item = ShelfItem(
            id: id, type: .screenshot, createdAt: Date(), isPinned: false,
            expiresAt: Date().addingTimeInterval(defaultExpiry),
            displayName: name, payloadPath: dest.path, textContent: nil
        )
        insert(item)
        return item
    }

    // MARK: - Mutations

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        items[idx].expiresAt = items[idx].isPinned
            ? nil
            : Date().addingTimeInterval(defaultExpiry)   // unpin restarts the clock
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        deletePayload(items[idx])
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            _ = items.remove(at: idx)
        }
        HapticManager.shared.itemDeleted()
        scheduleSave()
    }

    private func insert(_ item: ShelfItem) {
        withAnimation(NotchAnimation.newScreenshot) {
            items.insert(item, at: 0)
            // Capacity eviction: drop the oldest unpinned item.
            while items.count > capacity {
                if let evictIdx = items.lastIndex(where: { !$0.isPinned }) {
                    deletePayload(items[evictIdx])
                    items.remove(at: evictIdx)
                } else {
                    break   // everything pinned — allow overflow rather than data loss
                }
            }
        }
        scheduleSave()
    }

    /// "Clean up the tray" button: removes everything that isn't pinned.
    func clearUnpinned() {
        let removable = items.filter { !$0.isPinned }
        guard !removable.isEmpty else { return }
        for item in removable { deletePayload(item) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            items.removeAll { !$0.isPinned }
        }
        HapticManager.shared.itemDeleted()
        scheduleSave()
    }

    func sweepExpired() {
        let now = Date()
        let expired = items.filter { !$0.isPinned && ($0.expiresAt.map { $0 < now } ?? false) }
        guard !expired.isEmpty else { return }
        for item in expired { deletePayload(item) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            items.removeAll { item in expired.contains(where: { $0.id == item.id }) }
        }
        scheduleSave()
    }

    private func deletePayload(_ item: ShelfItem) {
        guard let path = item.payloadPath else { return }
        ThumbnailCache.evict(fileAt: URL(fileURLWithPath: path))
        let itemDir = Self.shelfDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: itemDir)
    }

    // MARK: - Persistence (JSON, debounced writes — same pattern as AppSettings)

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        // Drop items whose payload file vanished.
        items = decoded.filter { item in
            guard let path = item.payloadPath else { return true }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        saveWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            if let data = try? JSONEncoder().encode(self.items) {
                try? data.write(to: self.indexURL)
            }
        }
    }
}
