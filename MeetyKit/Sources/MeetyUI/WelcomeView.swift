import MeetyCore
import SwiftUI

/// As boas-vindas: o que é o Meety, as duas permissões e os modelos.
struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var step = Int(ProcessInfo.processInfo.environment["MEETY_STEP"] ?? "") ?? 0
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
            .padding(.horizontal, 40).padding(.top, 36)
            footer
        }
        .frame(width: 560, height: 460)
        .background(Color.meety.window)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    var footer: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
                    Circle().fill(i == step ? Color.meety.accent : Color.meety.fillStrong).frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step > 0 { Button(String(localized: "Back", bundle: .module)) { step -= 1 }.controlSize(.large) }
            if step < 3 {
                Button(String(localized: "Continue", bundle: .module)) { step += 1 }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "Start using Meety", bundle: .module)) { finish() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 40).padding(.bottom, 20).padding(.top, 12)
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
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text(String(localized: "Welcome to Meety", bundle: .module)).font(MeetyFont.sheetTitle).padding(.top, 20)
            Text(String(localized: "Record your meetings, get a transcript you can search, and a summary you can share. Everything runs on your Mac: your conversations stay with you.", bundle: .module))
                .font(.system(size: 14)).lineSpacing(3)
                .multilineTextAlignment(.center).foregroundStyle(Color.meety.textSecondary).frame(maxWidth: 420)
                .padding(.top, 14)
            PrivacyLine(text: String(localized: "Two quick permissions and one download, then you're set.", bundle: .module))
                .padding(.top, 18)
            Spacer()
        }
    }

    var microphone: some View {
        PermissionStep(
            icon: "mic.fill",
            title: String(localized: "Microphone", bundle: .module),
            text: String(localized: "So Meety can hear you. Your voice is recorded on its own track, which is how Meety knows which lines are yours.", bundle: .module),
            granted: micState == .granted,
            buttonTitle: micState == .denied ? String(localized: "Open System Settings", bundle: .module) : String(localized: "Allow microphone", bundle: .module),
            caption: micState == .denied ? nil : String(localized: "macOS will ask you to confirm.", bundle: .module),
            note: nil
        ) {
            if micState == .denied { Permissions.openMicrophoneSettings() }
            else { Task { _ = await Permissions.requestMicrophone(); refresh() } }
        }
    }

    var screen: some View {
        PermissionStep(
            icon: "rectangle.inset.filled.and.person.filled",
            title: String(localized: "System audio", bundle: .module),
            text: String(localized: "So Meety can hear the other people in the call. macOS groups this under Screen & System Audio Recording. Meety never records your screen.", bundle: .module),
            granted: screenProbe ?? (screenState == .granted),
            buttonTitle: String(localized: "Open System Settings", bundle: .module),
            caption: nil,
            note: String(localized: "Turn Meety on in the list that opens. macOS may ask you to quit and reopen Meety afterwards.", bundle: .module)
        ) {
            Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
        }
        .task { screenProbe = await Permissions.probeScreenRecording() }
    }

    var models: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Download the models", bundle: .module)).font(MeetyFont.sheetTitle)
            Text(String(localized: "Meety picked the right sizes for this Mac (\(ModelCatalog.physicalMemoryGB) GB of memory). Everything is stored on this Mac and works offline afterwards.", bundle: .module))
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Color.meety.textSecondary).padding(.top, 8)
            ModelsListView(model: model, modelsToShow: model.models.catalog.recommended(), style: .welcome)
                .padding(.top, 16)
            VStack(spacing: 8) {
                if !model.models.recommendedPending.isEmpty, !model.models.recommendedPending.contains(where: { model.models.isDownloading($0) }) {
                    Button { model.models.downloadRecommended() } label: {
                        Label(String(localized: "Download recommended (\(totalPendingText))", bundle: .module), systemImage: "arrow.down.circle")
                            .font(.system(size: 15, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                } else if model.models.recommendedPending.isEmpty {
                    Label(String(localized: "All set. The models are ready.", bundle: .module), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.meety.success).font(MeetyFont.headline)
                }
                Text(String(localized: "One time only. You can keep using Meety while it downloads.", bundle: .module))
                    .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.top, 16)
            Spacer()
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
    let caption: String?
    let note: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroIcon(systemName: icon, size: 84,
                     tint: granted ? Color.meety.success : Color.meety.accentText,
                     background: granted ? Color.meety.successTint : Color.meety.accentTint)
            Text(title).font(MeetyFont.sheetTitle).padding(.top, 18)
            Text(text).font(.system(size: 14)).lineSpacing(3).multilineTextAlignment(.center)
                .foregroundStyle(Color.meety.textSecondary).frame(maxWidth: 440).padding(.top, 12)
            if granted {
                Badge(text: String(localized: "Allowed", bundle: .module), style: .success).padding(.top, 20)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 20)
                if let caption {
                    Text(caption).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).padding(.top, 8)
                }
            }
            if let note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Color.meety.textSecondary)
                    Text(note).foregroundStyle(Color.meety.textSecondary)
                }
                .font(MeetyFont.body)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.meety.fill, in: RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous))
                .padding(.top, 20)
            }
            Spacer()
        }
    }
}
