import AVFoundation
import Foundation

/// Transcrição de uma reunião inteira na Groq. O áudio (PCM 16 kHz mono) é cortado em partes de
/// até 10 minutos, sempre num ponto de silêncio, cada parte sobe como m4a e os trechos voltam
/// com o tempo somado ao início da parte. Assim uma reunião longa cabe no teto de tamanho por
/// envio da Groq e nenhuma palavra é cortada ao meio.
public enum GroqTranscription {
    /// Duração alvo de cada parte.
    static let chunkSeconds: Double = 600
    /// Quanto antes do alvo se procura o ponto mais silencioso para cortar.
    static let searchSeconds: Double = 20
    /// Um resto menor que isto fica junto da última parte.
    static let minimumTailSeconds: Double = 30

    public typealias Upload = @Sendable (_ audio: Data, _ language: String?, _ key: String) async throws -> Groq.Detailed

    public static func transcribe(samples: [Float], language: String?, key: String,
                                  upload: Upload = { try await Groq.transcribeDetailed($0, language: $1, key: $2) },
                                  progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Groq.Detailed {
        let ranges = chunkRanges(samples)
        var segments: [Groq.Segment] = []
        var detected: String?
        for (i, range) in ranges.enumerated() {
            try Task.checkCancellation()
            let audio = try encodeM4A(samples[range])
            let part = try await uploadWithRetry(audio, language: language ?? detected, key: key, upload: upload)
            // Whisper detecta o idioma em cada envio; o da primeira parte vale para as seguintes.
            if detected == nil { detected = part.language }
            let offset = Double(range.lowerBound) / AudioPrep.sampleRate
            let length = Double(range.count) / AudioPrep.sampleRate
            for s in part.segments {
                let start = min(max(0, s.start), length), end = min(max(start, s.end), length)
                segments.append(Groq.Segment(start: offset + start, end: offset + end, text: s.text))
            }
            progress(Double(i + 1) / Double(ranges.count))
        }
        return Groq.Detailed(language: language ?? detected, segments: segments)
    }

    private static func uploadWithRetry(_ audio: Data, language: String?, key: String, upload: Upload) async throws -> Groq.Detailed {
        do {
            return try await upload(audio, language, key)
        } catch {
            // Uma segunda tentativa só para falha passageira (rede que piscou, erro 5xx da Groq).
            guard isTransient(error), !Task.isCancelled else { throw error }
            try await Task.sleep(for: .seconds(2))
            return try await upload(audio, language, key)
        }
    }

    static func isTransient(_ error: Error) -> Bool {
        if let e = error as? GroqError { return e.isTransient }
        if let e = error as? URLError { return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(e.code) }
        return false
    }

    /// Divide o áudio em partes de até `chunkSeconds`, cortando no trecho mais silencioso dos
    /// últimos `searchSeconds` antes do alvo.
    static func chunkRanges(_ samples: [Float], sampleRate: Double = AudioPrep.sampleRate, chunkSeconds: Double = chunkSeconds,
                            searchSeconds: Double = searchSeconds, minimumTailSeconds: Double = minimumTailSeconds) -> [Range<Int>] {
        let total = samples.count
        guard total > 0 else { return [] }
        let chunk = Int(chunkSeconds * sampleRate), tail = Int(minimumTailSeconds * sampleRate)
        var ranges: [Range<Int>] = []
        var start = 0
        while total - start > chunk + tail {
            let target = start + chunk
            let cut = quietestPoint(samples, from: max(start + 1, target - Int(searchSeconds * sampleRate)), to: target, sampleRate: sampleRate)
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<total)
        return ranges
    }

    /// Centro da janela de 0,2 s com menos energia entre `from` e `to`.
    static func quietestPoint(_ samples: [Float], from: Int, to: Int, sampleRate: Double) -> Int {
        let window = max(1, Int(0.2 * sampleRate)), step = max(1, Int(0.05 * sampleRate))
        guard to - from > window else { return to }
        var best = to, bestEnergy = Float.infinity
        var i = from
        while i + window <= to {
            var energy: Float = 0
            for j in i..<(i + window) { energy += samples[j] * samples[j] }
            // Com empate (silêncio total), fica o ponto mais perto do alvo: partes maiores, menos envios.
            if energy <= bestEnergy { bestEnergy = energy; best = i + window / 2 }
            i += step
        }
        return best
    }

    /// Codifica um trecho em AAC 16 kHz mono (o mesmo formato do ditado): 10 min ficam em cerca de 2,4 MB.
    static func encodeM4A(_ samples: ArraySlice<Float>) throws -> Data {
        let url = AppPaths.temporary.appendingPathComponent("groq-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioPrep.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000]
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioPrep.sampleRate, channels: 1, interleaved: false) else {
            throw AudioPrep.PrepError.cannotRead("audio format")
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let block = 16_000 * 30
            var position = samples.startIndex
            while position < samples.endIndex {
                let count = min(block, samples.endIndex - position)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channel = buffer.floatChannelData?[0] else { throw AudioPrep.PrepError.cannotRead("audio buffer") }
                samples[position..<(position + count)].withUnsafeBufferPointer { src in
                    channel.update(from: src.baseAddress!, count: count)
                }
                buffer.frameLength = AVAudioFrameCount(count)
                try file.write(from: buffer)
                position += count
            }
        }  // o arquivo fecha aqui, antes da leitura
        return try Data(contentsOf: url)
    }
}

/// O que a fila de transcrição precisa da Groq. Nos testes, entra uma versão de mentira.
public struct GroqClient: Sendable {
    public var key: @Sendable () -> String?
    public var transcribe: @Sendable (_ samples: [Float], _ language: String?, _ key: String,
                                      _ progress: @escaping @Sendable (Double) -> Void) async throws -> Groq.Detailed

    public init(key: @escaping @Sendable () -> String?,
                transcribe: @escaping @Sendable ([Float], String?, String, @escaping @Sendable (Double) -> Void) async throws -> Groq.Detailed) {
        self.key = key; self.transcribe = transcribe
    }

    public static let live = GroqClient(key: { Groq.apiKey }) { samples, language, key, progress in
        try await GroqTranscription.transcribe(samples: samples, language: language, key: key, progress: progress)
    }
}
