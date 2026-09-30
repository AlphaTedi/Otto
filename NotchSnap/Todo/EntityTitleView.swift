import AppKit
import SwiftUI

// MARK: - EntityTitleView — a to-do title with inline entity chips (EH-1..7)
//
// SwiftUI Text can't embed views (icons, bordered backgrounds) inside a
// wrapping text flow, so this is the NSAttributedString/NSTextAttachment
// route the entity PRD §2.3 recommends: each recognized entity
// becomes a pre-rendered chip image attached inline; plain runs stay real
// text; AppKit's layout manager handles wrapping (EH-6).
//
// Clicks: a click on a link chip opens its URL (EH-7, the only interactive
// entity in v1); any other click is forwarded to `onTap` so the row's
// expand/focus behavior still works even though an NSView sits over it.

struct EntityTitleView: NSViewRepresentable {
    let title: String
    let isBright: Bool
    let onTap: () -> Void
    /// Removes an image chip's token from the title (its ✕ on hover).
    var onRemoveImage: ((String) -> Void)? = nil
    /// Width kept free at the end of the FIRST line only, for the row's
    /// trailing hints (⌘↵, grip, note glyph). Later lines run to the edge.
    var firstLineReserve: CGFloat = 0

    func makeNSView(context: Context) -> EntityTextView {
        let view = EntityTextView()
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = false
        // The URL lives on an image attachment and clicks are handled below.
        // AppKit's default link decoration underlines the attachment glyph,
        // leaving blue fragments visible below the chip's rounded corners.
        view.linkTextAttributes = [:]
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        // Wrap the DISPLAYED text to the view's width so a long title flows
        // onto multiple lines (FB1) instead of clipping on one line. The
        // container follows the view width; height grows with content.
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        return view
    }

    func updateNSView(_ view: EntityTextView, context: Context) {
        view.onPlainTap = onTap
        view.chips.onRemove = onRemoveImage
        view.firstLineReserve = firstLineReserve
        // Only when the title actually changed: re-setting the same string
        // re-laid-out every row's text view on every panel update.
        let key = Self.cacheKey(title, bright: isBright)
        guard view.renderedKey != key else { return }
        view.renderedKey = key
        view.textStorage?.setAttributedString(
            Self.attributedTitle(title, bright: isBright)
        )
    }

