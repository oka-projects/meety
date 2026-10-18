import FluidAudio
import Foundation
import OSLog

/// Separa falantes com o FluidAudio (Core ML, no Neural Engine). Os modelos (~50 MB) são baixados
/// uma vez pelo gerenciador de modelos para `Models/speaker-diarization-coreml`.
public actor Diarizer {
    public static let shared = Diarizer()

    public static var modelsFolder: URL {
        AppPaths.models.appendingPathComponent("speaker-diarization-coreml", isDirectory: true)
    }

    public static var isInstalled: Bool {
        // O pipeline offline usa estes quatro modelos (mais plda-parameters.json).
        let f = modelsFolder
        return ["Segmentation", "Embedding", "FBank", "PldaRho"].allSatisfy {
            FileManager.default.fileExists(atPath: f.appendingPathComponent("\($0).mlmodelc/coremldata.bin").path)
        } && FileManager.default.fileExists(atPath: f.appendingPathComponent("plda-parameters.json").path)
    }

    private var manager: OfflineDiarizerManager?
    private var managerSpeakers: Int?

    /// Distância de corte do agrupamento (0...2): maior junta mais vozes numa só. O padrão do
    /// FluidAudio (0,6, paridade com o pyannote) tende a juntar demais em chamadas comprimidas.
    public static var clusteringThreshold: Double = {
        if let s = ProcessInfo.processInfo.environment["MEETY_DIARIZER_THRESHOLD"], let d = Double(s) { return d }
        return 0.6
    }()

    /// Diariza amostras a 16 kHz. `expectedSpeakers` (opcional) orienta o agrupamento.
    public func diarize(_ samples: [Float], expectedSpeakers: Int? = nil) async throws -> [SpeakerAttribution.LabeledSpan] {
        MeetyLog.speakers.info("diarize: \(samples.count) samples, expected \(expectedSpeakers ?? -1)")
        let manager = try await prepared(expectedSpeakers: expectedSpeakers)
        MeetyLog.speakers.info("models ready")
        let result = try await manager.process(audio: samples)
        MeetyLog.speakers.info("done: \(result.segments.count) segments")
        var spans = result.segments.map {
            SpeakerAttribution.LabeledSpan(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), label: $0.speakerId)
        }
        spans.sort { $0.start < $1.start }
        return spans
    }

    private func prepared(expectedSpeakers: Int?) async throws -> OfflineDiarizerManager {
        if let manager, managerSpeakers == expectedSpeakers { return manager }
        var config = OfflineDiarizerConfig()
        config.clustering.threshold = Self.clusteringThreshold
        let env = ProcessInfo.processInfo.environment
        if let fa = env["MEETY_DIARIZER_FA"].flatMap(Double.init) { config.clustering.warmStartFa = fa }
        if let fb = env["MEETY_DIARIZER_FB"].flatMap(Double.init) { config.clustering.warmStartFb = fb }
        if env["MEETY_DIARIZER_MIN2"] == "1" { config.clustering.minSpeakers = 2 }
        config.clustering.numSpeakers = expectedSpeakers
        let m = OfflineDiarizerManager(config: config)
        managerSpeakers = expectedSpeakers
        // Os pesos ficam em Models/speaker-diarization-coreml; o FluidAudio procura por esse nome
        // dentro da pasta dada e só baixa se faltar.
        try await m.prepareModels(directory: AppPaths.models)
        manager = m
        return m
    }
}

public enum MeetyLog {
    public static let speakers = Logger(subsystem: "dev.oka.meety", category: "speakers")
    public static let transcription = Logger(subsystem: "dev.oka.meety", category: "transcription")
}
