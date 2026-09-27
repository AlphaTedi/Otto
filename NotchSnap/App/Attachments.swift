import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Image attachments — inline chips in notes and to-dos (2026-09-27)
//
// An image dropped or pasted into a note or the to-do field is copied into
// the vault's `Attachments/` folder and shows as a small chip — thumbnail and
// name — in the text, the way Raycast and Conductor show an attachment in
// their input. Clicking the chip opens the image.
//
// Markdown mirror (principle 7): the file is a real file in the vault, and
// the reference is ordinary markdown, `![name](Attachments/file.png)`, so
// Notes.md and each section's file open with their images in Obsidian.
// In a note the token sits in the text itself; a to-do keeps its images in
// `TodoItem.attachments`, and its line in the vault ends with the tokens.

@MainActor
enum AttachmentStore {
    nonisolated static let folderName = "Attachments"

    static var directory: URL { MarkdownVault.shared.directory.appendingPathComponent(folderName, isDirectory: true) }

    /// Relative path (what markdown stores) → file on disk.
    static func url(for relativePath: String) -> URL {
        MarkdownVault.shared.directory.appendingPathComponent(relativePath)
    }

    nonisolated static func displayName(for relativePath: String) -> String {
        let file = (relativePath as NSString).lastPathComponent
        // Drop the uniquing suffix added on import: "shot-3f2a.png" → "shot.png".
        let ext = (file as NSString).pathExtension
        var stem = (file as NSString).deletingPathExtension
        if let dash = stem.range(of: "-", options: .backwards), stem[dash.upperBound...].count == 6 {
            stem = String(stem[..<dash.lowerBound])
        }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// Copies an image file into the vault. Returns its relative path.
    static func importFile(_ source: URL) -> String? {
        guard isImage(source) else { return nil }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = uniqueName(base: base, ext: ext)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            return "\(folderName)/\(name)"
        } catch {
            print("[Attachments] import failed: \(error)")
            return nil
        }
    }

    /// Writes pasted image data (a screenshot on the clipboard) as a PNG.
    static func importImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(19).replacingOccurrences(of: ":", with: ".")
        let name = uniqueName(base: "Image \(stamp)", ext: "png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name))
            return "\(folderName)/\(name)"
        } catch {
            print("[Attachments] paste failed: \(error)")
            return nil
        }
    }

    /// Image files, or else image data, from a paste or a drop.
    static func importFrom(pasteboard: NSPasteboard) -> [String] {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let images = urls.filter(isImage)
        if !images.isEmpty { return images.compactMap(importFile) }
        if urls.isEmpty, let image = NSImage(pasteboard: pasteboard) { return importImage(image).map { [$0] } ?? [] }
        return []
    }

    /// Whether the pasteboard carries something `importFrom` would take.
    static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { return urls.contains(where: isImage) }
        return NSImage.canInit(with: pasteboard)
    }

    nonisolated static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// "Add image…": the open panel, in front of the notch the same way the
    /// Download .md save panel is (NotesStore.exportOpenNote).
    @MainActor
    static func chooseImages(_ done: @escaping @MainActor ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        let controller = NotchController.shared
        let host = controller.dialogHostWindow
        panel.level = NSWindow.Level(rawValue: (host?.level.rawValue ?? NSWindow.Level.modalPanel.rawValue) + 1)
        controller.isPresentingDialog = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            controller.isPresentingDialog = false
            let paths = response == .OK ? panel.urls.compactMap(importFile) : []
            controller.focusPanel()
            done(paths)
        }
        if host != nil { SpaceAnchor.pin(panel) }
        panel.makeKeyAndOrderFront(nil)
    }

    static func open(_ relativePath: String) {
        NSWorkspace.shared.open(url(for: relativePath))
    }

    private static func uniqueName(base: String, ext: String) -> String {
        let clean = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
        let suffix = UUID().uuidString.prefix(6).lowercased()
        return "\(clean.isEmpty ? "image" : clean)-\(suffix).\(ext)"
    }

    // MARK: Markdown token

    /// `![name](Attachments/file.png)` — only paths inside Attachments/, so a
    /// user's own image link to somewhere else is left as text.
    nonisolated static let tokenPattern = try! NSRegularExpression(
        pattern: #"!\[([^\]\n]*)\]\((Attachments/[^)\s]+)\)"#)

    nonisolated static func token(for relativePath: String) -> String {
        "![\(displayName(for: relativePath))](\(relativePath))"
    }

    // MARK: Thumbnails

    nonisolated(unsafe) private static let thumbnails = NSCache<NSString, NSImage>()  // NSCache is thread-safe

    static func thumbnail(for relativePath: String) -> NSImage? {
        if let cached = thumbnails.object(forKey: relativePath as NSString) { return cached }
        guard let image = NSImage(contentsOf: url(for: relativePath)) else { return nil }
        let side: CGFloat = 32
        let thumb = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let size = image.size
            let scale = max(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: NSRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
            return true
        }
        thumbnails.setObject(thumb, forKey: relativePath as NSString)
        return thumb
    }
}

