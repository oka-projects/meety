import FluidAudio
import Foundation
@testable import MeetyCore
import Testing

/// Compara o diarizador "online" do FluidAudio (DiarizerManager, agrupamento por cosseno) com o
/// offline (VBx) no mesmo clipe. Só com MEETY_NETWORK=1 e MEETY_AUDIO.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEETY_NETWORK"] == "1"))
struct OnlineDiarizerTests {
    @Test func onlineManagerSeparatesSpeakers() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MEETY_AUDIO"])
        let samples = try await AudioPrep.samples(from: URL(fileURLWithPath: path))
        let folder = Diarizer.modelsFolder
        let models = try await DiarizerModels.load(
            localSegmentationModel: folder.appendingPathComponent("pyannote_segmentation.mlmodelc"),
            localEmbeddingModel: folder.appendingPathComponent("wespeaker_v2.mlmodelc"))
        let threshold = ProcessInfo.processInfo.environment["MEETY_ONLINE_THRESHOLD"].flatMap(Double.init).map(Float.init) ?? 0.7
        var config = DiarizerConfig()
        config.clusteringThreshold = threshold
        let manager = DiarizerManager(config: config)
        manager.initialize(models: models)
        let t0 = Date()
        let result = try manager.performCompleteDiarization(samples)
        print("online threshold \(threshold): \(result.segments.count) segments in \(Date().timeIntervalSince(t0))s")
        let labels = Set(result.segments.map(\.speakerId)).sorted()
        print("online labels:", labels)
        for s in result.segments { print(String(format: "[%6.1f-%6.1f] %@", s.startTimeSeconds, s.endTimeSeconds, s.speakerId)) }
        #expect(!result.segments.isEmpty)
    }
}
