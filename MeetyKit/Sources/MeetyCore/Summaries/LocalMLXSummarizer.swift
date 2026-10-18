import Foundation

/// Resumo com um modelo de linguagem local (mlx-lm, no motor embutido). 100% offline.
public struct LocalMLXSummarizer: SummaryProvider {
    public let id = "local-mlx"
    public let title = String(localized: "Local model", bundle: .module)
    public let subtitle = String(localized: "Runs on this Mac. Nothing leaves your computer.", bundle: .module)
    public let systemIcon = "cpu"
    public let isCloud = false

    let model: ModelInfo?
    let installed: Bool
    let engine: EngineRunner?

    public init(model: ModelInfo?, installed: Bool, engine: EngineRunner? = EngineRunner.bundled()) {
        self.model = model; self.installed = installed; self.engine = engine
    }

    public var contextTokens: Int { min(model?.contextTokens ?? 8192, 16_384) }

    public func availability() async -> ProviderAvailability {
        guard engine != nil else { return .unavailable(reason: EngineError.notBundled.localizedDescription, action: nil) }
        guard let model else { return .unavailable(reason: String(localized: "No summary model selected.", bundle: .module), action: .openSettingsSection("models")) }
        guard installed else {
            return .unavailable(reason: String(localized: "\(model.name) isn't downloaded yet (\(model.sizeText)).", bundle: .module), action: .downloadModel(model.id))
        }
        return .available(detail: model.name)
    }

    public func summarize(system: String, user: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let engine, let model else { throw SummaryError.unavailable(EngineError.notBundled.localizedDescription) }
        let dir = AppPaths.temporary
        let promptURL = dir.appendingPathComponent("prompt-\(UUID().uuidString).txt")
        let systemURL = dir.appendingPathComponent("system-\(UUID().uuidString).txt")
        try user.write(to: promptURL, atomically: true, encoding: .utf8)
        try system.write(to: systemURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: promptURL); try? FileManager.default.removeItem(at: systemURL) }
        var acc = ""
        var result: String?
        for try await ev in engine.run("summarize", args: ["--model", model.folder.path, "--prompt-file", promptURL.path, "--system-file", systemURL.path, "--max-tokens", "2000"]) {
            switch ev {
            case .token(let t): acc += t; onPartial(acc)
            case .text(let t): result = t
            default: break
            }
        }
        return Self.stripThinking(result ?? acc)
    }

    /// Alguns modelos devolvem `<think>…</think>` antes da resposta.
    static func stripThinking(_ s: String) -> String {
        guard let r = s.range(of: "</think>") else { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
