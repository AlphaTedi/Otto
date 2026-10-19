import SwiftUI

// MARK: - The B3 colour dock — an experiment on the notch container
//
// Marcello's redesign of the notch container (OTTO-B3-DOCK-SPEC, 2026-10-14):
// no input card — the list's first row IS the input; the spaces move to a dock
// of coloured dots at the foot, Notes and Meetings get round buttons beside
// it and the gear one on the other side; the panel stops hugging and stands
// at one fixed height.
//
// Built as an experiment behind a Debug / Otto Lab switch, then PROMOTED
// (Marcello, 2026-10-17): it is now simply what the notch container is, in
// every build, and the switch is gone. The names keep "Experiment" so the
// history reads. It rides on the container layout rather than being a third
// one: the ~95 places that ask "is this the
// container?" keep their answers, and only the furniture the design replaces
// is swapped. docs/parity-checklist.md is the list of everything that has to
// keep working.

enum DockExperiment {
    /// The UserDefaults key the old Settings switch wrote. Read by the
    /// views' @AppStorage still, but no longer consulted: the dock is on in
    /// the container for everyone.
    static let key = "containerDock"

    /// The dock IS the notch container now — `flag` is ignored.
    static func isOn(layout: NotchLayout, flag: Bool) -> Bool {
        layout == .container
    }

    /// For code that is not a view (geometry, key routing).
    static var isOn: Bool {
        let layout = NotchLayout(rawValue: UserDefaults.standard.string(forKey: "notchLayout") ?? "") ?? .panels
        return isOn(layout: layout, flag: UserDefaults.standard.bool(forKey: key))
    }

    /// Flip the switch the way a layout change is made: close first and drop
    /// the stale measurements, so the next open sizes itself from scratch.
    @MainActor
    static func set(_ on: Bool) {
        guard UserDefaults.standard.bool(forKey: key) != on else { return }
        UserDefaults.standard.set(on, forKey: key)
        NotchController.shared.forceCollapse()
        AppState.shared.todoContentHeight = 0
        AppState.shared.objectWillChange.send()
    }
}

/// Every number the dock is drawn with. 1 CSS px = 1 pt.
///
/// The final flow (OTTO-NOTCH-FINAL-FLOW-SPEC, 2026-10-16) set the grid in
/// SILHOUETTE coordinates: content 30 in, row highlights 20 in, the bar 20 in.
/// The content frame NotchShapeView hands us already starts `frameInset` in
/// from each side, so the values used inside it are those minus 16.
enum NotchContainerMetrics {
    /// The whole silhouette, notch strip included. FIXED: the dock is the one
    /// place the panel does not hug its content (principle 2's exception,
    /// Marcello, 2026-10-14). One constant, so it can be tuned. 560 → 470 in
    /// the final flow.
    static let panelHeight: CGFloat = 470
    /// The top band left pure black, from the screen's edge.
    /// 44 in the final flow; 50 for more air under the notch (2026-10-17).
    static let notchZone: CGFloat = 50
    /// NotchShapeView's content frame, from the silhouette's VISIBLE edge.
    /// The frame is 16 in from the shape's frame, but the body is narrower
    /// than that frame by the top fillets (12 a side,
    /// `NotchController.containerBodyWidth`), so measured against the edge you
    /// see it starts only 4 in — the first pass assumed 16 and drew the whole
    /// grid 12 pt to the left (panel-snap, 2026-10-16). It ends 4 above the
    /// foot.
    static let frameInset: CGFloat = 4
    static let frameFootGap: CGFloat = 4

    // The grid, from the silhouette's edge.
    //
    // The bar is CONCENTRIC with the silhouette's bottom corners: a round
    // button sits as far from the side as from the foot, and that distance
    // is the corner radius less the button's own (Marcello, 2026-10-17 — the
    // spec's 20 at the side against 14 at the foot looked off). Everything
    // else hangs from it: row highlights start at the button's outer edge,
    // and checkboxes, note glyphs and the first row's box are centred on the
    // Notes button's axis, so the text column follows.
    ///
    /// Strictly concentric was 11 (radius 30 less 19) and read as glued to the
    /// edges (Marcello, 2026-10-17): 16, still the same at the side and the
    /// foot.
    @MainActor static var barInset: CGFloat {
        max(16, (NotchController.shared.containerBottomRadius - roundButton / 2).rounded())
    }
    @MainActor static var barBottom: CGFloat { barInset }
    /// Hover, focus and the opened card start here.
    @MainActor static var highlightInset: CGFloat { barInset }
    /// Checkboxes and the like: centred on the Notes button (18 on a 38).
    @MainActor static var contentInset: CGFloat { barInset + (roundButton - box) / 2 }
    /// Inside a highlight: the content column.
    static let rowPadding: CGFloat = (roundButton - box) / 2
    static let highlightRadius: CGFloat = 14
    /// The same three, inside the content frame.
    @MainActor static var highlightInFrame: CGFloat { highlightInset - frameInset }
    @MainActor static var contentInFrame: CGFloat { contentInset - frameInset }
    @MainActor static var barInFrame: CGFloat { barInset - frameInset }

    static let rowMinHeight: CGFloat = 38
    /// Checkbox 18 + 12: the text column at 60.
    static let rowGap: CGFloat = 12
    static let box: CGFloat = 18
    static let boxRadius: CGFloat = 6
    static let boxStroke: CGFloat = 2

