import AVFoundation
import Foundation

/// Decodifica qualquer áudio ou vídeo que o AVFoundation leia para PCM Float32 mono a 16 kHz,
/// o formato do Whisper e dos modelos de falantes. Sem ffmpeg.
public enum AudioPrep {
    public static let sampleRate: Double = 16_000

    /// Extensões que o Meety aceita arrastar ou importar.
    public static let supportedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "aac", "mp4", "m4v", "mov", "mpeg", "mpg", "ogg", "opus", "webm", "mkv"
    ]
    /// Dessas, as que o AVFoundation normalmente não abre. A UI avisa antes de tentar.
    public static let unsupportedByAVFoundation: Set<String> = ["ogg", "opus", "webm", "mkv"]

    public enum PrepError: LocalizedError {
        case noAudioTrack
        case cannotRead(String)
        public var errorDescription: String? {
            switch self {
            case .noAudioTrack: return String(localized: "This file has no audio track.", bundle: .module)
            case .cannotRead(let d): return String(localized: "Meety can't read this file. \(d)", bundle: .module)
            }
        }
    }

    /// Lê o arquivo inteiro para memória (1 h de áudio = 230 MB de Float32). Reuniões cabem com folga.
    public static func samples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw PrepError.noAudioTrack }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw PrepError.cannotRead(error.localizedDescription) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw PrepError.cannotRead("reader output") }
        reader.add(output)
        guard reader.startReading() else { throw PrepError.cannotRead(reader.error?.localizedDescription ?? "") }

        var samples: [Float] = []
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            samples.reserveCapacity(Int(seconds * sampleRate) + 16_000)
        }
        while let sb = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var tmp = [Float](repeating: 0, count: length / 4)
            tmp.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            samples.append(contentsOf: tmp)
            try Task.checkCancellation()
        }
        if reader.status == .failed { throw PrepError.cannotRead(reader.error?.localizedDescription ?? "") }
        return samples
    }

    /// Grava amostras como `.f32` cru (o que o motor lê com `np.fromfile`).
    public static func write(_ samples: [Float], to url: URL) throws {
        try samples.withUnsafeBufferPointer { buf in
            try Data(buffer: buf).write(to: url, options: .atomic)
        }
    }

    public static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return nil }
        let s = d.seconds
        return s.isFinite ? s : nil
    }

    /// Energia RMS de um trecho, em amostras a 16 kHz.
    public static func rms(_ samples: [Float], from start: Double, to end: Double) -> Float {
        let a = max(0, Int(start * sampleRate)), b = min(samples.count, Int(end * sampleRate))
        guard b > a else { return 0 }
        var acc: Float = 0
        for i in a..<b { acc += samples[i] * samples[i] }
        return (acc / Float(b - a)).squareRoot()
    }
}
