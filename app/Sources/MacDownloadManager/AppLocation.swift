import AppKit
import DownloadCore

/// Where the app is running from. Browsers launch the helper inside the app by its path, so the app
/// must live in an Applications folder, not on the mounted .dmg or in macOS's temporary
/// "App Translocation" copy of a freshly downloaded app.
enum AppLocation {
    static var bundleURL: URL { Bundle.main.bundleURL.resolvingSymlinksInPath() }

    static var isInApplications: Bool {
        let path = bundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    /// Downloaded apps carry a quarantine flag that can stop the browser from starting the helper
    /// directly. The user has already chosen to open the app, so clear it from our own bundle.
    static func clearQuarantine(at url: URL = bundleURL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Copies the app into /Applications (or ~/Applications without permission), opens the copy and quits.
    static func moveToApplications() throws {
        let fileManager = FileManager.default
        var folder = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if !fileManager.isWritableFile(atPath: folder.path) {
            folder = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let target = folder.appendingPathComponent(bundleURL.lastPathComponent)
        if fileManager.fileExists(atPath: target.path) {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: Paths.appBundleID)
            where app.bundleURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath() {
                app.terminate()
            }
            try fileManager.trashItem(at: target, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: bundleURL, to: target)
        clearQuarantine(at: target)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
