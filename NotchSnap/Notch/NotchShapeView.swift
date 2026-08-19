import SwiftUI

// MARK: - NotchState

enum NotchState: Equatable {
    case idle
    case hovering
    case expanded
    case captureNotification  // micro-expand: thumbnail + checkmark, auto-dismiss
}

// MARK: - NotchShape — Custom shape replicating Alcove's notch

struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var filletRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, filletRadius) }
        set {
            bottomRadius = newValue.first
            filletRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let fr = min(max(filletRadius, 0), w / 4, h / 3)
        let bodyLeft = fr
        let bodyRight = w - fr
        let cr = min(max(bottomRadius, 0), h / 3, (bodyRight - bodyLeft) / 3)

        if fr > 0.5 {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addQuadCurve(to: CGPoint(x: bodyRight, y: fr), control: CGPoint(x: bodyRight, y: 0))
            path.addLine(to: CGPoint(x: bodyRight, y: h - cr))
            if cr > 0.5 {
                path.addCurve(to: CGPoint(x: bodyRight - cr, y: h),
                              control1: CGPoint(x: bodyRight, y: h - cr * 0.44),
                              control2: CGPoint(x: bodyRight - cr * 0.44, y: h))
            } else {
                path.addLine(to: CGPoint(x: bodyRight, y: h))
            }
            let bottomLeftX = cr > 0.5 ? bodyLeft + cr : bodyLeft
            path.addLine(to: CGPoint(x: bottomLeftX, y: h))
            if cr > 0.5 {
                path.addCurve(to: CGPoint(x: bodyLeft, y: h - cr),
                              control1: CGPoint(x: bodyLeft + cr * 0.44, y: h),
                              control2: CGPoint(x: bodyLeft, y: h - cr * 0.44))
            }
            path.addLine(to: CGPoint(x: bodyLeft, y: fr))
            path.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: bodyLeft, y: 0))
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h - cr))
            if cr > 0.5 {
                path.addCurve(to: CGPoint(x: w - cr, y: h),
                              control1: CGPoint(x: w, y: h - cr * 0.44),
                              control2: CGPoint(x: w - cr * 0.44, y: h))
            }
            path.addLine(to: CGPoint(x: cr, y: h))
            if cr > 0.5 {
                path.addCurve(to: CGPoint(x: 0, y: h - cr),
                              control1: CGPoint(x: cr * 0.44, y: h),
                              control2: CGPoint(x: 0, y: h - cr * 0.44))
            }
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Squish/Stretch values for KeyframeAnimator

struct NotchSquishValues {
    var scaleX: CGFloat = 1.0
    var scaleY: CGFloat = 1.0
    var verticalOffset: CGFloat = 0.0
}

// MARK: - NotchShapeView — Animated notch with Dynamic Island bounciness

struct NotchShapeView: View {
    @Binding var state: NotchState
    let notchSize: CGSize
    let expandedSize: CGSize
    /// VW-1: the expanded panel has ONE fixed width across every tab.
    /// Height is the only dimension that varies (VW-2) — a to-do list with
    /// eight rows is taller than one with two, but never wider.
    var extraExpandedHeight: CGFloat = 0
    let hasPhysicalNotch: Bool
    var screenshotJustArrived: Bool = false
    var contentVisible: Bool = false
    var notificationContentVisible: Bool = false
    var notificationWide: Bool = false
    let content: AnyView
    var notificationContent: AnyView? = nil

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("notchCornerRadius") private var userCornerRadius: Double = 10
    /// A permanent element on the user's menu bar is not something to impose,
    /// so it is switchable. Default on — the whole point is that Otto stops
    /// being invisible.
    @AppStorage("showNotchPresence") private var showNotchPresence: Bool = true
    @ObservedObject private var calendar = CalendarStore.shared
    @ObservedObject private var presence = NotchPresence.shared

    // MARK: - Raccordatura radius per state

    private var currentFilletRadius: CGFloat {
        switch state {
        case .idle:                 return 12
        case .hovering:             return 14
        case .expanded:             return 12
        case .captureNotification:  return 12
        }
    }

    // MARK: - Presence indicator geometry
    //
    // How far the collapsed silhouette grows is the entire cost of this
    // feature: every point of width covers a point of menu bar, and enlarges
    // the zone that swallows clicks meant for whatever is up there. So it
    // grows for a countdown and not one point otherwise.

    private var presenceState: NotchPresenceState? {
        guard showNotchPresence, state == .idle || state == .hovering else { return nil }
        // `.resting` draws NOTHING and adds NOTHING. A closed notch with
        // nothing coming up is just the notch — the resting glyph made it
        // permanently wider than the hardware for no information at all
        // (Marcello, 2026-08-18). Presence is now something you notice
        // because it appeared, not something always sitting there.
        guard case .countdown = presence.state else { return nil }
        return presence.state
    }