// MARK: - The chip, in AppKit text (notes)

/// An attachment character whose cell draws the chip. The path rides on it,
/// so the serializer can write the token back exactly.
final class ImageChipAttachment: NSTextAttachment {
    let path: String

    init(path: String) {
        self.path = path
        super.init(data: nil, ofType: nil)
        attachmentCell = ImageChipCell(path: path)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
}

final class ImageChipCell: NSTextAttachmentCell {
    let path: String
    private let name: String
    private let chipFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    private static let height: CGFloat = 20

    init(path: String) {
        self.path = path
        let full = AttachmentStore.displayName(for: path)
        name = full.count > 26 ? String(full.prefix(23)) + "…" : full
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func cellSize() -> NSSize {
        let text = (name as NSString).size(withAttributes: [.font: chipFont])
        return NSSize(width: ceil(6 + 14 + 5 + text.width + 7), height: Self.height)
    }

    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -5) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let frame = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let chip = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        chip.fill()
        NSColor.labelColor.withAlphaComponent(0.14).setStroke()
        chip.lineWidth = 1
        chip.stroke()

        let thumbRect = NSRect(x: frame.minX + 5, y: frame.midY - 7, width: 14, height: 14)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: thumbRect, xRadius: 3, yRadius: 3).addClip()
        if let thumb = MainActor.assumeIsolated({ AttachmentStore.thumbnail(for: path) }) {
            thumb.draw(in: thumbRect)
        } else {
            NSColor.labelColor.withAlphaComponent(0.2).setFill()
            thumbRect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let textSize = (name as NSString).size(withAttributes: [.font: chipFont])
        (name as NSString).draw(at: NSPoint(x: thumbRect.maxX + 5, y: frame.midY - textSize.height / 2),
                                withAttributes: [.font: chipFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85)])
    }

    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?,
                             untilMouseUp flag: Bool) -> Bool {
        if theEvent.type == .leftMouseDown { MainActor.assumeIsolated { AttachmentStore.open(path) } }
        return true
    }
}

// MARK: - The chip, in SwiftUI (to-dos)

struct AttachmentChip: View {
    let path: String
    var onRemove: (() -> Void)?

    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let thumb = AttachmentStore.thumbnail(for: path) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    OttoIcon("photo", pointSize: 10)
                }
            }
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(AttachmentStore.displayName(for: path))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140, alignment: .leading)
            if let onRemove, hover {
                Button(action: onRemove) { OttoIcon("xmark", pointSize: 8.5) }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(SpaceInk.a(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(SpaceInk.a(0.14), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { AttachmentStore.open(path) }
        .onHover { hover = $0 }
        .contextMenu {
            Button(L10n.t("attach.open")) { AttachmentStore.open(path) }
            if let onRemove { Button(L10n.t("attach.remove"), action: onRemove) }
        }
        .help(AttachmentStore.displayName(for: path))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("attach.a11y") + " " + AttachmentStore.displayName(for: path))
        .accessibilityAddTraits(.isButton)
    }
}
