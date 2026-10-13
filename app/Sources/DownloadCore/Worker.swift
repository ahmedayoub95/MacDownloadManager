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
        let resuming = status.percent > 0
        status.pid = getpid()
        status.state = .downloading
        JobStore.write(status)

        let command: Command
        if !request.usesExtractor, let aria2 = Paths.tool("aria2c") {
            command = aria2Command(request, tool: aria2, resuming: resuming)
        } else if let ytDlp = Paths.tool("yt-dlp") {
            // Without aria2, yt-dlp also handles plain files (one connection instead of 16).
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
        } else if !request.usesExtractor {
            let name = (request.filename ?? "").isEmpty ? "%(title).150B.%(ext)s" : request.filename!.replacingOccurrences(of: "%", with: "%%")
            args += ["-o", name]
            if let referrer = request.referrer, !referrer.isEmpty { args += ["--referer", referrer] }
            if let agent = request.userAgent, !agent.isEmpty { args += ["--user-agent", agent] }
            if let cookies = request.cookies, !cookies.isEmpty { args += ["--add-headers", "Cookie:\(cookies)"] }
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

    static func aria2Command(_ request: DownloadRequest, tool: String, resuming: Bool) -> Command {
        var args = [
            "--dir", request.destination.path,
            "--max-connection-per-server=16", "--split=16", "--min-split-size=1M",
            // A resume must write into the same file; a fresh download must not clobber an existing one.
            "--continue=true", "--auto-file-renaming=\(!resuming)", "--allow-overwrite=false",
            "--file-allocation=none", "--summary-interval=1", "--console-log-level=notice",
            "--enable-color=false", "--content-disposition-default-utf8=true",
        ]
        if let name = request.filename, !name.isEmpty { args.append("--out=\(name)") }
        if let referrer = request.referrer, !referrer.isEmpty { args.append("--referer=\(referrer)") }
        if let agent = request.userAgent, !agent.isEmpty { args.append("--user-agent=\(agent)") }
        if let cookies = request.cookies, !cookies.isEmpty { args.append("--header=Cookie: \(cookies)") }
        args.append(request.url)

        return Command(tool: tool, arguments: args) { line, status in
            if let match = firstMatch(#"Download complete: (.+)$"#, in: line) {
                let path = match[1].trimmingCharacters(in: .whitespaces)
                status.path = path
                status.name = URL(fileURLWithPath: path).lastPathComponent
                return true
            }
            // e.g. [#2089b0 400KiB/1.0MiB(39%) CN:16 DL:115KiB ETA:5s]
            guard let match = firstMatch(#"/([\d.]+\w+)\((\d+)%\)(?:.*?DL:([\d.]+\w+))?(?:.*?ETA:(\w+))?"#, in: line) else {
                return false
            }
            status.state = .downloading
            status.size = match[1]
            status.percent = Double(match[2]) ?? status.percent
            status.speed = match[3].isEmpty ? nil : "\(match[3])/s"
            status.eta = match[4].isEmpty ? nil : match[4]
            return true
        }
    }
}
