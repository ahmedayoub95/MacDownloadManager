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

struct AppCommands: Commands {
    @ObservedObject var model: DownloadsModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Setup…") { openWindow(id: "setup") }
        }
        CommandGroup(replacing: .newItem) {
            Button("Add URL…") {
                openWindow(id: "main")
                model.showingAddURL = true
            }
            .keyboardShortcut("n")
        }
        CommandGroup(before: .windowList) {
            Button("Downloads") { openWindow(id: "main") }
                .keyboardShortcut("0")
            Divider()
        }
    }
}

@main
struct MacDownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DownloadsModel()
    @StateObject private var setup = SetupModel()

    var body: some Scene {
        // A WindowGroup (not Window) so clicking the Dock icon, or the browser opening the app,
        // brings the window back after it was closed.
        WindowGroup("Mac Download Manager", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(setup)
                .frame(minWidth: 900, minHeight: 480)
        }
        .commands { AppCommands(model: model) }

        Window("Setup", id: "setup") {
            SetupView().environmentObject(setup)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}
