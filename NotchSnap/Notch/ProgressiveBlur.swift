import AppKit
import QuartzCore
import SwiftUI

// MARK: - ProgressiveBlur — a real variable-radius blur at a scroll edge
//
// What the list's foot had was a gradient: the rows faded out, and the one
// material ever tried there blurred at a single radius with only its AMOUNT
// ramped — which reads as a tint, not as blur (see TodoScrollEdgeEffect).
// Marcello asked for a progressive blur (2026-09-26, the skiper41 reference):
// sharp where the band begins, more and more blurred toward the pills.
//
// AppKit has no public variable blur. Core Animation does — `CABackdropLayer`
// with the `variableBlur` filter, whose radius follows a mask image — and
// it is what the system itself uses for this. Both are private, so both are
// looked up by name and the view simply draws nothing if either is missing:
// the list's own gradient fade stays underneath as the floor.
//
// Checked on this Mac (macOS 15.7, Intel) before it went in: `filterTypes`
// lists `variableBlur`, and an off-screen CARenderer pass of rows under the
// layer came out blurred along the ramp, with transparent areas left
// transparent — it blurs what is behind it, and adds no ground of its own.

struct ProgressiveBlur: NSViewRepresentable {
    /// Where the blur is strongest.
    var edge: VerticalEdge = .bottom
    /// Radius at the strongest end.
    var maxRadius: CGFloat = 8

    func makeNSView(context: Context) -> ProgressiveBlurView { ProgressiveBlurView() }

    func updateNSView(_ view: ProgressiveBlurView, context: Context) {
        view.edge = edge
        view.maxRadius = maxRadius
    }
}

final class ProgressiveBlurView: NSView {
    var edge: VerticalEdge = .bottom { didSet { if edge != oldValue { rebuildMask() } } }
    var maxRadius: CGFloat = 8 { didSet { filter?.setValue(maxRadius, forKey: "inputRadius"); applyFilter() } }

    private var backdrop: CALayer?
    private var filter: NSObject?
    private var maskHeight = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              let made = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur"),
              let filter = made.takeUnretainedValue() as? NSObject else { return }
        filter.setValue(maxRadius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        let backdrop = backdropClass.init()
        backdrop.actions = ["bounds": NSNull(), "position": NSNull(), "filters": NSNull()]
        layer?.addSublayer(backdrop)
        self.backdrop = backdrop
        self.filter = filter
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    /// Decoration: clicks and scrolls belong to the list under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        backdrop?.frame = bounds
        if Int(bounds.height) != maskHeight { rebuildMask() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backdrop?.setValue(window?.backingScaleFactor ?? 2, forKey: "scale")
    }

    /// The radius ramp: zero at the far end, full at `edge`, eased so there
    /// is no knee where the blur visibly starts.
    private func rebuildMask() {
        let height = max(1, Int(bounds.height.rounded(.up)))
        maskHeight = Int(bounds.height)
        guard let context = CGContext(data: nil, width: 1, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
        // CG draws y-up and the layer is not flipped, so row 0 of the context
        // is the view's bottom.
        for row in 0..<height {
            let fromBottom = (CGFloat(row) + 0.5) / CGFloat(height)
            let t = edge == .bottom ? 1 - fromBottom : fromBottom
            let alpha = t * t * (3 - 2 * t)            // smoothstep
            context.setFillColor(CGColor(gray: 0, alpha: alpha))
            context.fill(CGRect(x: 0, y: row, width: 1, height: 1))
        }
        filter?.setValue(context.makeImage(), forKey: "inputMaskImage")
        applyFilter()
    }

    /// Filters are value-copied into the layer, so every change re-assigns.
    private func applyFilter() {
        guard let backdrop, let filter else { return }
        backdrop.filters = [filter]
    }
}
