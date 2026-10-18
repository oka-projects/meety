import AVFoundation
import CoreMedia
import ExceptionCatcher
import Foundation
import Observation
import ScreenCaptureKit

/// Grava a reunião com o ScreenCaptureKit: o áudio do sistema (as outras pessoas) e o microfone
/// (você) em dois arquivos AAC separados. As duas trilhas ficam guardadas: é por elas que o Meety
/// sabe quem é "Você". A mixagem para ouvir é feita depois pelo `AudioMixer`.
///
/// Concorrência: os escritores vivem na `writerQueue`, que também é a fila dos callbacks do SCK,
/// então todo append é serializado. O estado observável muda sempre na main.
@MainActor
@Observable
public final class Recorder: NSObject {

    public enum Phase: Equatable { case idle, starting, recording, finishing, failed(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var elapsed: TimeInterval = 0
    /// Nível 0...1 de cada fonte, para os medidores.
    public private(set) var micLevel: Float = 0
    public private(set) var systemLevel: Float = 0
    public private(set) var microphoneGranted = true

    public struct Result: Sendable {
        public let startedAt: Date
        public let duration: TimeInterval
        public let micTrack: URL?
        public let systemTrack: URL?
    }

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private let writerQueue = DispatchQueue(label: "dev.oka.meety.recorder.writer")
    @ObservationIgnored private let screenQueue = DispatchQueue(label: "dev.oka.meety.recorder.screen")
    @ObservationIgnored nonisolated private let writers = Writers()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var outputFolder: URL?
    @ObservationIgnored private var levelTick = 0

    /// Estado dos escritores, acessado SÓ na writerQueue.
    private final class Writers: @unchecked Sendable {
        var system: (AVAssetWriter, AVAssetWriterInput)?
        var mic: (AVAssetWriter, AVAssetWriterInput)?
        var systemStarted = false
        var micStarted = false
        var systemURL: URL?
        var micURL: URL?
        var stopping = false
        var micPeak: Float = 0
        var systemPeak: Float = 0
        func reset() {
            system = nil; mic = nil; systemStarted = false; micStarted = false
            systemURL = nil; micURL = nil; stopping = false; micPeak = 0; systemPeak = 0
        }
    }

    public var isRecording: Bool { phase == .recording }

    // MARK: - Início

    /// Começa a gravar. As trilhas vão para `folder/mic.m4a` e `folder/system.m4a`.
    public func start(into folder: URL, microphoneID: String? = nil) async {
        guard phase == .idle || isFailed else { return }
        phase = .starting
        elapsed = 0
        outputFolder = folder

        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = micGranted
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { fail(String(localized: "No display available to capture audio from.", bundle: .module)); return }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            // O SCK exige vídeo; pedimos o mínimo e ignoramos os quadros.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.queueDepth = 6
            if micGranted {
                config.captureMicrophone = true
                config.microphoneCaptureDeviceID = microphoneID
            }

            try writerQueue.sync { try self.setupWriters(folder: folder, captureMic: micGranted) }

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writerQueue)
            if micGranted { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: writerQueue) }
            try await stream.startCapture()
            self.stream = stream

