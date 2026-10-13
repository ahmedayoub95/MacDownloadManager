import Foundation

/// Connects the app to Chromium browsers (native messaging) and manages the bundled extension.
public enum BrowserSetup {
    public static let hostName = "com.ahmed.downloadmanager"
    /// Fixed by the "key" in the extension's manifest.json, so it is the same for every user.
    public static let extensionID = "pgfkdonjalnlcemopglppogdghdghigg"

    static let browsers: [(name: String, folder: String)] = [
        ("Google Chrome", "Google/Chrome"),
        ("Chrome Beta", "Google/Chrome Beta"),
        ("Chrome Canary", "Google/Chrome Canary"),
        ("Chromium", "Chromium"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Microsoft Edge", "Microsoft Edge"),
        ("Vivaldi", "Vivaldi"),
    ]

    static var applicationSupport: URL { Paths.home.appendingPathComponent("Library/Application Support", isDirectory: true) }
    static var lastSeenURL: URL { Paths.support.appendingPathComponent("extension-last-seen") }

    /// Writes the native messaging manifest for every installed browser. Returns the browsers registered.
    @discardableResult
    public static func registerWithBrowsers() -> [String] {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Mac Download Manager",
            "path": Downloads.workerExecutable,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes]) else {
            return []
        }
        var registered: [String] = []
        for browser in browsers {
            let profileRoot = applicationSupport.appendingPathComponent(browser.folder, isDirectory: true)
            guard Paths.fileManager.fileExists(atPath: profileRoot.path) else { continue }
            let folder = profileRoot.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            do {
                try Paths.fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("\(hostName).json"), options: .atomic)
                registered.append(browser.name)
            } catch {
                log("couldn't register with \(browser.name): \(error.localizedDescription)")
            }
        }
        return registered
    }

    /// Called by the browser helper whenever the extension talks to it.
    public static func markExtensionSeen() {
        try? Paths.fileManager.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? Data("\(Date().timeIntervalSince1970)".utf8).write(to: lastSeenURL, options: .atomic)
    }

    public static var extensionLastSeen: Date? {
        guard let text = try? String(contentsOf: lastSeenURL, encoding: .utf8), let seconds = Double(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Copies the extension out of the app bundle; Chrome's "Load unpacked" can't pick a folder inside an .app.
    /// Returns the folder to load, or nil if the app was built without the extension.
    @discardableResult
    public static func installBundledExtension() -> URL? {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("extension", isDirectory: true),
              Paths.fileManager.fileExists(atPath: bundled.appendingPathComponent("manifest.json").path) else {
            return nil
        }
        let target = Paths.bundledExtensionCopy
        if version(at: target) == version(at: bundled), version(at: target) != nil { return target }
        do {
            try Paths.fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Paths.fileManager.removeItem(at: target)
            try Paths.fileManager.copyItem(at: bundled, to: target)
            log("installed browser extension \(version(at: target) ?? "?") at \(target.path)")
            return target
        } catch {
            log("couldn't copy browser extension: \(error.localizedDescription)")
            return nil
        }
    }

    static func version(at folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return json["version"] as? String
    }
}
