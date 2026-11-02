import SwiftUI

// MARK: - The new-space card in the floating panels (experiment, 2026-11-02)
//
// In the floating panels "New section" replaced the whole panel with a form,
// which read as having opened a new section rather than as naming one
// (Marcello). This tries the notch's flow there: the pill itself grows into
// the card — name, colours, ✓ — over a veil, and folds back. Same state, keys
// and creation as the notch (DockState, DockNewSpaceCard); ⇧⌘N, ⇥, ⏎ and Esc
// work as they do there, and a click on the veil closes it.
//
// An EXPERIMENT: a switch in Settings › Appearance that only Debug and Otto Lab
// show or honour. Off, the panels keep their form.

enum NewSpaceCardExperiment {
    static let key = "floatingNewSpaceCard"

    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return AppBuild.isLab
        #endif
    }

    static var isOn: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: key)
            && UserDefaults.standard.string(forKey: "notchLayout") != NotchLayout.container.rawValue
    }
}

extension TodoStore {
    /// "New section", from wherever it was asked for: the dock's card, this
    /// experiment's card, or the panels' form.
    @MainActor
    func beginNewSection() {
        if DockExperiment.isOn || NewSpaceCardExperiment.isOn {
            DockState.shared.beginNewSpace()
        } else {
            setMode(.newCategory)
        }
        NotchController.shared.focusPanel()
    }
}

/// Where the "New section" pill is, for the card to grow out of.
struct NewSectionAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The veil and the card, over the whole panel. Grows from `pill` by animating
/// one surface's frame, with the card's content cross-fading inside it.
struct FloatingNewSpaceLayer: View {
    let pill: CGRect?
    let size: CGSize

    @ObservedObject private var dock = DockState.shared
    /// In the tree; outlives `open` for the length of the fold.
    @State private var shown = false
    @State private var open = false

    private static let inset: CGFloat = 12

    private var origin: CGRect {
        // A pill scrolled out of the row still has somewhere to start from.
        let card = DockNewSpaceCard.size
        let fallback = CGRect(x: size.width - 120 - Self.inset, y: size.height - 28 - Self.inset,
                              width: 120, height: 28)
        guard let pill, pill.minX >= 0, pill.maxX <= size.width, pill.width < card.width else { return fallback }
        return pill
    }

    private var target: CGRect {
        let card = DockNewSpaceCard.size
        let x = min(max(origin.midX - card.width / 2, Self.inset), size.width - card.width - Self.inset)
        return CGRect(x: x, y: origin.maxY - card.height, width: card.width, height: card.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shown {
                Color.black.opacity(open ? 0.32 : 0)
                    .overlay(MenuDismissCatcher { dock.cancelNewSpace() })
                surface
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: dock.isCreatingSpace) { creating in
            if creating {
                shown = true
                // Next turn: the surface has to exist at the pill's frame
                // before it can animate away from it.
                DispatchQueue.main.async {
                    withAnimation(DockMorph.open) { open = true }
                }
            } else {
                withAnimation(DockMorph.close) { open = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    if !dock.isCreatingSpace { shown = false }
                }
            }
        }
    }

    private var surface: some View {
        let frame = open ? target : origin
        let radius = open ? DockNewSpaceCard.radius : frame.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(OttoMenuStyle.ground)
            DockNewSpaceCard(floating: true)
                .opacity(open ? 1 : 0)
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(open ? 0.28 : 0), radius: 18, y: 8)
        .position(x: frame.midX, y: frame.midY)
    }
}
