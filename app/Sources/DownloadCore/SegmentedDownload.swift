import Foundation

/// Multi-connection HTTP download. The file is split into byte ranges fetched over separate
/// connections; whenever a connection frees up, the biggest remaining range is split in half so
/// every connection stays busy until the end. Progress is saved next to the partial file so a
/// paused or interrupted download continues where it stopped.
final class SegmentedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Progress {
        var downloaded: Int64
        var total: Int64?
        var bytesPerSecond: Double
        var connections: Int
    }

    struct Result {
        var file: URL
        var filename: String
    }

    static let maxConnections = 16
    static let minSplit: Int64 = 1 << 20
    static let maxRetries = 5

    private struct Segment: Codable {
        var start: Int64
        var end: Int64 // exclusive; Int64.max when the size is unknown
        var received: Int64 = 0
        var next: Int64 { start + received }
        var remaining: Int64 { end - next }
    }

    private struct SavedState: Codable {
        var url: String
        var total: Int64
        var validator: String?
        var filename: String
        var segments: [Segment]
    }

    private let request: DownloadRequest
    private let workDir: URL
    private let onProgress: (Progress) -> Void
    private var partFile: URL { workDir.appendingPathComponent("download.part") }
    private var stateFile: URL { workDir.appendingPathComponent("segments.json") }

    private let dispatchQueue = DispatchQueue(label: "SegmentedDownload")
    private lazy var delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = dispatchQueue
        return queue
    }()
    // One session per connection: a shared session would multiplex HTTP/2 onto a single TCP connection.
    private var sessions: [URLSession] = []
    private var freeSlots: [Int] = []
    private var active: [URLSessionTask: (segment: Int, slot: Int)] = [:]
    private var retries: [Int: Int] = [:]

    private var url: URL!
    private var total: Int64 = 0
    private var ranged = false
    private var validator: String?
    private var filename = ""
    private var segments: [Segment] = []
    private var fd: Int32 = -1
    private var failure: Error?
    private var finished = false
    private let done = DispatchSemaphore(value: 0)

    private var lastTickBytes: Int64 = 0
    private var lastTick = Date()
    private var speed: Double = 0
    private var timer: DispatchSourceTimer?

    init(request: DownloadRequest, workDir: URL, onProgress: @escaping (Progress) -> Void) {
        self.request = request
        self.workDir = workDir
        self.onProgress = onProgress
    }

    /// Blocks until the download finishes. The returned file is still in the work folder.
    func run() throws -> Result {
        guard let original = URL(string: request.url) else { throw DownloadError("Invalid link") }
        try Paths.fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        let probe = try Probe.run(makeRequest(original, range: "0-0"), originalHost: original.host)
        url = probe.url
        ranged = probe.total != nil
        total = probe.total ?? probe.length ?? -1
        validator = probe.validator
        filename = sanitize(request.filename.flatMap { $0.isEmpty ? nil : $0 } ?? probe.suggestedFilename)

        let saved = (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) }
        if ranged, let saved, saved.total == total, saved.validator == validator,
           Paths.fileManager.fileExists(atPath: partFile.path) {
            segments = saved.segments
            filename = saved.filename
            log("resuming \(request.url) at \(downloaded) of \(total) bytes")
        } else {
            try? Paths.fileManager.removeItem(at: partFile)
            segments = initialSegments()
        }

        fd = open(partFile.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { throw DownloadError("Can't write the download: \(String(cString: strerror(errno)))") }
        defer { close(fd) }

        let connections = ranged ? Self.maxConnections : 1
        sessions = (0..<connections).map { _ in URLSession(configuration: Self.configuration, delegate: self, delegateQueue: delegateQueue) }
        defer { sessions.forEach { $0.invalidateAndCancel() } }

        dispatchQueue.async {
            self.freeSlots = Array((0..<connections).reversed())
            self.lastTickBytes = self.downloaded
            self.startTimer()
            self.fillSlots()
            self.finishIfComplete()
        }
        done.wait()

        if let failure { throw failure }
        try? Paths.fileManager.removeItem(at: stateFile)
        return Result(file: partFile, filename: filename)
    }

    // MARK: - Scheduling (always on dispatchQueue)

    private var downloaded: Int64 { segments.reduce(0) { $0 + $1.received } }

    private func initialSegments() -> [Segment] {
        guard ranged, total > 0 else { return [Segment(start: 0, end: total >= 0 ? total : .max)] }
        let count = Int64(min(Self.maxConnections, max(1, Int(total / Self.minSplit))))
        let size = total / count
        return (0..<count).map { index in
            Segment(start: index * size, end: index == count - 1 ? total : (index + 1) * size)
        }
    }

    private func fillSlots() {
        while !finished, let slot = freeSlots.last, let segment = nextSegment() {
            freeSlots.removeLast()
            start(segment: segment, slot: slot)
        }
    }

    /// An unassigned range if there is one, otherwise the second half of the biggest active range.
    private func nextSegment() -> Int? {
        let busy = Set(active.values.map(\.segment))
        if let waiting = segments.indices.first(where: { !busy.contains($0) && segments[$0].remaining > 0 }) {
            return waiting
        }
        guard ranged,
              let biggest = busy.max(by: { segments[$0].remaining < segments[$1].remaining }),
              segments[biggest].remaining >= 2 * Self.minSplit else { return nil }
        let middle = segments[biggest].next + segments[biggest].remaining / 2
        segments.append(Segment(start: middle, end: segments[biggest].end))
        segments[biggest].end = middle
        return segments.count - 1
    }

    private func start(segment index: Int, slot: Int) {
        let segment = segments[index]
        let range = ranged ? "\(segment.next)-\(segment.end - 1)" : nil
        let task = sessions[slot].dataTask(with: makeRequest(url, range: range))
        active[task] = (index, slot)
        task.resume()
    }

    private func finishIfComplete() {
        guard !finished, active.isEmpty else { return }
        let complete = ranged || total >= 0 ? segments.allSatisfy { $0.remaining == 0 } : true
        if complete || failure != nil { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        active.keys.forEach { $0.cancel() }
        saveState()
        report()
        done.signal()
    }

    private func fail(_ message: String) {
        failure = DownloadError(message)
        finish()
    }

    // MARK: - URLSession delegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == (ranged ? 206 : 200) else {
            completionHandler(.cancel)
            if !finished { fail(status == 200 ? "The server stopped accepting split downloads. Try again." : "The server replied \(status)") }
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished, let index = active[dataTask]?.segment else { return }
        let take = Int(min(Int64(data.count), segments[index].remaining))
        guard take > 0 else { return }
        let offset = segments[index].next
        let written = data.withUnsafeBytes { buffer -> Bool in
            var count = 0
            while count < take {
                let result = pwrite(fd, buffer.baseAddress! + count, take - count, off_t(offset) + off_t(count))
                if result <= 0 { return false }
                count += result
            }
            return true
        }
        guard written else {
            fail("Can't write the download: \(String(cString: strerror(errno)))")
            return
        }
        segments[index].received += Int64(take)
        // This connection reached a range that another connection took over.
        if segments[index].remaining == 0 { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let entry = active.removeValue(forKey: task) else { return }
        let index = entry.segment, slot = entry.slot
        freeSlots.append(slot)
        guard !finished else { return }

        let segment = segments[index]
        let unknownSizeDone = !ranged && total < 0 && error == nil
        if segment.remaining > 0 && !unknownSizeDone {
            let attempt = (retries[index] ?? 0) + 1
            retries[index] = attempt
            let reason = error?.localizedDescription ?? "connection closed early"
            log("range \(segment.next)-\(segment.end) failed (\(attempt)/\(Self.maxRetries)): \(reason)")
            if attempt > Self.maxRetries || !ranged {
                fail(reason)
                return
            }
            // Give the slot back after a pause; another free connection may pick the range up sooner.
            freeSlots.removeAll { $0 == slot }
            dispatchQueue.asyncAfter(deadline: .now() + Double(attempt)) {
                self.freeSlots.append(slot)
                self.fillSlots()
                self.finishIfComplete()
            }
            return
        }
        if unknownSizeDone { total = segment.received }
        fillSlots()
        finishIfComplete()
    }

    // MARK: - Progress

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.saveState()
            self?.report()
        }
        timer.resume()
        self.timer = timer
    }

    private func report() {
        let bytes = downloaded
        let elapsed = Date().timeIntervalSince(lastTick)
        if elapsed > 0.2 {
            let current = Double(bytes - lastTickBytes) / elapsed
            speed = speed == 0 ? current : speed * 0.6 + current * 0.4
            lastTickBytes = bytes
            lastTick = Date()
        }
        onProgress(Progress(downloaded: bytes, total: total >= 0 ? total : nil,
                            bytesPerSecond: finished ? 0 : speed, connections: active.count))
    }

    private func saveState() {
        guard ranged else { return }
        let state = SavedState(url: request.url, total: total, validator: validator, filename: filename, segments: segments)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateFile, options: .atomic) }
    }

    // MARK: - Requests

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = 60
        return configuration
    }

    private func makeRequest(_ target: URL, range: String?) -> URLRequest {
        var urlRequest = URLRequest(url: target)
        // Ranges are byte offsets into the file itself, so it must not arrive compressed.
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let range { urlRequest.setValue("bytes=\(range)", forHTTPHeaderField: "Range") }
        if let agent = request.userAgent, !agent.isEmpty { urlRequest.setValue(agent, forHTTPHeaderField: "User-Agent") }
        if let referrer = request.referrer, !referrer.isEmpty { urlRequest.setValue(referrer, forHTTPHeaderField: "Referer") }
        // Browser cookies belong to the site the link was on, not to a CDN it redirects to.
        if let cookies = request.cookies, !cookies.isEmpty, target.host == URL(string: request.url)?.host {
            urlRequest.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        return urlRequest
    }

    private func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: #"[/:\x00-\x1f]"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "download" : String(cleaned.prefix(200))
    }
}

