import AVFoundation
import Foundation
import Observation

/// Tocador do áudio da reunião, com a posição publicada para a transcrição acompanhar.
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var rate: Float = 1 { didSet { if isPlaying { player?.rate = rate } } }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func load(_ url: URL) {
        unload()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = t.seconds
                if let d = p.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
        Task {
            if let d = try? await item.asset.load(.duration).seconds, d.isFinite { duration = d }
        }
    }

    func unload() {
        if let observer, let player { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil; endObserver = nil
        player?.pause(); player = nil
        isPlaying = false; currentTime = 0
    }

    func toggle() { isPlaying ? pause() : play() }
    func play() { player?.rate = rate; player?.play(); isPlaying = true }
    func pause() { player?.pause(); isPlaying = false }

    func seek(to seconds: Double, andPlay: Bool = false) {
        player?.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        if andPlay, !isPlaying { play() }
    }

    func skip(_ delta: Double) { seek(to: min(max(0, currentTime + delta), duration)) }
}
