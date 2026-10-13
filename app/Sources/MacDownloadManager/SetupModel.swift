import AppKit
import DownloadCore

@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var locations: [Tool: ToolLocation] = [:]
    @Published private(set) var installing: Tool?
    @Published private(set) var installProgress: Double = 0
    @Published var toolError: String?
    @Published private(set) var registeredBrowsers: [String] = []
    @Published private(set) var extensionFolder: URL?
    @Published private(set) var extensionLastSeen: Date?

    private var timer: Timer?

    static let chromeBundleIDs = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.chromium.Chromium"]

    private var prepared = false

    /// Runs once per launch; everything here is safe to repeat.
    func prepareOnce() {
        guard !prepared else { return }
        prepared = true
        registeredBrowsers = BrowserSetup.registerWithBrowsers()
        extensionFolder = BrowserSetup.installBundledExtension()
        Tools.updateYtDlpIfNeeded()
        refresh()
    }

    func refresh() {
        var found: [Tool: ToolLocation] = [:]
        for tool in Tool.allCases { found[tool] = Tools.locate(tool) }
        locations = found
        extensionLastSeen = BrowserSetup.extensionLastSeen
    }

    var missingRequired: [Tool] { Tool.allCases.filter { $0.isRequired && locations[$0] == nil } }
    var toolsReady: Bool { missingRequired.isEmpty }
    var extensionConnected: Bool { extensionLastSeen != nil }
    var needsSetup: Bool { !toolsReady || !AppSettings.setupCompleted }

    func startWatching() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.extensionLastSeen = BrowserSetup.extensionLastSeen }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func installMissingTools() async {
        toolError = nil
        for tool in missingRequired where tool.canInstallFromApp {
            installing = tool
            installProgress = 0
            do {
                try await Tools.install(tool) { value in
                    Task { @MainActor in self.installProgress = value }
                }
            } catch {
                toolError = "\(tool.title): \(error.localizedDescription)"
                break
            }
        }
        installing = nil
        refresh()
    }

    func registerAgain() {
        registeredBrowsers = BrowserSetup.registerWithBrowsers()
    }

    func revealExtensionFolder() {
        if extensionFolder == nil { extensionFolder = BrowserSetup.installBundledExtension() }
        guard let folder = extensionFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func copyExtensionPath() {
        guard let folder = extensionFolder else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder.path, forType: .string)
    }

    /// Browsers don't let other apps open chrome:// pages, so copy the address and bring the browser forward.
    func openExtensionsPage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("chrome://extensions", forType: .string)
        let browser = Self.chromeBundleIDs.lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
        if let browser {
            NSWorkspace.shared.openApplication(at: browser, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func finish() {
        AppSettings.setupCompleted = true
    }
}
