import Foundation

/// Decide onde o ditado é transcrito: na Groq quando há chave, e no modelo do Mac quando não há
/// chave ou quando a Groq falha (rede, limite, chave recusada).
public struct DictationTranscriber: Sendable {
    /// Chave da Groq; nil = ditado só local.
    public var groqKey: String?
    /// Pasta do modelo local; nil = não baixado.
    public var localModel: URL?
    public var language: String?

    public init(groqKey: String?, localModel: URL?, language: String?) {
        self.groqKey = groqKey; self.localModel = localModel; self.language = language
    }

    public var canTranscribe: Bool { groqKey != nil || localModel != nil }

    /// Carrega o modelo local enquanto a pessoa fala, quando ele é o caminho principal. Com a Groq
    /// ligada, o modelo só ocupa memória se ela falhar.
    public func warmUp() {
        if groqKey == nil, let localModel { DictationEngine.shared.warmUp(model: localModel) }
    }

    /// `onFallback` é chamado quando a Groq falhou e o Mac assumiu, com o motivo.
    public func transcribe(_ recording: DictationRecorder.Recording,
                           onFallback: @escaping @Sendable (String) -> Void) async throws -> (text: String, origin: DictationOrigin) {
        if let groqKey {
            do {
                return (try await Groq.transcribe(recording.m4a, language: language, key: groqKey), .groq)
            } catch {
                guard localModel != nil, !(error is CancellationError) else { throw error }
                MeetyLog.transcription.info("dictation: Groq failed, using the local model: \(error.localizedDescription)")
                onFallback(error.localizedDescription)
            }
        }
        guard let localModel else { throw DictationError.noTranscriber }
        let text = try await DictationEngine.shared.transcribe(pcm: recording.pcm, model: localModel, language: language)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), .local)
    }
}

public enum DictationError: LocalizedError, Sendable {
    case noTranscriber
    public var errorDescription: String? {
        String(localized: "Add a Groq key or download a dictation model in Settings > Dictation.", bundle: .module)
    }
}
