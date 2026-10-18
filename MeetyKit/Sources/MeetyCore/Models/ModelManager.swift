import Foundation
import Observation

/// Baixa os modelos do Hugging Face para `Models/` e diz quais estão instalados.
/// Download em partes, com retomada: cada arquivo é baixado para `<nome>.part` com `Range`.
@MainActor
@Observable
public final class ModelManager {
    public let catalog: ModelCatalog
    public private(set) var installed: Set<String> = []
    public private(set) var downloads: [String: DownloadState] = [:]

    public struct DownloadState: Equatable, Sendable {
        public var fraction: Double
        public var receivedBytes: Int64
        public var totalBytes: Int64
        public var currentFile: String
        public var error: String?
    }

    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    public init(catalog: ModelCatalog = .bundled()) {
        self.catalog = catalog
        refresh()
    }

    public func isInstalled(_ model: ModelInfo) -> Bool { installed.contains(model.id) }
    public func isDownloading(_ model: ModelInfo) -> Bool { downloads[model.id] != nil && downloads[model.id]?.error == nil }

    public func refresh() {
        var set = Set<String>()
        for m in catalog.models where Self.looksComplete(m) { set.insert(m.id) }
        installed = set
    }

    /// Instalado = tem o marcador `.meety-complete`, gravado no fim do download.
    static func looksComplete(_ m: ModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: m.folder.appendingPathComponent(".meety-complete").path)
    }

    public func installedModels(of kind: ModelKind) -> [ModelInfo] {
        catalog.models(of: kind).filter { installed.contains($0.id) }
    }

    public func sizeOnDisk() -> Int64 { AppPaths.directorySize(AppPaths.models) }

    // MARK: - Download

    public func download(_ model: ModelInfo) {
        guard tasks[model.id] == nil else { return }
        downloads[model.id] = DownloadState(fraction: 0, receivedBytes: 0, totalBytes: model.sizeBytes, currentFile: "")
        tasks[model.id] = Task { [weak self] in
            do {
                try await HuggingFaceDownloader.download(repo: model.repo, into: model.folder, wants: model.wants(file:)) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, var s = self.downloads[model.id] else { return }
                        s.fraction = progress.fraction; s.receivedBytes = progress.received
                        s.totalBytes = progress.total; s.currentFile = progress.file
                        self.downloads[model.id] = s
                    }
                }
                try "ok".write(to: model.folder.appendingPathComponent(".meety-complete"), atomically: true, encoding: .utf8)
                await MainActor.run { [weak self] in
                    self?.downloads[model.id] = nil
                    self?.installed.insert(model.id)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in self?.downloads[model.id] = nil }
            } catch {
                await MainActor.run { [weak self] in
                    self?.downloads[model.id]?.error = error.localizedDescription
                }
            }
            await MainActor.run { [weak self] in self?.tasks[model.id] = nil }
        }
    }

    public func cancelDownload(_ model: ModelInfo) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        downloads[model.id] = nil
    }

    public func retry(_ model: ModelInfo) {
        downloads[model.id] = nil
        download(model)
    }

    public func delete(_ model: ModelInfo) throws {
        try FileManager.default.removeItem(at: model.folder)
        installed.remove(model.id)
    }

    /// Baixa, em sequência, tudo que falta dos recomendados.
    public func downloadRecommended() {
        for m in catalog.recommended() where !installed.contains(m.id) { download(m) }
    }

    public var recommendedPending: [ModelInfo] { catalog.recommended().filter { !installed.contains($0.id) } }
}

/// Download de um repositório do Hugging Face por HTTP, sem a biblioteca deles.
public enum HuggingFaceDownloader {
    public struct Progress: Sendable { public var fraction: Double; public var received: Int64; public var total: Int64; public var file: String }

    struct TreeEntry: Decodable { let type: String; let path: String; let size: Int64? }

    public enum DownloadError: LocalizedError {
        case http(Int, String), noFiles
        public var errorDescription: String? {
            switch self {
            case .http(let code, let file): return String(localized: "Download failed (HTTP \(code)) for \(file). Check your connection and try again.", bundle: .module)
            case .noFiles: return String(localized: "The model repository is empty or unavailable.", bundle: .module)
            }
        }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    /// Lista os arquivos (recursivo) do repositório.
    public static func listFiles(repo: String, path: String = "") async throws -> [(path: String, size: Int64)] {
        var url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main")!
        if !path.isEmpty { url = url.appendingPathComponent(path) }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, repo)
        }
        let entries = try JSONDecoder().decode([TreeEntry].self, from: data)
        var out: [(String, Int64)] = []
        for e in entries {
            if e.type == "directory" { out += try await listFiles(repo: repo, path: e.path) }
            else { out.append((e.path, e.size ?? 0)) }
        }
        return out
    }

    public static func download(repo: String, into folder: URL, wants: @Sendable (String) -> Bool = { !$0.hasPrefix(".git") },
                                progress: @escaping @Sendable (Progress) -> Void) async throws {
        let files = try await listFiles(repo: repo).filter { wants($0.path) }
        guard !files.isEmpty else { throw DownloadError.noFiles }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = files.reduce(0) { $0 + $1.size }
        var done: Int64 = 0
        for f in files {
            try Task.checkCancellation()
            let dest = folder.appendingPathComponent(f.path)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == f.size, f.size > 0 {
                done += f.size
                progress(Progress(fraction: total > 0 ? Double(done) / Double(total) : 0, received: done, total: total, file: f.path))
                continue
            }
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/")!.appendingPathComponent(f.path)
            try await downloadFile(url, to: dest, expected: f.size) { received in
                progress(Progress(fraction: total > 0 ? Double(done + received) / Double(total) : 0, received: done + received, total: total, file: f.path))
            }
            done += f.size
        }
        progress(Progress(fraction: 1, received: total, total: total, file: ""))
    }

    /// Baixa um arquivo em stream para `<dest>.part`, retomando de onde parou, e renomeia no fim.
    static func downloadFile(_ url: URL, to dest: URL, expected: Int64, onBytes: @escaping @Sendable (Int64) -> Void) async throws {
        let part = dest.appendingPathExtension("part")
        var existing: Int64 = 0
        if let s = try? part.resourceValues(forKeys: [.fileSizeKey]).fileSize { existing = Int64(s) }
        if existing > expected, expected > 0 { try? FileManager.default.removeItem(at: part); existing = 0 }

        var req = URLRequest(url: url)
        if existing > 0 { req.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DownloadError.http(0, dest.lastPathComponent) }
        switch http.statusCode {
        case 200:
            // O servidor ignorou o Range: recomeça.
            try? FileManager.default.removeItem(at: part); existing = 0
        case 206: break
        case 416 where existing == expected: break
        default: throw DownloadError.http(http.statusCode, dest.lastPathComponent)
        }
        if !FileManager.default.fileExists(atPath: part.path) { FileManager.default.createFile(atPath: part.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var received = existing
        var buffer = Data(); buffer.reserveCapacity(1 << 20)
        var lastReport = Date()
        if http.statusCode != 416 {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= (1 << 20) {
                    try handle.write(contentsOf: buffer); received += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                    if Date().timeIntervalSince(lastReport) > 0.2 { onBytes(received); lastReport = Date() }
                    try Task.checkCancellation()
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer); received += Int64(buffer.count) }
        }
        try handle.close()
        onBytes(received)
        if expected > 0, received != expected {
            throw DownloadError.http(0, "\(dest.lastPathComponent) (incomplete)")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: part, to: dest)
    }
}
