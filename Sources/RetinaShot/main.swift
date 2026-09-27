import AppKit
import Carbon.HIToolbox
import MenuHub
import ScreenCaptureKit
import ServiceManagement

let appName = "RetinaShot"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeys = HotKeys()
    private let preferences = ScreenshotPreferences()
    private var hub: MenuHub?
    private var session: SelectionSession?
    private var thumbnail: ThumbnailPanel?
    private var isCapturing = false
    private var prefetchedContent: SCShareableContent?
    private var permissionWatch: Timer?
    private var shortcuts: [UInt32] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--unregister-login") { // used by uninstall.sh
            try? SMAppService.mainApp.unregister()
            NSApp.terminate(nil)
            return
        }
        let symbol = NSImage(systemSymbolName: "viewfinder.rectangular", accessibilityDescription: nil) != nil
            ? "viewfinder.rectangular" : "viewfinder"
        hub = MenuHub(symbol: symbol) { self.section }
        // While the menu is open, Shift-Cmd-4 goes to its Capture Selection item instead, which closes the
        // menu first; the hot key would take the keystroke and hold it until the menu closed.
        hub?.onMenuOpen = { open in if open { self.releaseShortcuts() } else { self.registerShortcuts() } }

        registerShortcuts()
        if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
        if !ScreenRecording.isGranted { explainPermission() }
    }

    private func registerShortcuts() {
        guard shortcuts.isEmpty else { return }
        shortcuts = [cmdKey | shiftKey, cmdKey | shiftKey | controlKey].map { modifiers in
            hotKeys.register(kVK_ANSI_4, modifiers: modifiers) { [weak self] pressed in if pressed { self?.beginSelection() } }
        }
    }

    private func releaseShortcuts() {
        shortcuts.forEach(hotKeys.unregister)
        shortcuts = []
    }

    // MARK: Menu

    /// This app's part of the menu, read again whenever it may be shown, so every state it shows is current.
    private var section: MenuSection {
        let granted = ScreenRecording.isGranted
        return MenuSection(items: [
            .action("Capture Selection", key: "4", modifiers: [.shift, .command]) { self.afterMenuCloses { self.beginSelection() } },
            .action("Capture Window") {
                self.afterMenuCloses { self.capture(on: nil) { await Capture.window(preferences: self.preferences) } }
            },
            .separator,
            .action("Show Floating Thumbnail", isOn: preferences.showsThumbnail) { self.preferences.showsThumbnail.toggle() },
            .action("Open at Login", isOn: SMAppService.mainApp.status == .enabled) { self.toggleLogin() },
            granted ? .info("Screen Recording Allowed", isOn: true) : .action("Allow Screen Recording…") { self.explainPermission() },
            .alternate("Reset Screen Recording Permission…") { self.resetPermission() },
            .action("Reveal Screenshots in Finder") { NSWorkspace.shared.activateFileViewerSelecting([self.preferences.directory]) },
        ], isActive: granted)
    }

    private func toggleLogin() {
        do { try SMAppService.mainApp.status == .enabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register() }
        catch { NSApp.presentError(error) }
    }

    private func resetPermission() { ScreenRecording.reset(); relaunch() }

    /// Menu actions arrive as the menu starts fading; wait for it to leave the screen so it isn't captured.
    private func afterMenuCloses(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            work()
        }
    }

    // MARK: Capture

    private func beginSelection() {
        guard session == nil, !isCapturing else { return }
        guard ScreenRecording.isGranted else { explainPermission(); return }
        thumbnail?.dismiss()
        prefetchedContent = nil
        let prefetch = Task { prefetchedContent = try? await Capture.shareableContent() } // so the grab is instant on mouse-up
        session = SelectionSession(hotKeys: hotKeys) { [weak self] outcome in
            guard let self = self else { return }
            self.session = nil
            switch outcome {
            case .cancelled:
                prefetch.cancel()
            case .window:
                prefetch.cancel()
                self.capture(on: nil) { await Capture.window(preferences: self.preferences) }
            case .selected(let rect, let screen):
                self.capture(on: screen) {
                    await prefetch.value
                    let content: SCShareableContent
                    if let prefetched = self.prefetchedContent { content = prefetched } else { content = try await Capture.shareableContent() }
                    try await Task.sleep(nanoseconds: 30_000_000) // one frame for the overlay to leave the screen
                    return try await Capture.selection(rect, content: content, preferences: self.preferences)
                }
            }
        }
    }

    /// Runs a capture, then shows the thumbnail on `screen` (the display captured) or, for window
    /// captures, on the display under the pointer.
    private func capture(on screen: NSScreen?, _ work: @escaping @MainActor () async throws -> Screenshot?) {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                guard let shot = try await work() else { return }
                guard preferences.showsThumbnail,
                      let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
                else { return }
                thumbnail?.dismiss()
                thumbnail = ThumbnailPanel(shot, on: screen)
                thumbnail?.present()
            } catch {
                NSSound.beep()
                if (error as NSError).domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" { explainPermission() }
                else { presentError(error) }
            }
        }
    }

    // MARK: Permission

    private func explainPermission() {
        hub?.update() // fades the icon, if the permission was just found missing
        ScreenRecording.request()
        let alert = NSAlert()
        alert.messageText = "\(appName) needs Screen Recording permission"
        alert.informativeText = """
            Every app that captures the screen needs this; only Apple’s own shortcuts are exempt.

            Turn on \(appName) under Privacy & Security › Screen & System Audio Recording. It will relaunch itself once enabled.

            If the switch is already on, macOS is holding an entry from an earlier build: choose Reset, then turn it on again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: ScreenRecording.openSettings(); watchForPermission()
        case .alertSecondButtonReturn: resetPermission()
        default: watchForPermission()
        }
    }

    private func watchForPermission() {
        permissionWatch?.invalidate()
        permissionWatch = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard ScreenRecording.isGranted else { return }
            timer.invalidate()
            Task { @MainActor in self?.relaunch() }
        }
    }

    private func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 0.6; /usr/bin/open -a \"\(Bundle.main.bundlePath)\""]
        try? shell.run()
        NSApp.terminate(nil)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "\(appName) couldn’t take the screenshot"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
