import SwiftUI

// MARK: - PanelTooltip — a tooltip that can appear inside the notch
//
// `.help()` asks AppKit for a tooltip window, and AppKit puts it at an
// ordinary window level. The notch panel lives far above that (and in a
// space of its own — SpaceAnchor), so every tooltip in the panel opened
// BEHIND it, under the notch and the floating cards (Marcello, 2026-10-12).
// This one is drawn by the panel itself: after a short hover a small label
// rises above the control, the way the system's would.

extension View {
    /// Use instead of `.help()` for controls inside the notch panel.
    func panelTooltip(_ text: String) -> some View {
        modifier(PanelTooltip(text: text))
    }
}

private struct PanelTooltip: ViewModifier {
    let text: String
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                pending?.cancel()
                if hovering {
                    // The system's own delay, near enough.
                    pending = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.12)) { shown = true }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.08)) { shown = false }
                }
            }
            .overlay(alignment: .top) {
                if shown {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .offset(y: -30)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .accessibilityHint(text)
    }
}
