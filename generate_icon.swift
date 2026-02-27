import Cocoa
import Foundation

func createIconImage(size: Int) -> Data? {
    let s = CGFloat(size)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // Background
    let blue = CGColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0)
    cg.setFillColor(blue)
    cg.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
    cg.fillPath()

    // Clipboard body
    let bodyW = s * 0.52, bodyH = s * 0.56
    let bodyX = (s - bodyW) / 2, bodyY = s * 0.11
    let bodyR = s * 0.04
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    cg.addPath(CGPath(roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
                       cornerWidth: bodyR, cornerHeight: bodyR, transform: nil))
    cg.fillPath()

    // Clip
    let clipW = s * 0.22, clipH = s * 0.13
    let clipX = (s - clipW) / 2, clipY = bodyY + bodyH - clipH * 0.45
    let clipR = s * 0.035
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    cg.addPath(CGPath(roundedRect: CGRect(x: clipX, y: clipY, width: clipW, height: clipH),
                       cornerWidth: clipR, cornerHeight: clipR, transform: nil))
    cg.fillPath()

    // Clip inner hole
    let holeW = s * 0.10, holeH = s * 0.045
    let holeX = (s - holeW) / 2, holeY = clipY + (clipH - holeH) / 2
    cg.setFillColor(blue)
    cg.addPath(CGPath(roundedRect: CGRect(x: holeX, y: holeY, width: holeW, height: holeH),
                       cornerWidth: holeH / 2, cornerHeight: holeH / 2, transform: nil))
    cg.fillPath()

    // Text lines
    let lineH = max(s * 0.028, 1)
    let lineX = bodyX + bodyW * 0.14
    let lineR = lineH / 2
    cg.setFillColor(CGColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.22))

    let lines: [(yFrac: CGFloat, wFrac: CGFloat)] = [
        (0.57, 0.72), (0.42, 0.50), (0.27, 0.62)
    ]
    for line in lines {
        let ly = bodyY + bodyH * line.yFrac
        let lw = bodyW * line.wFrac
        cg.addPath(CGPath(roundedRect: CGRect(x: lineX, y: ly, width: lw, height: lineH),
                           cornerWidth: lineR, cornerHeight: lineR, transform: nil))
        cg.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// Generate iconset
let iconsetPath = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    if let data = createIconImage(size: size) {
        try? data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
    }
}
print("Icon images generated.")
