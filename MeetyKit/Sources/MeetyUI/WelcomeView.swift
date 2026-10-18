import MeetyCore
import SwiftUI

/// As boas-vindas: o que é o Meety, as duas permissões e os modelos.
struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var step = 0
    @State private var micState = Permissions.microphone
    @State private var screenState = Permissions.screenRecording
    @State private var screenProbe: Bool?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: intro
                case 1: microphone
                case 2: screen
                default: models
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
            Divider()
            HStack {
                HStack(spacing: 6) { ForEach(0..<4) { i in Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7) } }
                Spacer()
                if step > 0 { Button(String(localized: "Back", bundle: .module)) { step -= 1 } }
                if step < 3 {
                    Button(String(localized: "Continue", bundle: .module)) { step += 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "Start using Meety", bundle: .module)) { finish() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    func refresh() {
        micState = Permissions.microphone
        screenState = Permissions.screenRecording
        // A sondagem (SCShareableContent) dispara o pedido do macOS: só no passo da permissão.
        if step == 2 { Task { screenProbe = await Permissions.probeScreenRecording() } }
    }

    func finish() {
        model.settings.welcomeDone = true
        model.showWelcome = false
    }

    var intro: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.mic").font(.system(size: 64)).foregroundStyle(.tint)
            Text(String(localized: "Welcome to Meety", bundle: .module)).font(.largeTitle.weight(.bold))
            Text(String(localized: "Record your meetings, get a transcript you can search, and a summary you can share. Everything runs on your Mac: your conversations stay with you.", bundle: .module))
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            Text(String(localized: "Two quick permissions and one download, then you're set.", bundle: .module)).font(.callout)
        }
    }

    var microphone: some View {
        PermissionStep(
            icon: "mic.fill",
            title: String(localized: "Microphone", bundle: .module),
            text: String(localized: "So Meety can hear you. Your voice is recorded on its own track, which is how Meety knows which lines are yours.", bundle: .module),
            granted: micState == .granted,
            buttonTitle: micState == .denied ? String(localized: "Open System Settings", bundle: .module) : String(localized: "Allow microphone", bundle: .module)
        ) {
            if micState == .denied { Permissions.openMicrophoneSettings() }
            else { Task { _ = await Permissions.requestMicrophone(); refresh() } }
        }
    }

    var screen: some View {
        PermissionStep(
            icon: "rectangle.inset.filled.and.person.filled",
            title: String(localized: "System audio", bundle: .module),
            text: String(localized: "So Meety can hear the other people in the call. macOS groups this under \"Screen & System Audio Recording\". Meety never records your screen, only the sound.\n\nAfter turning it on, macOS may ask you to quit and reopen Meety.", bundle: .module),
            granted: screenProbe ?? (screenState == .granted),
            buttonTitle: String(localized: "Open System Settings", bundle: .module)
        ) {
            Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
        }
        .task { screenProbe = await Permissions.probeScreenRecording() }
    }

    var models: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(systemName: "arrow.down.circle.fill").font(.largeTitle).foregroundStyle(.tint); Text(String(localized: "Download the models", bundle: .module)).font(.title.weight(.semibold)) }
            Text(String(localized: "Meety picked the right sizes for this Mac (\(ModelCatalog.physicalMemoryGB) GB of memory). This happens once; after that, everything works offline.", bundle: .module))
                .foregroundStyle(.secondary)
            ModelsListView(model: model, modelsToShow: model.models.catalog.recommended(), compact: true)
            if !model.models.recommendedPending.isEmpty, !model.models.recommendedPending.contains(where: { model.models.isDownloading($0) }) {
                Button { model.models.downloadRecommended() } label: {
                    Label(String(localized: "Download recommended (\(totalPendingText))", bundle: .module), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text(String(localized: "You can keep using Meety while this downloads, and change models later in Settings.", bundle: .module)).font(.caption).foregroundStyle(.secondary)
        }
    }

    var totalPendingText: String {
        ByteCountFormatter.string(fromByteCount: model.models.recommendedPending.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file)
    }
}

struct PermissionStep: View {
    let icon: String
    let title: String
    let text: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 56)).foregroundStyle(granted ? .green : .accentColor)
            Text(title).font(.title.weight(.semibold))
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            if granted {
                Label(String(localized: "Allowed", bundle: .module), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            } else {
                Button(buttonTitle, action: action).buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }
}
