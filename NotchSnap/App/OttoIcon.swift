import AppKit
import SwiftUI

// MARK: - OttoIcon — every icon in Otto is a Lucide icon (lucide.dev, ISC)
//
// One icon family, one stroke, one grid (24 × 24, 2-pt stroke, round caps),
// so icons from different screens line up with each other (Marcello,
// 2026-09-27). The SVGs live in Assets.xcassets/Lucide as template vectors;
// the licence is Resources/LUCIDE-LICENSE.txt.
//
// Call sites still name icons the way they did — by their SF Symbol name —
// and `Icons.lucide(for:)` maps that to the Lucide glyph. That keeps every
// place that passes a symbol name around (menus, enums, settings sections)
// working unchanged, and a symbol with no mapping shows up in DEBUG instead
// of silently falling back.

enum Icons {
    /// SF Symbol name → Lucide name. Add a pair here, and the SVG to
    /// Assets.xcassets/Lucide, when a new icon is needed.
    static let lucide: [String: String] = [
        "app.fill": "app-window",
        "arrow.down": "arrow-down",
        "arrow.left": "arrow-left",
        "arrow.up.right": "arrow-up-right",
        "arrow.uturn.backward": "undo-2",
        "arrow.uturn.forward": "redo-2",
        "at": "at-sign",
        "bell.fill": "bell",
        "book": "book-open",
        "bubble.left": "message-square",
        "calendar": "calendar",
        "calendar.badge.clock": "calendar-clock",
        "calendar.badge.plus": "calendar-plus",
        "camera.viewfinder": "scan",
        "chart.bar": "chart-column",
        "checklist": "list-checks",
        "checkmark": "check",
        "checkmark.circle": "circle-check",
        "checkmark.circle.fill": "circle-check",
        "checkmark.square": "square-check",
        "checkmark.square.fill": "square-check",
        "chevron.down": "chevron-down",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "chevron.up": "chevron-up",
        "chevron.left.forwardslash.chevron.right": "code",
        "circle": "circle",
        "command": "command",
        "cursorarrow.rays": "mouse-pointer-2",
        "checkmark.shield.fill": "shield-check",
        "exclamationmark.triangle.fill": "triangle-alert",
        "lock.fill": "lock",
        "clipboard": "clipboard",
        "curlybraces": "braces",
        "doc": "file",
        "doc.fill": "file",
        "doc.on.doc": "copy",
        "doc.richtext": "file-text",
        "ellipsis": "ellipsis",
        "exclamationmark.bubble.fill": "message-square-warning",
        "folder": "folder",
        "folder.fill": "folder",
        "gearshape": "settings",
        "gearshape.fill": "settings",
        "globe": "globe",
        "info.circle": "info",
        "keyboard": "keyboard",
        "link": "link",
        "location": "map-pin",
        "macbook": "laptop",
        "magnifyingglass": "search",
        "message": "message-circle",
        "mic.fill": "mic",
        "note": "sticky-note",
        "note.text": "sticky-note",
        "number": "hash",
        "paintbrush": "paintbrush",
        "paintpalette": "palette",
        "paintpalette.fill": "palette",
        "pencil": "pencil",
        "pencil.circle.fill": "pencil",
        "pencil.tip": "pen-tool",
        "person": "user",
        "person.fill": "user",
        "person.2.fill": "users",
        "photo": "image",
        "pin": "pin",
        "pin.fill": "pin",
        "pin.slash": "pin-off",
        "plus": "plus",
        "plus.circle": "circle-plus",
        "power": "power",
        "questionmark.circle": "circle-question-mark",
        "rectangle": "rectangle-horizontal",
        "scope": "crosshair",
        "square": "square",
        "square.and.arrow.down": "download",
        "square.grid.2x2": "layout-grid",
        "text.alignleft": "text-align-start",
        "text.badge.star": "sparkles",
        "text.viewfinder": "scan-text",
        "trash": "trash-2",
        "tray.full": "inbox",
        "video": "video",
        "video.fill": "video",
        "waveform": "audio-lines",
        "wind": "wind",
        "xmark": "x",
        "xmark.circle.fill": "circle-x",
    ]

    static func assetName(for symbol: String) -> String? {
        lucide[symbol].map { "Lucide/\($0)" }
    }

    /// Lucide draws on a 24-pt grid with ~2 pt of air; an SF Symbol at font
    /// size N reads about this much larger than N. So a call site that used
    /// `.font(.system(size: 13))` keeps the same optical size.
    static let opticalScale: CGFloat = 1.15

    /// For AppKit call sites (menus, attributed strings).
    static func nsImage(_ symbol: String, pointSize: CGFloat) -> NSImage? {
        guard let name = assetName(for: symbol), let image = NSImage(named: name)?.copy() as? NSImage else {
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        let side = pointSize * opticalScale
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }
}

/// A Lucide icon sized like the SF Symbol it replaces: `pointSize` is the
/// font size the old `.font(.system(size:))` gave the symbol.
struct OttoIcon: View {
    let symbol: String
    var pointSize: CGFloat = 13

    init(_ symbol: String, pointSize: CGFloat = 13) {
        self.symbol = symbol
        self.pointSize = pointSize
    }

    var body: some View {
        if let name = Icons.assetName(for: symbol) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: pointSize * Icons.opticalScale, height: pointSize * Icons.opticalScale)
        } else {
            #if DEBUG
            let _ = print("[OttoIcon] no Lucide mapping for \(symbol)")
            #endif
            Image(systemName: symbol).font(.system(size: pointSize))
        }
    }
}
