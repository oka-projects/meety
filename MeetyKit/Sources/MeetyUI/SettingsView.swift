import MeetyCore
import SwiftUI

public struct SettingsView: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label(String(localized: "General", bundle: .module), systemImage: "gear") }
            ModelsSettings(model: model).tabItem { Label(String(localized: "Models", bundle: .module), systemImage: "cpu") }
            SummarySettings(model: model).tabItem { Label(String(localized: "Summaries", bundle: .module), systemImage: "sparkles") }
            AboutSettings(model: model).tabItem { Label(String(localized: "About", bundle: .module), systemImage: "info.circle") }
        }
        .frame(width: 560)
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    var body: some View {
        Form {
            Picker(String(localized: "Meeting language", bundle: .module), selection: settings.language) {
                ForEach(TranscriptionLanguage.allCases) { l in Text(l.title).tag(l) }
            }
            Text(String(localized: "Leave on automatic unless the detection gets it wrong.", bundle: .module)).font(.caption).foregroundStyle(.secondary)
            Toggle(String(localized: "Tell speakers apart", bundle: .module), isOn: settings.separateSpeakers)
            Toggle(String(localized: "Transcribe automatically when a recording ends", bundle: .module), isOn: settings.transcribeAfterRecording)
            Section(String(localized: "Permissions", bundle: .module)) {
                PermissionRow(title: String(localized: "Microphone", bundle: .module), state: Permissions.microphone) { Permissions.openMicrophoneSettings() }
                PermissionRow(title: String(localized: "Screen & System Audio Recording", bundle: .module), state: Permissions.screenRecording) { Permissions.openScreenRecordingSettings() }
            }
            Section(String(localized: "Library", bundle: .module)) {
                LabeledContent(String(localized: "Location", bundle: .module)) {
                    Button(String(localized: "Show in Finder", bundle: .module)) { NSWorkspace.shared.activateFileViewerSelecting([model.library.root]) }
                }
                LabeledContent(String(localized: "Size", bundle: .module), value: ByteCountFormatter.string(fromByteCount: model.library.fileSizeOnDisk(), countStyle: .file))
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionRow: View {
    let title: String
    let state: Permissions.State
    let open: () -> Void
    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(state == .granted ? String(localized: "Allowed", bundle: .module) : String(localized: "Not allowed", bundle: .module))
                    .foregroundStyle(state == .granted ? .green : .orange)
                Button(String(localized: "Open", bundle: .module), action: open)
            }
        }
    }
}

struct ModelsSettings: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    var body: some View {
        Form {
            Section(String(localized: "Transcription", bundle: .module)) {
                Picker(String(localized: "Use", bundle: .module), selection: settings.transcriptionModelID) {
                    ForEach(model.models.catalog.models(of: .transcription)) { m in Text(m.name).tag(m.id) }
                }
                ModelsListView(model: model, modelsToShow: model.models.catalog.models(of: .transcription))
            }
            Section(String(localized: "Local summaries", bundle: .module)) {
                Picker(String(localized: "Use", bundle: .module), selection: settings.summaryModelID) {
                    ForEach(model.models.catalog.models(of: .summary)) { m in Text(m.name).tag(m.id) }
                }
                ModelsListView(model: model, modelsToShow: model.models.catalog.models(of: .summary))
            }
            Section(String(localized: "Speakers", bundle: .module)) {
                ModelsListView(model: model, modelsToShow: model.models.catalog.models(of: .speakers))
            }
            LabeledContent(String(localized: "Space used by models", bundle: .module), value: ByteCountFormatter.string(fromByteCount: model.models.sizeOnDisk(), countStyle: .file))
        }
        .formStyle(.grouped)
    }
}

