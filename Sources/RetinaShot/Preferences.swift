import AppKit

/// Reads Apple's own screenshot settings (Screenshot app › Options, and `defaults write com.apple.screencapture`),
/// so RetinaShot saves exactly where, and how, the built-in tool would.
struct ScreenshotPreferences {
    private let defaults = UserDefaults(suiteName: "com.apple.screencapture")

    var directory: URL {
        if let raw = defaults?.string(forKey: "location") {
            let path = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    var baseName: String { defaults?.string(forKey: "name") ?? "Screenshot" }
    var includesDate: Bool { bool("include-date", default: true) }
    var includesWindowShadow: Bool { !bool("disable-shadow", default: false) }

    var showsThumbnail: Bool {
        get { bool("show-thumbnail", default: true) }
        nonmutating set { defaults?.set(newValue, forKey: "show-thumbnail") }
    }

    var fileType: (ext: String, type: NSBitmapImageRep.FileType) {
        switch (defaults?.string(forKey: "type") ?? "png").lowercased() {
        case "jpg", "jpeg": return ("jpg", .jpeg)
        case "tiff", "tif": return ("tiff", .tiff)
        default: return ("png", .png)
        }
    }

    /// A fresh, non-colliding file URL named like Apple's: "Screenshot 2026-09-25 at 1.02.03 PM.png".
    func newFileURL() -> URL {
        var name = baseName
        if includesDate {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
            name += " " + f.string(from: Date())
        }
        let ext = fileType.ext
        var url = directory.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name) \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        (defaults?.object(forKey: key) as? Bool) ?? value
    }
}