    /// Hugging height: report the wrapped height for the proposed width so
    /// the panel measures chips-in-flow like any other content.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EntityTextView,
                      context: Context) -> CGSize? {
        let width: CGFloat = {
            if let w = proposal.width, w.isFinite, w > 0 { return w }
            return 100_000   // unconstrained: natural single-line size
        }()

        // Measure the CURRENT title directly, NOT the live text view's layout
        // manager. SwiftUI can call this before updateNSView has re-laid-out,
        // so the view still holds the previous string: a title that now wraps
        // to two lines was measured as one, the row kept a one-line height, and
        // the second line drew over the row beneath it (Marcello, 2026-08-04).
        //
        // Exactly the same trap as HighlightingTitleField, which carries the
        // same warning — reading a live NSView's layout during SwiftUI's sizing
        // pass is never safe.
        let sizeKey = Self.cacheKey(title, bright: isBright) + "\u{1}\(width)\u{1}\(firstLineReserve)" as NSString
        let measured: CGSize
        if let cached = Self.sizeCache.object(forKey: sizeKey) {
            measured = cached.sizeValue
        } else {
            measured = Self.measure(Self.attributedTitle(title, bright: isBright),
                                    width: width, firstLineReserve: firstLineReserve)
            Self.sizeCache.setObject(NSValue(size: measured), forKey: sizeKey)
        }
        return CGSize(width: proposal.width ?? ceil(measured.width),
                      height: ceil(measured.height))
    }

    /// The reserve is an exclusion path a couple of points tall at the top
    /// right: only the line fragment that starts at y = 0 overlaps it, so only
    /// the first line is shortened — whatever its height.
    static func exclusionPaths(width: CGFloat, reserve: CGFloat) -> [NSBezierPath] {
        guard reserve > 0, width > reserve else { return [] }
        return [NSBezierPath(rect: NSRect(x: width - reserve, y: 0, width: reserve, height: 2))]
    }

    /// Wrapped size with the same container the view draws with (exclusion
    /// included) — boundingRect cannot take an exclusion path.
    private static func measure(_ string: NSAttributedString, width: CGFloat,
                                firstLineReserve: CGFloat) -> CGSize {
        guard firstLineReserve > 0, width < 50_000 else {
            return string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        }
        let storage = NSTextStorage(attributedString: string)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.exclusionPaths = exclusionPaths(width: width, reserve: firstLineReserve)
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).size
    }

    // MARK: Caches
    //
    // Opening the panel lays every row out several times per frame, and each
    // pass used to rebuild the title from scratch — entity parsing with a
    // data detector, chip images — then measure it. That was a quarter of
    // the main thread during the open animation (Time Profiler, 2026-09-30:
    // "l'animazione è super laggante"). A title is a pure function of its
    // text, brightness and appearance, so both results are cached on that.

    nonisolated(unsafe) private static let stringCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>(); cache.countLimit = 400; return cache
    }()
    nonisolated(unsafe) private static let sizeCache: NSCache<NSString, NSValue> = {
        let cache = NSCache<NSString, NSValue>(); cache.countLimit = 1200; return cache
    }()

    private static func cacheKey(_ title: String, bright: Bool) -> String {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (dark ? "d" : "l") + (bright ? "b" : "n") + title
    }

    // MARK: Attributed assembly

    static func attributedTitle(_ title: String, bright: Bool) -> NSAttributedString {
        let key = cacheKey(title, bright: bright) as NSString
        if let cached = stringCache.object(forKey: key) { return cached }
        let built = buildAttributedTitle(title, bright: bright)
        stringCache.setObject(built, forKey: key)
        return built
    }

    private static func buildAttributedTitle(_ title: String, bright: Bool) -> NSAttributedString {
        // Must equal DSFont.todoTitleSize — this is the same title, drawn
        // through TextKit so chips can flow inline with the words.
        let bodyFont = NSFont.systemFont(ofSize: DSFont.todoTitleSize)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor(bright ? DSColor.textPrimaryBright : DSColor.textPrimary),
        ]
        // Vertically centre the chip on the text rather than on the baseline.
        // Derived from the font, not a magic number: the old hardcoded -4.5
        // was correct for 13pt only, and silently drifted when the title grew.
        let textCentre = (bodyFont.ascender + bodyFont.descender) / 2
        let chipOffset = textCentre - EntityChipRenderer.chipHeight / 2
        let result = NSMutableAttributedString()
        // Image tokens first, as chips where they were typed; the text
        // between them goes through the entity parser as before.
        let ns = title as NSString
        var cursor = 0
        var pieces: [(text: String, image: String?)] = []
        for match in AttachmentStore.tokenPattern.matches(in: title, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                pieces.append((ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), nil))
            }
            pieces.append(("", ns.substring(with: match.range(at: 2))))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { pieces.append((ns.substring(from: cursor), nil)) }
        for piece in pieces {
            if let path = piece.image {
                var chipAttributes = bodyAttributes
                chipAttributes[.attachment] = ImageChipAttachment(path: path)
                result.append(NSAttributedString(string: "\u{FFFC}", attributes: chipAttributes))
                continue
            }
            appendEntities(piece.text, to: result, bodyAttributes: bodyAttributes, chipOffset: chipOffset)
        }
        return result
    }

    private static func appendEntities(_ title: String, to result: NSMutableAttributedString,
                                       bodyAttributes: [NSAttributedString.Key: Any], chipOffset: CGFloat) {
        for segment in EntityParser.parse(title) {
            switch segment {
            case .text(let run):
                result.append(NSAttributedString(string: run, attributes: bodyAttributes))
            case .entity(let kind, let display, let url):
                let attachment = NSTextAttachment()
                let image = EntityChipRenderer.image(kind: kind, label: display)
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: chipOffset,
                                           width: image.size.width,
                                           height: image.size.height)
                let chip = NSMutableAttributedString(attachment: attachment)
                if kind == .link, let url {
                    chip.addAttribute(.link, value: url,
                                      range: NSRange(location: 0, length: chip.length))
                }
                // §2.2 margin:0 2px — a thin space each side keeps chips from
                // touching adjacent words.
                result.append(NSAttributedString(string: "\u{2009}", attributes: bodyAttributes))
                result.append(chip)
                result.append(NSAttributedString(string: "\u{2009}", attributes: bodyAttributes))
            }
        }
    }
}

// MARK: - EntityTextView — click routing