struct SummarySettings: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    @State private var vendor: APISummarizer.Vendor = .anthropic
    @State private var key = ""
    @State private var savedKey = false

    var body: some View {
        Form {
            Picker(String(localized: "Summary language", bundle: .module), selection: settings.summaryLanguage) {
                ForEach(MeetySettings.SummaryLanguage.allCases) { l in Text(l.title).tag(l) }
            }
            Section(String(localized: "Claude and ChatGPT on this Mac", bundle: .module)) {
                CLIStatusRow(tool: .claude)
                CLIStatusRow(tool: .codex)
                Text(String(localized: "Meety uses the Claude Code or Codex command line tools that come with the Mac apps or that you installed from the terminal. They use your own account.", bundle: .module)).font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "API key", bundle: .module)) {
                Picker(String(localized: "Provider", bundle: .module), selection: $vendor) {
                    ForEach(APISummarizer.Vendor.allCases) { v in Text(v.title).tag(v) }
                }
                .onChange(of: vendor) { _, v in model.settings.apiProvider = v.rawValue; key = Keychain.get(v.keychainAccount) ?? "" }
                SecureField(vendor.keyHint, text: $key)
                HStack {
                    Button(String(localized: "Save key", bundle: .module)) { Keychain.set(key, for: vendor.keychainAccount); savedKey = true }
                        .disabled(key.isEmpty)
                    if savedKey { Label(String(localized: "Saved in your Keychain", bundle: .module), systemImage: "checkmark").foregroundStyle(.green).font(.caption) }
                    Spacer()
                    Link(String(localized: "Get a key", bundle: .module), destination: vendor.consoleURL).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            vendor = APISummarizer.Vendor(rawValue: model.settings.apiProvider) ?? .anthropic
            key = Keychain.get(vendor.keychainAccount) ?? ""
        }
    }
}

struct CLIStatusRow: View {
    let tool: CLISummarizer.Tool
    @State private var found: CLISummarizer.Found?
    @State private var checked = false
    var body: some View {
        LabeledContent(tool.title) {
            if !checked { ProgressView().controlSize(.small) }
            else if let found { Label("\(found.originTitle) · \(found.url.path)", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption).lineLimit(1).truncationMode(.middle).help(found.url.path) }
            else { Label(String(localized: "Not found", bundle: .module), systemImage: "minus.circle").foregroundStyle(.secondary).font(.caption) }
        }
        .task { found = await Task.detached { CLISummarizer.locate(tool) }.value; checked = true }
    }
}

struct AboutSettings: View {
    let model: AppModel
    var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
    var body: some View {
        Form {
            LabeledContent(String(localized: "Version", bundle: .module), value: version)
            if let h = model.engineHealth {
                LabeledContent(String(localized: "Speech engine", bundle: .module), value: "Python \(h.python) · MLX \(h.mlx ?? "?") · \(h.device ?? "")")
            } else if model.engineMissing {
                LabeledContent(String(localized: "Speech engine", bundle: .module), value: String(localized: "Missing", bundle: .module))
            }
            LabeledContent(String(localized: "Memory", bundle: .module), value: "\(ModelCatalog.physicalMemoryGB) GB")
            Section {
                Button(String(localized: "Export diagnostics…", bundle: .module)) { exportDiagnostics() }
                Text(String(localized: "A text file with the engine log and your settings, without any transcript. Useful when reporting a problem.", bundle: .module)).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("GitHub", destination: URL(string: "https://github.com/oka-projects/meety")!)
                Text(String(localized: "Meety is free and open source. Made by Oka.", bundle: .module)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func exportDiagnostics() {
        var text = "Meety \(version)\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nMemory \(ModelCatalog.physicalMemoryGB) GB\n"
        text += "Engine: \(model.engineHealth.map { "Python \($0.python) MLX \($0.mlx ?? "?") metal=\($0.metal) \($0.device ?? "")" } ?? "missing")\n"
        text += "Installed models: \(model.models.installed.sorted().joined(separator: ", "))\n"
        text += "Settings: model=\(model.settings.transcriptionModelID) language=\(model.settings.language.rawValue) speakers=\(model.settings.separateSpeakers)\n\n--- engine.log ---\n"
        text += EngineLog.contents()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "meety-diagnostics.txt"
        if panel.runModal() == .OK, let url = panel.url { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}
