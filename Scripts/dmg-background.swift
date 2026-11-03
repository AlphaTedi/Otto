// Draws the install window's background (Scripts/assets/dmg-background.tiff).
// The icon centres in Scripts/dmg-settings.py must match the arrow here.
//
//   swiftc -O Scripts/dmg-background.swift -o /tmp/dmgbg && /tmp/dmgbg bg.png bg@2x.png Otto/Resources/Fonts/HostGrotesk-VariableFont_wght.ttf
//   tiffutil -cathidpicheck bg.png bg@2x.png -out Scripts/assets/dmg-background.tiff
import AppKit
import CoreText

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
    // Headline in the site's face: Host Grotesk at 450, tracked in (-0.042 em).
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineHeightMultiple = 1.05
    let face = NSFontDescriptor(fontAttributes: [.family: "Host Grotesk",
                                                 .variation: [NSNumber(value: 0x77676874): 450]])
    let size: CGFloat = 24
    let title = NSAttributedString(string: "To install, drag Otto\ninto your Applications folder", attributes: [
        .font: NSFont(descriptor: face, size: size)!, .kern: -0.042 * size,
        .foregroundColor: c(0x1E1530), .paragraphStyle: para])
    title.draw(in: NSRect(x: 0, y: 292, width: 640, height: 70))
    // A hand-drawn arrow from Otto to Applications: it leaves the app's right
    // edge, makes one loop on the way, and lands on the folder's left edge.
    // Window points from the top left, as in dmg-settings.py (icons 112 wide,
    // centred at x 160 and 480, y 205).
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 400 - y) }
    let doodle = CGMutablePath()
    doodle.move(to: pt(226, 214))
    doodle.addCurve(to: pt(306, 186), control1: pt(256, 218), control2: pt(286, 206))
    doodle.addCurve(to: pt(300, 150), control1: pt(322, 170), control2: pt(318, 148))
    doodle.addCurve(to: pt(296, 198), control1: pt(280, 152), control2: pt(276, 182))
    doodle.addCurve(to: pt(412, 200), control1: pt(318, 216), control2: pt(368, 218))
    // The head: two strokes back from the tip, ±32° off the line's heading.
    let tip = CGPoint(x: 412, y: 200), from = CGPoint(x: 368, y: 218)
    let heading = atan2(tip.y - from.y, tip.x - from.x)
    for side in [-1.0, 1.0] {
        let a = heading + .pi - side * 0.56
        doodle.move(to: pt(tip.x + 13 * cos(a), tip.y + 13 * sin(a)))
        doodle.addLine(to: pt(tip.x, tip.y))
    }
    ctx.addPath(doodle)
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(3.2)
    ctx.setStrokeColor(c(0x5E46BA).cgColor)
    ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[3]) as CFURL, .process, nil)
render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
