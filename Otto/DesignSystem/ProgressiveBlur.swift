import AppKit
import QuartzCore
import SwiftUI

// MARK: - ProgressiveBlur — a real variable-radius blur at the panel's foot
//
// Placed ABOVE the scrolling rows (the floating footer overlays the list), so
// the rows are what it blurs. The radius ramps from zero at the band's top to
// `maxRadius` at the window edge — sharp, then progressively softer, like the
// skiper41 reference and Marcello's Figma (2026-09-26).
//
// Why not NSVisualEffectView: its blur radius is constant; only its ALPHA can
// ramp. Half-transparent material over sharp rows reads as a fade, not a blur
// — which is exactly what shipped and was rejected (2026-09-26, screenshot:
// "c'è solo una sfumatura"). A variable radius needs Core Animation's
// `CABackdropLayer` + `variableBlur` filter. Both are private, so both are
// looked up by name; if either is missing the view falls back to the masked
// material rather than drawing nothing.
//
// The view's own layer carries the lower-corner mask, which also clips the
// backdrop sample, so the blur can never leave the rounded window.
struct ProgressiveBlur: NSViewRepresentable {
    var cornerRadius: CGFloat = 24
    /// Radius at the window edge.
    var maxRadius: CGFloat = 14

    func makeNSView(context: Context) -> ProgressiveBlurView { ProgressiveBlurView() }

    func updateNSView(_ view: ProgressiveBlurView, context: Context) {
        view.cornerRadius = cornerRadius
        view.maxRadius = maxRadius
    }
}

final class ProgressiveBlurView: NSView {
    var cornerRadius: CGFloat = 24 { didSet { needsLayout = true } }
    var maxRadius: CGFloat = 14 {
        didSet {
            guard maxRadius != oldValue else { return }
            filter?.setValue(maxRadius, forKey: "inputRadius")
            applyFilter()
        }
    }

    private var backdrop: CALayer?
    private var filter: NSObject?
    /// Only when the private blur is unavailable.
    private var fallback: NSVisualEffectView?
    private let tint = CAGradientLayer()
    private let cornerMask = CAShapeLayer()
    private var rampSize = NSSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.mask = cornerMask

        if let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
           let made = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur"),
           let filter = made.takeUnretainedValue() as? NSObject {
            filter.setValue(maxRadius, forKey: "inputRadius")
            filter.setValue(true, forKey: "inputNormalizeEdges")
            let backdrop = backdropClass.init()
            backdrop.actions = ["bounds": NSNull(), "position": NSNull(), "filters": NSNull()]
            layer?.addSublayer(backdrop)
            self.backdrop = backdrop
            self.filter = filter
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            addSubview(effect)
            fallback = effect
        }
        // A whisper of the panel's ground toward the foot, so the pills read
        // as sitting on a layer rather than directly on the blurred rows.
        tint.actions = ["bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(tint)
        updateTint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    /// Decoration only: clicks and scroll gestures reach the controls below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTint()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backdrop?.setValue(window?.backingScaleFactor ?? 2, forKey: "scale")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop?.frame = bounds
        fallback?.frame = bounds
        tint.frame = bounds

        let width = bounds.width
        let height = bounds.height
        let radius = min(cornerRadius, width / 2, height)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width, y: radius))
        path.addQuadCurve(to: CGPoint(x: width - radius, y: 0), control: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        cornerMask.frame = bounds
        cornerMask.path = path
        CATransaction.commit()

        if bounds.size != rampSize {
            rampSize = bounds.size
            rebuildRamp()
        }
    }

    private func updateTint() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor.white
        // Layer y is up: startPoint 0 is the foot.
        tint.colors = [color.withAlphaComponent(dark ? 0.28 : 0.30).cgColor,
                       color.withAlphaComponent(0).cgColor]
        tint.startPoint = CGPoint(x: 0.5, y: 0)
        tint.endPoint = CGPoint(x: 0.5, y: 1)
    }

    /// Zero at the band's top, full at the foot, smoothstepped so there is no
    /// visible knee where the blur begins. CG draws y-up and the layer is not
    /// flipped, so context row 0 is the view's bottom.
    private func rebuildRamp() {
        let height = max(1, Int(bounds.height.rounded(.up)))
        let width = fallback == nil ? 1 : max(1, Int(bounds.width.rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
        for row in 0..<height {
            let t = 1 - (CGFloat(row) + 0.5) / CGFloat(height)
            // Eased in: the filter's radius already climbs fast off a small
            // mask value, so a linear or smoothstep ramp showed a visible
            // "blur starts here" edge a few points into the band.
            context.setFillColor(CGColor(gray: 0, alpha: t * t))
            context.fill(CGRect(x: 0, y: row, width: width, height: 1))
        }
        guard let image = context.makeImage() else { return }
        if let fallback {
            fallback.maskImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))
        } else {
            filter?.setValue(image, forKey: "inputMaskImage")
            applyFilter()
        }
    }

    /// Filters are value-copied into the layer, so every change re-assigns.
    private func applyFilter() {
        guard let backdrop, let filter else { return }
        backdrop.filters = [filter]
    }
}
