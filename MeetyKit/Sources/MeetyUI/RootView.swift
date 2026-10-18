import MeetyCore
import SwiftUI
import UniformTypeIdentifiers

/// A janela principal: biblioteca à esquerda (gravações ou projetos), reunião ou projeto à direita.
public struct RootView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false
    @State private var showNewProject = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            Group {
                if let meeting = model.selectedMeeting {
                    MeetingDetailView(model: model, meeting: meeting)
                        .id(meeting.id)
                } else if let project = model.selectedProject {
                    ProjectDetailView(model: model, project: project)
                        .id(project.id)
                } else {
                    EmptyLibraryView(model: model)
                }
            }
            .background(Color.meety.content)
            .navigationTitle("")
        }
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { model.importFiles(await Self.urls(from: providers)) }
            return true
        }
        .overlay { if isDropTargeted { DropOverlay() } }
        .sheet(isPresented: $model.showWelcome) { WelcomeView(model: model) }
        .sheet(isPresented: $showNewProject) { NewProjectSheet(model: model) }
        .alert(item: $model.alert) { a in Alert(title: Text(a.title), message: Text(a.message)) }
        .frame(minWidth: 820, minHeight: 520)
    }

    // MARK: - Barra lateral

    var sidebar: some View {
        VStack(spacing: 0) {
            modeSwitcher
            if model.sidebarMode == .recordings {
                RecordBar(model: model)
                searchField
                recordingsList
            } else {
                projectsList
            }
        }
        .background(Color.meety.sidebar)
        .toolbar(removing: .title)
    }

    /// "Recordings ▾" / "Projects ▾": troca o que a barra lateral mostra.
    var modeSwitcher: some View {
        Menu {
            ForEach(AppModel.SidebarMode.allCases) { mode in
                Button { model.sidebarMode = mode } label: {
                    Label(mode.title, systemImage: mode.systemIcon)
                    if mode == model.sidebarMode { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.sidebarMode.systemIcon).font(.system(size: 12, weight: .semibold))
                Text(model.sidebarMode.title).font(MeetyFont.headline)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.meety.textPrimary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.meety.fill, in: RoundedRectangle(cornerRadius: MeetyRadius.control, style: .continuous))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.meety.textSecondary)
            TextField(String(localized: "Search meetings", bundle: .module), text: $model.searchText).textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.meety.textTertiary) }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).frame(height: 30)
        .background(Color.meety.fill, in: RoundedRectangle(cornerRadius: MeetyRadius.field, style: .continuous))
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    @ViewBuilder
    var recordingsList: some View {
        if model.filteredMeetings.isEmpty {
            emptySidebar.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selectedMeetingID) {
                ForEach(model.filteredMeetings) { meeting in
                    MeetingRow(model: model, meeting: meeting, showProject: true)
                        .tag(meeting.id)
                        .draggable(meeting.id)
                        .contextMenu { meetingMenu(meeting) }
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    func meetingMenu(_ meeting: Meeting) -> some View {
        ProjectPicker(model: model, meeting: meeting, newProject: { showNewProject = true })
        Divider()
        Button(String(localized: "Show in Finder", bundle: .module)) { model.revealInFinder(meeting) }
        if meeting.status != .transcribing {
            Button(meeting.status == .transcribed ? String(localized: "Transcribe again", bundle: .module) : String(localized: "Transcribe", bundle: .module)) { model.transcribe(meeting) }
        }
        Divider()
        Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) { model.delete(meeting) }
    }

    var emptySidebar: some View {
        VStack(spacing: 6) {
            Text(model.searchText.isEmpty ? String(localized: "No meetings yet", bundle: .module) : String(localized: "Nothing found", bundle: .module))
                .font(MeetyFont.headline)
            Text(model.searchText.isEmpty ? String(localized: "Your recordings and imported files will show up here.", bundle: .module)
                                          : String(localized: "Try another word. The search looks at titles and transcripts.", bundle: .module))
                .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    /// Modo Projetos: um por linha, com a contagem; soltar uma reunião em cima aloca.
    var projectsList: some View {
        VStack(spacing: 0) {
            if model.library.projects.isEmpty {
                VStack(spacing: 6) {
                    Text(String(localized: "No projects yet", bundle: .module)).font(MeetyFont.headline)
                    Text(String(localized: "Group your meetings by client, course or team. Drag a recording onto a project to file it.", bundle: .module))
                        .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).multilineTextAlignment(.center)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { model.selectedProjectID }, set: { id in if let p = model.library.project(id: id) { model.openProject(p) } })) {
                    ForEach(model.library.projects) { project in
                        ProjectRow(model: model, project: project)
                            .tag(project.id)
                            .dropDestination(for: String.self) { ids, _ in
                                for id in ids where model.library.meetings.contains(where: { $0.id == id }) { model.library.assign(id, to: project.id) }
                                return true
                            }
                            .contextMenu {
                                Button(String(localized: "Delete project", bundle: .module), role: .destructive) { model.deleteProject(project) }
                            }
                    }
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden)
            }
            Button { showNewProject = true } label: {
                Label(String(localized: "New project", bundle: .module), systemImage: "plus").labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(10)
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { model.chooseFilesToImport() } label: {
                Label(String(localized: "Import", bundle: .module), systemImage: "square.and.arrow.down").labelStyle(.titleAndIcon)
            }
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
    var showProject = false

    var body: some View {
        let job = model.queue.job(for: meeting.id)
        let project = showProject ? model.library.project(id: meeting.projectID) : nil
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title).lineLimit(1).font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(subtitle(job: job)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).lineLimit(1)
                    if let project { ProjectTag(project: project) }
                }
            }
            Spacer(minLength: 0)
            if model.recordingMeetingID == meeting.id {
                Circle().fill(Color.meety.recordFill).frame(width: 8, height: 8)
            } else if let job, !job.stage.isFinished {
                ProgressView().controlSize(.small)
            } else if meeting.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.meety.warning).font(.system(size: 12))
            } else if meeting.source == .imported {
                Image(systemName: "doc").foregroundStyle(Color.meety.textTertiary).font(.system(size: 13))
            }
        }
        .padding(.vertical, 3)
    }

    func subtitle(job: TranscriptionJob?) -> String {
        var parts = [MeetyFormat.dayAndTime(meeting.createdAt)]
        if let job, !job.stage.isFinished { parts.append(String(localized: "transcribing", bundle: .module)) }
        else if meeting.status == .failed { parts.append(String(localized: "transcription failed", bundle: .module)) }
        else if let d = meeting.duration { parts.append(MeetyFormat.duration(d)) }
        return parts.joined(separator: " · ")
    }
}

