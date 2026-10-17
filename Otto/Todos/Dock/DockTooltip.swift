import SwiftUI

// MARK: - The bar's tooltip (final flow §4.11, screen 12b)
//
// Label + the real shortcut, 28 pt tall, its foot 12 pt above the bar. It
// waits for the pointer to REST (`restDelay`), the way macOS tooltips do —
// showing at once put a label under the pointer on every pass and left
// "Settings" sitting under the menu it had just opened (Marcello,
// 2026-10-17). Once one has been seen, the next shows at once: reading along
// the bar never waits twice. A click hides it until the pointer leaves.
//
// Reduce Motion: a fade, nothing else.

@MainActor
final class DockTooltipClock {
    static let shared = DockTooltipClock()
    /// When the last tooltip went away. Within the grace period the next one
    /// appears without its delay.
    var lastHidden = Date.distantPast
    /// True while one is up, or within the grace period after it went.
    var isShowing = false
    var isWarm: Bool { isShowing || Date().timeIntervalSince(lastHidden) < 0.5 }
    /// How long the pointer rests before the first tooltip.
    static let restDelay: TimeInterval = 0.9

    func delay() -> TimeInterval { isWarm ? 0 : Self.restDelay }
    func didShow() { isShowing = true }
    func didHide() { isShowing = false; lastHidden = Date() }
}

// MARK: - ONE tooltip for the whole bar, gliding (skiper43)
//
// Every control in the bar — Notes, the dock's dots, the "+", Settings, and
// in a note Back, every format tool and Export — reports its frame and its
// hover here; the bar draws a single tooltip over whichever one the pointer
// is on. Moving from one control to the next it stays up and glides, its box
// springing to the new width while the old label fades out inside it (the
// Vercel tooltip skiper-ui's skiper43 recreates). The note bar's tooltips used
// to be one per button and closed between buttons (Marcello, 2026-10-17).

struct BarTip: Equatable {
    let label: String
    let shortcut: String?
}

@MainActor
final class BarTipState: ObservableObject {
    static let shared = BarTipState()

    /// The control the tooltip stands over (nil: none shown).
    @Published private(set) var shownID: String?
    private(set) var tips: [String: BarTip] = [:]
    private var hoveredID: String?
    /// A click hides the tooltip until the pointer leaves that control: it
    /// would otherwise sit under the menu the click opened.
    private var suppressedID: String?
    private var pending: DispatchWorkItem?

    #if DEBUG
    /// `dock-tip <i>`: show a tooltip without a pointer.
    @Published var debugID: String?
    func debugShow(_ id: String?, tip: BarTip?) {
        if let id, let tip { tips[id] = tip }
        debugID = id
    }
    #endif

    var visibleID: String? {
        #if DEBUG
        return shownID ?? debugID
        #else
        return shownID
        #endif
    }

    func tip(for id: String) -> BarTip? { tips[id] }

    func hover(_ id: String, tip: BarTip?, on: Bool) {
        if on {
            if let tip { tips[id] = tip }
            if hoveredID != id { suppressedID = nil }
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
            if suppressedID == id { suppressedID = nil }
        }
        update()
    }

    func clicked(_ id: String) {
        suppressedID = id
        update()
    }

    /// A menu opened: hide the tooltip, and keep it hidden until the pointer
    /// moves to another control.
    func dismiss() {
        suppressedID = hoveredID
        update()
    }

    /// A tip whose text changed under the pointer (a space renamed).
    func refresh(_ id: String, tip: BarTip?) {
        if let tip { tips[id] = tip } else { tips[id] = nil; if hoveredID == id { hoveredID = nil } }
        update()
    }

    private var blocked: Bool {
        DockState.shared.menuSpaceID != nil || DockState.shared.noteMenuID != nil
            || TodoStore.shared.showsAvatarMenu
    }

