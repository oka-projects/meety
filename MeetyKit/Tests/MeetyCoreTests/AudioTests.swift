import Foundation
@testable import MeetyCore
import Testing

/// Usa os arquivos de teste em engine/.cache/test (gerados à mão). Só com MEETY_NETWORK=1.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEETY_NETWORK"] == "1"))
struct AudioTests {
    let dir = URL(fileURLWithPath: NSString(string: "~/Projetos/meety/engine/.cache/test").expandingTildeInPath)

    @Test func decodesVideoToPCM() async throws {
        let samples = try await AudioPrep.samples(from: dir.appendingPathComponent("video.mov"))
        #expect(abs(Double(samples.count) / 16000 - 20) < 0.5)
        #expect(samples.contains { abs($0) > 0.01 })
    }

    @Test func mixesTwoTracks() async throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("meety-mix-\(UUID().uuidString).m4a")
        try await AudioMixer.mix(tracks: [dir.appendingPathComponent("amostra.m4a"), dir.appendingPathComponent("video.mov")], output: out)
        let d = try #require(await AudioPrep.duration(of: out))
        #expect(abs(d - 90) < 1)
        try? FileManager.default.removeItem(at: out)
    }
}
