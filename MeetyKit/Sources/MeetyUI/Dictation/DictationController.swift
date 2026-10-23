import AppKit
import AVFoundation
import MeetyCore
import Observation

/// Ditado (vindo do OkaMic): atalho → grava → transcreve (Groq ou Mac) → cola no cursor, copia e
/// guarda no histórico. Tocar o atalho liga e desliga; segurar grava até soltar.
@MainActor
@Observable
public final class DictationController {
    public enum State { case idle, recording, transcribing }

    public private(set) var state = State.idle
    /// O atalho escolhido está registrado (false: outro app já usa a mesma combinação).
    public private(set) var shortcutAvailable = true
    /// Gravação cuja transcrição falhou, para tentar de novo pelo menu.
    public private(set) var failedRecording: DictationRecorder.Recording?
    public let history = DictationHistory()

    /// Quando devolve true, o ditado não começa (uma reunião está sendo gravada).
    @ObservationIgnored public var isBlocked: () -> Bool = { false }

    @ObservationIgnored private let settings: MeetySettings
    @ObservationIgnored private let models: ModelManager
    @ObservationIgnored private let panel = DictationPanel()
    @ObservationIgnored private let recorder = DictationRecorder()
    @ObservationIgnored private let hotkeys = DictationHotkeys()
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var pressedAt = Date()
    /// Enquanto false, o estado é "gravando" mas o microfone ainda está abrindo.
    @ObservationIgnored private var micReady = false

    /// Segurar o atalho por mais que isto e soltar encerra a gravação (aperte e fale).
    private static let holdThreshold: TimeInterval = 0.6

    public init(settings: MeetySettings, models: ModelManager) {
        self.settings = settings
        self.models = models
        recorder.onLevel = { [weak self] level, bands in
            DispatchQueue.main.async { self?.panel.push(level: level, bands: bands) }
        }
        recorder.onFirstAudio = { [weak self] in self?.micOpened() }
        panel.onStop = { [weak self] in self?.stop() }
        panel.onCancel = { [weak self] in self?.cancel() }
        hotkeys.handler = { [weak self] action, pressed in
            MainActor.assumeIsolated { self?.handle(action, pressed) }
        }
        applySettings()
    }

    /// Registra ou tira o atalho conforme as Configurações. Chamado quando elas mudam.
    public func applySettings() {
        panel.model.style = settings.dictationWaveStyle
        panel.model.shortcut = settings.dictationShortcut.title
        if settings.dictationEnabled {
            shortcutAvailable = hotkeys.register(settings.dictationShortcut)
        } else {
            hotkeys.unregister(.dictate)
            shortcutAvailable = true
            if state == .recording { cancel() }
        }
    }

    /// O transcritor com as Configurações de agora.
    public var transcriber: DictationTranscriber {
        let local = models.catalog.model(id: settings.dictationModelID).flatMap { models.isInstalled($0) ? $0.folder : nil }
        let key = settings.dictationUseGroq ? Groq.apiKey : nil
        return DictationTranscriber(groqKey: key, localModel: local, language: settings.language.code)
    }

    private func handle(_ action: DictationHotkeys.Action, _ pressed: Bool) {
        switch (action, pressed) {
        case (.dictate, true):
            pressedAt = Date()
            toggle()
        case (.dictate, false):
            if state == .recording, Date().timeIntervalSince(pressedAt) > Self.holdThreshold { stop() }
        case (.escape, true): cancel()
        default: break
        }
    }