/// Reads the response headers for a one-byte range request to learn the size, final URL and file name.
private final class Probe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Info {
        var url: URL
        var total: Int64?      // set when the server supports ranges
        var length: Int64?     // full size from a plain 200 reply
        var validator: String?
        var suggestedFilename: String
    }

    private let originalHost: String?
    private var response: HTTPURLResponse?
    private var error: Error?
    private let done = DispatchSemaphore(value: 0)

    private init(originalHost: String?) {
        self.originalHost = originalHost
    }

    static func run(_ request: URLRequest, originalHost: String?) throws -> Info {
        let probe = Probe(originalHost: originalHost)
        let session = URLSession(configuration: SegmentedDownload.configuration, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request).resume()
        probe.done.wait()

        guard let response = probe.response else {
            throw probe.error ?? DownloadError("No reply from the server")
        }
        let status = response.statusCode
        guard status == 200 || status == 206 || status == 416 else {
            throw DownloadError("The server replied \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))")
        }
        let header = { (name: String) in response.value(forHTTPHeaderField: name) }
        var total: Int64?
        if status == 206, let range = header("Content-Range"), let slash = range.lastIndex(of: "/") {
            total = Int64(range[range.index(after: slash)...])
        }
        let length = status == 200 && response.expectedContentLength >= 0 ? response.expectedContentLength : nil
        return Info(
            url: response.url ?? request.url!,
            total: total,
            length: length,
            validator: header("ETag") ?? header("Last-Modified"),
            suggestedFilename: response.suggestedFilename ?? "download"
        )
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = newRequest
        if newRequest.url?.host != originalHost { next.setValue(nil, forHTTPHeaderField: "Cookie") }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.error = error
        done.signal()
    }
}
