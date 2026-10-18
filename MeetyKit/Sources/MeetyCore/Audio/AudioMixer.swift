import AVFoundation
import Foundation

/// Junta as duas trilhas (microfone e sistema) num `audio.m4a` para ouvir, com AVFoundation.
public enum AudioMixer {
    public enum MixError: LocalizedError {
        case noInput, exportFailed(String)
        public var errorDescription: String? {
            switch self {
            case .noInput: return String(localized: "No audio was captured.", bundle: .module)
            case .exportFailed(let d): return String(localized: "Couldn't save the recording: \(d)", bundle: .module)
            }
        }
    }

    public static func mix(tracks: [URL], output: URL) async throws {
        let inputs = tracks.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !inputs.isEmpty else { throw MixError.noInput }
        try? FileManager.default.removeItem(at: output)

        let composition = AVMutableComposition()
        for url in inputs {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            guard let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw MixError.exportFailed("export session")
        }
        do {
            try await session.export(to: output, as: .m4a)
        } catch {
            throw MixError.exportFailed(error.localizedDescription)
        }
    }
}
