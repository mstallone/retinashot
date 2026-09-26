import AppKit
import ScreenCaptureKit

struct Screenshot {
    let url: URL
    let image: NSImage   // sized in points, so `image.size` is what the built-in tool would report
}

enum CaptureError: LocalizedError {
    case noDisplay, crop, encode
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Couldn’t find the display under the selection."
        case .crop: return "Couldn’t crop the captured image."
        case .encode: return "Couldn’t encode the image."
        }
    }
}

enum Capture {
    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Selection at full Retina resolution: grab the whole display at its native pixel size, then crop.
    /// `rect` is in global CoreGraphics points (origin top-left of the main display).
    static func selection(_ rect: CGRect, content: SCShareableContent, preferences: ScreenshotPreferences) async throws -> Screenshot {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) else { throw CaptureError.noDisplay }
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        let pixelWidth = mode?.pixelWidth ?? Int(display.frame.width * 2)
        let pixelHeight = mode?.pixelHeight ?? Int(display.frame.height * 2)
        let scale = CGFloat(pixelWidth) / display.frame.width

        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.captureResolution = .best
        config.scalesToFit = false
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.displayP3 // what Apple's tool embeds on Apple displays
        let full = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: ownWindows), configuration: config)

        let local = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let pixels = CGRect(x: (local.minX * scale).rounded(), y: (local.minY * scale).rounded(),
                            width: (local.width * scale).rounded(), height: (local.height * scale).rounded())
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !pixels.isEmpty, let cropped = full.cropping(to: pixels) else { throw CaptureError.crop }

        let rep = NSBitmapImageRep(cgImage: cropped)
        rep.size = NSSize(width: pixels.width / scale, height: pixels.height / scale) // tags 144 dpi at 2x, like Apple
        let (_, type) = preferences.fileType
        let properties: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg ? [.compressionFactor: 0.9] : [:]
        guard let data = rep.representation(using: type, properties: properties) else { throw CaptureError.encode }
        let url = preferences.newFileURL()
        try data.write(to: url, options: .atomic)
        tagAsScreenshot(url, kind: "selection", globalRect: rect)
        return publish(rep, at: url)
    }

    /// Window capture, delegated to Apple's tool: its window path is unaffected by the macOS 27 bug, and its
    /// camera-cursor window picker is the one people know. Returns nil when the user presses Escape.
    static func window(preferences: ScreenshotPreferences) async -> Screenshot? {
        let url = preferences.newFileURL()
        var arguments = ["-i", "-w", "-x"] // interactive, windows only, no sound
        if !preferences.includesWindowShadow { arguments.append("-o") }
        arguments.append(url.path)
        await run("/usr/sbin/screencapture", arguments)
        guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { return nil }
        return publish(rep, at: url)
    }

    /// Puts the image on the clipboard as PNG and TIFF (what the built-in tool provides) and wraps it up.
    private static func publish(_ rep: NSBitmapImageRep, at url: URL) -> Screenshot {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pasteboard.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return Screenshot(url: url, image: image)
    }

    private static func run(_ executable: String, _ arguments: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
    }
}
