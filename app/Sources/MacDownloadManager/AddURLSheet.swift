import AppKit
import SwiftUI

struct AddURLSheet: View {
    @EnvironmentObject private var model: DownloadsModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var filename = ""
    @State private var isVideoPage = false
    @State private var folder: URL?

    private static let videoSites = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitter.com", "x.com",
                                     "instagram.com", "facebook.com", "tiktok.com", "twitch.tv", "reddit.com"]

    private var isValid: Bool {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)) else { return false }
        return ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") && parsed.host != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Download").font(.title2.bold())

            TextField("https://example.com/file.zip", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 460)
                .onChange(of: url) { _, value in isVideoPage = Self.looksLikeVideoSite(value) }

            Toggle("This is a video page (YouTube, Vimeo, Instagram…)", isOn: $isVideoPage)

            if !isVideoPage {
                TextField("File name (optional)", text: $filename)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Save to:")
                Image(systemName: "folder.fill").foregroundStyle(.blue)
                Text(((folder ?? model.downloadFolder).path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change…") {
                    if let picked = model.pickFolder(startingAt: folder) { folder = picked }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download") {
                    model.add(url: url, filename: isVideoPage ? "" : filename, isVideoPage: isVideoPage,
                              folder: folder ?? model.downloadFolder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               clip.hasPrefix("http"), !clip.contains(" ") {
                url = clip
            }
        }
    }

    static func looksLikeVideoSite(_ text: String) -> Bool {
        guard let host = URL(string: text.trimmingCharacters(in: .whitespaces))?.host?.lowercased() else { return false }
        return videoSites.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
