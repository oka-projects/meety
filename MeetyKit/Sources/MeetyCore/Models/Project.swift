import Foundation

/// Um projeto agrupa reuniões ("Cliente X", "Curso de direito"). Guardado em `Library/projects.json`;
/// cada reunião aponta para o projeto pelo `projectID` no seu `meta.json`.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    /// Índice na paleta de cores (a mesma dos falantes, de 1 a 7).
    public var colorIndex: Int

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), colorIndex: Int = 1) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.colorIndex = colorIndex
    }
}