    private func update() {
        pending?.cancel()
        if let id = hoveredID, id != suppressedID, tips[id] != nil, !blocked {
            if shownID != nil {
                // Already up: glide to the next control at once.
                shownID = id
            } else {
                // First one: wait for the pointer to rest, as macOS does.
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.hoveredID == id, id != self.suppressedID, !self.blocked else { return }
                    self.shownID = id
                    DockTooltipClock.shared.didShow()
                }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + DockTooltipClock.shared.delay(), execute: work)
            }
            return
        }
        guard shownID != nil else { return }
        // After a beat, so crossing the gap between two controls never blinks it.
        let work = DispatchWorkItem { [weak self] in
            self?.shownID = nil
            DockTooltipClock.shared.didHide()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// The bar went away: nothing may stay up.
    func reset() {
        pending?.cancel()
        hoveredID = nil
        suppressedID = nil
        if shownID != nil { shownID = nil; DockTooltipClock.shared.didHide() }
    }
}

struct BarTipAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct BarTipModifier: ViewModifier {
    let id: String
    let tip: BarTip?
    @ObservedObject private var tips = BarTipState.shared

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: BarTipAnchorKey.self, value: .bounds) { [id: $0] }
            .onHover { tips.hover(id, tip: tip, on: $0) }
            .onChange(of: tip) { tips.refresh(id, tip: $0) }
    }
}

/// Draws the bar's one tooltip over the control it stands on. Put it on the
/// view that holds every control of the bar.
private struct BarTipHost: ViewModifier {
    @ObservedObject private var tips = BarTipState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(BarTipAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let id = tips.visibleID, let anchor = anchors[id], let tip = tips.tip(for: id) {
                        let frame = proxy[anchor]
                        let width = DockGlidingTooltip.width(of: tip)
                        // Centred over its control, but never past the bar's
                        // ends: the end buttons' tooltips lean inward.
                        let x = min(max(frame.midX, width / 2), proxy.size.width - width / 2)
                        DockGlidingTooltip(tip: tip)
                            .position(x: x, y: frame.minY - NotchContainerMetrics.tooltipGap
                                      - NotchContainerMetrics.tooltipHeight / 2)
                            .transition(reduceMotion ? .opacity
                                        : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom))
                                            .combined(with: .offset(y: 6)))
                    }
                }
                .allowsHitTesting(false)
                .animation(reduceMotion ? .easeOut(duration: 0.15)
                           : .spring(response: 0.32, dampingFraction: 0.82), value: tips.visibleID)
            }
            .onDisappear { tips.reset() }
    }
}

extension View {
    /// This control's tooltip in the bar's shared, gliding one. `tip: nil`
    /// means no tooltip here (the active space, which already says its name).
    func barTip(_ id: String, _ tip: BarTip?) -> some View {
        modifier(BarTipModifier(id: id, tip: tip))
    }

    func barTip(_ id: String, label: String, shortcut: String? = nil) -> some View {
        modifier(BarTipModifier(id: id, tip: BarTip(label: label, shortcut: shortcut)))
    }

    /// Hosts the bar's gliding tooltip.
    func barTipHost() -> some View { modifier(BarTipHost()) }
}

/// The tooltip itself: label, then the real shortcut in grey, 28 pt tall.
/// Its box's width is stated, not left to the text, so it can spring from one
/// label's width to the next with the labels clipped inside it.
struct DockGlidingTooltip: View {
    let tip: BarTip

    static func width(of tip: BarTip) -> CGFloat {
        let label = NSFont.systemFont(ofSize: 12, weight: .semibold)
        var width = ceil((tip.label as NSString).size(withAttributes: [.font: label]).width)
        if let shortcut = tip.shortcut {
            let font = NSFont.systemFont(ofSize: 11, weight: .medium)
            width += 7 + ceil((shortcut as NSString).size(withAttributes: [.font: font]).width)
        }
        return width + 20
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            HStack(spacing: 7) {
                Text(tip.label)
                    .font(DSDock.tooltipFont)
                    .foregroundStyle(DSDock.tooltipText)
                if let shortcut = tip.shortcut {
                    Text(shortcut)
                        .font(DSDock.tooltipShortcut)
                        .foregroundStyle(DSDock.text2)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .id(tip.label + (tip.shortcut ?? ""))
            .transition(.asymmetric(
                insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.05)),
                removal: .opacity.animation(.easeIn(duration: 0.1))))
        }
        .frame(width: Self.width(of: tip), height: NotchContainerMetrics.tooltipHeight)
        .background(shape.fill(DSDock.tooltip))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
