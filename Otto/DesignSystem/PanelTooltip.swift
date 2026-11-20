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

    /// THE tooltip for a new control, on either surface: the label, then its
    /// shortcut, the way every Otto tooltip reads ("Download  ⌘⇧S").
    /// Shortcuts live here, never printed permanently (principle 4).
    ///
    /// The container's dock BAR has its own gliding tooltip (`.barTip`, in
    /// Dock/DockTooltip.swift) because its tips slide between neighbours;
    /// use that only for controls inside `DockBar`.
    func ottoTooltip(_ label: String, shortcut: String? = nil) -> some View {
        panelTooltip(shortcut.map { label + "  " + $0 } ?? label)
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
                        withAnimation(Motion.hintFade) { shown = true }
                    }
                } else {
                    withAnimation(Motion.hintFade) { shown = false }
                }
            }
            .overlay(alignment: .top) {
                if shown {
                    Text(text)
                        .font(DSType.tooltip)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize()
                        .padding(.horizontal, DSSpace.m)
                        .padding(.vertical, DSSpace.xs)
                        .background(DSShape.squircle(DSRadius.keycap)
                            .fill(Color(white: 0.16)))
                        .overlay(DSShape.squircle(DSRadius.keycap)
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