/// Etiqueta pequena com o nome do projeto, na cor dele.
struct ProjectTag: View {
    let project: Project
    var body: some View {
        Text(project.name)
            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
            .foregroundStyle(Color.meety.speaker(project.colorIndex))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.meety.speaker(project.colorIndex).opacity(0.14), in: Capsule())
    }
}

struct ProjectRow: View {
    let model: AppModel
    let project: Project
    var body: some View {
        let meetings = model.library.meetings(in: project)
        HStack(spacing: 10) {
            Circle().fill(Color.meety.speaker(project.colorIndex)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).lineLimit(1).font(.system(size: 13))
                Text(countText(meetings)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    func countText(_ meetings: [Meeting]) -> String {
        let total = meetings.compactMap(\.duration).reduce(0, +)
        let n = String(localized: "\(meetings.count) meetings", bundle: .module)
        return total > 0 ? "\(n) · \(MeetyFormat.duration(total))" : n
    }
}

/// Menu "Project ▸": nenhum, cada projeto, novo projeto.
struct ProjectPicker: View {
    let model: AppModel
    let meeting: Meeting
    var newProject: () -> Void
    var body: some View {
        Menu(String(localized: "Project", bundle: .module)) {
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
            Button(String(localized: "New project…", bundle: .module), action: newProject)
        }
    }
}

/// Pede o nome de um projeto novo. Com `meetingToAssign`, já aloca essa reunião nele.
struct NewProjectSheet: View {
    let model: AppModel
    var meetingToAssign: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "New project", bundle: .module)).font(MeetyFont.sheetTitle)
            Text(String(localized: "A client, a course, a team: anything you want to keep together.", bundle: .module))
                .foregroundStyle(Color.meety.textSecondary)
            TextField(String(localized: "Project name", bundle: .module), text: $name)
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .onSubmit { create() }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Create", bundle: .module)) { create() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(24).frame(width: 420)
        .background(Color.meety.window)
    }

    func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let id = meetingToAssign {
            if let p = try? model.library.createProject(name: n) { model.library.assign(id, to: p.id) }
        } else {
            model.createProject(named: n)
        }
        dismiss()
    }
}

struct EmptyLibraryView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HeroIcon(systemName: "waveform", size: 96)
            Text(String(localized: "Record a meeting or drop a file here", bundle: .module)).font(MeetyFont.stateTitle).padding(.top, 24)
            Text(String(localized: "Everything stays on this Mac. Nothing leaves it unless you choose a cloud summary.", bundle: .module))
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Color.meety.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                .padding(.top, 10)
            HStack(spacing: 10) {
                Button { model.startRecording() } label: {
                    Label(String(localized: "Record", bundle: .module), systemImage: "circle.fill").labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(Color.meety.recordFill)
                Button { model.chooseFilesToImport() } label: { Text(String(localized: "Import file…", bundle: .module)).padding(.horizontal, 6) }
            }
            .controlSize(.large)
            .padding(.top, 22)
            Text(String(localized: "Audio or video: m4a, mp3, wav, mp4, mov and more.", bundle: .module))
                .font(MeetyFont.callout).foregroundStyle(Color.meety.textTertiary).padding(.top, 18)
            if model.engineMissing {
                Label(EngineError.notBundled.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.meety.warning).padding(.top, 20)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A borda tracejada que cobre a janela enquanto um arquivo é arrastado.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.meety.accentTint
            RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous)
                .strokeBorder(Color.meety.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(10)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line").font(.system(size: 36, weight: .medium)).foregroundStyle(Color.meety.accentText)
                Text(String(localized: "Drop to transcribe", bundle: .module)).font(MeetyFont.stateTitle).foregroundStyle(Color.meety.accentText)
            }
        }
        .allowsHitTesting(false)
    }
}
