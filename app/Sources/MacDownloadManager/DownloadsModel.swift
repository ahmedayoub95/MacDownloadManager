import AppKit
import DownloadCore
import UserNotifications

enum Category: String, CaseIterable, Identifiable {
    case all, unfinished, finished, video, music, compressed, documents, programs, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Downloads"
        case .unfinished: "Unfinished"
        case .finished: "Finished"
        default: rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .unfinished: "arrow.down.circle"
        case .finished: "checkmark.circle"
        case .video: "film"
        case .music: "music.note"
        case .compressed: "doc.zipper"
        case .documents: "doc.text"
        case .programs: "app.badge"
        case .other: "doc"
        }
    }

    static let extensions: [Category: Set<String>] = [
        .video: ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp", "ts"],
        .music: ["mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "wma"],
        .compressed: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "iso", "img"],
        .documents: ["pdf", "epub", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "pages", "numbers", "key"],
        .programs: ["dmg", "pkg", "app", "exe", "msi", "apk"],
    ]

    static func of(_ job: JobStatus) -> Category {
        let ext = URL(fileURLWithPath: job.path ?? job.name).pathExtension.lowercased()
        if let match = extensions.first(where: { $0.value.contains(ext) })?.key { return match }
        if let kind = job.kind, kind != "file" { return .video }
        return .other
    }

    func contains(_ job: JobStatus) -> Bool {
        switch self {
        case .all: true
        case .unfinished: job.state != .done
        case .finished: job.state == .done
        default: Category.of(job) == self
        }
    }
}

@MainActor
final class DownloadsModel: ObservableObject {
    @Published private(set) var jobs: [JobStatus] = []
    @Published var showingAddURL = false
    @Published var errorMessage: String?

    private var timer: Timer?
    private var knownStates: [String: JobState] = [:]
    private var loadedOnce = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let list = JobStore.list()
            await MainActor.run { self.apply(list) }
        }
    }

    private func apply(_ list: [JobStatus]) {
        if loadedOnce {
            for job in list where knownStates[job.id] != job.state {
                if job.state == .done { notify("Download complete", job.name) }
                if job.state == .failed { notify("Download failed", job.error ?? job.name) }
            }
        }
        knownStates = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.state) })
        loadedOnce = true
        if list != jobs { jobs = list }
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func count(_ category: Category) -> Int {
        jobs.filter(category.contains).count
    }

    func jobs(in category: Category) -> [JobStatus] {
        jobs.filter(category.contains)
    }

    func selected(_ ids: Set<String>) -> [JobStatus] {
        jobs.filter { ids.contains($0.id) }
    }

    var totalSpeed: String {
        let bytes = jobs.filter { $0.state.isActive }.compactMap { $0.speed.flatMap(Self.parseRate) }.reduce(0, +)
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary) + "/s" : ""
    }

    /// "1.5MiB/s" -> bytes per second
    static func parseRate(_ text: String) -> Double? {
        let units: [String: Double] = ["B": 1, "KiB": 1024, "MiB": 1_048_576, "GiB": 1_073_741_824, "KB": 1000, "MB": 1e6, "GB": 1e9]
        let trimmed = text.replacingOccurrences(of: "/s", with: "").trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: { $0.isLetter }), let value = Double(trimmed[..<split]) else { return nil }
        return units[String(trimmed[split...])].map { value * $0 }
    }

    // MARK: - Actions

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func add(url: String, filename: String, isVideoPage: Bool, folder: URL) {
        perform {
            let request = DownloadRequest(
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: isVideoPage ? "page" : "file",
                source: "manual",
                filename: filename.isEmpty ? nil : filename,
                saveDir: folder.path
            )
            try Downloads.start(request)
        }
    }

    func pause(_ ids: Set<String>) {
        perform { selected(ids).filter { $0.state.isActive }.forEach { Downloads.pause($0.id) } }
    }

    func resume(_ ids: Set<String>) {
        perform {
            for job in selected(ids) where job.state == .paused || job.state == .failed {
                try Downloads.resume(job.id)
            }
        }
    }

    func cancel(_ ids: Set<String>) {
        perform { selected(ids).filter { !$0.state.isFinished }.forEach { Downloads.cancel($0.id) } }
    }

    func remove(_ ids: Set<String>, moveToTrash: Bool) {
        perform { ids.forEach { Downloads.remove($0, moveFileToTrash: moveToTrash) } }
    }

    func clearFinished() {
        perform { Downloads.clearFinished() }
    }

    func open(_ ids: Set<String>) {
        for id in ids { if let url = Downloads.fileURL(id) { NSWorkspace.shared.open(url) } }
    }

    func reveal(_ ids: Set<String>) {
        let urls = ids.compactMap(Downloads.fileURL)
        if urls.isEmpty { NSWorkspace.shared.open(downloadFolder) } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    // MARK: - Download folder

    @Published private(set) var downloadFolder = AppSettings.downloadFolder

    var downloadFolderDisplay: String {
        (downloadFolder.path as NSString).abbreviatingWithTildeInPath
    }

    func setDownloadFolder(_ url: URL) {
        AppSettings.downloadFolder = url
        downloadFolder = AppSettings.downloadFolder
    }

    func resetDownloadFolder() {
        AppSettings.resetDownloadFolder()
        downloadFolder = AppSettings.downloadFolder
    }

    /// Shows a folder picker starting at `start`; returns nil if the user cancels.
    func pickFolder(startingAt start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = start ?? downloadFolder
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseDownloadFolder() {
        if let url = pickFolder() { setDownloadFolder(url) }
    }
}
