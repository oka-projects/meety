import Foundation

public enum ModelKind: String, Codable, Sendable, CaseIterable {
    case transcription, summary, speakers

    public var title: String {
        switch self {
        case .transcription: return String(localized: "Transcription", bundle: .module)
        case .summary: return String(localized: "Summaries", bundle: .module)
        case .speakers: return String(localized: "Speakers", bundle: .module)
        }
    }
}

/// Um modelo do catálogo (`models.json`).
public struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ModelKind
    public var name: String
    public var repo: String
    public var sizeBytes: Int64
    public var minMemoryGB: Int
    public var contextTokens: Int?
    public var tags: [String]
    public var description: String
    /// Arquivos do repositório que não precisam ser baixados (pacotes não compilados, gráficos).
    public var excludePrefixes: [String]?
    public var excludeExtensions: [String]?

    public func wants(file path: String) -> Bool {
        if path.hasPrefix(".git") { return false }
        if let p = excludePrefixes, p.contains(where: { path.hasPrefix($0) }) { return false }
        if let e = excludeExtensions, e.contains((path as NSString).pathExtension.lowercased()) { return false }
        return true
    }

    public var isRecommended: Bool { tags.contains("recommended") }
    public var tagTitle: String? {
        if tags.contains("recommended") { return String(localized: "Recommended", bundle: .module) }
        if tags.contains("accurate") { return String(localized: "Most accurate", bundle: .module) }
        if tags.contains("light") { return String(localized: "Light", bundle: .module) }
        return nil
    }
    /// Pasta local do modelo: `Models/<owner>/<nome>`. O de falantes fica em `Models/<nome>`,
    /// que é onde o FluidAudio procura.
    public var folder: URL {
        if kind == .speakers { return AppPaths.models.appendingPathComponent(repo.split(separator: "/").last.map(String.init) ?? repo, isDirectory: true) }
        return AppPaths.models.appendingPathComponent(repo, isDirectory: true)
    }
    public var sizeText: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
}

public struct ModelCatalog: Codable, Sendable {
    public var version: Int
    public var models: [ModelInfo]

    public static func bundled() -> ModelCatalog {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(ModelCatalog.self, from: data) else {
            return ModelCatalog(version: 0, models: [])
        }
        return c
    }

    public func model(id: String) -> ModelInfo? { models.first { $0.id == id } }
    public func models(of kind: ModelKind) -> [ModelInfo] { models.filter { $0.kind == kind } }

    /// Memória física do Mac em GB inteiros.
    public static var physicalMemoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) }

    /// Os modelos recomendados para este Mac: um de cada tipo, o maior "recomendado" que cabe.
    public func recommended(memoryGB: Int = physicalMemoryGB) -> [ModelInfo] {
        ModelKind.allCases.compactMap { kind in
            let fitting = models(of: kind).filter { $0.minMemoryGB <= memoryGB }
            if kind == .summary, memoryGB >= 24, let big = fitting.first(where: { $0.tags.contains("accurate") }) { return big }
            return fitting.first(where: \.isRecommended) ?? fitting.first
        }
    }
}
