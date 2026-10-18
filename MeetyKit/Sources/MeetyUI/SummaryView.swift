import MeetyCore
import SwiftUI

/// A aba Resumo: escolhe o tipo e quem escreve, gera, mostra e guarda.
struct SummaryView: View {
    @Bindable var model: AppModel
    let meeting: Meeting
    let transcript: Transcript?

    @State private var template: SummaryTemplate = .minutes
    @State private var customPrompt = ""
    @State private var providers: [ProviderRow] = []
    @State private var selectedProviderID: String = ""
    @State private var generating = false
    @State private var partial = ""
    @State private var error: String?
    @State private var saved: [SummaryDocument] = []
    @State private var selectedDoc: SummaryDocument?
    @State private var docText = ""
    @State private var task: Task<Void, Never>?
    @State private var showCloudConsent = false

    struct ProviderRow: Identifiable {
        let provider: any SummaryProvider
        var availability: ProviderAvailability
        var id: String { provider.id }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                controls
                Divider()
                output
            }
            .frame(minWidth: 420)
            savedList.frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
        }
        .task { await loadProviders(); reloadSaved() }
        .alert(String(localized: "Send the transcript to the cloud?", bundle: .module), isPresented: $showCloudConsent) {
            Button(String(localized: "Send", bundle: .module)) { model.settings.cloudConsent = true; generate(force: true) }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(String(localized: "This option sends the whole transcript to an outside service to write the summary. Local options keep everything on your Mac.", bundle: .module))
        }
    }

    var selectedRow: ProviderRow? { providers.first { $0.id == selectedProviderID } }

    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "What do you need", bundle: .module)).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $template) {
                        ForEach(SummaryTemplate.allCases) { t in Label(t.title, systemImage: t.systemIcon).tag(t) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Written by", bundle: .module)).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $selectedProviderID) {
                        ForEach(providers) { row in
                            HStack {
                                Label(row.provider.title, systemImage: row.provider.systemIcon)
                                if !row.availability.isAvailable { Text("·").foregroundStyle(.secondary); Text(String(localized: "not ready", bundle: .module)).foregroundStyle(.secondary) }
                            }.tag(row.id)
                        }
                    }
                    .labelsHidden().frame(width: 240)
                    .onChange(of: selectedProviderID) { _, v in model.settings.summaryProviderID = v }
                }
                Spacer()
                Button {
                    if generating { task?.cancel() } else { generate(force: false) }
                } label: {
                    if generating { Label(String(localized: "Stop", bundle: .module), systemImage: "stop.fill") }
                    else { Label(String(localized: "Generate", bundle: .module), systemImage: "sparkles") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(transcript == nil || (!generating && !(selectedRow?.availability.isAvailable ?? false)))
                .keyboardShortcut(.return, modifiers: .command)
            }
            if template == .custom {
                TextField(String(localized: "Ask something about this meeting…", bundle: .module), text: $customPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
            }
            if let row = selectedRow {
                HStack(spacing: 6) {
                    Image(systemName: row.provider.isCloud ? "cloud" : "lock").foregroundStyle(.secondary)
                    switch row.availability {
                    case .available(let detail):
                        Text(row.provider.subtitle + (detail.map { " (\($0))" } ?? "")).foregroundStyle(.secondary)
                    case .unavailable(let reason, let action):
                        Text(reason).foregroundStyle(.orange)
                        if let action { actionButton(action) }
                    }
                }
                .font(.callout)
            }
            if transcript == nil {
                Label(String(localized: "Transcribe the meeting first.", bundle: .module), systemImage: "info.circle").foregroundStyle(.secondary).font(.callout)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    func actionButton(_ action: ProviderAction) -> some View {
        switch action {
        case .downloadModel(let id):
            if let m = model.models.catalog.model(id: id) {
                if model.models.isDownloading(m) { ProgressView().controlSize(.small) }
                else { Button(String(localized: "Download", bundle: .module)) { model.models.download(m); Task { try? await Task.sleep(for: .seconds(1)); await loadProviders() } } }
            }
        case .openApp(let bundleID):
            Button(String(localized: "Open app", bundle: .module)) {
                if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { NSWorkspace.shared.openApplication(at: u, configuration: .init()) }
            }
        case .openSettingsSection(let s):
            if s.hasPrefix("x-apple") { Button(String(localized: "Open System Settings", bundle: .module)) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } } }
            else { SettingsLink { Text(String(localized: "Open Settings", bundle: .module)) } }
        case .enterAPIKey:
            SettingsLink { Text(String(localized: "Add key", bundle: .module)) }
        }
    }

    var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if generating {
                    HStack { ProgressView().controlSize(.small); Text(partial.isEmpty ? String(localized: "Thinking…", bundle: .module) : String(localized: "Writing…", bundle: .module)).foregroundStyle(.secondary) }
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if generating, !partial.isEmpty {
                    MarkdownText(partial)
                } else if let doc = selectedDoc {
                    HStack {
                        Text(doc.title).font(.headline)
                        Text(doc.createdAt, format: .dateTime.day().month().hour().minute()).foregroundStyle(.secondary).font(.caption)
                        Text("· \(doc.provider)").foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button { copy(docText) } label: { Image(systemName: "doc.on.doc") }.help(String(localized: "Copy", bundle: .module))
                        Button(role: .destructive) { deleteDoc(doc) } label: { Image(systemName: "trash") }
                    }
                    .buttonStyle(.borderless)
                    TextEditor(text: $docText)
                        .font(.body).scrollContentBackground(.hidden).frame(minHeight: 300)
                        .onChange(of: docText) { _, t in try? model.library.updateSummary(doc, text: t, of: meeting) }
                } else if !generating, saved.isEmpty {
                    Text(String(localized: "No summary yet. Pick what you need above and press Generate.", bundle: .module)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    var savedList: some View {
        List(selection: $selectedDoc) {
            Section(String(localized: "Saved summaries", bundle: .module)) {
                ForEach(saved) { doc in
                    VStack(alignment: .leading) {
                        Text(doc.title).lineLimit(1)
                        Text(doc.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(doc)
                }
            }
        }
        .onChange(of: selectedDoc) { _, d in if let d { docText = model.library.summaryText(d, of: meeting) } }
    }

    func reloadSaved() {
        saved = model.library.summaries(of: meeting)
        if selectedDoc == nil { selectedDoc = saved.first; if let d = selectedDoc { docText = model.library.summaryText(d, of: meeting) } }
    }

    func loadProviders() async {
        let list = SummaryRegistry.providers(models: model.models, settings: model.settings)
        var rows: [ProviderRow] = []
        for p in list { rows.append(ProviderRow(provider: p, availability: await p.availability())) }
        providers = rows
        if selectedProviderID.isEmpty {
            if rows.contains(where: { $0.id == model.settings.summaryProviderID }) { selectedProviderID = model.settings.summaryProviderID }
            else { selectedProviderID = rows.first(where: { !$0.provider.isCloud && $0.availability.isAvailable })?.id ?? rows.first?.id ?? "" }
        }
    }

    func generate(force: Bool) {
        guard let row = selectedRow, let transcript else { return }
        if row.provider.isCloud, !model.settings.cloudConsent, !force { showCloudConsent = true; return }
        generating = true; partial = ""; error = nil; selectedDoc = nil
        let lang = model.settings.summaryLanguage == .meeting ? (meeting.language ?? Locale.current.language.languageCode?.identifier ?? "en")
                                                             : (Locale.current.language.languageCode?.identifier ?? "en")
        let provider = row.provider, tpl = template, custom = customPrompt, m = meeting
        task = Task {
            do {
                let text = try await SummaryService.generate(provider: provider, template: tpl, custom: custom, meeting: m, transcript: transcript, languageCode: lang) { p in
                    Task { @MainActor in partial = p }
                }
                let doc = try model.library.saveSummary(text, template: tpl, provider: provider.title, for: m)
                reloadSaved()
                selectedDoc = doc; docText = text
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            generating = false
        }
    }

    func deleteDoc(_ doc: SummaryDocument) {
        try? model.library.deleteSummary(doc, of: meeting)
        selectedDoc = nil
        reloadSaved()
    }

    func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
}

/// Markdown simples: títulos, listas e ênfase em linha. Suficiente para atas.
struct MarkdownText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    func lineView(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("### ") { inline(String(line.dropFirst(4))).font(.headline).padding(.top, 6) }
        else if line.hasPrefix("## ") { inline(String(line.dropFirst(3))).font(.title3.weight(.semibold)).padding(.top, 8) }
        else if line.hasPrefix("# ") { inline(String(line.dropFirst(2))).font(.title2.weight(.semibold)).padding(.top, 8) }
        else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: line.hasPrefix("- [x] ") ? "checkmark.square" : "square").foregroundStyle(.secondary)
                inline(String(line.dropFirst(6)))
            }
        }
        else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); inline(String(line.dropFirst(2))) }.padding(.leading, 8)
        }
        else if line.isEmpty { Spacer().frame(height: 2) }
        else { inline(line) }
    }

    func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(a) }
        return Text(s)
    }
}
