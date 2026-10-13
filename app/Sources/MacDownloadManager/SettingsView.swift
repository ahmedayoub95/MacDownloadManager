import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DownloadsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Save downloads to") {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(model.downloadFolderDisplay)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.downloadFolder.path)
                    }
                }
                HStack {
                    Button("Change…") { model.chooseDownloadFolder() }
                    Button("Show in Finder") { NSWorkspace.shared.open(model.downloadFolder) }
                    Button("Use Downloads Folder") { model.resetDownloadFolder() }
                        .disabled(model.downloadFolder.standardizedFileURL.path
                            == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").standardizedFileURL.path)
                }
            } footer: {
                Text("Applies to new downloads from the browser and from Add URL. Downloads already in progress keep their folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
