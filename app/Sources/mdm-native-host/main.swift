// Native messaging host for the browser extension. Chrome starts this process, sends
// length-prefixed JSON on stdin and reads replies on stdout. With `--run-job <id>` the same binary
// runs a single download as a detached worker.

import AppKit
import DownloadCore

let version = "0.5.0"

func readMessage() -> [String: Any]? {
    let input = FileHandle.standardInput
    let header = input.readData(ofLength: 4)
    guard header.count == 4 else { return nil }
    let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    let body = input.readData(ofLength: Int(length))
    guard body.count == Int(length) else { return nil }
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

func reply(_ object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    var length = UInt32(body.count).littleEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(body)
    FileHandle.standardOutput.write(frame)
}

func jobsAsJSON() -> [[String: Any]] {
    JobStore.list().compactMap { job in
        guard let data = try? JSONEncoder().encode(job) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Brings the app window forward, like IDM's download window.
func showApp() {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard bundle.pathExtension == "app" else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, _ in done.signal() }
    _ = done.wait(timeout: .now() + 5)
}

let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--run-job" {
    exit(Worker.run(arguments[2]))
}

while let message = readMessage() {
    BrowserSetup.markExtensionSeen()
    let id = message["id"] as? String ?? ""
    do {
        switch message["type"] as? String {
        case "ping":
            reply(["ok": true, "version": version])

        case "download":
            let data = try JSONSerialization.data(withJSONObject: message)
            var request = try JSONDecoder().decode(DownloadRequest.self, from: data)
            request.saveDir = nil // the browser never chooses where files go; the app's setting does

            let result = try Downloads.start(request)
            reply(["ok": true, "accepted": true, "id": result.id, "duplicate": result.duplicate])
            showApp()

        case "list-jobs":
            reply(["ok": true, "jobs": jobsAsJSON()])

        case "pause":
            Downloads.pause(id)
            reply(["ok": true])

        case "resume":
            try Downloads.resume(id)
            reply(["ok": true])

        case "cancel":
            Downloads.cancel(id)
            reply(["ok": true])

        case "reveal", "open":
            guard let url = Downloads.fileURL(id) else { throw DownloadError("The file is no longer there") }
            if message["type"] as? String == "reveal" {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
            reply(["ok": true])

        case "clear-finished":
            Downloads.clearFinished()
            reply(["ok": true])

        default:
            reply(["ok": false, "error": "Unknown message type"])
        }
    } catch {
        reply(["ok": false, "error": error.localizedDescription])
    }
}
