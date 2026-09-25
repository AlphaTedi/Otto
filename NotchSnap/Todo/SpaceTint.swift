import SwiftUI

// MARK: - SpaceTint — the colour a space lends the panel (U5 §7)
//
// Colour is AMBIENT: the glow behind the list, the dot in the capture field,
// the selected pill and the floating panel's rim. It is never on content —
// checkboxes and titles keep their own colours in every space.
//
// Three values per space, straight from the handoff's table:
//   base       the glow, shadows and the rim
//   light      the dot and the selected pill's fill
//   neighbour  the second, drifting glow
//
// A list STORES its tint (`TodoCollection.tint`, a key into `palette`) so its
// hue survives renames and reordering. Lists made before U5 are given one on
// load: Grocery, Work and Personal by name, everything else from the palette
// in order.

struct SpaceTint: Equatable {
    let key: String
    let base: RGB
    let light: RGB
    let neighbour: RGB

    struct RGB: Equatable {
        let r: Double, g: Double, b: Double   // 0–255, sRGB
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
        }
        var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1) }
    }

    static let grocery = SpaceTint(key: "grocery", base: RGB(120, 215, 150),
                                   light: RGB(hex: 0x9FE0B0), neighbour: RGB(150, 210, 255))
    static let work = SpaceTint(key: "work", base: RGB(105, 155, 255),
                                light: RGB(hex: 0x9CC0FF), neighbour: RGB(160, 130, 255))
    static let personal = SpaceTint(key: "personal", base: RGB(255, 135, 175),
                                    light: RGB(hex: 0xFFB0C9), neighbour: RGB(255, 175, 130))
    static let notes = SpaceTint(key: "notes", base: RGB(255, 195, 110),
                                 light: RGB(hex: 0xFFD49A), neighbour: RGB(255, 150, 120))
    static let calendar = SpaceTint(key: "calendar", base: RGB(110, 200, 190),
                                    light: RGB(hex: 0x9AD8CF), neighbour: RGB(120, 160, 255))
    // "These kinds of pairs" for lists the user makes (U5 §7) — same
    // lightness family, hues the five above do not already take.
    static let violet = SpaceTint(key: "violet", base: RGB(160, 130, 255),
                                  light: RGB(hex: 0xC6B4FF), neighbour: RGB(255, 150, 200))
    static let coral = SpaceTint(key: "coral", base: RGB(255, 150, 120),
                                 light: RGB(hex: 0xFFBFA8), neighbour: RGB(255, 195, 110))
    static let sky = SpaceTint(key: "sky", base: RGB(110, 190, 255),
                               light: RGB(hex: 0xA8D6FF), neighbour: RGB(120, 215, 150))
    static let lime = SpaceTint(key: "lime", base: RGB(185, 215, 110),
                                light: RGB(hex: 0xD6EB9F), neighbour: RGB(110, 200, 190))

    /// Every tint a list can hold, in the order new lists receive them.
    static let palette: [SpaceTint] = [grocery, work, personal, violet, coral, sky, lime]

    /// THE section colour (top-navigation spec): the active pill, the
    /// section's checkboxes, the capture circle, the caret and the selection
    /// all read this, and nothing else. Light tone on dark; in light mode the
    /// same hue darkened until it holds contrast on a pale panel.
    var sectionColor: Color {
        let dark = light, lightMode = SpaceTint.deepened(base)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : lightMode
            return NSColor(srgbRed: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255, alpha: 1)
        })
    }

    /// The same hue with its OKLCH lightness held at 0.52 at most.
    static func deepened(_ rgb: RGB) -> RGB {
        var lch = OKLCH(rgb)
        lch.l = min(lch.l, 0.52)
        return lch.rgb
    }

    static func named(_ key: String?) -> SpaceTint? {
        guard let key else { return nil }
        return (palette + [notes, calendar]).first { $0.key == key }
    }

    /// The tint a list should get when it has none yet.
    static func assign(name: String, isToday: Bool, taken: Set<String>) -> SpaceTint {
        if isToday { return violet }
        let lower = name.lowercased()
        if ["grocery", "groceries", "spesa"].contains(lower) { return grocery }
        if ["work", "lavoro"].contains(lower) { return work }
        if ["personal", "personale"].contains(lower) { return personal }
        return palette.first { !taken.contains($0.key) } ?? palette[taken.count % palette.count]
    }

    // MARK: OKLCH — for `deepened`

    fileprivate struct OKLCH {
        var l: Double, c: Double, h: Double

        init(l: Double, c: Double, h: Double) { self.l = l; self.c = c; self.h = h }

        init(_ rgb: RGB) {
            func lin(_ v: Double) -> Double {
                let s = v / 255
                return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            let r = lin(rgb.r), g = lin(rgb.g), b = lin(rgb.b)
            let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
            let A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
            let B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
            l = L; c = sqrt(A * A + B * B); h = atan2(B, A)
        }

        var rgb: RGB {
            let A = c * cos(h), B = c * sin(h)
            let l_ = l + 0.3963377774 * A + 0.2158037573 * B
            let m_ = l - 0.1055613458 * A - 0.0638541728 * B
            let s_ = l - 0.0894841775 * A - 1.2914855480 * B
            let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
            let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
            let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
            let b = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
            func enc(_ v: Double) -> Double {
                let x = min(max(v, 0), 1)
                return 255 * (x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055)
            }
            return RGB(enc(r), enc(g), enc(b))
        }
    }
}

extension TodoCollection {
    /// This list's tint. Falls back to a stable guess for a list that has not
    /// been assigned one yet (the store assigns and saves on load).
    var spaceTint: SpaceTint {
        SpaceTint.named(tint) ?? SpaceTint.assign(name: name, isToday: isSystemToday, taken: [])
    }
}

@MainActor
extension TodoStore {
    /// The space on screen, as a tint: Notes and Calendar have their own, a
    /// list has its stored one.
    var activeSpaceTint: SpaceTint {
        switch panelMode {
        case .notes: return .notes
        case .calendar: return .calendar
        default: return activeCollection?.spaceTint ?? .work
        }
    }

    /// Where a typed to-do will land — the dot and "Save to …" wear this, not
    /// the tab, because Today files into another list.
    var draftSpaceTint: SpaceTint {
        draftDestination?.spaceTint ?? activeSpaceTint
    }
}
