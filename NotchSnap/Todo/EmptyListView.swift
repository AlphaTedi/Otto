import SwiftUI

// Empty state B, "Lista che dorme" (Marcello, 2026-09-26): a sleeping page
// with two z's rising off it, a title and one line. It replaces the old
// top-left one-line placeholder in every list and the Notes stream.
//
// It hugs: the block's natural height plus its 32pt padding IS the area
// between the field and the bar, so it is centred there without ever asking
// the panel for height it does not need (principle 2).
//
// Not interactive — no hover, no click, the caret stays in the field.

struct EmptyListView: View {
    /// The section's colour; the stroke follows it.
    let tint: Color
    /// The notch container's short variant: an 80×64 drawing.
    var compact = false
    /// False where the container has less than 180pt to give.
    var showsSubtitle = true
    var subtitleKey = "todo.emptySubtitle"
    /// Floating panels only: the list region's budget. That block is a fixed
    /// 556 with the pills pushed to its foot, so hugging left the page high
    /// with the slack all below it (Marcello, 2026-09-26). Filling the budget
    /// centres it between the capture header and the pills. Nil in the
    /// container, which hugs.
    var fillHeight: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            NappingPage(tint: tint, animated: !reduceMotion)
                .frame(width: compact ? 80 : 120, height: compact ? 64 : 96)
                .accessibilityHidden(true)
            Text(L10n.t("todo.emptyTitle"))
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.primary.opacity(0.92))
            if showsSubtitle {
                Text(L10n.t(subtitleKey))
                    .font(.system(size: 14))
                    // 1.5 line height on a 14pt face.
                    .lineSpacing(14 * 0.5)
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        // The container sits right on the panel's rounded foot and read as
        // cramped there, so it takes a deeper bottom margin — and sits 3pt
        // higher than even, which is where it looked centred (Marcello,
        // 2026-09-26).
        .padding(.top, compact ? 29 : 32)
        .padding(.bottom, compact ? 59 : 32)
        .frame(maxWidth: .infinity, minHeight: fillHeight)
        // The budget is 16pt short of the real gap in the floating panels
        // (it subtracts the container's top padding), and that 16 lands under
        // the region. Half of it is the geometric centre; 5 is the optical
        // one — the eye wants a centred block a touch high.
        .offset(y: fillHeight == nil ? 0 : 5)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("todo.emptyA11y") + " " + L10n.t(subtitleKey))
    }

    /// Comes in on the project's spring, leaves in 150ms — the new row takes
    /// its place.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96))
                .animation(Motion.contentHug),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }
}

/// The drawing, on the design's 120×96 artboard. The page breathes (1.0 ↔
/// 1.02 over 3s) and each z rises 6pt and fades on a 2.4s loop, the small one
/// 0.6s behind. Still under Reduce Motion.
private struct NappingPage: View {
    let tint: Color
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation) { context in
                frame(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(at: nil)
        }
    }

    private func frame(at time: TimeInterval?) -> some View {
        let breath = time.map { 1 + 0.01 * (1 - cos(2 * .pi * $0 / 3)) } ?? 1
        return GeometryReader { geo in
            let scale = min(geo.size.width / 120, geo.size.height / 96)
            ZStack {
                ArtboardPath(part: .page, scale: scale)
                    .stroke(tint, style: Self.stroke(2.2))
                    .scaleEffect(breath, anchor: UnitPoint(x: 56.0 / 120, y: 58.0 / 96))
                z(.bigZ, width: 2, opacity: 1, time: time, delay: 0, scale: scale)
                z(.smallZ, width: 1.6, opacity: 0.6, time: time, delay: 0.6, scale: scale)
            }
        }
    }

    private func z(_ part: ArtboardPath.Part, width: CGFloat, opacity: Double,
                   time: TimeInterval?, delay: TimeInterval, scale: CGFloat) -> some View {
        // p runs 0 → 1 eased; the z fades in at the bottom of its climb and
        // out at the top, so the loop's restart is never seen.
        let p = time.map { t -> Double in
            let raw = (t - delay).truncatingRemainder(dividingBy: 2.4) / 2.4
            let linear = raw < 0 ? raw + 1 : raw
            return linear * linear * (3 - 2 * linear)
        }
        return ArtboardPath(part: part, scale: scale)
            .stroke(tint, style: Self.stroke(width))
            .offset(y: -6 * (p ?? 0))
            .opacity(opacity * (p.map { sin(.pi * $0) } ?? 1))
    }

    private static func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// A path drawn in artboard units and scaled to the frame.
private struct ArtboardPath: Shape {
    enum Part { case page, bigZ, smallZ }

    let part: Part
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .page: Self.page(&path)
        case .bigZ: Self.bigZ(&path)
        case .smallZ: Self.smallZ(&path)
        }
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    // The approved SVG, point for point.
    private static func page(_ p: inout Path) {
        p.addRoundedRect(in: CGRect(x: 24, y: 30, width: 64, height: 56),
                         cornerSize: CGSize(width: 10, height: 10))
        p.move(to: CGPoint(x: 36, y: 50))                       // left eye, closed
        p.addQuadCurve(to: CGPoint(x: 48, y: 50), control: CGPoint(x: 42, y: 55))
        p.move(to: CGPoint(x: 64, y: 50))                       // right eye, closed
        p.addQuadCurve(to: CGPoint(x: 76, y: 50), control: CGPoint(x: 70, y: 55))
        p.move(to: CGPoint(x: 50, y: 70))                       // mouth
        p.addQuadCurve(to: CGPoint(x: 62, y: 70), control: CGPoint(x: 56, y: 67))
    }

    private static func bigZ(_ p: inout Path) {
        p.addLines([CGPoint(x: 88, y: 22), CGPoint(x: 98, y: 22),
                    CGPoint(x: 88, y: 34), CGPoint(x: 98, y: 34)])
    }

    private static func smallZ(_ p: inout Path) {
        p.addLines([CGPoint(x: 102, y: 6), CGPoint(x: 109, y: 6),
                    CGPoint(x: 102, y: 14), CGPoint(x: 109, y: 14)])
    }
}

#if DEBUG
struct EmptyListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EmptyListView(tint: SpaceTint.work.sectionColor)
                .frame(width: 657)
                .previewDisplayName("Floating panel")
            EmptyListView(tint: SpaceTint.grocery.sectionColor, compact: true)
                .frame(width: 440)
                .previewDisplayName("Notch container")
            EmptyListView(tint: SpaceTint.personal.sectionColor, compact: true, showsSubtitle: false)
                .frame(width: 440)
                .previewDisplayName("Notch container, short")
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
#endif
