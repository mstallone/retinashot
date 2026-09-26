import AppKit
import CoreServices

// Two private-but-long-stable system calls that make RetinaShot behave like the built-in screenshot tool.
// Each is wrapped so a future macOS that stops honoring it degrades gracefully instead of failing.

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: UInt32, _ owner: UInt32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// Shows the crosshair while another app stays active, so the selection never steals focus (or window
/// shadows) from whatever you are working in. The window server does not keep the permission reliably,
/// so it is re-granted on every call rather than once at launch.
func showCrosshairInBackground() {
    let cid = CGSMainConnectionID()
    _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    NSCursor.crosshair.set()
}

@_silgen_name("MDItemSetAttribute")
private func MDItemSetAttribute(_ item: MDItem, _ name: CFString, _ value: CFTypeRef?) -> DarwinBoolean

/// Tags a file the way Apple's screencapture does, so Finder, Spotlight and Photos treat it as a screenshot.
func tagAsScreenshot(_ url: URL, kind: String, globalRect: CGRect?) {
    guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return }
    _ = MDItemSetAttribute(item, "kMDItemIsScreenCapture" as CFString, kCFBooleanTrue)
    _ = MDItemSetAttribute(item, "kMDItemScreenCaptureType" as CFString, kind as CFString)
    if let r = globalRect {
        _ = MDItemSetAttribute(item, "kMDItemScreenCaptureGlobalRect" as CFString,
                               [r.minX, r.minY, r.width, r.height].map { Int($0) } as CFArray)
    }
}