    public func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .transcribing: NSSound.beep()
        }
    }

    public func start() {
        guard state == .idle else { return }
        if isBlocked() {
            panel.show(.failed(String(localized: "Meety is recording a meeting", bundle: .module)))
            return
        }
        let transcriber = transcriber
        guard transcriber.canTranscribe else {
            panel.show(.failed(DictationError.noTranscriber.localizedDescription))
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { if ok { self.start() } }
            }
            return
        case .denied, .restricted:
            panel.show(.failed(String(localized: "Allow the microphone in System Settings > Privacy", bundle: .module)))
            return
        default: break
        }
        // O painel aparece na hora; o microfone abre em segundo plano (com AirPods leva ~3 s).
        state = .recording
        micReady = false
        panel.model.seconds = 0
        panel.model.notice = ""
        panel.resetLevels()
        panel.show(.connecting)
        hotkeys.registerEscape()
        transcriber.warmUp()
        let uid = settings.microphoneID.flatMap { id in Permissions.microphones().contains { $0.id == id } ? id : nil }  // desconectado → padrão
        recorder.start(deviceUID: uid) { [weak self] error in
            guard let self, let error, self.state == .recording, !self.micReady else { return }
            self.endRecording()
            self.recorder.cancel()
            self.panel.show(.failed(error.localizedDescription))
            self.state = .idle
        }
    }

    /// Primeiro áudio chegou: agora sim está gravando. O "Pop" avisa que pode falar.
    private func micOpened() {
        guard state == .recording, !micReady else { return }
        micReady = true
        startedAt = Date()
        panel.show(.recording)
        NSSound(named: "Pop")?.play()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.model.seconds = Int(Date().timeIntervalSince(self.startedAt))
            }
        }
    }

    public func stop() {
        guard state == .recording else { return }
        guard micReady else { return cancel() }  // parou antes de o microfone abrir
        endRecording()
        guard let recording = recorder.stop() else { state = .idle; return }
        NSSound(named: "Tink")?.play()
        if recording.duration < 0.5 {  // toque sem querer
            recording.discard()
            panel.hide()
            state = .idle
            return
        }
        send(recording)
    }

    public func cancel() {
        guard state == .recording else { return }
        endRecording()
        recorder.cancel()
        NSSound(named: "Bottle")?.play()
        panel.hide()
        state = .idle
    }

    public func retryFailed() {
        guard state == .idle, let recording = failedRecording else { return }
        failedRecording = nil
        send(recording)
    }

    public func copy(_ item: Dictation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        panel.show(.done(String(localized: "Copied", bundle: .module), String(localized: "ready to paste", bundle: .module)))
    }

    // MARK: - Internos

    private func endRecording() {
        clock?.invalidate()
        clock = nil
        hotkeys.unregister(.escape)
    }

    private func send(_ recording: DictationRecorder.Recording) {
        state = .transcribing
        panel.model.notice = ""
        panel.show(.transcribing)
        let transcriber = transcriber
        Task {
            do {
                let result = try await transcriber.transcribe(recording) { reason in
                    Task { @MainActor in
                        self.panel.model.notice = String(localized: "Groq didn't respond (\(reason))", bundle: .module)
                    }
                }
                self.finish(result.text, result.origin, recording)
            } catch {
                self.failedRecording?.discard()
                self.failedRecording = recording
                NSSound(named: "Basso")?.play()
                self.panel.show(.failed(error.localizedDescription))
                self.state = .idle
            }
        }
    }

    private func finish(_ text: String, _ origin: DictationOrigin, _ recording: DictationRecorder.Recording) {
        recording.discard()
        state = .idle
        guard !text.isEmpty else {
            panel.show(.failed(String(localized: "Nothing was heard", bundle: .module)))
            return
        }
        history.add(Dictation(id: UUID(), date: Date(), text: text, origin: origin, duration: recording.duration))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let via = String(localized: "via \(origin.title)", bundle: .module)
        if settings.dictationPaste, Permissions.accessibility == .granted {
            pasteAtCursor()
            panel.show(.done(String(localized: "Pasted", bundle: .module), String(localized: "and copied · \(via)", bundle: .module)))
        } else if settings.dictationPaste {
            panel.show(.done(String(localized: "Copied", bundle: .module), String(localized: "allow Meety in Accessibility to paste automatically", bundle: .module)))
        } else {
            panel.show(.done(String(localized: "Copied", bundle: .module), via))
        }
    }

    private func pasteAtCursor() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // V
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
