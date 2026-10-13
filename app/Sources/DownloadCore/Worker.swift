import Foundation

/// Runs one download in a detached process and keeps its status file up to date.
public enum Worker {
    struct Command {
        let tool: String
        let arguments: [String]
        /// Applies one line of tool output to the status. Returns false if the line was irrelevant.
        let parse: (String, inout JobStatus) -> Bool
    }

    public static func run(_ id: String) -> Int32 {
        guard let request = JobStore.loadRequest(id), var status = JobStore.read(id) else {
            log("job \(id): missing request or status")
            return 1
        }
        status.pid = getpid()
        status.state = .downloading
        JobStore.write(status)

        if !request.usesExtractor { return runFile(request, id: id, status: status) }

        let command: Command
        if let ytDlp = Paths.tool("yt-dlp") {
            command = ytDlpCommand(request, id: id, tool: ytDlp)
        } else {
            status.state = .failed
            status.error = "Download tools are missing. Open Mac Download Manager → Setup to install them."
            JobStore.write(status)
            return 1
        }
        log("job \(id) started: \(URL(fileURLWithPath: command.tool).lastPathComponent) \(request.url)")

        let jobLog = Paths.logs.appendingPathComponent("jobs/\(id).log")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.tool)
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (Paths.toolDirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        let lock = NSLock()
        var pending = ""
        var dirty = false
        var lastWrite = Date.distantPast
        var lastError = ""

        // Pause/cancel are written by another process; never overwrite them.
        func stoppedElsewhere() -> Bool {
            let state = JobStore.read(id)?.state
            return state == .paused || state == .cancelled
        }

        func consume(_ text: String, flush: Bool) {
            lock.lock()
            defer { lock.unlock() }
            pending += text
            var lines = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            pending = flush ? "" : (lines.popLast() ?? "")
            for line in lines where !line.isEmpty {
                if line.contains("ERROR") || line.contains("errorCode=") { lastError = line }
                if command.parse(line, &status) { dirty = true }
            }
            if dirty && (flush || Date().timeIntervalSince(lastWrite) >= 0.5) && !stoppedElsewhere() {
                JobStore.write(status)
                dirty = false
                lastWrite = Date()
            }
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            appendData(chunk, to: jobLog)
            consume(String(decoding: chunk, as: UTF8.self), flush: false)
        }

        do {
            try process.run()
        } catch {
            status.state = .failed
            status.error = error.localizedDescription
            JobStore.write(status)
            return 1
        }
        status.toolPid = process.processIdentifier
        JobStore.write(status)
        process.waitUntilExit()

        output.fileHandleForReading.readabilityHandler = nil
        let rest = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        consume(String(decoding: rest, as: UTF8.self), flush: true)

        if stoppedElsewhere() { return 1 }

        status.speed = nil
        status.eta = nil
        if process.terminationStatus == 0 {
            status.state = .done
            status.percent = 100
            if let path = status.path { status.name = URL(fileURLWithPath: path).lastPathComponent }
            JobStore.write(status)
            JobStore.removeRequest(id)
            try? Paths.fileManager.removeItem(at: Paths.temp.appendingPathComponent(id))
            log("job \(id) finished: \(status.path ?? "?")")
            return 0
        }

        // Keep the request and temp files so the download can be resumed.
        let message = lastError.isEmpty ? "Failed (exit code \(process.terminationStatus))" : lastError
        status.state = .failed
        status.error = String(message.prefix(300))
        JobStore.write(status)
        log("job \(id) failed: \(message)")
        return process.terminationStatus
    }

