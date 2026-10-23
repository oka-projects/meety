import MeetyCore
import SwiftUI

public struct SettingsView: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    public init(model: AppModel) { self.model = model }

    @State private var tab = ProcessInfo.processInfo.environment["MEETY_SETTINGS_TAB"] ?? "general"
    public var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(model: model).tag("general").tabItem { Label(String(localized: "General", bundle: .module), systemImage: "gearshape") }
            ModelsSettings(model: model).tag("models").tabItem { Label(String(localized: "Models", bundle: .module), systemImage: "shippingbox") }
            DictationSettings(model: model).tag("dictation").tabItem { Label(String(localized: "Dictation", bundle: .module), systemImage: "mic") }
            SummarySettings(model: model).tag("summaries").tabItem { Label(String(localized: "Summaries", bundle: .module), systemImage: "text.alignleft") }
            AboutSettings(model: model).tag("about").tabItem { Label(String(localized: "About", bundle: .module), systemImage: "info.circle") }
        }
        .frame(width: 560)
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    var body: some View {
        Form {
            Section(String(localized: "Transcription", bundle: .module)) {
                Picker(String(localized: "Meeting language", bundle: .module), selection: settings.language) {
                    ForEach(TranscriptionLanguage.allCases) { l in Text(l.title).tag(l) }
                }
                Text(String(localized: "Leave on automatic unless the detection gets it wrong.", bundle: .module)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
                Toggle(String(localized: "Tell speakers apart", bundle: .module), isOn: settings.separateSpeakers)
                Toggle(String(localized: "Transcribe automatically when a recording ends", bundle: .module), isOn: settings.transcribeAfterRecording)
            }
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
            HStack(spacing: 10) {
                if state == .granted { Badge(text: String(localized: "Allowed", bundle: .module), style: .success) }
                else { Badge(text: String(localized: "Not allowed", bundle: .module), style: .warning) }
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
                    ForEach(model.models.catalog.models(of: .transcription)) { m in Text(m.displayName).tag(m.id) }
                }
                ModelsListView(model: model, modelsToShow: model.models.catalog.models(of: .transcription))
            }
            Section(String(localized: "Local summaries", bundle: .module)) {
                Picker(String(localized: "Use", bundle: .module), selection: settings.summaryModelID) {
                    ForEach(model.models.catalog.models(of: .summary)) { m in Text(m.displayName).tag(m.id) }
                }
                ModelsListView(model: model, modelsToShow: model.models.catalog.models(of: .summary))
            }
            Section(String(localized: "Speakers", bundle: .module)) {
                ModelsListView(model: model, modelsToShow: model.models.catalog.models(of: .speakers))
            }
            Section {
                LabeledContent(String(localized: "Space used by models", bundle: .module)) {
                    HStack(spacing: 12) {
                        Text(String(localized: "\(ByteCountFormatter.string(fromByteCount: model.models.sizeOnDisk(), countStyle: .file)) · stored on this Mac, used offline", bundle: .module))
                            .foregroundStyle(Color.meety.textSecondary)
                        Button(String(localized: "Show in Finder", bundle: .module)) { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.models]) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct DictationSettings: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    @Environment(\.openWindow) private var openWindow
    @State private var key = ""
    @State private var keyState: KeyState = .idle
    @State private var axState = Permissions.accessibility
    private let axTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    enum KeyState { case idle, checking, valid, invalid }

    var dictationModels: [ModelInfo] { DictationModels.all.compactMap { model.models.catalog.model(id: $0) } }

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Dictate anywhere with a shortcut", bundle: .module), isOn: settings.dictationEnabled)
                Picker(String(localized: "Shortcut", bundle: .module), selection: settings.dictationShortcut) {
                    ForEach(DictationShortcut.allCases) { s in Text(verbatim: s.title).tag(s) }
                }
                .disabled(!model.settings.dictationEnabled)
                if !model.dictation.shortcutAvailable {
                    Label(String(localized: "Another app is already using this shortcut. Pick a different one.", bundle: .module), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.meety.warning).font(MeetyFont.callout)
                }
                Text(String(localized: "Tap the shortcut to start and again to stop, or hold it while you talk. The text is pasted where your cursor is and copied.", bundle: .module))
                    .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
                Picker(String(localized: "Animation", bundle: .module), selection: settings.dictationWaveStyle) {
                    ForEach(DictationWaveStyle.allCases) { s in Text(s.title).tag(s) }
                }
                Toggle(String(localized: "Paste at the cursor", bundle: .module), isOn: settings.dictationPaste)
                if model.settings.dictationPaste {
                    PermissionRow(title: String(localized: "Accessibility", bundle: .module), state: axState) { Permissions.requestAccessibility() }
                        .onReceive(axTimer) { _ in axState = Permissions.accessibility }
                }
                LabeledContent(String(localized: "History", bundle: .module)) {
                    Button(String(localized: "Show dictations", bundle: .module)) { openWindow(id: "dictations"); NSApp.activate(ignoringOtherApps: true) }
                }
            }
            Section(String(localized: "Groq (first option)", bundle: .module)) {
                Toggle(String(localized: "Use Groq when there's a key", bundle: .module), isOn: settings.dictationUseGroq)
                SecureField(String("gsk_…"), text: $key)
                HStack {
                    Button(String(localized: "Save key", bundle: .module)) { saveKey() }.disabled(key.isEmpty || keyState == .checking)
                    switch keyState {
                    case .checking: ProgressView().controlSize(.small)
                    case .valid: Label(String(localized: "Saved in your Keychain", bundle: .module), systemImage: "checkmark").foregroundStyle(Color.meety.success).font(MeetyFont.callout)
                    case .invalid: Label(String(localized: "Groq didn't accept this key", bundle: .module), systemImage: "xmark").foregroundStyle(Color.meety.warning).font(MeetyFont.callout)
                    case .idle: EmptyView()
                    }
                    Spacer()
                    if Groq.apiKey != nil {
                        Button(String(localized: "Remove", bundle: .module)) { Groq.apiKey = nil; key = ""; keyState = .idle }
                    }
                    Link(String(localized: "Get a key", bundle: .module), destination: Groq.consoleURL).font(MeetyFont.callout)
                }
                Text(String(localized: "With a key, the dictation audio goes to Groq, which is fast and accurate. Meetings are always transcribed on this Mac.", bundle: .module))
                    .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
            }
            Section(String(localized: "On this Mac", bundle: .module)) {
                Picker(String(localized: "Model", bundle: .module), selection: settings.dictationModelID) {
                    ForEach(dictationModels) { m in Text(verbatim: "\(DictationModels.title(m.id)) · \(m.displayName)").tag(m.id) }
                }
                ModelsListView(model: model, modelsToShow: dictationModels)
                Text(String(localized: "Used when there's no Groq key, and as a backup when Groq fails. Nothing leaves your Mac.", bundle: .module))
                    .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { key = Groq.apiKey ?? ""; if !key.isEmpty { keyState = .valid } }
        .onChange(of: model.settings.dictationEnabled) { model.dictation.applySettings() }
        .onChange(of: model.settings.dictationShortcut) { model.dictation.applySettings() }
        .onChange(of: model.settings.dictationWaveStyle) { model.dictation.applySettings() }
    }

    func saveKey() {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keyState = .checking
        Task {
            if await Groq.check(key: k) { Groq.apiKey = k; keyState = .valid } else { keyState = .invalid }
        }
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
                Text(String(localized: "Meety uses the Claude Code or Codex command line tools that come with the Mac apps or that you installed from the terminal. They use your own account.", bundle: .module)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
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
                    if savedKey { Label(String(localized: "Saved in your Keychain", bundle: .module), systemImage: "checkmark").foregroundStyle(Color.meety.success).font(MeetyFont.callout) }
                    Spacer()
                    Link(String(localized: "Get a key", bundle: .module), destination: vendor.consoleURL).font(MeetyFont.callout)
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
            else if let found {
                HStack(spacing: 8) {
                    Badge(text: found.originTitle, style: .success)
                    Text(found.url.path).font(MeetyFont.caption).foregroundStyle(Color.meety.textSecondary).lineLimit(1).truncationMode(.middle).help(found.url.path)
                }
            }
            else { Badge(text: String(localized: "Not found", bundle: .module), style: .neutral) }
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
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Meety").font(MeetyFont.sectionTitle)
                        Text(String(localized: "Version \(version)", bundle: .module)).foregroundStyle(Color.meety.textSecondary)
                        Text(String(localized: "Meety is free and open source. Made by Oka.", bundle: .module)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                if let h = model.engineHealth {
                    LabeledContent(String(localized: "Speech engine", bundle: .module), value: "Python \(h.python) · MLX \(h.mlx ?? "?") · \(h.device ?? "")")
                } else if model.engineMissing {
                    LabeledContent(String(localized: "Speech engine", bundle: .module), value: String(localized: "Missing", bundle: .module))
                }
                LabeledContent(String(localized: "Memory", bundle: .module), value: "\(ModelCatalog.physicalMemoryGB) GB")
            }
            Section {
                Button(String(localized: "Export diagnostics…", bundle: .module)) { exportDiagnostics() }
                Text(String(localized: "A text file with the engine log and your settings, without any transcript. Useful when reporting a problem.", bundle: .module)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
            }
            Section {
                Link("GitHub", destination: URL(string: "https://github.com/oka-projects/meety")!)
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