    /// Extra width the indicator needs, over the bare notch.
    ///
    /// Every point of this covers a point of menu bar and enlarges the
    /// collapsed hit zone, so it is sized off MEASURED content, not guessed:
    /// "in 34′" is 31pt at 11pt monospaced-digit, plus a 6pt dot and a 4pt gap
    /// = 41pt, and 6pt of breathing room each side of it makes a 53pt wing.
    /// Doubling that for the two wings is the whole number.
    ///
    /// Fixed at the widest label rather than tracking the current one: a notch
    /// that resized itself every minute as "in 10′" became "in 9′" would be
    /// far more distracting than a few points of slack.
    private static let presenceWingWidth: CGFloat = 53

    private var presenceExtraWidth: CGFloat {
        presenceState == nil ? 0 : Self.presenceWingWidth * 2
    }

    private var currentWidth: CGFloat {
        let base: CGFloat = {
            switch state {
            case .idle:
                return notchSize.width + presenceExtraWidth + currentFilletRadius * 2
            case .hovering:
                return notchSize.width + max(28, presenceExtraWidth) + currentFilletRadius * 2
            case .expanded:             return expandedSize.width
            case .captureNotification:  return notificationWide ? 320 : notchSize.width + 80 + currentFilletRadius * 2
            }
        }()
        return screenshotJustArrived ? base + 16 : base
    }

    private var currentHeight: CGFloat {
        let base: CGFloat = {
            switch state {
            // The indicator NEVER adds height. It exceeded the hardware notch
            // vertically, which reads as a bar hanging into the desktop rather
            // than as the notch itself (Marcello, 2026-08-18). It widens, and
            // only as far as its content needs.
            case .idle:                 return notchSize.height
            case .hovering:             return notchSize.height + 6
            case .expanded:             return expandedSize.height + extraExpandedHeight
            case .captureNotification:  return notchSize.height
            }
        }()
        return screenshotJustArrived ? base + 12 : base
    }

    private var bottomCornerRadius: CGFloat {
        // Scale with height so taller presets (Wide / Extra Large) keep a
        // visibly rounded silhouette instead of looking like a flat slab.
        // Cap at 28pt so tiny notches don't get over-rounded.
        let base = CGFloat(userCornerRadius)
        let h = expandedSize.height
        let scaled = max(base, min(28, h * 0.13))
        switch state {
        case .idle:                 return base
        case .hovering:             return base + 2
        case .expanded:             return scaled + 4
        case .captureNotification:  return base
        }
    }

    // MARK: - Shadow

    private var shadowColor: Color {
        switch state {
        case .idle:                 return .clear
        case .hovering:             return .black.opacity(0.35)
        case .expanded:             return .clear
        case .captureNotification:  return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch state {
        case .idle:                 return 0
        case .hovering:             return 20
        case .expanded:             return 0
        case .captureNotification:  return 0
        }
    }

    // MARK: - Spring animation selection

    private var shapeAnimation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        if screenshotJustArrived { return NotchAnimation.bounce }
        switch state {
        case .expanded:             return NotchAnimation.expand
        case .hovering:             return NotchAnimation.hover
        case .idle:                 return NotchAnimation.collapse
        case .captureNotification:  return NotchAnimation.notificationExpand
        }
    }