    /// Plain files use the built-in multi-connection downloader.
    static func runFile(_ request: DownloadRequest, id: String, status initial: JobStatus) -> Int32 {
        var status = initial
        log("job \(id) started: \(request.url)")
        let stoppedElsewhere = {
            let state = JobStore.read(id)?.state
            return state == .paused || state == .cancelled
        }

        let download = SegmentedDownload(request: request, workDir: Paths.temp.appendingPathComponent(id)) { progress in
            guard !stoppedElsewhere() else { return }
            if let total = progress.total, total > 0 {
                status.percent = Double(progress.downloaded) / Double(total) * 100
                status.size = formatBytes(total)
                if progress.bytesPerSecond > 0 {
                    status.eta = formatDuration(Double(total - progress.downloaded) / progress.bytesPerSecond)
                }
            } else {
                status.size = formatBytes(progress.downloaded)
            }
            status.speed = progress.bytesPerSecond > 0 ? formatBytes(Int64(progress.bytesPerSecond)) + "/s" : nil
            status.stage = progress.connections > 1 ? "\(progress.connections) connections" : nil
            JobStore.write(status)
        }

        do {
            let result = try download.run()
            if stoppedElsewhere() { return 1 }
            let destination = uniqueDestination(in: request.destination, name: result.filename)
            try Paths.fileManager.moveItem(at: result.file, to: destination)
            try? Paths.fileManager.removeItem(at: Paths.temp.appendingPathComponent(id))
            status.state = .done
            status.percent = 100
            status.speed = nil
            status.eta = nil
            status.stage = nil
            status.path = destination.path
            status.name = destination.lastPathComponent
            JobStore.write(status)
            JobStore.removeRequest(id)
            log("job \(id) finished: \(destination.path)")
            return 0
        } catch {
            if stoppedElsewhere() { return 1 }
            // Keep the request and partial file so the download can be resumed.
            status.state = .failed
            status.error = String(error.localizedDescription.prefix(300))
            status.speed = nil
            status.eta = nil
            status.stage = nil
            JobStore.write(status)
            log("job \(id) failed: \(error.localizedDescription)")
            return 1
        }
    }

    static func uniqueDestination(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 1
        while Paths.fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
            number += 1
        }
        return candidate
    }

    /// Same style as yt-dlp ("12.3MiB") so the app can add up speeds from both.
    static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(bytes)B" : String(format: "%.1f%@", value, units[unit])
    }

    static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "" }
        let total = Int(seconds.rounded())
        if total >= 3600 { return "\(total / 3600)h \(total % 3600 / 60)m" }
        if total >= 60 { return "\(total / 60)m \(total % 60)s" }
        return "\(total)s"
    }

    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func ytDlpCommand(_ request: DownloadRequest, id: String, tool: String) -> Command {
        let title = cleanTitle(request.pageTitle ?? "")
        var args = [
            "--newline", "--no-playlist", "--no-mtime", "--color", "never",
            "--paths", request.destination.path,
            "--paths", "temp:\(Paths.temp.appendingPathComponent(id).path)",
            "--concurrent-fragments", "8",
            // H.264/AAC in MP4 plays in QuickTime and everywhere else on a Mac.
            "-f", "bv*+ba/b",
            "-S", "vcodec:h264,res,acodec:m4a",
            "--merge-output-format", "mp4",
            "--progress-template",
            "download:MDM|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s|%(progress._total_bytes_estimate_str)s",
            "--print", "after_move:MDMPATH|%(filepath)s",
            "--no-quiet",
        ]
        if let ffmpeg = Paths.tool("ffmpeg") { args += ["--ffmpeg-location", ffmpeg] }

        if request.kind == "page" {
            args += ["-o", "%(title).150B.%(ext)s"]
        } else {
            // Raw stream URLs have meaningless names; use the page title instead.
            let name = title.isEmpty ? "%(title).150B" : title.replacingOccurrences(of: "%", with: "%%")
            args += ["-o", "\(name).%(ext)s"]
            if let referrer = request.referrer, !referrer.isEmpty { args += ["--referer", referrer] }
            if let agent = request.userAgent, !agent.isEmpty { args += ["--user-agent", agent] }
            if let cookies = request.cookies, !cookies.isEmpty { args += ["--add-headers", "Cookie:\(cookies)"] }
        }
        args.append(request.url)

        var part = 0
        return Command(tool: tool, arguments: args) { line, status in
            if line.hasPrefix("MDMPATH|") {
                status.path = String(line.dropFirst("MDMPATH|".count))
                return true
            }
            if line.hasPrefix("[download] Destination:") {
                part += 1
                status.stage = part == 1 ? "video" : "audio"
                return true
            }
            if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoConvertor]") || line.hasPrefix("[FixupM3u8]") {
                status.state = .merging
                status.speed = nil
                status.eta = nil
                return true
            }
            guard line.hasPrefix("MDM|") else { return false }
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 6 else { return false }
            let value = { (s: String) in s == "NA" || s == "N/A" || s.isEmpty ? nil : s }
            status.state = .downloading
            status.percent = Double(fields[1].replacingOccurrences(of: "%", with: "")) ?? status.percent
            status.speed = value(fields[2])
            status.eta = value(fields[3])
            status.size = value(fields[4]) ?? value(fields[5]) ?? status.size
            return true
        }
    }
}
