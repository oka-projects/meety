import Foundation

/// Quem escreve o resumo. Cada provedor diz se está disponível e se manda a transcrição para fora do Mac.
public protocol SummaryProvider: Sendable {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    var systemIcon: String { get }
    /// Verdadeiro quando o texto sai do Mac (a UI avisa antes).
    var isCloud: Bool { get }
    func availability() async -> ProviderAvailability
    /// Gera o texto; `onPartial` recebe o texto acumulado conforme chega (quando houver stream).
    func summarize(system: String, user: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String
    /// Tamanho de contexto aproximado em tokens, para decidir se resume por partes.
    var contextTokens: Int { get }
}

public enum ProviderAvailability: Equatable, Sendable {
    case available(detail: String?)
    case unavailable(reason: String, action: ProviderAction?)

    public var isAvailable: Bool { if case .available = self { return true }; return false }
}

public enum ProviderAction: Equatable, Sendable {
    case downloadModel(String)
    case openApp(bundleID: String)
    case openSettingsSection(String)
    case enterAPIKey
}

public enum SummaryError: LocalizedError, Sendable {
    case unavailable(String)
    case emptyTranscript
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let r): return r
        case .emptyTranscript: return String(localized: "There is no transcript to summarize yet.", bundle: .module)
        case .failed(let m): return m
        }
    }
}

/// Orquestra: escolhe o provedor, divide em partes se preciso, grava o resultado.
public enum SummaryService {
    /// ~4 caracteres por token é uma estimativa boa o bastante para decidir se cabe.
    public static func estimateTokens(_ text: String) -> Int { text.utf8.count / 4 + 1 }

    public static func generate(provider: SummaryProvider, template: SummaryTemplate, custom: String?,
                                meeting: Meeting, transcript: Transcript, languageCode: String,
                                onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        let text = TranscriptExporter.plain(transcript, meeting: meeting, timestamps: false)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryError.emptyTranscript }
        let system = SummaryPrompts.system(languageName: SummaryPrompts.languageName(for: languageCode))
        // Reserva um terço do contexto para o prompt e a resposta.
        let budget = max(2_000, provider.contextTokens * 2 / 3)
        if estimateTokens(text) <= budget {
            return try await provider.summarize(system: system, user: SummaryPrompts.user(template: template, custom: custom, meeting: meeting, transcriptText: text), onPartial: onPartial)
        }
        // Por partes: notas de cada pedaço, depois o resumo final a partir das notas.
        let parts = split(text, maxTokens: budget)
        var notes: [String] = []
        for (i, part) in parts.enumerated() {
            try Task.checkCancellation()
            let n = try await provider.summarize(system: system, user: SummaryPrompts.chunkPrompt(part: i + 1, total: parts.count, text: part), onPartial: { _ in })
            notes.append(n)
            onPartial(String(localized: "Read part \(i + 1) of \(parts.count)…", bundle: .module))
        }
        return try await provider.summarize(system: system, user: SummaryPrompts.mergePrompt(template: template, custom: custom, meeting: meeting, notes: notes), onPartial: onPartial)
    }

    static func split(_ text: String, maxTokens: Int) -> [String] {
        let maxChars = maxTokens * 4
        var parts: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if current.utf8.count + paragraph.utf8.count > maxChars, !current.isEmpty {
                parts.append(current); current = ""
            }
            if paragraph.utf8.count > maxChars {
                // Um bloco gigante: corta por frases.
                var piece = ""
                for sentence in paragraph.split(separator: ". ", omittingEmptySubsequences: true) {
                    if piece.utf8.count + sentence.utf8.count > maxChars, !piece.isEmpty { parts.append(piece); piece = "" }
                    piece += sentence + ". "
                }
                if !piece.isEmpty { current = piece }
            } else {
                current += (current.isEmpty ? "" : "\n\n") + paragraph
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
