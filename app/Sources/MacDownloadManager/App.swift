import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Keep running with the window closed so finished downloads still notify.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MacDownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DownloadsModel()

    var body: some Scene {
        Window("Mac Download Manager", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add URL…") { model.showingAddURL = true }
                    .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}
