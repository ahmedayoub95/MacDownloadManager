import Foundation

/// Preferences shared by the app and the detached download workers.
public enum AppSettings {
    // Not the app's own bundle ID: that domain can't be opened as a suite.
    static let defaults = UserDefaults(suiteName: "\(Paths.appBundleID).shared") ?? .standard
    static let downloadFolderKey = "downloadFolder"

    public static var downloadFolder: URL {
        get {
            guard let path = defaults.string(forKey: downloadFolderKey), !path.isEmpty else { return Paths.downloads }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            if newValue.standardizedFileURL == Paths.downloads.standardizedFileURL {
                defaults.removeObject(forKey: downloadFolderKey)
            } else {
                defaults.set(newValue.path, forKey: downloadFolderKey)
            }
        }
    }

    public static var isUsingDefaultFolder: Bool {
        defaults.string(forKey: downloadFolderKey) == nil
    }

    public static var setupCompleted: Bool {
        get { defaults.bool(forKey: "setupCompleted") }
        set { defaults.set(newValue, forKey: "setupCompleted") }
    }

    public static func resetDownloadFolder() {
        defaults.removeObject(forKey: downloadFolderKey)
    }
}
