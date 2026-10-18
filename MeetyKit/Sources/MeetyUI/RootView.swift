import MeetyCore
import SwiftUI

/// A janela principal: biblioteca à esquerda, reunião à direita.
public struct RootView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            if let meeting = model.selectedMeeting {
                MeetingDetailView(model: model, meeting: meeting)
                    .id(meeting.id)
            } else {
                EmptyLibraryView(model: model)
            }
        }
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { model.importFiles(await Self.urls(from: providers)) }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .padding(8)
                    .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay { Label(String(localized: "Drop to transcribe", bundle: .module), systemImage: "arrow.down.doc").font(.title2).padding().background(.regularMaterial, in: Capsule()) }
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $model.showWelcome) { WelcomeView(model: model) }
        .alert(item: $model.alert) { a in Alert(title: Text(a.title), message: Text(a.message)) }
        .frame(minWidth: 820, minHeight: 520)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            RecordBar(model: model)
            List(selection: $model.selectedMeetingID) {
                ForEach(model.filteredMeetings) { meeting in
                    MeetingRow(model: model, meeting: meeting)
                        .tag(meeting.id)
                        .contextMenu {
                            Button(String(localized: "Show in Finder", bundle: .module)) { model.revealInFinder(meeting) }
                            if meeting.status != .transcribing {
                                Button(meeting.status == .transcribed ? String(localized: "Transcribe again", bundle: .module) : String(localized: "Transcribe", bundle: .module)) { model.transcribe(meeting) }
                            }
                            Divider()
                            Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { model.delete(meeting) }
                        }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $model.searchText, placement: .sidebar, prompt: String(localized: "Search meetings", bundle: .module))
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { model.chooseFilesToImport() } label: { Label(String(localized: "Import", bundle: .module), systemImage: "square.and.arrow.down") }
                .help(String(localized: "Transcribe an audio or video file", bundle: .module))
        }
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for p in providers {
            if let url = try? await p.loadItem(forTypeIdentifier: "public.file-url") as? Data,
               let s = String(data: url, encoding: .utf8), let u = URL(string: s) { urls.append(u) }
            else if let u = try? await p.loadItem(forTypeIdentifier: "public.file-url") as? URL { urls.append(u) }
        }
        return urls
    }
}

struct MeetingRow: View {
    let model: AppModel
    let meeting: Meeting

    var body: some View {
        let job = model.queue.job(for: meeting.id)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(meeting.title).lineLimit(1).fontWeight(.medium)
                Spacer()
                if model.recordingMeetingID == meeting.id {
                    Circle().fill(.red).frame(width: 8, height: 8)
                } else if let job, !job.stage.isFinished {
                    ProgressView().controlSize(.mini)
                } else if meeting.status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                }
            }
            HStack(spacing: 6) {
                Text(meeting.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                if let d = meeting.duration { Text("·"); Text(TranscriptExporter.clock(d)) }
                if meeting.source == .imported { Image(systemName: "doc").font(.caption2) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct EmptyLibraryView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.and.mic").font(.system(size: 56)).foregroundStyle(.tint)
            Text(String(localized: "Record a meeting or drop a file here", bundle: .module)).font(.title2.weight(.semibold))
            Text(String(localized: "Meety transcribes on your Mac. Your audio never leaves your computer.", bundle: .module))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button { model.startRecording() } label: { Label(String(localized: "Record", bundle: .module), systemImage: "record.circle") }
                    .buttonStyle(.borderedProminent).tint(.red)
                Button { model.chooseFilesToImport() } label: { Label(String(localized: "Import file…", bundle: .module), systemImage: "square.and.arrow.down") }
            }
            .controlSize(.large)
            if model.engineMissing {
                Label(EngineError.notBundled.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(.top)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
