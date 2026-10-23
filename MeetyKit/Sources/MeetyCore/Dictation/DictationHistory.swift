import Foundation
import Observation

public struct Dictation: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let origin: DictationOrigin
    public let duration: Double
    public init(id: UUID = UUID(), date: Date = Date(), text: String, origin: DictationOrigin, duration: Double) {
        self.id = id; self.date = date; self.text = text; self.origin = origin; self.duration = duration
    }
}

/// Onde o ditado foi transcrito.
public enum DictationOrigin: String, Codable, Sendable {
    case groq, local
    public var title: String {
        switch self {
        case .groq: return "Groq"
        case .local: return String(localized: "This Mac", bundle: .module)
        }
    }
}

/// Histórico dos ditados em Application Support/Meety/dictations.json, mais novo primeiro.
@MainActor
@Observable
public final class DictationHistory {
    private static let limit = 1000
    public private(set) var items: [Dictation] = []
    private let fileURL = AppPaths.applicationSupport.appendingPathComponent("dictations.json")

    public init() {
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSON.decoder.decode([Dictation].self, from: data) {
            items = saved
        }
    }

    public func add(_ item: Dictation) {
        items.insert(item, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        save()
    }

    public func remove(_ item: Dictation) {
        items.removeAll { $0.id == item.id }
        save()
    }

    public func removeAll() {
        items.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSON.encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
