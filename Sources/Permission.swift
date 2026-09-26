import AppKit

/// Screen Recording permission. Every app that reads screen pixels needs it; Apple's shortcuts skip it only
/// because they run inside the system.
enum ScreenRecording {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds the app to the Screen Recording list (and shows the system prompt the first time).
    static func request() { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// Clears this app's entry. Needed if the entry goes stale, e.g. after the app's code signature changes.
    static func reset() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? ""]
        try? p.run()
        p.waitUntilExit()
    }
}
