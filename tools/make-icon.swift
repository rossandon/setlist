// Renders the app icon as a .iconset. Run via tools/make-icon.sh.
//
// The artwork is drawn in code rather than shipped as a binary asset so it
// stays diffable and can be tweaked without a design tool.
import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// Canvas is 1024pt; every size is rendered by scaling this drawing.
func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let s = size / 1024.0
    ctx.scaleBy(x: s, y: s)

    // Rounded-square plate, matching the macOS corner proportion.
    let plate = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904),
                             xRadius: 202, yRadius: 202)
    ctx.saveGState()
    plate.addClip()
    let bg = NSGradient(colors: [
        NSColor(srgbRed: 0.98, green: 0.71, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.87, green: 0.36, blue: 0.16, alpha: 1),
    ])!
    bg.draw(in: NSRect(x: 60, y: 60, width: 904, height: 904), angle: -90)
    ctx.restoreGState()

    let ink = NSColor(srgbRed: 0.16, green: 0.11, blue: 0.08, alpha: 1)
    let body = NSColor.white

    // Metronome case: a trapezoid standing on a plinth.
    let caseShape = NSBezierPath()
    caseShape.move(to: NSPoint(x: 248, y: 214))
    caseShape.line(to: NSPoint(x: 776, y: 214))
    caseShape.line(to: NSPoint(x: 608, y: 820))
    caseShape.line(to: NSPoint(x: 416, y: 820))
    caseShape.close()
    body.setFill()
    caseShape.fill()

    let plinth = NSBezierPath(roundedRect: NSRect(x: 232, y: 158, width: 560, height: 78),
                              xRadius: 30, yRadius: 30)
    plinth.fill()

    // Pendulum rod, pivoting from the top and leaning right.
    let pivot = NSPoint(x: 512, y: 800)
    let tip = NSPoint(x: 604, y: 286)
    let rod = NSBezierPath()
    rod.move(to: pivot)
    rod.line(to: tip)
    rod.lineWidth = 34
    rod.lineCapStyle = .round
    ink.setStroke()
    rod.stroke()

    // Sliding weight, squared to the rod's lean.
    let angle = atan2(tip.x - pivot.x, pivot.y - tip.y)
    let t: CGFloat = 0.44
    let center = NSPoint(x: pivot.x + (tip.x - pivot.x) * t,
                         y: pivot.y + (tip.y - pivot.y) * t)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -angle)
    let weight = NSBezierPath(roundedRect: NSRect(x: -100, y: -56, width: 200, height: 112),
                              xRadius: 24, yRadius: 24)
    ink.setFill()
    weight.fill()
    ctx.restoreGState()

    // Pivot cap.
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: pivot.x - 30, y: pivot.y - 30, width: 60, height: 60)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    let rep = draw(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(name)\n".utf8))
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
}
print("rendered \(variants.count) sizes into \(outputDir)")
