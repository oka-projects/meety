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
            Button(String(localized: "Stop recording", bundle: .module)) { model.stopRecording() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        } else {
            Button(String(localized: "Start recording", bundle: .module)) { model.startRecording() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.recorder.phase != .idle)
        }
        Divider()
        Button(String(localized: "Open Meety", bundle: .module)) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text(String(localized: "Settings…", bundle: .module)) }
        Divider()
        Button(String(localized: "Quit Meety", bundle: .module)) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    public static func label(model: AppModel) -> some View {
        Image(systemName: model.recorder.isRecording ? "record.circle.fill" : "waveform.and.mic")
            .symbolRenderingMode(model.recorder.isRecording ? .multicolor : .monochrome)
    }
}