final class EntityTextView: NSTextView {
    var onPlainTap: (() -> Void)?
    /// The cache key of the title on screen (EntityTitleView.updateNSView).
    var renderedKey: String?
    var firstLineReserve: CGFloat = 0 { didSet { if firstLineReserve != oldValue { applyReserve() } } }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed { applyReserve() }
    }

    private func applyReserve() {
        textContainer?.exclusionPaths = EntityTitleView.exclusionPaths(width: bounds.width,
                                                                       reserve: firstLineReserve)
    }
    /// Image chips: hover preview, ✕ (through `onRemove`), click to open.
    lazy var chips = MainActor.assumeIsolated { ImageChipInteraction(textView: self, canRemove: true) }
    private var chipTracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let chipTracking { removeTrackingArea(chipTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        chipTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        MainActor.assumeIsolated { _ = chips.mouseMoved(convert(event.locationInWindow, from: nil)) }
    }

    override func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated { chips.clear() }
    }

    /// The view is INVISIBLE to the mouse except where a link chip actually
    /// sits.
    ///
    /// This is what lets the row own its own drag. Previously this text view
    /// swallowed every mouse event in the title area, so SwiftUI never saw the
    /// press that starts a drag — which is why reordering needed a separate
    /// grip handle beside the checkbox, and why that handle pushed every row
    /// inward. Returning nil here hands plain clicks and drags back to the
    /// SwiftUI row (which already has `.onTapGesture(perform: activateRow)`),
    /// while a click on a link chip is still ours to handle.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the SUPERVIEW's coordinate space.
        let local = convert(point, from: superview)
        if MainActor.assumeIsolated({ chips.chip(at: local) != nil }) { return self }
        return linkURL(at: local) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        // Deliberately no super: non-selectable label; we only route clicks.
        // hitTest means we are only reached when the point is on a link.
        let point = convert(event.locationInWindow, from: nil)
        if MainActor.assumeIsolated({ chips.mouseDown(point) }) { return }
        if let url = linkURL(at: point) {
            NSWorkspace.shared.open(url)   // EH-7
        } else {
            onPlainTap?()
        }
    }

    /// The URL of the link chip under `point`, in this view's coordinates.
    private func linkURL(at point: NSPoint) -> URL? {
        guard let layout = layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        let glyphIndex = layout.glyphIndex(for: point, in: container)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                            in: container)
        guard glyphRect.contains(point) else { return nil }
        let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length else { return nil }
        return storage.attribute(.link, at: charIndex, effectiveRange: nil) as? URL
    }
}

// MARK: - EntityChipRenderer — chips as cached NSImages
//
// Metrics mirror DSEntityChip / EntityChipReference exactly (EH-5): radius 5,
// padding 1×7, 12pt label (monospaced for code), 10pt SF Symbol icon, only
// colors and icon differ per kind.

@MainActor
enum EntityChipRenderer {
    static let chipHeight: CGFloat = 18

    private static var cache: [String: NSImage] = [:]

    static func image(kind: EntityKind, label: String) -> NSImage {
        let key = "\(kind)|\(label)"
        if let cached = cache[key] { return cached }

        let font: NSFont = DSEntityChip.isMonospaced(kind)
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        let textColor = NSColor(DSEntityChip.text(for: kind))
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: textColor,
        ]
        let textSize = (label as NSString).size(withAttributes: textAttributes)

        var icon: NSImage?
        if let symbolName = DSEntityChip.sfSymbol(for: kind),
           let symbol = Icons.nsImage(symbolName, pointSize: 10) {
            icon = symbol.tinted(with: textColor)
        }
        let iconAdvance: CGFloat = icon.map { $0.size.width + 4 } ?? 0

        let size = NSSize(width: ceil(7 + iconAdvance + textSize.width + 7),
                          height: chipHeight)
        let background = NSColor(DSEntityChip.background(for: kind))
        let border = NSColor(DSEntityChip.border(for: kind))

        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 5, yRadius: 5)
            background.setFill()
            path.fill()
            border.setStroke()
            path.lineWidth = 0.5
            path.stroke()

            var x: CGFloat = 7
            if let icon {
                icon.draw(at: NSPoint(x: x, y: (rect.height - icon.size.height) / 2),
                          from: .zero, operation: .sourceOver, fraction: 1)
                x += icon.size.width + 4
            }
            (label as NSString).draw(
                at: NSPoint(x: x, y: (rect.height - textSize.height) / 2),
                withAttributes: textAttributes
            )
            return true
        }
        cache[key] = image
        return image
    }
}

private extension NSImage {
    /// Color fill masked by the symbol's alpha — standard template tinting.
    func tinted(with color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }
}
