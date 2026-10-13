import Foundation

public enum Tool: String, CaseIterable, Identifiable {
    case ytDlp = "yt-dlp"
    case ffmpeg
    case deno
    case aria2c

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ytDlp: "yt-dlp"
        case .ffmpeg: "ffmpeg"
        case .deno: "Deno"
        case .aria2c: "aria2"
        }
    }

    public var purpose: String {
        switch self {
        case .ytDlp: "Downloads from YouTube and other video sites"
        case .ffmpeg: "Joins video and audio into one MP4"
        case .deno: "Needed by yt-dlp for YouTube"
        case .aria2c: "Optional: faster downloads of normal files"
        }
    }

    /// aria2 has no official standalone Mac build, so it is only used when installed with Homebrew.
    public var canInstallFromApp: Bool { self != .aria2c }
    public var isRequired: Bool { self != .aria2c }

    var downloadURL: URL? {
        #if arch(arm64)
        let denoArch = "aarch64", ffmpegArch = "arm64"
        #else
        let denoArch = "x86_64", ffmpegArch = "x64"
        #endif
        switch self {
        case .ytDlp:
            return URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")
        case .deno:
            return URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-\(denoArch)-apple-darwin.zip")
        case .ffmpeg:
            return URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-\(ffmpegArch).gz")
        case .aria2c:
            return nil
        }
    }

    var versionArguments: [String] {
        self == .ffmpeg ? ["-version"] : ["--version"]
    }
}

public struct ToolLocation: Equatable {
    public let path: String
    public var isManagedByApp: Bool { path.hasPrefix(Paths.appBin.path) }
    public var sourceDescription: String {
        isManagedByApp ? "Installed by Mac Download Manager" : "Found at \(path)"
    }
}

public enum Tools {
    public static func locate(_ tool: Tool) -> ToolLocation? {
        Paths.tool(tool.rawValue).map(ToolLocation.init)
    }

    public static var missingRequired: [Tool] {
        Tool.allCases.filter { $0.isRequired && locate($0) == nil }
    }

    /// Downloads a tool into the app's own folder and checks that it runs.
    public static func install(_ tool: Tool, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let url = tool.downloadURL else {
            throw DownloadError("\(tool.title) can only be installed with Homebrew: brew install \(tool.rawValue == "aria2c" ? "aria2" : tool.rawValue)")
        }
        try Paths.fileManager.createDirectory(at: Paths.appBin, withIntermediateDirectories: true)

        let downloaded = try await FileDownloader.download(url, progress: progress)
        defer { try? Paths.fileManager.removeItem(at: downloaded) }

        let destination = Paths.appBin.appendingPathComponent(tool.rawValue)
        let staging = Paths.appBin.appendingPathComponent(".\(tool.rawValue)-\(UUID().uuidString)", isDirectory: true)
        try Paths.fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? Paths.fileManager.removeItem(at: staging) }

        let binary: URL
        switch url.pathExtension {
        case "zip":
            try run("/usr/bin/ditto", ["-x", "-k", downloaded.path, staging.path])
            guard let found = Paths.fileManager.enumerator(at: staging, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL })
                .first(where: { $0.lastPathComponent == tool.rawValue }) else {
                throw DownloadError("\(tool.title) wasn't found in the downloaded archive")
            }
            binary = found
        case "gz":
            binary = staging.appendingPathComponent(tool.rawValue)
            try run("/bin/sh", ["-c", "/usr/bin/gunzip -c \"$0\" > \"$1\"", downloaded.path, binary.path])
        default:
            binary = staging.appendingPathComponent(tool.rawValue)
            try Paths.fileManager.moveItem(at: downloaded, to: binary)
        }

        try Paths.fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        removexattr(binary.path, "com.apple.quarantine", 0)
        do {
            try run(binary.path, tool.versionArguments)
        } catch {
            throw DownloadError("\(tool.title) was downloaded but doesn't run on this Mac")
        }

        try? Paths.fileManager.removeItem(at: destination)
        try Paths.fileManager.moveItem(at: binary, to: destination)
        log("installed \(tool.rawValue) from \(url)")
    }

    /// Keeps the app's own yt-dlp current; video sites change often. Runs at most once a day.
    public static func updateYtDlpIfNeeded() {
        guard let location = locate(.ytDlp), location.isManagedByApp else { return }
        let key = "lastYtDlpUpdate"
        let last = AppSettings.defaults.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 24 * 60 * 60 else { return }
        AppSettings.defaults.set(Date().timeIntervalSince1970, forKey: key)
        DispatchQueue.global(qos: .utility).async {
            _ = try? run(location.path, ["-U"])
        }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw DownloadError(text.split(separator: "\n").last.map(String.init) ?? "exit code \(process.terminationStatus)")
        }
        return text
    }
}

/// URLSession download with progress reporting.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let downloader = FileDownloader(progress: progress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation?.resume(throwing: DownloadError("Download failed (HTTP \(http.statusCode))"))
            continuation = nil
            return
        }
        // The temporary file is deleted when this method returns, so move it first.
        let kept = Paths.fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try Paths.fileManager.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
