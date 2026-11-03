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
    // The site's hero gradient (ottotofive.com, .hero-bg), its light first
    // half only: peach at the top to lavender at the foot, so Finder's black
    // icon labels stay readable (Marcello, 2026-11-03: no bands, one gradient).
    NSGradient(colors: [c(0xFCF6F3), c(0xF8EAE6), c(0xEAD6EC), c(0xC7B0EE), c(0x9276E0)],
               atLocations: [0, 0.22, 0.45, 0.75, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: 0, width: 640, height: 400), angle: -90)
    // Headline.
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 2
    let title = NSAttributedString(string: "To install, drag Otto\ninto the Applications folder.", attributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
        .foregroundColor: c(0x1A1530), .paragraphStyle: para])
    title.draw(in: NSRect(x: 0, y: 290, width: 640, height: 60))
    // Three chevrons between the icons (centres at x 160 and 480, y 205 from the top).
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(5)
    for (i, alpha) in [0.28, 0.6, 1.0].enumerated() {
        let x = 288 + CGFloat(i) * 28, y = 400 - 196.0
        ctx.setStrokeColor(c(0x5E46BA, alpha).cgColor)
        ctx.move(to: CGPoint(x: x, y: y + 20)); ctx.addLine(to: CGPoint(x: x + 18, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y - 20)); ctx.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
