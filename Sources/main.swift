import AppKit
import Carbon.HIToolbox
import ServiceManagement

let appName = "RetinaShot"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotKeys = HotKeys()
    private let preferences = ScreenshotPreferences()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var session: SelectionSession?
    private var thumbnail: ThumbnailPanel?
    private var isCapturing = false
    private var permissionWatch: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--unregister-login") { // used by uninstall.sh
            try? SMAppService.mainApp.unregister()
            NSApp.terminate(nil)
            return
        }
        enableCursorChangesInBackground()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder.rectangular", accessibilityDescription: appName)
            ?? NSImage(systemSymbolName: "viewfinder", accessibilityDescription: appName)
        menu.delegate = self
        item.menu = menu
        statusItem = item

        for modifiers in [cmdKey | shiftKey, cmdKey | shiftKey | controlKey] {
            hotKeys.register(kVK_ANSI_4, modifiers: modifiers) { [weak self] pressed in if pressed { self?.beginSelection() } }
        }
        if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
        if !ScreenRecording.isGranted { explainPermission() }
    }

    // MARK: Menu, rebuilt on open so every state it shows is current

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let capture = menu.addItem(withTitle: "Capture Selection", action: #selector(captureSelection), keyEquivalent: "4")
        capture.keyEquivalentModifierMask = [.shift, .command]
        menu.addItem(withTitle: "Capture Window", action: #selector(captureWindow), keyEquivalent: "")
        menu.addItem(.separator())

        let thumb = menu.addItem(withTitle: "Show Floating Thumbnail", action: #selector(toggleThumbnail), keyEquivalent: "")
        thumb.state = preferences.showsThumbnail ? .on : .off
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if ScreenRecording.isGranted {
            let granted = menu.addItem(withTitle: "Screen Recording Allowed", action: nil, keyEquivalent: "")
            granted.state = .on
        } else {
            menu.addItem(withTitle: "Allow Screen Recording…", action: #selector(showPermissionHelp), keyEquivalent: "")
        }
        let reset = menu.addItem(withTitle: "Reset Screen Recording Permission…", action: #selector(resetPermission), keyEquivalent: "")
        reset.isAlternate = true
        reset.keyEquivalentModifierMask = .option
        menu.addItem(withTitle: "Reveal Screenshots in Finder", action: #selector(revealFolder), keyEquivalent: "")
        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        menu.addItem(withTitle: "\(appName) \(version)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate), keyEquivalent: "q")
    }

    @objc private func captureSelection() { afterMenuCloses { self.beginSelection() } }
    @objc private func captureWindow() { afterMenuCloses { self.capture { await Capture.window(preferences: self.preferences) } } }
    @objc private func toggleThumbnail() { preferences.showsThumbnail.toggle() }
    @objc private func toggleLogin() {
        do { try SMAppService.mainApp.status == .enabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register() }
        catch { NSApp.presentError(error) }
    }
    @objc private func showPermissionHelp() { explainPermission() }
    @objc private func resetPermission() { ScreenRecording.reset(); relaunch() }
    @objc private func revealFolder() { NSWorkspace.shared.activateFileViewerSelecting([preferences.directory]) }

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
        let content = Task { try await Capture.shareableContent() } // starts now so the grab is instant on mouse-up
        session = SelectionSession(hotKeys: hotKeys) { [weak self] outcome in
            guard let self = self else { return }
            self.session = nil
            switch outcome {
            case .cancelled:
                content.cancel()
            case .window:
                content.cancel()
                self.capture { await Capture.window(preferences: self.preferences) }
            case .selected(let rect):
                self.capture {
                    let shareable = try await content.value
                    try await Task.sleep(nanoseconds: 30_000_000) // one frame for the overlay to leave the screen
                    return try await Capture.selection(rect, content: shareable, preferences: self.preferences)
                }
            }
        }
    }

    private func capture(_ work: @escaping () async throws -> Screenshot?) {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                guard let shot = try await work() else { return }
                guard preferences.showsThumbnail,
                      let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
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