    /// The progressive blur + gradient under the bar: the bar's own band and
    /// at most 40 pt above it (Marcello, 2026-10-17 — the spec's 130 began
    /// blurring rows halfway up the list).
    @MainActor static var footZone: CGFloat { barBottom + roundButton + 40 }
    /// How far past its end a list scrolls: the whole foot zone and a
    /// little more, so the last row — Completed included — can rest ABOVE
    /// the blur, in focus and clickable. 62 left it under the blur
    /// (Marcello, 2026-10-19).
    @MainActor static var listTravel: CGFloat { footZone + 12 }
    /// What the empty state leaves at the list's foot: the bar and its
    /// margin, so the block centres in the room you can see.
    @MainActor static var dockEmptyFoot: CGFloat { barBottom + roundButton + 8 }

    // Bottom bar
    static let barGap: CGFloat = 8
    static let roundButton: CGFloat = 38
    static let roundIcon: CGFloat = 16

    // Dock
    static let dockItem: CGFloat = 30
    /// 4: the dock is then 38 tall, the round buttons' height, so their tops
    /// — where the tooltips hang from — are one line.
    static let dockPadding: CGFloat = 4
    /// Between a tooltip's foot and the top of the bar.
    static let tooltipGap: CGFloat = 12
    static let tooltipHeight: CGFloat = 28
    static let dockItemGap: CGFloat = 2
    static let dockDot: CGFloat = 7
    static let dockItemPaddingH: CGFloat = 11.5
    static let dockLabelLeading: CGFloat = 7
    static let dockLabelTrailing: CGFloat = 5
    /// About eight spaces fit; past this width the dock scrolls in its capsule.
    static let dockMaxWidth: CGFloat = 380

    // Steps (final flow 4.3)
    static let stepBox: CGFloat = 14
    static let stepBoxRadius: CGFloat = 4.5
    static let stepStroke: CGFloat = 1.75
    static let stepRowHeight: CGFloat = 26
}

/// The three motion styles the designer is choosing between (spec §8).
/// Glide is the default; the other two are picked with
/// `defaults write com.notchsnap.app containerDockMotion pages|rise`.
enum NotchDockMotion: String {
    case glide, pages, rise

    static var current: NotchDockMotion {
        NotchDockMotion(rawValue: UserDefaults.standard.string(forKey: "containerDockMotion") ?? "") ?? .glide
    }

    /// The one curve the dock label, the highlight and the content share.
    var curve: Animation {
        switch self {
        case .glide: return .timingCurve(0.4, 0, 0.2, 1, duration: 0.32)
        case .pages: return .timingCurve(0.32, 0.72, 0, 1, duration: 0.48)
        case .rise:  return .timingCurve(0.34, 1.28, 0.64, 1, duration: 0.42)
        }
    }

    /// Reduce Motion: every transition is a 150 ms crossfade (spec §6.6).
    static func curve(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : current.curve
    }

    /// The list swapping between spaces. `forward` is the direction of travel
    /// along the dock (Pages slides that way).
    static func listTransition(reduceMotion: Bool, forward: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.15)) }
        switch current {
        case .glide:
            // Out first (110 ms), in after the swap at 120 ms — in sequence,
            // never crossfading over each other.
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 3))
                    .animation(.easeOut(duration: 0.22).delay(0.12)),
                removal: .opacity.combined(with: .offset(y: 3))
                    .animation(.easeIn(duration: 0.11)))
        case .pages:
            let edge: Edge = forward ? .trailing : .leading
            return .asymmetric(insertion: .move(edge: edge), removal: .move(edge: edge == .trailing ? .leading : .trailing))
                .animation(NotchDockMotion.pages.curve)
        case .rise:
            // The rows rise one by one (DockRise); the block itself just swaps.
            return .identity
        }
    }
}

/// Rise: each row comes up 10 pt from transparent, 18 ms after the one above
/// it, the stagger capped at row 8 (spec §8.3).
struct DockRise: ViewModifier {
    let index: Int
    /// Only in the dock; the other layouts never rise.
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    func body(content: Content) -> some View {
        let active = enabled && NotchDockMotion.current == .rise && !reduceMotion
        content
            .opacity(!active || risen ? 1 : 0)
            .offset(y: !active || risen ? 0 : 10)
            .onAppear {
                guard active else { return }
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.36)
                    .delay(Double(min(index, 8)) * 0.018)) { risen = true }
            }
    }
}

extension View {
    func dockRise(index: Int, enabled: Bool = true) -> some View {
        modifier(DockRise(index: index, enabled: enabled))
    }
}

// MARK: - A space's colours, derived (final flow 3.2)

/// Every variant the dock paints a space with. The base is the final flow's
/// swatch for the space's stored tint — the same seven, in the same order as
/// `SpaceTint.palette`, that the new-space card and the space menu offer.
struct DockTint: Equatable {
    let base: Color
    let light: Color

    /// The nine swatches by tint key, plus Notes' gold.
    static let swatches: [String: UInt32] = [
        "grocery": 0x9EE0B0, "work": 0x8FB8FF, "personal": 0xF4A9C4, "violet": 0xC3B1FF,
        "coral": 0xF5C2A6, "sky": 0xA9D8FF, "lime": 0xD9EBA3, "teal": 0x8FE0D6,
        "amber": 0xF5D68A, "notes": 0xE5B66B,
        "calendar": 0x9AD8CF,
    ]

    init(_ tint: SpaceTint) {
        let rgb = Self.swatches[tint.key].map(SpaceTint.RGB.init(hex:)) ?? tint.light
        base = rgb.color
        // The base mixed half-way to white.
        light = Color(.sRGB, red: (rgb.r / 255 + 1) / 2, green: (rgb.g / 255 + 1) / 2,
                      blue: (rgb.b / 255 + 1) / 2, opacity: 1)
    }

    var highlight: Color { base.opacity(0.24) }
    var checkboxStroke: Color { base.opacity(0.85) }
    var firstRowStroke: Color { base.opacity(0.85) }
    var firstRowFill: Color { base.opacity(0.12) }
    var stepStroke: Color { base.opacity(0.7) }
}
