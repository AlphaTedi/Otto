// Draws the install window's background (Scripts/assets/dmg-background.tiff).
// The icon centres in Scripts/dmg-settings.py must match the chevrons here.
//
//   swiftc -O Scripts/dmg-background.swift -o /tmp/dmgbg && /tmp/dmgbg bg.png bg@2x.png
//   tiffutil -cathidpicheck bg.png bg@2x.png -out Scripts/assets/dmg-background.tiff
import AppKit

// 640×400 points; drawn at 1x and 2x.
func render(scale: CGFloat, to path: String) {
    let w = 640 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 640, height: 400)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: a)
    }
    // Ground: near-white lavender, cooler toward the foot.
    NSGradient(colors: [c(0xFBFAFF), c(0xEEEBFF)])!.draw(in: NSRect(x: 0, y: 0, width: 640, height: 400), angle: -90)
    // Two soft bands in the icon's blues, sweeping up from the lower left.
    func band(_ y0: CGFloat, _ y1: CGFloat, _ colors: [NSColor]) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: 0))
        p.line(to: NSPoint(x: 0, y: y0))
        p.curve(to: NSPoint(x: 640, y: y1), controlPoint1: NSPoint(x: 220, y: y0 - 150),
                controlPoint2: NSPoint(x: 430, y: y1 - 40))
        p.line(to: NSPoint(x: 640, y: 0))
        p.close()
        NSGradient(colors: colors)!.draw(in: p, angle: 0)
    }
    band(190, 70, [c(0xC9C2FF, 0.55), c(0xA9B8FF, 0.35)])
    band(120, 34, [c(0x5B57E8, 0.55), c(0x3C5BDB, 0.40)])
    // Headline.
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 2
    let title = NSAttributedString(string: "To install, drag Otto\ninto the Applications folder.", attributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
        .foregroundColor: c(0x1C1A4A), .paragraphStyle: para])
    title.draw(in: NSRect(x: 0, y: 290, width: 640, height: 60))
    // Three chevrons between the icons (centres at x 160 and 480, y 205 from the top).
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(5)
    for (i, alpha) in [0.28, 0.6, 1.0].enumerated() {
        let x = 288 + CGFloat(i) * 28, y = 400 - 196.0
        ctx.setStrokeColor(c(0x5B57E8, alpha).cgColor)
        ctx.move(to: CGPoint(x: x, y: y + 20)); ctx.addLine(to: CGPoint(x: x + 18, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y - 20)); ctx.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
