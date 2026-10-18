import MeetyCore
import SwiftUI

/// Uma reunião: cabeçalho, tocador, e as abas Transcrição e Resumo.
struct MeetingDetailView: View {
    @Bindable var model: AppModel
    let meeting: Meeting

    @State private var player = AudioPlayer()
    @State private var tab: Tab = .transcript
    @State private var transcript: Transcript?
    @State private var title: String = ""
    @State private var showExport = false
    @State private var confirmDelete = false

    enum Tab: Hashable { case transcript, summary }

    var folder: MeetingFolder { model.library.folder(for: meeting) }
    var job: TranscriptionJob? { model.queue.job(for: meeting.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.recordingMeetingID == meeting.id {
                RecordingInProgressView(model: model)
            } else if let job, !job.stage.isFinished {
                TranscribingView(job: job)
            } else {
                content
            }
        }
        .toolbar { toolbar }
        .onAppear { load() }
        .onChange(of: meeting.status) { _, _ in load() }
        .onChange(of: meeting.speakerNames) { _, _ in transcript = model.library.transcript(of: meeting) }
        .onDisappear { player.unload() }
        .sheet(isPresented: $showExport) {
            if let transcript { ExportSheet(meeting: meeting, transcript: transcript) }
        }
        .confirmationDialog(String(localized: "Move this meeting to the Trash?", bundle: .module), isPresented: $confirmDelete) {
            Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { model.delete(meeting) }
        } message: { Text(String(localized: "The audio, the transcript and the summaries go together.", bundle: .module)) }
    }

    func load() {
        title = meeting.title
        transcript = model.library.transcript(of: meeting)
        if folder.hasAudio, model.recordingMeetingID != meeting.id { player.load(folder.audio) }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(String(localized: "Title", bundle: .module), text: $title)
                .textFieldStyle(.plain).font(.title.weight(.semibold))
                .onSubmit { commitTitle() }
                .onChange(of: title) { _, _ in commitTitleDebounced() }
            HStack(spacing: 8) {
                Text(meeting.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                if let d = meeting.duration { Text("·"); Text(TranscriptExporter.clock(d)) }
                if let lang = meeting.language, let name = Locale.current.localizedString(forLanguageCode: lang) { Text("·"); Text(name.capitalized) }
                if meeting.status == .failed, let e = meeting.error {
                    Text("·"); Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1).help(e)
                }
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @State private var titleTask: Task<Void, Never>?
    func commitTitleDebounced() {
        titleTask?.cancel()
        titleTask = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { commitTitle() } }
    }
    func commitTitle() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != meeting.title else { return }
        model.library.update(meeting.id) { $0.title = t }
    }

    @ViewBuilder
    var content: some View {
        if folder.hasAudio { PlayerBar(player: player) ; Divider() }
        Picker("", selection: $tab) {
            Text(String(localized: "Transcript", bundle: .module)).tag(Tab.transcript)
            Text(String(localized: "Summary", bundle: .module)).tag(Tab.summary)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 260).padding(.vertical, 10)
        Divider()
        switch tab {
        case .transcript:
            if let transcript, !transcript.segments.isEmpty {
                TranscriptView(model: model, meeting: meeting, transcript: transcript, player: player)
            } else {
                notTranscribed
            }
        case .summary:
            SummaryView(model: model, meeting: meeting, transcript: transcript)
        }
    }

    var notTranscribed: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: meeting.status == .failed ? "exclamationmark.triangle" : "text.quote").font(.system(size: 40)).foregroundStyle(.secondary)
            if meeting.status == .failed, let e = meeting.error {
                Text(String(localized: "The transcription didn't finish", bundle: .module)).font(.title3.weight(.semibold))
                Text(e).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            } else {
                Text(String(localized: "Not transcribed yet", bundle: .module)).font(.title3.weight(.semibold))
            }
            if folder.hasAudio {
                Button { model.transcribe(meeting) } label: { Label(String(localized: "Transcribe", bundle: .module), systemImage: "waveform") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if transcript != nil {
                Button { showExport = true } label: { Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up") }
                    .help(String(localized: "Export the transcript", bundle: .module))
            }
            Menu {
                if meeting.status == .transcribed, job == nil {
                    Button(String(localized: "Transcribe again", bundle: .module)) { model.transcribe(meeting) }
                }
                Button(String(localized: "Show in Finder", bundle: .module)) { model.revealInFinder(meeting) }
                Divider()
                Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
}

struct RecordingInProgressView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(.red).symbolEffect(.variableColor.iterative, isActive: true)
            Text(TranscriptExporter.clock(model.recorder.elapsed)).font(.system(size: 40, weight: .light).monospacedDigit())
            Text(String(localized: "Recording. Press stop when the meeting ends.", bundle: .module)).foregroundStyle(.secondary)
            Button { model.stopRecording() } label: { Label(String(localized: "Stop", bundle: .module), systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TranscribingView: View {
    let job: TranscriptionJob
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView(value: job.progress).progressViewStyle(.linear).frame(width: 320)
            Text(job.stage.title).font(.headline)
            if let p = job.progress, let r = job.estimatedRemaining, job.stage == .transcribing {
                Text(String(localized: "\(Int(p * 100))% · about \(TranscriptExporter.clock(r)) left", bundle: .module)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Button(String(localized: "Cancel", bundle: .module)) { job.cancel() }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerBar: View {
    @Bindable var player: AudioPlayer
    var body: some View {
        HStack(spacing: 14) {
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 28) }
                .keyboardShortcut(.space, modifiers: [])
            Button { player.skip(15) } label: { Image(systemName: "goforward.15") }
            Text(TranscriptExporter.clock(player.currentTime)).monospacedDigit().font(.callout).frame(width: 56, alignment: .trailing)
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(1, player.duration))
            Text(TranscriptExporter.clock(player.duration)).monospacedDigit().font(.callout).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Menu {
                ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button("\(r.formatted())×") { player.rate = Float(r) }
                }
            } label: { Text("\(Double(player.rate).formatted())×").monospacedDigit() }
            .menuStyle(.borderlessButton).frame(width: 52)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
