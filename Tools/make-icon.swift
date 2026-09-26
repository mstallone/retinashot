// Renders the app icon (a viewfinder on a blue-to-indigo gradient) into an .iconset directory.
// Usage: make-icon <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: px, height: px))
    image.lockFocus()
    let inset = px * 0.10                                  // Apple's icon grid: artwork fills ~80% of the canvas
    let square = NSRect(x: inset, y: inset, width: px - 2 * inset, height: px - 2 * inset)
    let plate = NSBezierPath(roundedRect: square, xRadius: square.width * 0.225, yRadius: square.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.53, blue: 1.00, alpha: 1),
                        NSColor(srgbRed: 0.31, green: 0.24, blue: 0.93, alpha: 1)])!
        .draw(in: plate, angle: -60)

    // Four corner brackets.
    let stroke = square.width * 0.075
    let reach = square.width * 0.20
    let edge = square.insetBy(dx: square.width * 0.22, dy: square.width * 0.22)
    let brackets = NSBezierPath()
    brackets.lineWidth = stroke
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    for (x, dx) in [(edge.minX, 1.0), (edge.maxX, -1.0)] {
        for (y, dy) in [(edge.minY, 1.0), (edge.maxY, -1.0)] {
            brackets.move(to: NSPoint(x: x + dx * reach, y: y))
            brackets.line(to: NSPoint(x: x, y: y))
            brackets.line(to: NSPoint(x: x, y: y + dy * reach))
        }
    }
    NSColor.white.withAlphaComponent(0.96).setStroke()
    brackets.stroke()

    // Center mark.
    let dot = NSBezierPath(ovalIn: NSRect(x: square.midX - stroke * 0.7, y: square.midY - stroke * 0.7, width: stroke * 1.4, height: stroke * 1.4))
    NSColor.white.setFill()
    dot.fill()
    image.unlockFocus()
    return image
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(size * scale)
        let image = render(px)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
