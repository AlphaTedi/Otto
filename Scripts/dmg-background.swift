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
    // A hand-drawn arrow from Otto to Applications: up off the app, one loop,
    // then over into the folder. Drawn in the reference doodle's own 800-unit
    // box, mirrored to point right, and placed between the icons.
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 232 + (800 - x - 20) * 0.228, y: 400 - (152 + (y - 110) * 0.17))
    }
    let doodle = CGMutablePath()
    doodle.move(to: pt(755, 730))
    doodle.addCurve(to: pt(600, 358), control1: pt(770, 560), control2: pt(720, 390))
    doodle.addCurve(to: pt(425, 490), control1: pt(480, 345), control2: pt(410, 420))
    doodle.addCurve(to: pt(600, 520), control1: pt(440, 560), control2: pt(540, 580))
    doodle.addCurve(to: pt(600, 320), control1: pt(650, 470), control2: pt(640, 380))
    doodle.addCurve(to: pt(25, 212), control1: pt(520, 190), control2: pt(250, 110))
    doodle.move(to: pt(75, 115)); doodle.addLine(to: pt(25, 212)); doodle.addLine(to: pt(115, 240))
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
