import Accelerate
import AVFoundation

/// Grava o ditado em dois arquivos ao mesmo tempo: AAC 16 kHz mono (pequeno, sobe rápido para
/// a Groq) e PCM float32 cru, que é o que o motor local lê.
///
/// Usa AVCaptureSession e não AVAudioEngine: o inputNode do AVAudioEngine sempre abre antes o
/// microfone padrão do sistema, e com AirPods isso custa ~3 s de troca de modo do Bluetooth
/// mesmo quando o ditado usa outro microfone. A captura abre direto o dispositivo escolhido,
/// numa fila própria, sem travar a thread principal.
public final class DictationRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public struct Recording: Sendable {
        public let m4a: URL
        public let pcm: URL
        public let duration: Double
        public func discard() {
            try? FileManager.default.removeItem(at: m4a)
            try? FileManager.default.removeItem(at: pcm)
        }
    }

    /// Nível de 0 a 1 e as faixas do espectro de cada bloco gravado, chamado fora da thread principal.
    public var onLevel: ((Float, [Float]) -> Void)?
    /// O primeiro áudio chegou: o microfone está de fato aberto. Chamado na thread principal.
    public var onFirstAudio: (() -> Void)?

    private let queue = DispatchQueue(label: "dev.oka.meety.dictation-recorder")
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    // Tudo abaixo só é tocado dentro de `queue`.
    private var session: AVCaptureSession?
    private var file: AVAudioFile?
    private var url: URL?
    private var pcmHandle: FileHandle?
    private var pcmURL: URL?
    private var converter: AVAudioConverter?
    private var framesWritten: AVAudioFramePosition = 0
    private var cancelled = false
    private let spectrum = DictationSpectrum()

    /// Abre o microfone (UID do CoreAudio, nil = padrão do sistema). `completion` vem na thread
    /// principal assim que a captura começa a rodar, ou com o erro.
    public override init() { super.init() }

    public func start(deviceUID: String?, completion: @escaping (Error?) -> Void) {
        queue.async { [self] in
            do {
                cancelled = false
                guard let device = deviceUID.flatMap(AVCaptureDevice.init(uniqueID:))
                        ?? AVCaptureDevice.default(for: .audio) else {
                    throw NSError(domain: "Meety", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "No microphone found.", bundle: .module)])
                }
                let session = AVCaptureSession()
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureAudioDataOutput()
                output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                                        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
                                        AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false]
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    throw NSError(domain: "Meety", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "The microphone is unavailable.", bundle: .module)])
                }
                session.addInput(input)
                session.addOutput(output)

                let name = "dictation-\(UUID().uuidString)"
                let url = AppPaths.temporary.appendingPathComponent("\(name).m4a")
                let pcm = AppPaths.temporary.appendingPathComponent("\(name).f32")
                FileManager.default.createFile(atPath: pcm.path, contents: nil)
                pcmHandle = try FileHandle(forWritingTo: pcm)
                pcmURL = pcm
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000,
                                               AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000]
                file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                self.url = url
                framesWritten = 0
                converter = nil
                floorDB = 0
                ceilDB = -30
                spectrum.reset()

                session.startRunning()  // com AirPods, é aqui que o Bluetooth troca de modo
                self.session = session
                if cancelled { finish()?.discard() }  // cancelaram enquanto o microfone abria
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    /// Para a gravação e devolve o arquivo e a duração em segundos (nil se nada foi gravado).
    /// Só para quando o microfone já abriu; antes disso, use `cancel()`, que não espera.
    public func stop() -> Recording? {
        queue.sync { finish() }
    }

    /// Descarta a gravação sem travar quem chama, mesmo com o microfone ainda abrindo.
    public func cancel() {
        cancelled = true
        queue.async { [self] in finish()?.discard() }
    }

    private func finish() -> Recording? {
        session?.stopRunning()
        session = nil
        file = nil  // fecha o arquivo
        try? pcmHandle?.close()
        pcmHandle = nil
        defer { url = nil; pcmURL = nil }
        guard let url, let pcmURL else { return nil }
        return Recording(m4a: url, pcm: pcmURL, duration: Double(framesWritten) / target.sampleRate)
    }

    // MARK: - Áudio

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let file, let pcm = Self.pcmBuffer(from: sampleBuffer), let mono = convert(pcm) else { return }
        try? file.write(from: mono)
        try? pcmHandle?.write(contentsOf: Data(bytes: mono.floatChannelData![0], count: Int(mono.frameLength) * 4))
        if framesWritten == 0 { DispatchQueue.main.async { self.onFirstAudio?() } }
        framesWritten += AVAudioFramePosition(mono.frameLength)

        // Um nível (e um espectro) a cada 20 ms (320 amostras a 16 kHz), para as ondas acompanharem a fala.
        let samples = Array(UnsafeBufferPointer(start: mono.floatChannelData![0], count: Int(mono.frameLength)))
        var start = 0
        while start < samples.count {
            let chunk = samples[start..<min(start + 320, samples.count)]
            start += 320
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            onLevel?(normalize(20 * log10(max(rms, 1e-7))), spectrum.analyze(chunk))
        }
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                  into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    /// Normalmente o próprio AVCapture já entrega 16 kHz mono float; se o dispositivo não
    /// aceitar, converte aqui.
    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.downmix = true
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var delivered = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    // Escala que se adapta ao microfone: o piso segue o ruído de fundo e o teto o pico da voz,
    // assim AirPods (baixo) e microfone USB (alto) mexem as ondas do mesmo jeito.
    private var floorDB: Float = 0  // a primeira leitura já vira o piso
    private var ceilDB: Float = -30

    private func normalize(_ db: Float) -> Float {
        floorDB = db < floorDB ? db : floorDB + 0.002 * (db - floorDB)  // sobe devagar (~10 s)
        ceilDB = db > ceilDB ? db : ceilDB - 0.03
        let range = max(ceilDB - floorDB, 18)
        let value = (db - floorDB - 4) / range
        return min(max(value, 0), 1)
    }
}

