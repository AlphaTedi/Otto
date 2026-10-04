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
        "arrow.left": "arrow-left",
        "at": "at-sign",
        "book": "book-open",
        "bubble.left": "message-square",
        "calendar": "calendar",
        "calendar.badge.plus": "calendar-plus",
        "chart.bar": "chart-column",
        "checkmark": "check",
        "checkmark.circle": "circle-check",
        "checkmark.circle.fill": "circle-check",
        "checkmark.square.fill": "square-check",
        "chevron.down": "chevron-down",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "chevron.up": "chevron-up",
        "cursorarrow.rays": "mouse-pointer-2",
        "checkmark.shield.fill": "shield-check",
        "exclamationmark.triangle.fill": "triangle-alert",
        "lock.fill": "lock",
        "doc": "file",
        "ellipsis": "ellipsis",
        "exclamationmark.bubble.fill": "message-square-warning",
        "folder": "folder",
        "folder.fill": "folder",
        "gearshape": "settings",
        "gearshape.fill": "settings",
        "keyboard": "keyboard",
        "link": "link",
        "macbook": "laptop",
        "magnifyingglass": "search",
        "note": "sticky-note",
        "note.text": "sticky-note",
        "number": "hash",
        "paintpalette.fill": "palette",
        "person.2.fill": "users",
        "photo": "image",
        "plus": "plus",
        "plus.circle": "circle-plus",
        "power": "power",
        "square": "square",
        "text.alignleft": "text-align-start",
        "video.fill": "video",
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
