import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DownloadsModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Mac Download Manager at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in setOpenAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Keeps the app running so it's ready when you download from the browser. Closing the window doesn't quit the app; use ⌘Q to quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .onAppear { openAtLogin = SMAppService.mainApp.status == .enabled }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). You can add the app in System Settings → General → Login Items."
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
