import MeetyCore
import MeetyUI
import Sparkle
import SwiftUI

@main
struct MeetyApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Sparkle: confere atualizações sozinho (uma vez por dia) e pelo menu.
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        Window("Meety", id: "main") {
            RootView(model: model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "Import Audio or Video…")) { model.chooseFilesToImport() }.keyboardShortcut("o")
                Button(model.recorder.isRecording ? String(localized: "Stop Recording") : String(localized: "Start Recording")) { model.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater.updater)
            }
            CommandGroup(after: .help) {
                Button(String(localized: "Show Welcome Again")) { model.showWelcome = true }
            }
        }

        MenuBarExtra { MenuBarView(model: model) } label: { MenuBarView.label(model: model) }

        Settings { SettingsView(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    /// Arquivos soltos no ícone do Dock ou abertos com o Meety.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in model?.importFiles(urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.recorder.isRecording else { return .terminateNow }
        // Encerra a gravação antes de sair, para não perder o áudio.
        Task { @MainActor in
            model.stopRecording()
            try? await Task.sleep(for: .seconds(2))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// "Verificar atualizações…", só habilitado quando o Sparkle pode checar.
struct CheckForUpdatesView: View {
    @State private var canCheck = false
    let updater: SPUUpdater

    var body: some View {
        Button(String(localized: "Check for Updates…")) { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