    // MARK: - Squish state (Dynamic Island style)
    @State private var squishScaleX: CGFloat = 1.0
    @State private var squishScaleY: CGFloat = 1.0
    // Sequencing task for the multi-phase squish. Cancelled and replaced on
    // every state change so a rapid hover-in/hover-out can never leave a
    // stale phase firing on an already-collapsed notch.
    @State private var squishTask: Task<Void, Never>? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // The notch shape with squish/stretch overlay
            NotchShape(
                bottomRadius: bottomCornerRadius,
                filletRadius: currentFilletRadius
            )
            .fill(Color.black)
            .frame(width: currentWidth, height: currentHeight)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 4)
            .scaleEffect(x: squishScaleX, y: squishScaleY, anchor: .top)
            .animation(shapeAnimation, value: state)
            .animation(NotchAnimation.bounce, value: screenshotJustArrived)
            // Hugging height (§8.3): the silhouette grows/shrinks on the SAME
            // spring as row enter/exit, so container and content move as one.
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : NotchAnimation.contentHug,
                       value: extraExpandedHeight)
            .onChange(of: state) { newState in
                if !reduceMotion {
                    runSquishAnimation(for: newState)
                }
            }
            // The presence indicator (spec 2026-08-17). It replaces CA-2's
            // lone amber dot, which said only "a meeting exists" — this says
            // which kind, and how long you have.
            //
            // Each side's content is centred in its own wing — the strip
            // between the camera housing's edge and the silhouette's outer
            // edge — so it sits exactly between the two, which is only tight
            // because the wing is barely wider than the content.
            .overlay(alignment: .top) {
                if let presenceState {
                    // The shape's INNER rect: full silhouette height, and the
                    // width between its two straight sides (the fillet eats a
                    // radius off each). Anchoring inside this is what makes
                    // "inset from the edge of the notch" mean the real edge.
                    NotchPresenceView(
                        state: presenceState,
                        notchWidth: notchSize.width,
                        wingWidth: Self.presenceWingWidth
                    )
                    .frame(width: currentWidth - currentFilletRadius * 2,
                           height: notchSize.height)
                }
            }
            .animation(NotchAnimation.contentHug, value: presenceExtraWidth)
            .animation(NotchAnimation.hintFade, value: presence.state)

            // Content gallery — staggered fade-in.
            // The content is hard-clipped to the same NotchShape used for the
            // black silhouette so thumbnails / tiles can never paint outside
            // the rounded body (otherwise on taller presets the bottom rows
            // would visibly stick out past the rounded corners and look like
            // they had been "cut").
            if state == .expanded {
                content
                    // TOP alignment (FB4): if the content is ever taller than
                    // this window, the overflow must fall off the BOTTOM, never
                    // bleed up into the notch strip / tab row and get clipped by
                    // the screen top. The to-do view caps + scrolls its own body,
                    // so this is a belt-and-suspenders guard.
                    .frame(width: expandedSize.width - 32,
                           height: expandedSize.height + extraExpandedHeight - notchSize.height - 8,
                           alignment: .top)
                    .padding(.top, notchSize.height + 4)
                    // The block-level treatment is now deliberately light —
                    // opacity plus a whisper of blur. The visible motion comes
                    // from the CHILDREN, each on its own staggered spring via
                    // `.notchEntry(index:)`. Scaling the whole slab was what
                    // made a tall card look pasted-in rather than assembled.
                    .opacity(contentVisible ? 1.0 : 0.0)
                    .blur(radius: contentVisible ? 0 : 2)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.1) : NotchAnimation.contentIn,
                        value: contentVisible
                    )
                    // Children read this to time their own entry against the
                    // silhouette's expansion.
                    .environment(\.notchContentAppeared, contentVisible)
                    .frame(width: currentWidth, height: currentHeight, alignment: .top)
                    .mask(
                        NotchShape(
                            bottomRadius: bottomCornerRadius,
                            filletRadius: currentFilletRadius
                        )
                        .frame(width: currentWidth, height: currentHeight)
                    )
                    // Content window + clip mask track the hugging silhouette
                    // on the same spring — otherwise the mask snaps and rows
                    // get visibly clipped mid-shrink (§8.4).
                    .animation(reduceMotion ? .easeInOut(duration: 0.15) : NotchAnimation.contentHug,
                               value: extraExpandedHeight)
            }

            // Notification content — icon in left wing, text in right wing
            // The physical notch (~notchSize.width) sits in the center of the 280pt pill,
            // so content must stay in the lateral wings to avoid the safe area.
            if state == .captureNotification, let notificationContent = notificationContent {
                let pillWidth: CGFloat = notificationWide ? 320 : notchSize.width + 80 + currentFilletRadius * 2
                let wingWidth = (pillWidth - notchSize.width) / 2 - currentFilletRadius
                notificationContent
                    .frame(width: pillWidth - currentFilletRadius * 2, height: notchSize.height - 4)
                    .padding(.top, 2)
                    .opacity(notificationContentVisible ? 1.0 : 0.0)
                    .scaleEffect(notificationContentVisible ? 1.0 : 0.9)
                    .blur(radius: notificationContentVisible ? 0 : 4)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.1) : NotchAnimation.notificationContentIn,
                        value: notificationContentVisible
                    )
                    .environment(\.notchWingWidth, wingWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Squish Animation (multi-phase spring sequence)
    //
    // Every phase runs inside ONE cancellable Task. When the state changes
    // mid-sequence the old task is cancelled, so late phases can never fire
    // on a notch that has already moved on — springs then blend from the
    // current (mid-flight) scale with preserved velocity.

    private func runSquishAnimation(for newState: NotchState) {
        squishTask?.cancel()
        squishTask = Task { @MainActor in
            switch newState {
            case .expanded:
                // Phase 1: anticipation squish (80ms)
                withAnimation(.spring(duration: 0.08, bounce: 0.0)) {
                    squishScaleX = 0.96
                    squishScaleY = 1.04
                }
                // Phase 2: overshoot
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                    squishScaleX = 1.02
                    squishScaleY = 0.99
                }
                // Phase 3: settle
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
                    squishScaleX = 1.0
                    squishScaleY = 1.0
                }

            case .idle:
                // Phase 1: micro expand
                withAnimation(.spring(duration: 0.12, bounce: 0.2)) {
                    squishScaleX = 1.02
                    squishScaleY = 0.98
                }
                // Phase 2: settle
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.28, bounce: 0.0)) {
                    squishScaleX = 1.0
                    squishScaleY = 1.0
                }

            case .hovering:
                // Micro breath
                withAnimation(.spring(duration: 0.22, bounce: 0.3)) {
                    squishScaleX = 1.0
                    squishScaleY = 1.0
                }

            case .captureNotification:
                // Horizontal stretch — pill widens
                withAnimation(.spring(duration: 0.12, bounce: 0.2)) {
                    squishScaleX = 1.03
                    squishScaleY = 0.97
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                    squishScaleX = 1.0
                    squishScaleY = 1.0
                }
            }
        }
    }
}
