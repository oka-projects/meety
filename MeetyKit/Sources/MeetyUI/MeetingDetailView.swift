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
    @State private var renaming: String?
    @State private var editingTitle = false
    @State private var showNewProject = false
    @FocusState private var titleFocused: Bool

    enum Tab: Hashable { case transcript, summary }

    var folder: MeetingFolder { model.library.folder(for: meeting) }
    var job: TranscriptionJob? { model.queue.job(for: meeting.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .sheet(isPresented: $showNewProject) { NewProjectSheet(model: model, meetingToAssign: meeting.id) }
        .confirmationDialog(String(localized: "Move this meeting to the Trash?", bundle: .module), isPresented: $confirmDelete) {
            Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { model.delete(meeting) }
        } message: { Text(String(localized: "The audio, the transcript and the summaries go together.", bundle: .module)) }
    }

    func load() {
        title = meeting.title
        transcript = model.library.transcript(of: meeting)
        if folder.hasAudio, model.recordingMeetingID != meeting.id { player.load(folder.audio) }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["MEETY_TAB"] == "summary" { tab = .summary }
        if env["MEETY_SHOW"] == "export" { showExport = true }
        #endif
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editingTitle {
                TextField(String(localized: "Title", bundle: .module), text: $title)
                    .textFieldStyle(.plain).font(MeetyFont.windowTitle).focused($titleFocused)
                    .onSubmit { commitTitle(); editingTitle = false }
                    .onChange(of: titleFocused) { _, f in if !f { commitTitle(); editingTitle = false } }
            } else {
                Text(meeting.title).font(MeetyFont.windowTitle).lineLimit(1)
                    .onTapGesture { title = meeting.title; editingTitle = true; titleFocused = true }
                    .help(String(localized: "Click to rename", bundle: .module))
            }
            HStack(spacing: 10) {
                Text(metaLine).font(.system(size: 14)).foregroundStyle(Color.meety.textSecondary).lineLimit(1)
                projectChip
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Projeto ▾" na linha de dados: aloca a reunião a um projeto.
    var projectChip: some View {
        Menu {
            Button { model.library.assign(meeting.id, to: nil) } label: {
                Text(String(localized: "No project", bundle: .module))
                if meeting.projectID == nil { Image(systemName: "checkmark") }
            }
            if !model.library.projects.isEmpty { Divider() }
            ForEach(model.library.projects) { p in
                Button { model.library.assign(meeting.id, to: p.id) } label: {
                    Text(p.name)
                    if meeting.projectID == p.id { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Button(String(localized: "New project…", bundle: .module)) { showNewProject = true }
        } label: {
            let project = model.library.project(id: meeting.projectID)
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
                Text(project?.name ?? String(localized: "Add to project", bundle: .module)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(project.map { Color.meety.speaker($0.colorIndex) } ?? Color.meety.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(project.map { Color.meety.speaker($0.colorIndex).opacity(0.14) } ?? Color.meety.fill, in: Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    var metaLine: String {
        var parts = [meeting.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year())]
        if model.recordingMeetingID == meeting.id {
            parts.append(String(localized: "started at \(meeting.createdAt.formatted(.dateTime.hour().minute()))", bundle: .module))
        } else {
            if let d = meeting.duration { parts.append(MeetyFormat.duration(d)) }
            if let lang = meeting.language, let name = Locale.current.localizedString(forLanguageCode: lang) { parts.append(name.capitalized) }
            if meeting.source == .imported, let f = meeting.originalFileName { parts.append(String(localized: "imported from \(f)", bundle: .module)) }
        }
        return parts.joined(separator: " · ")
    }

    func commitTitle() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != meeting.title else { return }
        model.library.update(meeting.id) { $0.title = t }
    }

    @ViewBuilder
    var content: some View {
        if folder.hasAudio { PlayerBar(player: player) }
        HStack {
            Picker("", selection: $tab) {
                Text(String(localized: "Transcript", bundle: .module)).tag(Tab.transcript)
                Text(String(localized: "Summary", bundle: .module)).tag(Tab.summary)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            if tab == .transcript, meeting.hasSpeakers, let transcript {
                SpeakerChips(meeting: meeting, speakerIDs: transcript.speakerIDs, renaming: $renaming)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        Divider().overlay(Color.meety.separator)
        switch tab {
        case .transcript:
            if let transcript, !transcript.segments.isEmpty {
                TranscriptView(model: model, meeting: meeting, transcript: transcript, player: player, renaming: $renaming)
            } else {
                notTranscribed
            }
        case .summary:
            SummaryView(model: model, meeting: meeting, transcript: transcript)
        }
    }

    var notTranscribed: some View {
        let failed = meeting.status == .failed
        return VStack(spacing: 0) {
            Spacer()
            HeroIcon(systemName: failed ? "exclamationmark.triangle" : "text.alignleft", size: 96,
                     tint: failed ? Color.meety.warning : Color.meety.accentText,
                     background: failed ? Color.meety.warningTint : Color.meety.accentTint)
            Text(failed ? String(localized: "Transcription didn't finish", bundle: .module) : String(localized: "Not transcribed yet", bundle: .module))
                .font(MeetyFont.stateTitle).padding(.top, 24)
            Text(failed ? (meeting.error ?? "") : String(localized: "The audio is saved. Transcribe it whenever you like; it runs on this Mac.", bundle: .module))
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Color.meety.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                .padding(.top, 10)
            if folder.hasAudio {
                Button { model.transcribe(meeting) } label: {
                    Text(failed ? String(localized: "Transcribe again", bundle: .module) : String(localized: "Transcribe", bundle: .module)).padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 22)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { showExport = true } label: {
                Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
            }
            .disabled(transcript == nil)
            .help(String(localized: "Export the transcript", bundle: .module))
            Menu {
                if meeting.status == .transcribed, job == nil {
                    Button(String(localized: "Transcribe again", bundle: .module)) { model.transcribe(meeting) }
                }
                Button(String(localized: "Show in Finder", bundle: .module)) { model.revealInFinder(meeting) }
                Divider()
                Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis") }
        }
    }
}

struct RecordingInProgressView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RecordingWave()
            Text(TranscriptExporter.clock(model.recorder.elapsed)).font(MeetyFont.timeBig).padding(.top, 28)
            Text(String(localized: "Recording. Press stop when the meeting ends.", bundle: .module))
                .font(.system(size: 14)).foregroundStyle(Color.meety.textSecondary).padding(.top, 10)
            Button { model.stopRecording() } label: {
                Label(String(localized: "Stop", bundle: .module), systemImage: "stop.fill").labelStyle(.titleAndIcon).padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent).tint(Color.meety.recordFill).controlSize(.large).padding(.top, 22)
            PrivacyLine(text: String(localized: "Saved on this Mac as it records. Transcription starts when you stop.", bundle: .module)).padding(.top, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Barras vermelhas que pulsam enquanto grava.
struct RecordingWave: View {
    @State private var on = false
    let heights: [CGFloat] = [22, 52, 96, 72, 118, 84, 60, 40, 24]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(Color.meety.recordFill).frame(width: 10, height: heights[i])
                    .scaleEffect(y: on ? 1 : 0.45, anchor: .center)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i % 5) * 0.1), value: on)
            }
        }
        .frame(height: 118)
        .onAppear { on = true }
    }
}

struct TranscribingView: View {
    let job: TranscriptionJob
    let steps: [TranscriptionJob.Stage] = [.preparing, .loadingModel, .transcribing, .speakers, .saving]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroIcon(systemName: "text.alignleft", size: 96)
            Text(String(localized: "Transcribing…", bundle: .module)).font(MeetyFont.stateTitle).padding(.top, 24)
            VStack(spacing: 8) {
                ProgressView(value: job.progress ?? 0).progressViewStyle(.linear).tint(Color.meety.accent)
                HStack {
                    Text(verbatim: job.progress.map { "\(Int($0 * 100))%" } ?? "")
                    Spacer()
                    if let r = job.estimatedRemaining, job.stage == .transcribing {
                        Text(String(localized: "about \(TranscriptExporter.clock(r)) left", bundle: .module))
                    }
                }
                .font(MeetyFont.timeInline).foregroundStyle(Color.meety.textSecondary)
            }
            .frame(width: 440).padding(.top, 20)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps.indices, id: \.self) { i in
                    let state = stepState(i)
                    HStack(spacing: 10) {
                        ZStack {
                            switch state {
                            case .done:
                                Circle().fill(Color.meety.success).frame(width: 18, height: 18)
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            case .current:
                                ProgressView().controlSize(.small).frame(width: 18, height: 18)
                            case .pending:
                                Circle().stroke(Color.meety.borderStrong, lineWidth: 1.5).frame(width: 18, height: 18)
                            }
                        }
                        .frame(width: 18, height: 18)
                        Text(stepTitle(steps[i]))
                            .font(.system(size: 14, weight: state == .current ? .semibold : .regular))
                            .foregroundStyle(state == .pending ? Color.meety.textSecondary : Color.meety.textPrimary)
                    }
                }
            }
            .padding(.top, 24)
            Button(String(localized: "Cancel", bundle: .module)) { job.cancel() }.controlSize(.large).padding(.top, 24)
            PrivacyLine(text: String(localized: "Running on this Mac's chip. You can keep using Meety meanwhile.", bundle: .module)).padding(.top, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    enum StepState { case done, current, pending }
    func stepState(_ i: Int) -> StepState {
        let current = steps.firstIndex(of: job.stage) ?? (job.stage == .queued ? -1 : steps.count)
        if i < current { return .done }
        if i == current { return .current }
        return .pending
    }
    func stepTitle(_ s: TranscriptionJob.Stage) -> String {
        s.title.replacingOccurrences(of: "…", with: "")
    }
}

struct PlayerBar: View {
    @Bindable var player: AudioPlayer
    var body: some View {
        HStack(spacing: 10) {
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 16)) }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 32, height: 32)
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { player.skip(15) } label: { Image(systemName: "goforward.15").font(.system(size: 16)) }
            Text(TranscriptExporter.clock(player.currentTime)).font(MeetyFont.timeInline).frame(width: 60, alignment: .trailing).padding(.leading, 6)
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(1, player.duration))
                .tint(Color.meety.accent)
            Text(TranscriptExporter.clock(player.duration)).font(MeetyFont.timeInline).foregroundStyle(Color.meety.textSecondary).frame(width: 60, alignment: .leading)
            Menu {
                ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button { player.rate = Float(r) } label: { Text(verbatim: "\(r.formatted())×") }
                }
            } label: { Text(verbatim: "\(Double(player.rate).formatted())×").font(MeetyFont.timeInline) }
            .menuStyle(.button).fixedSize().menuIndicator(.hidden)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.meety.textPrimary)
        .padding(.horizontal, 28).padding(.bottom, 12)
    }
}
