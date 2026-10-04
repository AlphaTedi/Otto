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
        let name = uniqueName(base: "Image-\(stamp)", ext: "png")
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

    /// The image as PNG — what a chat box (ChatGPT, Claude) takes as an
    /// attachment when it is pasted.
    nonisolated static func pngData(at url: URL) -> Data? {
        if UTType(filenameExtension: url.pathExtension) == .png { return try? Data(contentsOf: url) }
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// "Copy image": the picture and its file, one item — pastes as an image
    /// in a chat box, a document or the Finder.
    static func copy(_ relativePath: String) {
        let file = url(for: relativePath)
        let item = NSPasteboardItem()
        if let png = pngData(at: file) { item.setData(png, forType: .png) }
        item.setString(file.absoluteString, forType: .fileURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    private static func uniqueName(base: String, ext: String) -> String {
        // No spaces: the markdown link must stay one unbroken path.
        let clean = base.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
        let suffix = UUID().uuidString.prefix(6).lowercased()
        return "\(clean.isEmpty ? "image" : clean)-\(suffix).\(ext)"
    }

    // MARK: Markdown token

    /// `![name](Attachments/file.png)` — only paths inside Attachments/, so a
    /// user's own image link to somewhere else is left as text.
    nonisolated static let tokenPattern = try! NSRegularExpression(
        // Spaces allowed in the path: images pasted before 2026-09-27 were
        // named "Image 2026-…png", and a token that did not match stayed text.
        pattern: #"!\[([^\]\n]*)\]\((Attachments/[^)\n]+)\)"#)

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
    /// Under the pointer. With `showsRemove`, the thumbnail's slot becomes an
    /// ✕ — the Conductor chip (Marcello, 2026-09-27).
    var hovered = false
    var showsRemove = false
    /// No air of its own: `AttachmentStore.spaceChips` kerns the gap in, and
    /// only where text touches the chip (2026-10-02).
    static let margin: CGFloat = 0
    /// The ✕ / icon slot, from the glyph's leading edge.
    static let removeZone: CGFloat = margin + 19
    private static let iconSide: CGFloat = 11

    init(path: String) {
        self.path = path
        let full = AttachmentStore.displayName(for: path)
        name = full.count > 26 ? String(full.prefix(23)) + "…" : full
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func cellSize() -> NSSize {
        let text = (name as NSString).size(withAttributes: [.font: chipFont])
        return NSSize(width: ceil(Self.margin + 6 + Self.iconSide + 4 + text.width + 7 + Self.margin), height: Self.height)
    }

    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -5) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let frame = cellFrame.insetBy(dx: Self.margin + 0.5, dy: 0.5)
        let chip = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(hovered ? 0.13 : 0.08).setFill()
        chip.fill()
        NSColor.labelColor.withAlphaComponent(hovered ? 0.22 : 0.14).setStroke()
        chip.lineWidth = 1
        chip.stroke()

        let side = Self.iconSide
        let thumbRect = NSRect(x: frame.minX + 6, y: frame.midY - side / 2, width: side, height: side)
        if hovered && showsRemove {
            // ✕ in the icon's place — no divider (Marcello, 2026-09-27).
            let x = NSBezierPath()
            let inset = thumbRect.insetBy(dx: 1.5, dy: 1.5)
            x.move(to: NSPoint(x: inset.minX, y: inset.minY)); x.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
            x.move(to: NSPoint(x: inset.minX, y: inset.maxY)); x.line(to: NSPoint(x: inset.maxX, y: inset.minY))
            x.lineWidth = 1.5
            x.lineCapStyle = .round
            NSColor.labelColor.withAlphaComponent(0.8).setStroke()
            x.stroke()
        } else {
            // A small Lucide "image" glyph, not a thumbnail: at this size a
            // thumbnail read as a dark square (Marcello, 2026-09-27). The
            // hover preview shows the picture.
            Self.icon(side: side).draw(in: thumbRect)
        }

        let textSize = (name as NSString).size(withAttributes: [.font: chipFont])
        (name as NSString).draw(at: NSPoint(x: thumbRect.maxX + 5, y: frame.midY - textSize.height / 2),
                                withAttributes: [.font: chipFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85)])
    }

    private static var iconCache: NSImage?
    private static func icon(side: CGFloat) -> NSImage {
        if let iconCache { return iconCache }
        let glyph = Icons.nsImage("photo", pointSize: side / Icons.opticalScale)
        let tinted = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            glyph?.draw(in: rect)
            NSColor.labelColor.withAlphaComponent(0.7).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        iconCache = tinted
        return tinted
    }

    // Clicks and hover are the text view's (ImageChipInteraction), so the
    // chip behaves the same in a note, the to-do field and a to-do row.
    override func wantsToTrackMouse() -> Bool { false }
}

// MARK: - Hover preview and clicks, for any text view holding chips

/// Hover a chip: it lights up, shows its ✕ (where removing is allowed) and a
/// preview of the image floats above it. Click the ✕ to remove, anywhere
/// else on the chip to open the image.
@MainActor
final class ImageChipInteraction {
    private weak var textView: NSTextView?
    private let canRemove: Bool
    /// Default removal deletes the character (an editable text view). A
    /// read-only one — a to-do row — supplies its own.
    var onRemove: ((String) -> Void)?
    private var hovered: (index: Int, cell: ImageChipCell)?

    init(textView: NSTextView, canRemove: Bool) {
        self.textView = textView
        self.canRemove = canRemove
    }

    func chip(at point: NSPoint) -> (index: Int, rect: NSRect, cell: ImageChipCell)? {
        guard let view = textView, let layout = view.layoutManager, let container = view.textContainer,
              let storage = view.textStorage, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - view.textContainerOrigin.x, y: point.y - view.textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? ImageChipAttachment,
              let cell = attachment.attachmentCell as? ImageChipCell else { return nil }
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        return rect.contains(point) ? (index, rect, cell) : nil
    }

    /// True while the pointer is over a chip.
    @discardableResult
    func mouseMoved(_ point: NSPoint) -> Bool {
        guard let hit = chip(at: point) else { clear(); return false }
        if hovered?.index != hit.index {
            clear()
            hit.cell.hovered = true
            hit.cell.showsRemove = canRemove
            hovered = (hit.index, hit.cell)
            redraw(hit.index)
            if let view = textView, let window = view.window {
                let screen = window.convertToScreen(view.convert(hit.rect, to: nil))
                ImagePreviewPanel.shared.show(hit.cell.path, above: screen, owner: window) { [weak self] in self?.clear() }
            }
        }
        return true
    }

    func clear() {
        guard let current = hovered else { return }
        current.cell.hovered = false
        hovered = nil
        redraw(current.index)
        ImagePreviewPanel.shared.hide()
    }

    /// True when the click was the chip's.
    func mouseDown(_ point: NSPoint) -> Bool {
        guard let hit = chip(at: point) else { return false }
        clear()
        let isRemove = canRemove && (textView?.userInterfaceLayoutDirection == .rightToLeft
            ? point.x > hit.rect.maxX - ImageChipCell.removeZone
            : point.x < hit.rect.minX + ImageChipCell.removeZone)
        if isRemove {
            if let onRemove { onRemove(hit.cell.path) }
            else if let view = textView, view.isEditable {
                view.insertText("", replacementRange: NSRange(location: hit.index, length: 1))
            }
        } else {
            AttachmentStore.open(hit.cell.path)
        }
        return true
    }

    /// Right-click on a chip: copy, open, remove. Nil off a chip, so the text
    /// view's own menu shows there.
    func menu(at point: NSPoint) -> NSMenu? {
        guard let hit = chip(at: point) else { return nil }
        clear()
        let menu = NSMenu()
        menu.addItem(ChipMenuItem(L10n.t("attach.copy")) { AttachmentStore.copy(hit.cell.path) })
        menu.addItem(ChipMenuItem(L10n.t("attach.open")) { AttachmentStore.open(hit.cell.path) })
        if canRemove {
            menu.addItem(ChipMenuItem(L10n.t("attach.remove")) { [weak self] in
                guard let self else { return }
                if let onRemove { onRemove(hit.cell.path) }
                else if let view = textView, view.isEditable {
                    view.insertText("", replacementRange: NSRange(location: hit.index, length: 1))
                }
            })
        }
        return menu
    }

    private func redraw(_ index: Int) {
        guard let view = textView, let storage = view.textStorage, index < storage.length else { return }
        view.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: index, length: 1))
    }
}

