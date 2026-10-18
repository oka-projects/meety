import MeetyCore
import SwiftUI

/// O bloco de gravar no topo da barra lateral: botão, estado, medidores e microfone.
struct RecordBar: View {
    @Bindable var model: AppModel
    var settings: Bindable<MeetySettings> { Bindable(model.settings) }
    @State private var microphones: [Permissions.Microphone] = []

    var recording: Bool { model.recorder.isRecording }
    var busy: Bool { model.recorder.phase == .starting || model.recorder.phase == .finishing }

    var body: some View {
        Card(padding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    RecordButton(recording: recording, busy: busy) { model.toggleRecording() }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    VStack(alignment: .leading, spacing: 3) {
                        if recording {
                            Text(TranscriptExporter.clock(model.recorder.elapsed)).font(MeetyFont.timeBlock)
                            HStack(spacing: 6) {
                                Circle().fill(Color.meety.recordFill).frame(width: 7, height: 7)
                                Text(String(localized: "Recording", bundle: .module)).foregroundStyle(Color.meety.recordText)
                            }
                            .font(MeetyFont.body)
                        } else {
                            Text(String(localized: "Record", bundle: .module)).font(MeetyFont.headline)
                            Text(String(localized: "Your voice and the call audio", bundle: .module))
                                .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    if !recording {
                        Menu {
                            Picker(String(localized: "Microphone", bundle: .module), selection: settings.microphoneID) {
                                Text(String(localized: "Default", bundle: .module)).tag(String?.none)
                                ForEach(microphones) { m in Text(m.name).tag(Optional(m.id)) }
                            }
                            .pickerStyle(.inline)
                        } label: { Image(systemName: "mic") }
                        .menuStyle(.button).menuIndicator(.hidden).fixedSize().controlSize(.small)
                        .help(String(localized: "Microphone", bundle: .module))
                        .onAppear { microphones = Permissions.microphones() }
                    }
                }
                if recording {
                    VStack(spacing: 8) {
                        LevelMeter(level: model.recorder.micLevel, label: String(localized: "You", bundle: .module))
                        LevelMeter(level: model.recorder.systemLevel, label: String(localized: "Others", bundle: .module))
                    }
                    if !model.recorder.microphoneGranted {
                        Label(String(localized: "Microphone off: recording only the other participants.", bundle: .module), systemImage: "mic.slash")
                            .font(MeetyFont.callout).foregroundStyle(Color.meety.warning).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 6)
    }
}

/// O botão redondo vermelho: ponto branco em repouso, quadrado branco ao gravar.
struct RecordButton: View {
    var recording: Bool
    var busy: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.meety.recordTint).frame(width: 44, height: 44)
                Circle().fill(Color.meety.recordFill).frame(width: 36, height: 36)
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if recording {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 14, height: 14)
                } else {
                    Circle().fill(.white).frame(width: 16, height: 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(recording ? String(localized: "Stop recording", bundle: .module) : String(localized: "Start recording", bundle: .module))
    }
}

struct LevelMeter: View {
    var level: Float
    var label: String
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).frame(width: 50, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.meety.fillStrong)
                    Capsule().fill(level > 0.9 ? Color.meety.warning : Color.meety.accent).frame(width: max(3, g.size.width * CGFloat(level)))
                }
            }
            .frame(height: 4)
            .animation(.linear(duration: 0.15), value: level)
        }
    }
}
