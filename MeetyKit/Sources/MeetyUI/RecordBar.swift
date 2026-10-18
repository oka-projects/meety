import MeetyCore
import SwiftUI

/// O botão de gravar, com os medidores das duas fontes e o tempo. Fica no topo da barra lateral.
struct RecordBar: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    @State private var microphones: [Permissions.Microphone] = []

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { model.toggleRecording() } label: {
                    ZStack {
                        Circle().fill(model.recorder.isRecording ? Color.red.opacity(0.15) : Color.red).frame(width: 44, height: 44)
                        if model.recorder.isRecording {
                            RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 18, height: 18)
                        } else if model.recorder.phase == .starting || model.recorder.phase == .finishing {
                            ProgressView().controlSize(.small)
                        } else {
                            Circle().fill(.white).frame(width: 16, height: 16)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.recorder.phase == .starting || model.recorder.phase == .finishing)
                .help(model.recorder.isRecording ? String(localized: "Stop recording", bundle: .module) : String(localized: "Start recording", bundle: .module))
                .keyboardShortcut("r", modifiers: [.command, .shift])

                VStack(alignment: .leading, spacing: 4) {
                    if model.recorder.isRecording {
                        Text(TranscriptExporter.clock(model.recorder.elapsed)).font(.title3.monospacedDigit().weight(.semibold))
                        LevelMeter(level: model.recorder.micLevel, label: String(localized: "You", bundle: .module))
                        LevelMeter(level: model.recorder.systemLevel, label: String(localized: "Others", bundle: .module))
                    } else {
                        Text(String(localized: "Record", bundle: .module)).font(.headline)
                        Text(String(localized: "Your voice and the call audio", bundle: .module)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !model.recorder.isRecording {
                    Menu {
                        Picker(String(localized: "Microphone", bundle: .module), selection: settings.microphoneID) {
                            Text(String(localized: "Default", bundle: .module)).tag(String?.none)
                            ForEach(microphones) { m in Text(m.name).tag(Optional(m.id)) }
                        }
                        .pickerStyle(.inline)
                    } label: { Image(systemName: "mic") }
                    .menuStyle(.borderlessButton).frame(width: 24)
                    .onAppear { microphones = Permissions.microphones() }
                }
            }
            if model.recorder.isRecording, !model.recorder.microphoneGranted {
                Label(String(localized: "Microphone off: recording only the other participants.", bundle: .module), systemImage: "mic.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
    }
}

struct LevelMeter: View {
    var level: Float
    var label: String
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(level > 0.85 ? Color.orange : Color.green).frame(width: max(2, g.size.width * CGFloat(level)))
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.15), value: level)
        }
    }
}
