import Foundation
import AppKit
import SwiftUI

// MARK: - AppState — Source of truth

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isNotchExpanded: Bool = false
    @Published var settings: AppSettings = AppSettings.load()

    /// Which of the two expanded designs is up. The value lives in
    /// UserDefaults so views can bind to it with @AppStorage and re-render
    /// themselves, while geometry code reads it through here.
    var notchLayout: NotchLayout {
        NotchLayout(rawValue: UserDefaults.standard.string(forKey: "notchLayout") ?? "")
            ?? .panels
    }

    /// The one way to switch layouts — Settings and the onboarding's style
    /// step both come through here.
    ///
    /// The two layouts measure themselves differently, and the height one of
    /// them published is meaningless to the other. Close first, drop the stale
    /// measurements, and let the new layout measure itself on the next open —
    /// otherwise the silhouette animates to a size nothing on screen asked for.
    /// Both measurements, not just the column's: a panels-era
    /// todoContentHeight surviving into the container sized the silhouette to
    /// a panel that was no longer on screen.
    func setNotchLayout(_ layout: NotchLayout) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "notchLayout") != layout.rawValue else { return }
        defaults.set(layout.rawValue, forKey: "notchLayout")
        NotchController.shared.forceCollapse()
        NotchController.shared.applyNotchAppearance()
        labColumnHeight = 0
        todoContentHeight = 0
        objectWillChange.send()
    }

    /// Hugging height (pivot PRD §3): the to-do view MEASURES its natural
    /// content height and publishes it here; the panel is a direct animated
    /// function of this value — never a fixed container that scrolls.
    /// Published so the notch shape re-renders the moment content changes.
    @Published var todoContentHeight: CGFloat = 0
    /// LAB: the height of the whole detached column — gap, meeting block, gap,
    /// to-do block. The panel window and the hover zone are both derived from
    /// it, so the window can never be shorter than what it is drawing and the
    /// notch cannot collapse out from under panels the pointer is inside.
    @Published var labColumnHeight: CGFloat = 0

    /// Menu-bar/notch strip height, pushed in by NotchController on setup and
    /// screen changes — the hugging math needs it to convert "content height"
    /// into "total shape height".
    @Published var notchBarHeight: CGFloat = 38

    /// Headroom available inside the pre-sized panel window — the hugging
    /// height is clamped to this so the shape never outgrows its NSPanel.
    /// NotchController sizes the window from this SAME value, so the window
    /// and the shape cannot drift apart.
    ///
    /// The panel grows until it is `bottomInset` short of the usable screen —
    /// i.e. just above the Dock, or just above the screen edge when the Dock
    /// is hidden. `visibleFrame` already excludes the Dock and the menu bar,
    /// so this tracks the Dock moving, hiding, or changing size for free.
    ///
    /// An arbitrary fraction of the screen was the wrong rule: it still left a
    /// long list unreachable while a third of the display sat empty below the
    /// panel (Marcello, 2026-08-05). The limit people actually expect is
    /// "as far down as it can go without touching the Dock".
    static let bottomInset: CGFloat = 40

    static var maxExtraHeight: CGFloat {
        guard let screen = NSScreen.main else { return 372 }
        let floor = screen.visibleFrame.minY + bottomInset
        return max(372, screen.frame.maxY - floor - expandedBaseHeight)
    }

    /// The user's gallery height preset. Static because the height ceiling is
    /// itself static — both read the same @AppStorage key NotchController uses.
    fileprivate static var expandedBaseHeight: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "notchExpandedHeight")
        return stored > 0 ? CGFloat(stored) : 200
    }

    /// VW-2: extra HEIGHT (never width) for the expanded panel.
    ///
    /// For the to-do view this is the hugging-height core: total shape height
    /// = notch strip + chrome + measured content, expressed relative to the
    /// gallery baseline — so it's NEGATIVE when a short list needs less room
    /// than the gallery preset. The shape animates every change of this value
    /// on the shared contentHug spring.
    var notchExtraHeight: CGFloat {
        // notch strip + 8 (top gap) + measured panel (its own paddings and
        // bezel margins are inside the measurement).
        // The panels layout measures its whole column — meeting block
        // included — so the to-do panel's own height is not the whole story.
        //
        // In the container layout there is no column: the panel is drawn
        // inside the silhouette, so the silhouette has to hug the to-do
        // panel alone. Reading a stale `labColumnHeight` here would size the
        // notch to a column that is not on screen.
        let usesColumn = notchLayout == .panels && labColumnHeight > 0
        let content = usesColumn ? labColumnHeight : todoContentHeight + 8
        let desiredTotal = notchBarHeight + content
        let cappedTotal = min(desiredTotal, Self.expandedBaseHeight + Self.maxExtraHeight)
        return cappedTotal - Self.expandedBaseHeight
    }

    /// One-shot request to open Settings on a specific section (used by the
    /// calendar nudge card). Consumed by SettingsView.
    @Published var pendingSettingsSection: SettingsSection? = nil

    // MARK: - Settings

    func updateSettings(_ block: (inout AppSettings) -> Void) {
        block(&settings)
        settings.save()
        applyTheme()
    }

    /// Applies the selected app theme. Called on launch and after any settings change.
    func applyTheme() {
        switch settings.appTheme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
