import Foundation
@testable import MeetyCore
import Testing

/// Roda o FluidAudio num arquivo real (MEETY_AUDIO). Só com MEETY_NETWORK=1.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEETY_NETWORK"] == "1"))
struct DiarizerTests {
    @Test func diarizesClip() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MEETY_AUDIO"])
        let t0 = Date()
        let samples = try await AudioPrep.samples(from: URL(fileURLWithPath: path))
        print("samples \(samples.count) in \(Date().timeIntervalSince(t0))s; installed=\(Diarizer.isInstalled)")
        let expected = ProcessInfo.processInfo.environment["MEETY_SPEAKERS"].flatMap(Int.init)
        let spans = try await Diarizer.shared.diarize(samples, expectedSpeakers: expected)
        print("spans \(spans.count) in \(Date().timeIntervalSince(t0))s")
        for s in spans.prefix(40) { print(String(format: "[%6.1f-%6.1f] %@", s.start, s.end, s.label)) }
        print("labels:", Set(spans.map(\.label)).sorted())
        #expect(!spans.isEmpty)
    }
}
