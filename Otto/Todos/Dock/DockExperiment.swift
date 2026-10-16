import SwiftUI

// MARK: - The B3 colour dock — an experiment on the notch container
//
// Marcello's redesign of the notch container (OTTO-B3-DOCK-SPEC, 2026-10-14):
// no input card — the list's first row IS the input; the spaces move to a dock
// of coloured dots at the foot, Notes and Meetings get round buttons beside
// it and the gear one on the other side; the panel stops hugging and stands
// at one fixed height.
//
// An EXPERIMENT, and built as one: a switch in Settings › Notch that only
// Debug and Otto Lab builds show (and only they can turn on — a `defaults
// write` left behind cannot reach a release). It rides on the container
// layout rather than being a third one: the ~95 places that ask "is this the
// container?" keep their answers, and only the furniture the design replaces
// is swapped. docs/parity-checklist.md is the list of everything that has to
// keep working.

enum DockExperiment {
    /// The UserDefaults key the Settings switch writes (@AppStorage).
    static let key = "containerDock"

    /// Only Debug and Otto Lab can turn it on.
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return AppBuild.isLab
        #endif
    }

    static func isOn(layout: NotchLayout, flag: Bool) -> Bool {
        isAvailable && layout == .container && flag
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

/// Every number the dock is drawn with (spec §3, §5). 1 CSS px = 1 pt.
enum NotchContainerMetrics {
    /// The whole silhouette, notch strip included. FIXED: the dock is the one
    /// place the panel does not hug its content (principle 2's exception,
    /// Marcello, 2026-10-14). One constant, so it can be tuned.
    static let panelHeight: CGFloat = 560
    /// The top band left pure black, from the screen's edge.
    static let notchZone: CGFloat = 50
    /// From the silhouette's sides to the content.
    static let sideInset: CGFloat = 32
    static let bottomInset: CGFloat = 18
    /// The first row's box sits on the checkbox column of the rows under it:
    /// a container row pads 20 inside the content frame, which itself starts
    /// 16 in — 36 from the silhouette, the spec's 32 + 4.
    static let firstRowInset: CGFloat = PanelMetrics.barPaddingH
    static let rowMinHeight: CGFloat = 40
    static let rowGap: CGFloat = 14
    static let box: CGFloat = 18
    static let boxRadius: CGFloat = 6
    static let boxStroke: CGFloat = 1.5

    /// The list scrolls under a fade of this depth, and ends this far above
    /// the bar so the last row can scroll clear of it.
    static let listFade: CGFloat = 40

    // Bottom bar
    static let barTopGap: CGFloat = 10
    static let barGap: CGFloat = 8
    static let roundButton: CGFloat = 38
    static let roundIcon: CGFloat = 16

    // Dock
    static let dockItem: CGFloat = 30
    static let dockPadding: CGFloat = 3
    static let dockItemGap: CGFloat = 2
    static let dockDot: CGFloat = 9
    static let dockItemPaddingH: CGFloat = 10.5
    static let dockLabelLeading: CGFloat = 7
    static let dockLabelTrailing: CGFloat = 3.5
    static let dockCountGap: CGFloat = 5
    /// About eight spaces fit; past this width the dock scrolls in its capsule.
    static let dockMaxWidth: CGFloat = 380
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

// MARK: - A space's colours, derived (spec §4.1)

/// Every variant the dock paints a space with, from the colour the space
/// already has. The panel is always black, so the dark-appearance tone is the
/// base.
struct DockTint: Equatable {
    let base: Color
    let light: Color

    init(_ tint: SpaceTint) {
        let rgb = tint.light
        base = rgb.color
        // The base mixed half-way to white.
        light = Color(.sRGB, red: (rgb.r / 255 + 1) / 2, green: (rgb.g / 255 + 1) / 2,
                      blue: (rgb.b / 255 + 1) / 2, opacity: 1)
    }

    var highlight: Color { base.opacity(0.18) }
    var checkboxStroke: Color { base.opacity(0.5) }
    var firstRowStroke: Color { base.opacity(0.6) }
    var firstRowFill: Color { base.opacity(0.12) }
}
