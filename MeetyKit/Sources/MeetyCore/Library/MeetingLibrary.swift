import Foundation
import Observation

/// A pasta de cada reunião e os arquivos dentro dela.
public struct MeetingFolder: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public var meta: URL { url.appendingPathComponent("meta.json") }
    public var transcript: URL { url.appendingPathComponent("transcript.json") }
    public var audio: URL { url.appendingPathComponent("audio.m4a") }       // mixagem (o que se ouve)
    public var micTrack: URL { url.appendingPathComponent("mic.m4a") }      // só gravações
    public var systemTrack: URL { url.appendingPathComponent("system.m4a") }
    public var summaries: URL { url }

    public var hasAudio: Bool { FileManager.default.fileExists(atPath: audio.path) }
    public var hasTracks: Bool {
        FileManager.default.fileExists(atPath: micTrack.path) && FileManager.default.fileExists(atPath: systemTrack.path)
    }
}

/// Biblioteca de reuniões: uma pasta por reunião em `Library/`, com `meta.json`, `transcript.json`,
/// o áudio e os resumos. Nada de banco: a pasta é o formato, e dá para abrir no Finder.
@MainActor
@Observable
public final class MeetingLibrary {
    public private(set) var meetings: [Meeting] = []
    public let root: URL

    public static func defaultRoot() -> URL {
        AppPaths.applicationSupport.appendingPathComponent("Library", isDirectory: true)
    }

    public init(root: URL? = nil) {
        self.root = root ?? MeetingLibrary.defaultRoot()
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
    }

    public func folder(for meeting: Meeting) -> MeetingFolder {
        MeetingFolder(url: root.appendingPathComponent(meeting.id, isDirectory: true))
    }

    public func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var list: [Meeting] = []
        for dir in dirs where dir.hasDirectoryPath {
            let meta = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: meta),
                  let m = try? JSON.decoder.decode(Meeting.self, from: data) else { continue }
            list.append(m)
        }
        meetings = list.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Criar

    /// Cria a pasta de uma reunião nova e grava o meta. O id é `AAAA-MM-DD-HHmmss-<slug>`.
    public func create(title: String, source: MeetingSource, date: Date = Date(), originalFileName: String? = nil) throws -> Meeting {
        let id = Self.folderName(date: date, title: title)
        let folder = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let m = Meeting(id: id, title: title, createdAt: date, source: source, originalFileName: originalFileName)
        try save(m)
        return m
    }

    nonisolated static func folderName(date: Date, title: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let slug = Self.slug(title)
        return slug.isEmpty ? f.string(from: date) : "\(f.string(from: date))-\(slug)"
    }

    nonisolated static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let allowed = folded.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var out = String(allowed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        if out.count > 40 { out = String(out.prefix(40)) }
        return out
    }

    // MARK: - Salvar e ler

    public func save(_ meeting: Meeting) throws {
        let f = folder(for: meeting)
        try FileManager.default.createDirectory(at: f.url, withIntermediateDirectories: true)
        try JSON.encoder.encode(meeting).write(to: f.meta, options: .atomic)
        if let i = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[i] = meeting }
        else { meetings.insert(meeting, at: 0); meetings.sort { $0.createdAt > $1.createdAt } }
    }

    public func update(_ id: String, _ change: (inout Meeting) -> Void) {
        guard var m = meetings.first(where: { $0.id == id }) else { return }
        change(&m)
        try? save(m)
    }

    public func transcript(of meeting: Meeting) -> Transcript? {
        guard let data = try? Data(contentsOf: folder(for: meeting).transcript) else { return nil }
        return try? JSON.decoder.decode(Transcript.self, from: data)
    }

    public func save(transcript: Transcript, for meeting: Meeting) throws {
        try JSON.encoder.encode(transcript).write(to: folder(for: meeting).transcript, options: .atomic)
    }

    public func delete(_ meeting: Meeting) throws {
        try FileManager.default.trashItem(at: folder(for: meeting).url, resultingItemURL: nil)
        meetings.removeAll { $0.id == meeting.id }
    }

    // MARK: - Resumos

    public func summaries(of meeting: Meeting) -> [SummaryDocument] {
        let f = folder(for: meeting)
        let files = (try? FileManager.default.contentsOfDirectory(at: f.url, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("summary-") && $0.pathExtension == "md" }
            .compactMap { url -> SummaryDocument? in
                // summary-<template>-<provider>-<yyyyMMdd-HHmmss>.md
                let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-", omittingEmptySubsequences: false)
                guard parts.count >= 5 else { return nil }
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let template = String(parts[1]), provider = String(parts[2])
                let title = SummaryTemplate(rawValue: template)?.title ?? template
                return SummaryDocument(id: url.lastPathComponent, template: template, provider: provider, createdAt: created, title: title)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func summaryText(_ doc: SummaryDocument, of meeting: Meeting) -> String {
        (try? String(contentsOf: folder(for: meeting).url.appendingPathComponent(doc.id), encoding: .utf8)) ?? ""
    }

    @discardableResult
    public func saveSummary(_ text: String, template: SummaryTemplate, provider: String, for meeting: Meeting) throws -> SummaryDocument {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let safeProvider = provider.replacingOccurrences(of: "-", with: "_")
        let name = "summary-\(template.rawValue)-\(safeProvider)-\(f.string(from: Date())).md"
        let url = folder(for: meeting).url.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return SummaryDocument(id: name, template: template.rawValue, provider: provider, createdAt: Date(), title: template.title)
    }

    public func updateSummary(_ doc: SummaryDocument, text: String, of meeting: Meeting) throws {
        try text.write(to: folder(for: meeting).url.appendingPathComponent(doc.id), atomically: true, encoding: .utf8)
    }

    public func deleteSummary(_ doc: SummaryDocument, of meeting: Meeting) throws {
        try FileManager.default.removeItem(at: folder(for: meeting).url.appendingPathComponent(doc.id))
    }

    // MARK: - Busca

    /// Procura no título e no texto das transcrições. Simples e suficiente para centenas de reuniões.
    public func search(_ query: String) -> [Meeting] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return meetings }
        return meetings.filter { m in
            if m.title.localizedCaseInsensitiveContains(q) { return true }
            guard let t = transcript(of: m) else { return false }
            return t.segments.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    public func fileSizeOnDisk() -> Int64 { AppPaths.directorySize(root) }
}

public enum JSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

public enum AppPaths {
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("Meety", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static var models: URL {
        let url = applicationSupport.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static var temporary: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Meety", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static var logs: URL {
        let url = applicationSupport.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }
}
