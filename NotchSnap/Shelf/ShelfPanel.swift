import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

// MARK: - ThumbnailCache — PF-2/PF-7
//
// Decoding a payload file at full resolution for a 96pt card was a large
// per-render cost. CGImageSourceCreateThumbnailAtIndex decodes AT thumbnail
// size (never inflating the full bitmap into memory), and NSCache keeps
// decoded thumbnails around so scrolling back never re-reads the disk.

@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    static func thumbnail(forFileAt url: URL, maxPixel: CGFloat = 320) -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }

    static func evict(fileAt url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}

// MARK: - File Tray (in-notch shelf)
//
// The notch is the tray: drag any file/image/text/URL onto the expanded
// notch and it lands here, held until you drag it back out (dragging out
// removes it — it's "in transit", not archived), remove it, or the
// 10-minute auto-clean sweeps it. Pinning exempts an item from cleanup.

// MARK: - Drop handling (shared by the tray and the expanded notch)

enum ShelfDropHandler {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    @discardableResult
    static func handle(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in ShelfStore.shared.addFile(from: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in ShelfStore.shared.addImageData(data) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in ShelfStore.shared.addText(url.absoluteString) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    let text: String?
                    if let s = data as? String { text = s }
                    else if let d = data as? Data { text = String(data: d, encoding: .utf8) }
                    else { text = nil }
                    guard let text else { return }
                    Task { @MainActor in ShelfStore.shared.addText(text) }
                }
            }
        }
        return handled
    }
}

// MARK: - TrayCard — one tray item inside the notch gallery

struct TrayCard: View {
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail doubles as the native drag handle — dragging it out
            // deposits the real file/text and removes the item from the tray.
            ZStack(alignment: .topTrailing) {
                TrayDragSource(item: item)
                    .frame(width: 84, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if item.isPinned {
                    OttoIcon("pin.fill", pointSize: 8)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 4, y: -4)
                }
            }

            Text(item.displayName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 84)

            // Bottom row: type badge, or actions while hovering
            ZStack {
                HStack(spacing: 3) {
                    OttoIcon(item.type.iconName, pointSize: 7)
                    Text(item.type.rawValue.capitalized)
                        .font(.system(size: 8))
                }
                .foregroundStyle(.white.opacity(0.4))
                .opacity(hovering ? 0 : 1)

                HStack(spacing: 6) {
                    TrayMiniButton(icon: item.isPinned ? "pin.slash" : "pin") {
                        ShelfStore.shared.togglePin(item.id)
                    }
                    TrayMiniButton(icon: "doc.on.doc") { copyToPasteboard() }
                    TrayMiniButton(icon: "xmark") { ShelfStore.shared.remove(item.id) }
                }
                .opacity(hovering ? 1 : 0)
            }
            .frame(height: 16)
        }
        .padding(6)
        .frame(width: 96, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.10 : 0.05))
        )
        // Expiry cue: quiet fade as auto-clean approaches.
        .opacity(1.0 - 0.35 * item.expiryProgress())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovering)
    }

    private func copyToPasteboard() {
        ClipboardMonitor.shared.skipNextChange()
        let pb = NSPasteboard.general
        pb.clearContents()
        if let url = item.payloadURL,
           item.type == .image || item.type == .screenshot,
           let img = NSImage(contentsOf: url) {
            pb.writeObjects([img])
        } else if let url = item.payloadURL {
            pb.writeObjects([url as NSURL])
        } else if let text = item.textContent {
            pb.setString(text, forType: .string)
        }
        HapticManager.shared.copyConfirmed()
    }
}

private struct TrayMiniButton: View {
    let icon: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            OttoIcon(icon, pointSize: 8)
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(hover ? 0.3 : 0.15)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Tray empty state — the drop zone illustration

struct TrayEmptyState: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Concentric dashed rings that gently breathe
                Circle()
                    .strokeBorder(Color.white.opacity(0.12),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulse ? 1.06 : 1.0)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.03 : 1.0)
                OttoIcon("arrow.down", pointSize: 16)
                    .foregroundStyle(.white.opacity(0.6))
                    .offset(y: pulse ? 2 : -2)
            }
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

            Text("Drop files here, drag them out anywhere")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }
}

// MARK: - TrayDragSource — AppKit drag source with completion
//
// SwiftUI's .onDrag can't tell us when a drag actually lands somewhere, so
// the tray uses a real NSDraggingSource: when the drop completes in another
// app, the item leaves the tray (it was "in transit"); a cancelled drag
// keeps it.

private struct TrayDragSource: NSViewRepresentable {
    let item: ShelfItem

    func makeNSView(context: Context) -> TrayDragNSView {
        let v = TrayDragNSView()
        v.item = item
        return v
    }

    func updateNSView(_ nsView: TrayDragNSView, context: Context) {
        nsView.item = item
        nsView.needsDisplay = true
    }
}

private final class TrayDragNSView: NSView, NSDraggingSource {
    var item: ShelfItem? {
        didSet { rebuildThumbnail() }
    }
    private var thumbnail: NSImage?
    private var mouseDownEvent: NSEvent?

    override var isFlipped: Bool { true }

    private func rebuildThumbnail() {
        guard let item else { thumbnail = nil; return }
        if let url = item.payloadURL,
           item.type == .image || item.type == .screenshot,
           let img = ThumbnailCache.thumbnail(forFileAt: url) {
            // Decoded at thumbnail size + NSCache — never the full bitmap.
            thumbnail = img
        } else if let url = item.payloadURL {
            thumbnail = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            let icon = Icons.nsImage(item.type.iconName, pointSize: 16)
            thumbnail = icon
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let image = thumbnail else { return }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let isPhoto = item.map { $0.type == .image || $0.type == .screenshot } ?? false
        let inset: CGFloat = isPhoto ? 0 : 8
        let target = bounds.insetBy(dx: inset, dy: inset)
        let scale = isPhoto
            ? max(target.width / size.width, target.height / size.height)   // fill
            : min(target.width / size.width, target.height / size.height)   // fit
        let w = size.width * scale, h = size.height * scale
        let rect = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    // MARK: Drag session

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item, let down = mouseDownEvent else { return }
        let a = convert(down.locationInWindow, from: nil)
        let b = convert(event.locationInWindow, from: nil)
        guard hypot(b.x - a.x, b.y - a.y) > 5 else { return }
        mouseDownEvent = nil

        let pbItem: NSPasteboardWriting
        if let url = item.payloadURL {
            pbItem = url as NSURL
        } else if item.type == .url, let s = item.textContent, let url = URL(string: s) {
            pbItem = url as NSURL
        } else {
            pbItem = (item.textContent ?? item.displayName) as NSString
        }

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let dragImage = thumbnail ?? NSImage()
        dragItem.setDraggingFrame(bounds, contents: dragImage)
        beginDraggingSession(with: [dragItem], event: event, source: self)
        HapticManager.shared.dragBegan()
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        guard operation != [], let id = item?.id else { return }
        // The drop landed somewhere — the item has left the tray.
        Task { @MainActor in
            HapticManager.shared.dropCompleted()
            ShelfStore.shared.remove(id)
        }
    }
}
