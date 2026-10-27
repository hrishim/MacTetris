import AppKit

// Renders Tetris.app icon: dark squircle + tetromino stack, at all iconset sizes.
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)

    // squircle-ish rounded background with vertical gradient
    let radius = s * 0.225
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(srgbRed: 0.10, green: 0.13, blue: 0.24, alpha: 1).cgColor,
                                   NSColor(srgbRed: 0.03, green: 0.05, blue: 0.10, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // tetromino grid: 3 cols x 3 rows centered, cell = 26% of icon
    let cell = s * 0.26
    let gx = (s - cell * 3) / 2, gy = (s - cell * 3) / 2 - s * 0.02
    func block(_ col: Int, _ row: Int, _ color: NSColor) {
        // row 0 = top
        let x = gx + CGFloat(col) * cell
        let y = gy + (2 - CGFloat(row)) * cell
        let r = CGRect(x: x + cell*0.06, y: y + cell*0.06, width: cell*0.88, height: cell*0.88)
        color.setFill()
        let p = CGPath(roundedRect: r, cornerWidth: cell*0.14, cornerHeight: cell*0.14, transform: nil)
        ctx.addPath(p); ctx.fillPath()
        NSColor.white.withAlphaComponent(0.35).setFill()
        ctx.fill(CGRect(x: r.minX, y: r.maxY - cell*0.16, width: r.width, height: cell*0.16))
    }
    let purple = NSColor(srgbRed: 0.71, green: 0.42, blue: 0.94, alpha: 1)
    let green  = NSColor(srgbRed: 0.29, green: 0.87, blue: 0.50, alpha: 1)
    let yellow = NSColor(srgbRed: 0.96, green: 0.83, blue: 0.20, alpha: 1)
    let red    = NSColor(srgbRed: 0.94, green: 0.35, blue: 0.35, alpha: 1)
    let cyan   = NSColor(srgbRed: 0.24, green: 0.78, blue: 0.94, alpha: 1)
    let blue   = NSColor(srgbRed: 0.35, green: 0.48, blue: 0.94, alpha: 1)
    block(1, 0, purple)               // T top
    block(0, 1, green); block(1, 1, yellow); block(2, 1, yellow)  // S + O
    block(0, 2, red); block(1, 2, cyan); block(2, 2, cyan)        // Z + I
    // floating J above-left, subtle
    ctx.setAlpha(0.85); block(0, 0, blue)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try! render(px).write(to: url)
    print("wrote \(url.lastPathComponent) (\(px)px)")
}