            startDate = Date()
            phase = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            fail(Self.describe(error))
        }
    }

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func tick() {
        guard let start = startDate else { return }
        elapsed = Date().timeIntervalSince(start)
        writerQueue.async { [writers] in
            let m = writers.micPeak, s = writers.systemPeak
            writers.micPeak *= 0.6; writers.systemPeak *= 0.6
            Task { @MainActor [weak self] in
                self?.micLevel = min(1, m * 3)
                self?.systemLevel = min(1, s * 3)
            }
        }
    }

    private func setupWriters(folder: URL, captureMic: Bool) throws {
        writers.reset()
        let sysURL = folder.appendingPathComponent("system.m4a")
        writers.system = try Self.makeWriter(url: sysURL)
        writers.systemURL = sysURL
        if captureMic {
            let micURL = folder.appendingPathComponent("mic.m4a")
            writers.mic = try Self.makeWriter(url: micURL)
            writers.micURL = micURL
        }
    }

    /// Escritor AAC. Sem passthrough: o PCM Float32 planar do SCK trava o writer em passthrough
    /// (nada é gravado e o encerramento estoura). Com AAC explícito ele transcodifica de boa.
    nonisolated private static func makeWriter(url: URL) throws -> (AVAssetWriter, AVAssetWriterInput) {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 160_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) { writer.add(input) }
        writer.startWriting()
        return (writer, input)
    }

    // MARK: - Parada

    /// Para e devolve as trilhas gravadas (as vazias viram `nil`).
    public func stop() async -> Result? {
        guard phase == .recording else { return nil }
        phase = .finishing
        timer?.invalidate(); timer = nil
        if let stream { try? await stream.stopCapture() }
        stream = nil
        let started = startDate ?? Date()
        let duration = Date().timeIntervalSince(started)

        // finishWriting() TRAVA se nenhuma amostra chegou: nesse caso é cancelWriting().
        let (sys, mic): (URL?, URL?) = await withCheckedContinuation { cont in
            writerQueue.async { [writers] in
                writers.stopping = true
                let group = DispatchGroup()
                func finalize(_ pair: (AVAssetWriter, AVAssetWriterInput)?, started: Bool) {
                    guard let (writer, input) = pair, writer.status == .writing else { return }
                    guard started else { writer.cancelWriting(); return }
                    // markAsFinished/finishWriting podem lançar NSException em estados de borda; o
                    // Swift não captura, então o MTExceptionCatcher evita derrubar o app.
                    group.enter()
                    _ = MTExceptionCatcher.catching { input.markAsFinished() }
                    let err = MTExceptionCatcher.catching { writer.finishWriting { group.leave() } }
                    if err != nil {
                        if writer.status == .writing { writer.cancelWriting() }
                        group.leave()
                    }
                }
                finalize(writers.system, started: writers.systemStarted)
                finalize(writers.mic, started: writers.micStarted)
                group.notify(queue: self.writerQueue) {
                    cont.resume(returning: (Self.validFile(writers.systemURL), Self.validFile(writers.micURL)))
                }
            }
        }
        phase = .idle
        elapsed = 0
        micLevel = 0; systemLevel = 0
        if sys == nil && mic == nil { return nil }
        return Result(startedAt: started, duration: duration, micTrack: mic, systemTrack: sys)
    }

    nonisolated private static func validFile(_ url: URL?) -> URL? {
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1024 else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return url
    }

    private func fail(_ message: String) {
        timer?.invalidate(); timer = nil
        stream = nil
        writerQueue.async { [writers] in
            writers.stopping = true
            writers.system?.0.cancelWriting(); writers.mic?.0.cancelWriting()
        }
        phase = .failed(message)
    }

    public func reset() { if isFailed { phase = .idle } }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == SCStreamError.errorDomain {
            return String(localized: "Meety needs permission to record system audio. Open System Settings > Privacy & Security > Screen & System Audio Recording, turn on Meety and try again.", bundle: .module)
        }
        return String(localized: "Couldn't start recording: \(error.localizedDescription)", bundle: .module)
    }
}

// MARK: - SCStreamDelegate / SCStreamOutput (na writerQueue)

extension Recorder: SCStreamDelegate, SCStreamOutput {
    nonisolated public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.fail(String(localized: "Recording stopped: \(error.localizedDescription)", bundle: .module)) }
    }

    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sb) else { return }
        // Estamos na writerQueue (fila dos callbacks): é ela que protege o conteúdo de `writers`.
        let w = writers
        guard !w.stopping else { return }
        switch type {
        case .microphone:
            Self.append(sb, pair: w.mic, started: &w.micStarted)
            w.micPeak = max(w.micPeak, Self.peak(sb))
        case .audio:
            Self.append(sb, pair: w.system, started: &w.systemStarted)
            w.systemPeak = max(w.systemPeak, Self.peak(sb))
        default: break
        }
    }

    nonisolated private static func append(_ sb: CMSampleBuffer, pair: (AVAssetWriter, AVAssetWriterInput)?, started: inout Bool) {
        guard let (writer, input) = pair, writer.status == .writing else { return }
        if !started {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }

    /// Pico aproximado do buffer (Float32, qualquer layout), para os medidores.
    nonisolated private static func peak(_ sb: CMSampleBuffer) -> Float {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { return 0 }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr,
              let p = ptr, length >= 4 else { return 0 }
        let floats = UnsafeRawPointer(p).assumingMemoryBound(to: Float.self)
        let n = length / 4
        var m: Float = 0
        var i = 0
        while i < n { m = max(m, abs(floats[i])); i += 16 }
        return m
    }
}
