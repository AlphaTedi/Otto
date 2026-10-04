import SwiftUI

// MARK: - NotchExpandedView — the container layout's content
//
// In the container layout (Settings > Notch > Layout) the to-do panel is drawn
// INSIDE the black silhouette. NotchShapeView pins the appearance for it
// (`darkGroundSurface()`), and NotchController pins the panel WINDOW to
// darkAqua in this layout so the AppKit text views inside follow as well.

struct NotchExpandedView: View {
    var body: some View {
        TodoTabView()
            // TOP-aligned, explicitly. The default alignment of a max frame is
            // centre, and the silhouette proposes an ANIMATING height: for the
            // duration of a big-to-small section switch the proposal is taller
            // than the content, so the content sat centred in the slack and the
            // draft row slid up and down with every switch (Thomas, 2026-09-01).
            // The input must stay put; only the bottom edge moves.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    /// Pin the material's appearance instead of inheriting the system's.
    ///
    /// Materials resolve light or dark from the effective appearance, so on a
    /// light desktop `.hudWindow` came back LIGHT — and every panel in this
    /// app draws white text on it. nil keeps the old inherited behaviour for
    /// the callers that want it.
    var appearance: NSAppearance.Name?
    /// Bumped when the material must sample again — see GlassRefresh. The
    /// value is never read for its own sake; it exists so `updateNSView` runs.
    var refreshToken: Int = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        if let appearance { view.appearance = NSAppearance(named: appearance) }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = appearance.flatMap { NSAppearance(named: $0) }
        // Re-asserting `.active` is what makes AppKit re-sample what is behind
        // the window. Setting it to the value it already holds is not a no-op
        // here: it marks the effect dirty.
        nsView.state = .active
        nsView.needsDisplay = true
    }
}
