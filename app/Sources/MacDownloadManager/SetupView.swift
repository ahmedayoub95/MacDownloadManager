import DownloadCore
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var setup: SetupModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up Mac Download Manager").font(.title2.bold())
                    Text("Three quick steps. You can come back here any time from the app menu → Setup….")
                        .foregroundStyle(.secondary)
                }
            }

            if !setup.isInApplications { moveBanner }

            ScrollView {
                VStack(spacing: 14) {
                    toolsStep
                    browserStep
                    extensionStep
                }
            }

            HStack {
                if !setup.toolsReady {
                    Text("Video downloads need the tools from step 1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(setup.toolsReady && setup.extensionConnected ? "Done" : "Finish Later") {
                    setup.finish()
                    dismissWindow(id: "setup")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 640)
        .onAppear { setup.startWatching() }
        .onDisappear { setup.stopWatching() }
    }

    private var moveBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Move the app to your Applications folder").font(.headline)
                Text("It's running from the disk image or a temporary location, so your browser couldn't find it later.")
                    .foregroundStyle(.secondary)
                Button("Move to Applications") { setup.moveToApplications() }
                    .buttonStyle(.borderedProminent)
                if let error = setup.moveError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - Step 1

    private var toolsStep: some View {
        StepCard(number: 1, title: "Download tools", done: setup.toolsReady) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Tool.allCases) { tool in
                    HStack(alignment: .top, spacing: 8) {
                        statusIcon(found: setup.locations[tool] != nil)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title).fontWeight(.medium)
                            Text(detail(for: tool)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if setup.installing == tool {
                            ProgressView(value: setup.installProgress).frame(width: 90)
                        }
                    }
                }

                if !setup.toolsReady {
                    Button {
                        Task { await setup.installMissingTools() }
                    } label: {
                        Label(setup.installing == nil ? "Install Missing Tools" : "Installing \(setup.installing!.title)…",
                              systemImage: "arrow.down.circle")
                    }
                    .disabled(setup.installing != nil)
                    .padding(.top, 4)
                }
                if let error = setup.toolError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func detail(for tool: Tool) -> String {
        if let location = setup.locations[tool] { return "\(tool.purpose) · \(location.sourceDescription)" }
        return tool.purpose
    }

    // MARK: - Step 2

    private var browserStep: some View {
        StepCard(number: 2, title: "Connect to your browsers", done: !setup.registeredBrowsers.isEmpty) {
            VStack(alignment: .leading, spacing: 8) {
                if !setup.isInApplications {
                    Text("Happens automatically once the app is in your Applications folder.")
                        .foregroundStyle(.secondary)
                } else if setup.registeredBrowsers.isEmpty {
                    Text("No supported browser found. Install Chrome, Brave, Edge, Vivaldi or Chromium, then click Connect Again.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connected to \(setup.registeredBrowsers.joined(separator: ", ")). This happens automatically.")
                        .foregroundStyle(.secondary)
                }
                Button("Connect Again") { setup.registerAgain() }
                    .disabled(!setup.isInApplications)
            }
        }
    }

    // MARK: - Step 3

    private var extensionStep: some View {
        StepCard(number: 3, title: "Add the browser extension", done: setup.extensionConnected) {
            VStack(alignment: .leading, spacing: 10) {
                if setup.extensionConnected, let seen = setup.extensionLastSeen {
                    Label("Extension connected (last seen \(seen.formatted(.relative(presentation: .named))))",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                instruction(1, "Open your browser's extensions page.") {
                    Button("Open Browser & Copy Address") { setup.openExtensionsPage() }
                    Text("Paste into the address bar: chrome://extensions").font(.caption).foregroundStyle(.secondary)
                }
                instruction(2, "Turn on **Developer mode** (top-right switch).") { EmptyView() }
                instruction(3, "Drag the extension folder onto that page, or click **Load unpacked** and choose it.") {
                    HStack {
                        Button("Show Extension Folder") { setup.revealExtensionFolder() }
                        Button("Copy Folder Path") { setup.copyExtensionPath() }
                    }
                    .disabled(setup.extensionFolder == nil)
                    Text("In the Load unpacked window, press ⌘⇧G and paste the path.").font(.caption).foregroundStyle(.secondary)
                }
                if !setup.extensionConnected {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for the extension to connect…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func instruction<Content: View>(_ number: Int, _ text: LocalizedStringKey, @ViewBuilder extra: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                extra()
            }
        }
    }

    private func statusIcon(found: Bool) -> some View {
        Image(systemName: found ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(found ? .green : .red)
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Color.green : Color.accentColor).frame(width: 26, height: 26)
                    if done {
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.callout.bold()).foregroundStyle(.white)
                    }
                }
                Text(title).font(.headline)
                Spacer()
            }
            content.padding(.leading, 36)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
