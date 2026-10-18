import Foundation

/// Uma frase da transcrição, com o momento em que foi dita e quem falou.
public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var text: String
    /// Identificador estável do falante ("you", "p1", "p2"...). O nome mostrado vem de `Meeting.speakerNames`.
    public var speaker: String?

    public init(id: Int, start: Double, end: Double, text: String, speaker: String? = nil) {
        self.id = id; self.start = start; self.end = end; self.text = text; self.speaker = speaker
    }
}

public struct Transcript: Codable, Equatable, Sendable {
    public var language: String?
    public var segments: [TranscriptSegment]
    public var model: String?

    public init(language: String?, segments: [TranscriptSegment], model: String? = nil) {
        self.language = language; self.segments = segments; self.model = model
    }

    public var plainText: String { segments.map(\.text).joined(separator: " ") }
    public var speakerIDs: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in segments { if let sp = s.speaker, !seen.contains(sp) { seen.insert(sp); out.append(sp) } }
        return out
    }
}

public enum MeetingSource: String, Codable, Sendable { case recording, imported }

public enum MeetingStatus: String, Codable, Sendable {
    case recorded      // áudio pronto, sem transcrição
    case transcribing
    case transcribed
    case failed
}

/// Os dados de uma reunião (o `meta.json` da pasta).
public struct Meeting: Codable, Identifiable, Equatable, Sendable {
    public var id: String                 // nome da pasta
    public var title: String
    public var createdAt: Date
    public var duration: Double?
    public var source: MeetingSource
    public var status: MeetingStatus
    public var language: String?
    public var modelID: String?
    /// Nome dado pelo usuário a cada falante ("you" -> "Akira", "p1" -> "Fabio").
    public var speakerNames: [String: String]
    public var error: String?
    public var originalFileName: String?
    /// Os falantes já foram separados (gravação com duas trilhas ou diarização).
    public var hasSpeakers: Bool

    public init(id: String, title: String, createdAt: Date, duration: Double? = nil, source: MeetingSource,
                status: MeetingStatus = .recorded, language: String? = nil, modelID: String? = nil,
                speakerNames: [String: String] = [:], error: String? = nil, originalFileName: String? = nil,
                hasSpeakers: Bool = false) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.duration = duration
        self.source = source; self.status = status; self.language = language; self.modelID = modelID
        self.speakerNames = speakerNames; self.error = error; self.originalFileName = originalFileName
        self.hasSpeakers = hasSpeakers
    }

    public func displayName(for speakerID: String) -> String {
        if let n = speakerNames[speakerID], !n.isEmpty { return n }
        return Speaker.defaultName(for: speakerID)
    }
}

public enum Speaker {
    public static let you = "you"
    public static func participant(_ n: Int) -> String { "p\(n)" }
    public static func speaker(_ n: Int) -> String { "s\(n)" }

    public static func defaultName(for id: String) -> String {
        if id == you { return String(localized: "You", bundle: .module) }
        if id.hasPrefix("p"), let n = Int(id.dropFirst()) {
            return String(localized: "Participant \(n)", bundle: .module)
        }
        if id.hasPrefix("s"), let n = Int(id.dropFirst()) {
            return String(localized: "Speaker \(n)", bundle: .module)
        }
        return id
    }
}

/// Um resumo gerado (arquivo `summary-<template>-<data>.md` da pasta).
public struct SummaryDocument: Codable, Identifiable, Hashable, Sendable {
    public var id: String        // nome do arquivo
    public var template: String
    public var provider: String
    public var createdAt: Date
    public var title: String

    public init(id: String, template: String, provider: String, createdAt: Date, title: String) {
        self.id = id; self.template = template; self.provider = provider; self.createdAt = createdAt; self.title = title
    }
}
