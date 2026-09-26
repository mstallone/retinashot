// Renders the README illustrations from synthetic content, so nothing personal ends up in the repo.
//   make-readme-assets <output dir>
// Produces comparison.png (built-in 1x vs RetinaShot 2x of the same mock window) and overlay.png
// (a selection in progress).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let cream = NSColor(srgbRed: 0xF3 / 255, green: 0xED / 255, blue: 0xE0 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x24 / 255, green: 0x22 / 255, blue: 0x1F / 255, alpha: 1)
let terracotta = NSColor(srgbRed: 0xD0 / 255, green: 0x76 / 255, blue: 0x39 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xFA / 255, green: 0xF7 / 255, blue: 0xF0 / 255, alpha: 1)

/// Draws into a bitmap at `scale` pixels per point and returns the rep.
func bitmap(points: NSSize, scale: CGFloat, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(points.width * scale), pixelsHigh: Int(points.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = points
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(origin: .zero, size: points))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func text(_ s: String, _ size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink, mono: Bool = false) -> NSAttributedString {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
}

/// A small mock document window with the kind of fine detail that shows the 1x/2x difference.
func drawMockWindow(in r: NSRect) {
    NSColor.white.setFill()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
    NSColor(white: 0.85, alpha: 1).setStroke()
    NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()
    let titleBar = NSRect(x: r.minX, y: r.maxY - 38, width: r.width, height: 38)
    NSColor(white: 0.96, alpha: 1).setFill()
    let bar = NSBezierPath(roundedRect: titleBar, xRadius: 10, yRadius: 10); bar.appendRect(NSRect(x: r.minX, y: titleBar.minY, width: r.width, height: 10)); bar.fill()
    for (i, c) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)].enumerated() {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX + 14 + CGFloat(i) * 20, y: titleBar.midY - 6, width: 12, height: 12)).fill()
    }
    text("Untitled.txt", 13, weight: .semibold, color: NSColor(white: 0.25, alpha: 1)).draw(at: NSPoint(x: r.midX - 40, y: titleBar.midY - 8))
    var y = titleBar.minY - 34
    for line in ["The quick brown fox jumps over the lazy dog.", "Retina text is crisp at 2 pixels per point;", "at 1 pixel per point the strokes smear together.", "", "let scale = pixelWidth / pointWidth   // 2.0"] {
        text(line, 13, color: NSColor(white: 0.15, alpha: 1), mono: line.hasPrefix("let")).draw(at: NSPoint(x: r.minX + 18, y: y))
        y -= 22
    }
    let button = NSRect(x: r.maxX - 96, y: r.minY + 14, width: 80, height: 26)
    terracotta.setFill(); NSBezierPath(roundedRect: button, xRadius: 6, yRadius: 6).fill()
    text("Save", 13, weight: .medium, color: .white).draw(at: NSPoint(x: button.midX - 15, y: button.midY - 8))
}

// 1. comparison.png: the same window captured by the macOS 27 built-in tool (1x) and by RetinaShot (2x),
//    both shown at the same physical size so the difference is what you'd see on a Retina display.
let windowSize = NSSize(width: 360, height: 230)
let sharp = bitmap(points: windowSize, scale: 2) { drawMockWindow(in: $0.insetBy(dx: 1, dy: 1)) }
let soft1x = bitmap(points: windowSize, scale: 1) { drawMockWindow(in: $0.insetBy(dx: 1, dy: 1)) }
let comparison = bitmap(points: NSSize(width: 800, height: 470), scale: 2) { r in
    cream.setFill(); r.fill()
    for (i, (rep, label, note)) in [(soft1x, "macOS 27 Shift-Cmd-4", "360 × 230 px  ·  1 pixel per point"),
                                    (sharp, "RetinaShot", "720 × 460 px  ·  2 pixels per point")].enumerated() {
        let x = 24 + CGFloat(i) * 392
        let frame = NSRect(x: x, y: 200, width: 360, height: 230)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -4); shadow.set()
        NSColor.white.setFill(); NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = i == 0 ? .none : .high
        let image = NSImage(size: windowSize); image.addRepresentation(rep)
        image.draw(in: frame)
        text(label, 15, weight: .semibold).draw(at: NSPoint(x: x, y: 444))
        // Loupe: the word "crisp" magnified 4x, pixel for pixel.
        let source = NSRect(x: 92, y: 132, width: 90, height: 24)           // "crisp at 2 pi", in window points
        let loupe = NSRect(x: x, y: 40, width: 360, height: 96)
        NSColor.white.setFill(); NSBezierPath(roundedRect: loupe, xRadius: 8, yRadius: 8).fill()
        NSColor(white: 0.8, alpha: 1).setStroke(); NSBezierPath(roundedRect: loupe.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: loupe, xRadius: 8, yRadius: 8).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: loupe, from: source, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        text(note, 12, color: NSColor(white: 0.45, alpha: 1), mono: true).draw(at: NSPoint(x: x, y: 14))
        text("4× loupe", 11, weight: .medium, color: NSColor(white: 0.45, alpha: 1)).draw(at: NSPoint(x: x, y: 142))
    }
}
write(comparison, "comparison.png")

// 2. overlay.png: what the selection looks like mid-drag, drawn with the app's badge styling.
let overlay = bitmap(points: NSSize(width: 800, height: 360), scale: 2) { r in
    cream.setFill(); r.fill()
    drawMockWindow(in: NSRect(x: 120, y: 40, width: 560, height: 290))
    let sel = NSRect(x: 128, y: 150, width: 380, height: 132)
    NSColor(white: 1, alpha: 0.10).setFill(); sel.fill()
    NSColor(white: 0, alpha: 0.55).setStroke(); NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5)).stroke()
    NSColor.white.setStroke(); NSBezierPath(rect: sel.insetBy(dx: 0.5, dy: 0.5)).stroke()
    // Crosshair at the drag point.
    let c = NSPoint(x: sel.maxX, y: sel.minY)
    ink.setStroke()
    let cross = NSBezierPath(); cross.lineWidth = 1.5
    cross.move(to: NSPoint(x: c.x - 9, y: c.y)); cross.line(to: NSPoint(x: c.x + 9, y: c.y))
    cross.move(to: NSPoint(x: c.x, y: c.y - 9)); cross.line(to: NSPoint(x: c.x, y: c.y + 9)); cross.stroke()
    // Size badge, exactly as SelectionView draws it.
    let label = "\(Int(sel.width)) × \(Int(sel.height))" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
    let size = label.size(withAttributes: attrs)
    let box = NSRect(x: sel.maxX - 4 - size.width - 12, y: sel.minY - 4 - size.height - 6, width: size.width + 12, height: size.height + 6)
    NSColor(white: 0.1, alpha: 0.85).setFill(); NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
    label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    text("Drag to select. Space moves it, Shift locks an axis, Option grows from the center, Esc cancels.", 12, color: NSColor(white: 0.4, alpha: 1)).draw(at: NSPoint(x: 120, y: 12))
}
write(overlay, "overlay.png")

print("wrote comparison.png, overlay.png to \(out.path)")
