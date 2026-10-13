import DownloadCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DownloadsModel
    @State private var category: Category = .all
    @State private var selection = Set<String>()

    private var visible: [JobStatus] { model.jobs(in: category) }
    private var selectedJobs: [JobStatus] { model.selected(selection) }

    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Section("Downloads") {
                    ForEach([Category.all, .unfinished, .finished]) { sidebarRow($0) }
                }
                Section("Categories") {
                    ForEach([Category.video, .music, .compressed, .documents, .programs, .other]) { sidebarRow($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                if visible.isEmpty {
                    ContentUnavailableView(
                        "No downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Click “Download this video” in Chrome, click a file link, or press ⌘N to add a link.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    table
                }
                Divider()
                statusBar
            }
            .navigationTitle(category.title)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.showingAddURL) { AddURLSheet() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func sidebarRow(_ item: Category) -> some View {
        Label(item.title, systemImage: item.icon)
            .badge(model.count(item))
            .tag(item)
    }

    private var table: some View {
        Table(visible, selection: $selection) {
            TableColumn("File Name") { job in
                HStack(spacing: 6) {
                    Image(systemName: Category.of(job).icon).foregroundStyle(.secondary)
                    Text(job.name).lineLimit(1).truncationMode(.middle).help(job.path ?? job.url)
                }
            }
            .width(min: 220, ideal: 360)
            TableColumn("Size") { job in Text(job.size ?? "—").monospacedDigit() }
                .width(min: 60, ideal: 80)
            TableColumn("Status") { job in StatusCell(job: job) }
                .width(min: 170, ideal: 220)
            TableColumn("Speed") { job in Text(job.speed ?? "").monospacedDigit() }
                .width(min: 70, ideal: 90)
            TableColumn("Time Left") { job in Text(job.eta ?? "").monospacedDigit() }
                .width(min: 60, ideal: 75)
            TableColumn("Added") { job in
                Text(job.startedDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            model.open(ids)
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        let jobs = model.selected(ids)
        if jobs.contains(where: { $0.state == .done }) {
            Button("Open") { model.open(ids) }
            Button("Show in Finder") { model.reveal(ids) }
            Divider()
        }
        if jobs.contains(where: { $0.state == .paused || $0.state == .failed }) {
            Button("Resume") { model.resume(ids) }
        }
        if jobs.contains(where: { $0.state.isActive }) {
            Button("Pause") { model.pause(ids) }
        }
        if jobs.contains(where: { !$0.state.isFinished }) {
            Button("Cancel Download") { model.cancel(ids) }
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jobs.map(\.url).joined(separator: "\n"), forType: .string)
        }
        Divider()
        Button("Remove from List") { model.remove(ids, moveToTrash: false) }
        if jobs.contains(where: { $0.state == .done }) {
            Button("Move File to Trash", role: .destructive) { model.remove(ids, moveToTrash: true) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showingAddURL = true } label: { Label("Add URL", systemImage: "plus") }
                .help("Add a download link (⌘N)")
            Button { model.resume(selection) } label: { Label("Resume", systemImage: "play.fill") }
                .disabled(!selectedJobs.contains { $0.state == .paused || $0.state == .failed })
                .help("Resume")
            Button { model.pause(selection) } label: { Label("Pause", systemImage: "pause.fill") }
                .disabled(!selectedJobs.contains { $0.state.isActive })
                .help("Pause")
            Button { model.cancel(selection) } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(!selectedJobs.contains { !$0.state.isFinished })
                .help("Cancel download")
            Button { model.remove(selection, moveToTrash: false) } label: { Label("Remove", systemImage: "trash") }
                .disabled(selection.isEmpty)
                .help("Remove from list")
            Button { model.reveal(selection) } label: { Label("Show in Finder", systemImage: "folder") }
                .help("Show in Finder")
            Button { model.clearFinished() } label: { Label("Clear Finished", systemImage: "checkmark.circle.badge.xmark") }
                .disabled(!model.jobs.contains { $0.state.isFinished })
                .help("Remove finished downloads from the list")
        }
    }

    private var statusBar: some View {
        HStack {
            let active = model.jobs.filter { $0.state.isActive }.count
            Text(active == 0 ? "No active downloads" : "\(active) downloading")
            Spacer()
            if !model.totalSpeed.isEmpty {
                Label(model.totalSpeed, systemImage: "arrow.down").monospacedDigit()
            }
            Button {
                model.chooseDownloadFolder()
            } label: {
                Label("Saving to \(model.downloadFolderDisplay)", systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.link)
            .help("Click to change where downloads are saved")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct StatusCell: View {
    let job: JobStatus

    var body: some View {
        switch job.state {
        case .done:
            Label("Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(job.error ?? "")
        case .cancelled:
            Text("Cancelled").foregroundStyle(.secondary)
        case .paused:
            progress(label: "Paused", tint: .orange)
        case .merging:
            progress(label: "Joining video and audio…", tint: .purple, indeterminate: true)
        case .starting:
            progress(label: "Starting…", tint: .accentColor, indeterminate: true)
        case .downloading:
            let stage = job.stage.map { " (\($0))" } ?? ""
            progress(label: String(format: "%.1f%%", job.percent) + stage, tint: .accentColor)
        }
    }

    private func progress(label: String, tint: Color, indeterminate: Bool = false) -> some View {
        HStack(spacing: 8) {
            if indeterminate {
                ProgressView().progressViewStyle(.linear).frame(width: 70)
            } else {
                ProgressView(value: min(max(job.percent, 0), 100), total: 100).frame(width: 70)
            }
            Text(label).font(.caption).monospacedDigit().lineLimit(1)
        }
        .tint(tint)
    }
}
