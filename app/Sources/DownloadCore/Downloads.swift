import Foundation

/// Actions shared by the app window and the browser helper.
public enum Downloads {
    /// Both executables live next to each other (Contents/MacOS in the app bundle).
    static var workerExecutable: String {
        let current = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return current.deletingLastPathComponent().appendingPathComponent(Paths.workerName).path
    }

    @discardableResult
    public static func start(_ request: DownloadRequest) throws -> (id: String, duplicate: Bool) {
        guard let url = URL(string: request.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw DownloadError("Only http(s) links can be downloaded")
        }
        if let existing = JobStore.list().first(where: { $0.url == request.url && ($0.state.isActive || $0.state == .paused) }) {
            if existing.state == .paused { try resume(existing.id) }
            return (existing.id, true)
        }

        var request = request
        let folder = request.saveDir.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? AppSettings.downloadFolder
        do {
            try Paths.fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw DownloadError("Can't save to \(folder.path). Choose another download folder in Settings.")
        }
        request.saveDir = folder.path

        let id = request.id ?? UUID().uuidString
        try JobStore.saveRequest(request, id: id)
        let time = now()
        JobStore.write(JobStatus(
            id: id, name: displayName(for: request), url: request.url, state: .starting,
            kind: request.kind, startedAt: time, updatedAt: time
        ))
        try spawnWorker(id)
        log("accepted \(id) [\(request.kind ?? "file")] \(request.url)")
        return (id, false)
    }

    public static func pause(_ id: String) {
        stopProcesses(id)
        JobStore.update(id) {
            $0.state = .paused
            $0.speed = nil
            $0.eta = nil
        }
    }

    public static func resume(_ id: String) throws {
        guard let status = JobStore.read(id), !status.state.isActive, status.state != .done else { return }
        guard JobStore.loadRequest(id) != nil else {
            throw DownloadError("This download can't be resumed. Start it again from the browser.")
        }
        JobStore.update(id) {
            $0.state = .starting
            $0.error = nil
        }
        try spawnWorker(id)
    }

    public static func cancel(_ id: String) {
        stopProcesses(id)
        JobStore.update(id) {
            $0.state = .cancelled
            $0.speed = nil
            $0.eta = nil
        }
        JobStore.removeRequest(id)
        try? Paths.fileManager.removeItem(at: Paths.temp.appendingPathComponent(id))
    }

    public static func remove(_ id: String, moveFileToTrash: Bool = false) {
        if let status = JobStore.read(id), !status.state.isFinished { cancel(id) }
        if moveFileToTrash, let path = JobStore.read(id)?.path {
            try? Paths.fileManager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        }
        JobStore.removeStatus(id)
        JobStore.removeRequest(id)
    }

    public static func clearFinished() {
        for job in JobStore.list() where job.state.isFinished { remove(job.id) }
    }

    public static func fileURL(_ id: String) -> URL? {
        guard let path = JobStore.read(id)?.path, Paths.fileManager.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func stopProcesses(_ id: String) {
        guard let status = JobStore.read(id) else { return }
        // Process() gives the tool its own process group; signalling it also stops ffmpeg under yt-dlp.
        for pid in [status.toolPid, status.pid] {
            guard let pid, JobStore.isAlive(pid) else { continue }
            if kill(-pid, SIGTERM) != 0 { kill(pid, SIGTERM) }
        }
    }

    static func spawnWorker(_ id: String) throws {
        let executable = workerExecutable
        guard Paths.fileManager.isExecutableFile(atPath: executable) else {
            throw DownloadError("Download worker missing at \(executable)")
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID)) // survive the browser closing the pipe
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        for fd: Int32 in 0...2 {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }

        var argv: [UnsafeMutablePointer<CChar>?] = [executable, "--run-job", id].map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid = pid_t()
        let result = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
        guard result == 0 else {
            JobStore.update(id) {
                $0.state = .failed
                $0.error = "Could not start the download (\(result))"
            }
            throw DownloadError("Could not start the download (\(result))")
        }
        JobStore.update(id) { $0.pid = pid }
    }
}
