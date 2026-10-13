import Foundation

public enum Paths {
    public static let appBundleID = "com.ahmed.MacDownloadManager"
    public static let workerName = "mdm-native-host"

    static let fileManager = FileManager.default
    static let home = fileManager.homeDirectoryForCurrentUser
    public static let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
    static let support = home.appendingPathComponent("Library/Application Support/MacDownloadManager", isDirectory: true)
    static let requests = support.appendingPathComponent("jobs", isDirectory: true)
    static let status = support.appendingPathComponent("status", isDirectory: true)
    static let temp = home.appendingPathComponent("Library/Caches/MacDownloadManager", isDirectory: true)
    public static let logs = home.appendingPathComponent("Library/Logs/MacDownloadManager", isDirectory: true)
    static let toolDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func tool(_ name: String) -> String? {
        toolDirs.map { "\($0)/\(name)" }.first { fileManager.isExecutableFile(atPath: $0) }
    }
}

/// What the browser extension (or the Add URL window) asks to download.
public struct DownloadRequest: Codable {
    public var id: String?
    public var source: String?
    public var kind: String?
    public var url: String
    public var filename: String?
    public var mime: String?
    public var size: Double?
    public var referrer: String?
    public var pageUrl: String?
    public var pageTitle: String?
    public var cookies: String?
    public var userAgent: String?
    /// Folder to save into. Fixed when the download starts so a resume writes to the same place.
    public var saveDir: String?

    public init(url: String, kind: String, source: String, filename: String? = nil, saveDir: String? = nil) {
        self.url = url
        self.kind = kind
        self.source = source
        self.filename = filename
        self.saveDir = saveDir
    }

    var destination: URL {
        saveDir.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? AppSettings.downloadFolder
    }

    /// Video pages and streams go through yt-dlp; plain files go through aria2.
    var usesExtractor: Bool {
        (kind ?? "file") != "file" || source == "video"
    }
}

public enum JobState: String, Codable {
    case starting, downloading, merging, paused, done, failed, cancelled

    public var isActive: Bool { self == .starting || self == .downloading || self == .merging }
    public var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
}

public struct JobStatus: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var url: String
    public var state: JobState
    public var percent: Double = 0
    public var size: String?
    public var speed: String?
    public var eta: String?
    public var stage: String?
    public var path: String?
    public var error: String?
    public var kind: String?
    public var pid: Int32?
    public var toolPid: Int32?
    public var startedAt: Double
    public var updatedAt: Double

    public var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
}

func now() -> Double { Date().timeIntervalSince1970 * 1000 }

func cleanTitle(_ title: String) -> String {
    var t = title
    t = t.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression) // "(375) " unread count
    t = t.replacingOccurrences(of: #"\s+-\s+YouTube$"#, with: "", options: .regularExpression)
    t = t.replacingOccurrences(of: #"[/\\:*?"<>|\n\r\t]"#, with: " ", options: .regularExpression)
    t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
}

func displayName(for request: DownloadRequest) -> String {
    if let name = request.filename, !name.isEmpty { return name }
    let title = cleanTitle(request.pageTitle ?? "")
    if !title.isEmpty { return title }
    let last = URL(string: request.url)?.lastPathComponent ?? ""
    return last.isEmpty || last == "/" ? (URL(string: request.url)?.host ?? "Download") : last
}

public func log(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    appendData(Data("[\(stamp)] \(line)\n".utf8), to: Paths.logs.appendingPathComponent("native-host.log"))
}

func appendData(_ data: Data, to url: URL) {
    try? Paths.fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

public struct DownloadError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
