import Foundation

/// Jobs live on disk so the app, the browser helper and the detached workers all see the same list.
public enum JobStore {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func statusURL(_ id: String) -> URL { Paths.status.appendingPathComponent("\(id).json") }
    static func requestURL(_ id: String) -> URL { Paths.requests.appendingPathComponent("\(id).json") }

    public static func read(_ id: String) -> JobStatus? {
        guard let data = try? Data(contentsOf: statusURL(id)) else { return nil }
        return try? decoder.decode(JobStatus.self, from: data)
    }

    static func write(_ status: JobStatus) {
        var status = status
        status.updatedAt = now()
        guard let data = try? encoder.encode(status) else { return }
        try? Paths.fileManager.createDirectory(at: Paths.status, withIntermediateDirectories: true)
        try? data.write(to: statusURL(status.id), options: .atomic)
    }

    static func update(_ id: String, _ change: (inout JobStatus) -> Void) {
        guard var status = read(id) else { return }
        change(&status)
        write(status)
    }

    static func removeStatus(_ id: String) {
        try? Paths.fileManager.removeItem(at: statusURL(id))
    }

    /// Requests can hold session cookies, so they are only readable by the user.
    static func saveRequest(_ request: DownloadRequest, id: String) throws {
        try Paths.fileManager.createDirectory(at: Paths.requests, withIntermediateDirectories: true)
        let data = try encoder.encode(request)
        Paths.fileManager.createFile(atPath: requestURL(id).path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    static func loadRequest(_ id: String) -> DownloadRequest? {
        guard let data = try? Data(contentsOf: requestURL(id)) else { return nil }
        return try? decoder.decode(DownloadRequest.self, from: data)
    }

    static func removeRequest(_ id: String) {
        try? Paths.fileManager.removeItem(at: requestURL(id))
    }

    static func isAlive(_ pid: Int32?) -> Bool {
        guard let pid, pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    public static func list() -> [JobStatus] {
        let files = (try? Paths.fileManager.contentsOfDirectory(at: Paths.status, includingPropertiesForKeys: nil)) ?? []
        var jobs = files.filter { $0.pathExtension == "json" }.compactMap { read($0.deletingPathExtension().lastPathComponent) }
        for index in jobs.indices where jobs[index].state.isActive && !isAlive(jobs[index].pid) {
            // Allow a moment for a freshly spawned worker to record its pid.
            guard now() - jobs[index].updatedAt > 5000 else { continue }
            jobs[index].state = .failed
            jobs[index].error = "The download stopped unexpectedly"
            jobs[index].speed = nil
            jobs[index].eta = nil
            write(jobs[index])
        }
        return jobs.sorted { $0.startedAt > $1.startedAt }
    }
}
