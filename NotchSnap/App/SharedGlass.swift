import SwiftUI
import AppKit

// MARK: - Shared glass surfaces
//
// Lifted out of the old onboarding flow when it was replaced (2026-09-24).
// These two were never onboarding-specific: the snippet editor and Settings
// draw with them, so they outlive the flow they were first written for.

struct FrostedGlassBackground: View {
    /// Drives the slow drift of the ambient glows. One shared phase so the
    /// two blobs move in a loose, non-synchronised way rather than in lockstep.
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Layer 1: behind-window blur of the wallpaper.
            //
            // Reduce Transparency turns this off entirely rather than
            // softening it. Someone asking for it is saying they cannot read
            // text over a moving background, and a half-measure still fails
            // them — the gradient below is opaque on its own.
            if !reduceTransparency {
                VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)
            }

            // Layer 2: the window itself — purple at the top falling to
            // near-black at the foot. This replaces the white tint the old
            // flow lifted the wallpaper with; the design is a dark surface, so
            // the wallpaper now reads as depth behind it rather than as the
            // background colour.
            SharedGlassStyle.windowGradient

            // Layer 3: ambient colour wash — the single cheapest thing that
            // makes a flow read as "premium" rather than "a form". Two large,
            // heavily blurred radial gradients anchored off-canvas at opposite
            // corners, drifting slowly against each other so the light never
            // sits still but never draws the eye either. No assets, no video.
            //
            // Saturated at the edges, nothing in the centre: content always
            // sits on calm background, which is the rule that keeps this from
            // competing with the copy.
            if !reduceTransparency {
            GeometryReader { geo in
                ZStack {
                    ambientBlob(
                        colors: [Color(hex: "#7C5CFF"), Color(hex: "#C86DD7")],
                        size: geo.size.width * 0.95
                    )
                    .offset(x: -geo.size.width * 0.30,
                            y: drift ? -geo.size.height * 0.34 : -geo.size.height * 0.22)

                    ambientBlob(
                        colors: [Color(hex: "#FF8A4C"), Color(hex: "#4C8DFF")],
                        size: geo.size.width * 0.85
                    )
                    .offset(x: geo.size.width * 0.34,
                            y: drift ? geo.size.height * 0.30 : geo.size.height * 0.18)
                }
                .blur(radius: 90)
                .opacity(0.45)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            }

            // Layer 4: vignette, anchoring the cards against the gradient.
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.18)],
                center: .center,
                startRadius: 260,
                endRadius: 900
            )
        }
        .onAppear {
            // Reduce Motion: keep the colour, drop the drift. The glow is
            // decorative, so holding it still costs nothing.
            // A full-viewport moving background is the first thing Reduce
            // Motion is meant to stop. The colour stays; only the drift goes.
            guard !reduceMotion, !reduceTransparency else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func ambientBlob(colors: [Color], size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: colors.map { $0.opacity(0.55) } + [.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

struct GlassTile: View {
    var cornerRadius: CGFloat = SharedGlassStyle.cardRadius

    var body: some View {
        // rgba(0,0,0,0.3) with a hairline, per the export. It used to be
        // `.ultraThinMaterial`, which resolves LIGHT — on the new dark purple
        // surface every grouped row came out as a pale slab.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SharedGlassStyle.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Visual Effect Background (blur wallpaper)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Style

/// The three values these surfaces took from the retired onboarding design
/// system (OnboardingDesign.swift), kept here so that file could go.
enum SharedGlassStyle {
    /// #7F6CC5 at 0% to #251852 at 87%: the ramp finishes early and the last
    /// eighth holds the dark tone flat.
    static let windowGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#7F6CC5"), location: 0.0),
            .init(color: Color(hex: "#251852"), location: 0.87)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Grouped surfaces: deliberately dark under the light glass buttons.
    static let card = Color.black.opacity(0.3)
    static let cardRadius: CGFloat = 24
}
