import FluidAudio
import Foundation
import OSLog

/// Separa falantes com o FluidAudio (Core ML, no Neural Engine). Os modelos (~13 MB) são baixados
/// uma vez pelo gerenciador de modelos para `Models/speaker-diarization-coreml`.
///
/// Usa o `DiarizerManager` (segmentação pyannote + embeddings WeSpeaker + agrupamento por cosseno).
/// O pipeline offline com VBx foi testado em 17/10/2026 e é instável em chamadas comprimidas: junta
/// tudo num falante ou explode em dezenas conforme Fa/Fb. O online, com limiar 0,6, achou 5 falantes
/// onde o pyannote achou 6.
public actor Diarizer {
    public static let shared = Diarizer()

    public static var modelsFolder: URL {
        AppPaths.models.appendingPathComponent("speaker-diarization-coreml", isDirectory: true)
    }

    static var segmentationModel: URL { modelsFolder.appendingPathComponent("pyannote_segmentation.mlmodelc") }
    static var embeddingModel: URL { modelsFolder.appendingPathComponent("wespeaker_v2.mlmodelc") }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: segmentationModel.appendingPathComponent("coremldata.bin").path)
            && FileManager.default.fileExists(atPath: embeddingModel.appendingPathComponent("coremldata.bin").path)
    }

    /// Limiar de agrupamento (cosseno, 0...1): maior junta mais vozes numa só. 0,7 (padrão do
    /// FluidAudio) deixou 2 falantes onde havia 6; 0,6 achou 5. Ajustável para testes por variável.
    public static var clusteringThreshold: Float = {
        if let s = ProcessInfo.processInfo.environment["MEETY_DIARIZER_THRESHOLD"], let d = Float(s) { return d }
        return 0.6
    }()

    private var models: DiarizerModels?

    /// Diariza amostras a 16 kHz. `expectedSpeakers` (opcional) só orienta: com muitos participantes
    /// o limiar aperta um pouco para não juntar vozes parecidas.
    public func diarize(_ samples: [Float], expectedSpeakers: Int? = nil) async throws -> [SpeakerAttribution.LabeledSpan] {
        MeetyLog.speakers.info("diarize: \(samples.count) samples, expected \(expectedSpeakers ?? -1)")
        let models = try await loadedModels()
        var config = DiarizerConfig()
        config.clusteringThreshold = Self.clusteringThreshold
        if let n = expectedSpeakers, n >= 4 { config.clusteringThreshold = min(config.clusteringThreshold, 0.55) }
        let manager = DiarizerManager(config: config)
        manager.initialize(models: models)
        let result = try manager.performCompleteDiarization(samples)
        MeetyLog.speakers.info("done: \(result.segments.count) segments")
        var spans = result.segments.map {
            SpeakerAttribution.LabeledSpan(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), label: $0.speakerId)
        }
        spans.sort { $0.start < $1.start }
        return spans
    }

    private func loadedModels() async throws -> DiarizerModels {
        if let models { return models }
        let m = try await DiarizerModels.load(localSegmentationModel: Self.segmentationModel, localEmbeddingModel: Self.embeddingModel)
        models = m
        return m
    }
}

public enum MeetyLog {
    public static let speakers = Logger(subsystem: "dev.oka.meety", category: "speakers")
    public static let transcription = Logger(subsystem: "dev.oka.meety", category: "transcription")
}
