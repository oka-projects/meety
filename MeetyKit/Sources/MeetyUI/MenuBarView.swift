import MeetyCore
import SwiftUI

/// O menu da barra de menus: gravar e parar, tempo, abrir a janela.
public struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        if model.recorder.isRecording {
            Text(String(localized: "Recording · \(TranscriptExporter.clock(model.recorder.elapsed))", bundle: .module))
            Button { model.stopRecording() } label: { Label(String(localized: "Stop recording", bundle: .module), systemImage: "stop.fill") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        } else {
            Button { model.startRecording() } label: { Label(String(localized: "Start recording", bundle: .module), systemImage: "circle.fill") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.recorder.phase != .idle)
        }
        if model.settings.dictationEnabled {
            Divider()
            Button {
                model.dictation.toggle()
            } label: {
                Label(model.dictation.state == .recording ? String(localized: "Stop dictation", bundle: .module) : String(localized: "Dictate (\(model.settings.dictationShortcut.title))", bundle: .module),
                      systemImage: "mic")
            }
            .disabled(model.dictation.state == .transcribing || model.recorder.isRecording)
            if model.dictation.failedRecording != nil {
                Button(String(localized: "Try the last dictation again", bundle: .module)) { model.dictation.retryFailed() }
            }
            if let last = model.dictation.history.items.first {
                Button(String(localized: "Copy last dictation", bundle: .module)) { model.dictation.copy(last) }
            }
            Button(String(localized: "Dictation history…", bundle: .module)) {
                openWindow(id: "dictations")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Divider()
        Button(String(localized: "Open Meety", bundle: .module)) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text(String(localized: "Settings…", bundle: .module)) }.keyboardShortcut(",")
        Divider()
        Button(String(localized: "Quit Meety", bundle: .module)) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    /// Onda (modelo) em repouso; círculo vermelho ao gravar.
    public static func label(model: AppModel) -> some View {
        Group {
            if model.recorder.isRecording {
                Image(systemName: "record.circle.fill").foregroundStyle(.red).symbolRenderingMode(.hierarchical)
            } else {
                Image(systemName: "waveform")
            }
        }
    }
}