/// A menu item that runs a closure.
@MainActor
private final class ChipMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(_ title: String, _ run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    @objc private func fire() { run() }
}

/// The floating preview above a hovered chip: the image, fitted into at most
/// 320 × 220, on a dark rounded card. Borderless and non-activating, so it
/// never takes the caret or the key window.
@MainActor
final class ImagePreviewPanel {
    static let shared = ImagePreviewPanel()
    private var panel: NSPanel?
    private var shownPath: String?
    /// The preview never outlives its chip: it hides when the owning window
    /// hides (the notch closed) or another desktop comes in — neither sends a
    /// mouseExited
    /// (Marcello, 2026-09-27: it stayed after a swipe to the next desktop).
    private var watchdog: Timer?
    private var onDismiss: (() -> Void)?

    func show(_ path: String, above anchor: NSRect, owner: NSWindow, onDismiss: @escaping () -> Void) {
        guard let image = NSImage(contentsOf: AttachmentStore.url(for: path)), image.size.width > 0 else { return }
        let maxSize = NSSize(width: 320, height: 220)
        let scale = min(1, min(maxSize.width / image.size.width, maxSize.height / image.size.height))
        let imageSize = NSSize(width: max(40, image.size.width * scale), height: max(30, image.size.height * scale))
        let pad: CGFloat = 0
        let size = NSSize(width: imageSize.width + pad * 2, height: imageSize.height + pad * 2)

        let panel = self.panel ?? makePanel()
        let card = NSView(frame: NSRect(origin: .zero, size: size))
        card.wantsLayer = true
        // Just the picture, rounded — no card or frame around it
        // (Marcello, 2026-09-27).
        let imageView = NSImageView(frame: NSRect(x: pad, y: pad, width: imageSize.width, height: imageSize.height))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        card.addSubview(imageView)
        panel.contentView = card

        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 8)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.y + size.height > visible.maxY { origin.y = anchor.minY - 8 - size.height }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.level = NSWindow.Level(rawValue: owner.level.rawValue + 1)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        shownPath = path
        self.onDismiss = onDismiss
        watchdog?.invalidate()
        // Leaving the chip is the text view's mouseMoved/mouseExited; this
        // only catches the window going away under a still pointer.
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak owner] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if owner.map({ !$0.isVisible || $0.alphaValue < 0.05 }) ?? true { self.dismiss() }
            }
        }
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
    }

    private var spaceObserver: NSObjectProtocol?

    /// Close the preview and tell its chip, so the chip un-hovers too.
    func dismiss() {
        guard shownPath != nil else { return }
        let callback = onDismiss
        hide()
        callback?()
    }

    func hide() {
        watchdog?.invalidate()
        watchdog = nil
        onDismiss = nil
        panel?.orderOut(nil)
        shownPath = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

// MARK: - Chips in plain title text (the to-do field and rows)

extension AttachmentStore {
    /// `text` with each token drawn as a chip character.
    /// Air between a chip and the text it touches — only where it touches.
    ///
    /// The chip used to carry 6pt on both sides in its own cell, so a chip
    /// that wrapped to the start of a line stood 6pt right of the text
    /// column above it (Marcello, 2026-10-02). Kerning the character before
    /// it, and the chip itself, adds the gap only next to actual text.
    nonisolated static func spaceChips(in text: NSMutableAttributedString) {
        let string = text.string as NSString
        let gap: CGFloat = 6
        func isSpace(_ c: unichar) -> Bool {
            c == 0x20 || c == 0x0A || c == 0x09 || c == 0x2009 || c == 0x00A0
        }
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value is ImageChipAttachment else { return }
            if range.location > 0, !isSpace(string.character(at: range.location - 1)) {
                text.addAttribute(.kern, value: gap, range: NSRange(location: range.location - 1, length: 1))
            }
            let next = NSMaxRange(range)
            if next < string.length, !isSpace(string.character(at: next)) {
                text.addAttribute(.kern, value: gap, range: range)
            }
        }
    }

    static func chipped(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: attributes)
        for match in tokenPattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let path = (text as NSString).substring(with: match.range(at: 2))
            var chipAttributes = attributes
            chipAttributes[.attachment] = ImageChipAttachment(path: path)
            out.replaceCharacters(in: match.range, with: NSAttributedString(string: "\u{FFFC}", attributes: chipAttributes))
        }
        spaceChips(in: out)
        return out
    }

    /// Back to text: every chip becomes its token again.
    nonisolated static func unchipped(_ attributed: NSAttributedString) -> String {
        var out = ""
        let string = attributed.string as NSString
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let chip = value as? ImageChipAttachment {
                out += String(repeating: token(for: chip.path), count: range.length)
            } else {
                out += string.substring(with: range)
            }
        }
        return out
    }

    /// Where `range` of the token text falls once tokens are single chips.
    nonisolated static func displayRange(_ range: NSRange, in text: String) -> NSRange {
        var shift = 0
        for match in tokenPattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            where NSMaxRange(match.range) <= range.location {
            shift += match.range.length - 1
        }
        return NSRange(location: range.location - shift, length: range.length)
    }

    /// The title with one image's token taken out.
    nonisolated static func removingToken(_ path: String, from text: String) -> String {
        let ns = text as NSString
        guard let match = tokenPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .first(where: { ns.substring(with: $0.range(at: 2)) == path }) else { return text }
        return ns.replacingCharacters(in: match.range, with: "")
            .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Title text without its image tokens — for places that show it plain.
    nonisolated static func plainTitle(_ text: String) -> String {
        tokenPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                              withTemplate: "").replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - The chip, in SwiftUI (to-dos)

struct AttachmentChip: View {
    let path: String
    var onRemove: (() -> Void)?

    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            OttoIcon("photo", pointSize: 11 / Icons.opticalScale)
                .foregroundStyle(DSColor.textPrimary.opacity(0.7))
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
