import Foundation

/// Um evento do motor Python (uma linha JSON do stdout).
public enum EngineEvent: Sendable, Equatable {
    case stage(String)
    case progress(percent: Double, seconds: Double?)
    case info(duration: Double?)
    case token(String)
    case transcript(language: String?, segments: [EngineSegment], elapsed: Double)
    case text(String)
    case health(EngineHealth)
    case error(String)
    case other(String)

    public struct EngineSegment: Codable, Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var text: String
    }

    public struct EngineHealth: Codable, Sendable, Equatable {
        public var python: String
        public var mlx: String?
        public var metal: Bool
        public var device: String?
        public var memory: Int64?
    }

    static func parse(_ line: String) -> EngineEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ev = obj["event"] as? String else { return nil }
        switch ev {
        case "stage": return .stage(obj["stage"] as? String ?? "")
        case "progress": return .progress(percent: obj["percent"] as? Double ?? 0, seconds: obj["seconds"] as? Double)
        case "info": return .info(duration: obj["duration"] as? Double)
        case "token": return .token(obj["text"] as? String ?? "")
        case "error": return .error(obj["message"] as? String ?? "unknown error")
        case "health":
            let h = EngineHealth(python: obj["python"] as? String ?? "?", mlx: obj["mlx"] as? String,
                                 metal: obj["metal"] as? Bool ?? false, device: obj["device"] as? String,
                                 memory: (obj["memory"] as? NSNumber)?.int64Value)
            return .health(h)
        case "result":
            if let text = obj["text"] as? String { return .text(text) }
            let segs = (obj["segments"] as? [[String: Any]] ?? []).compactMap { s -> EngineSegment? in
                guard let start = s["start"] as? Double, let end = s["end"] as? Double, let text = s["text"] as? String else { return nil }
                return EngineSegment(start: start, end: end, text: text)
            }
            return .transcript(language: obj["language"] as? String, segments: segs, elapsed: obj["elapsed"] as? Double ?? 0)
        default: return .other(ev)
        }
    }
}

public enum EngineError: LocalizedError, Sendable {
    case notBundled
    case failed(String)
    case exit(Int32, String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notBundled: return String(localized: "The speech engine is missing from this copy of Meety. Please download Meety again.", bundle: .module)
        case .failed(let m): return m
        case .exit(let code, let tail): return String(localized: "The speech engine stopped unexpectedly (code \(code)). \(tail)", bundle: .module)
        case .cancelled: return String(localized: "Cancelled.", bundle: .module)
        }
    }
}

/// Roda o motor Python embutido (`Contents/Resources/engine/`) e entrega os eventos conforme chegam.
public final class EngineRunner: @unchecked Sendable {
    public let pythonURL: URL
    public let scriptURL: URL

    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public static func bundled(in bundle: Bundle = .main) -> EngineRunner? {
        guard let res = bundle.resourceURL else { return nil }
        let engine = res.appendingPathComponent("engine", isDirectory: true)
        let py = engine.appendingPathComponent("python/bin/python3.12")
        let script = engine.appendingPathComponent("meety_engine.py")
        guard FileManager.default.isExecutableFile(atPath: py.path),
              FileManager.default.fileExists(atPath: script.path) else { return nil }
        return EngineRunner(pythonURL: py, scriptURL: script)
    }

    public init(pythonURL: URL, scriptURL: URL) {
        self.pythonURL = pythonURL
        self.scriptURL = scriptURL
    }

    /// Ambiente do Python embutido: sem rede, sem pacotes do usuário, cache do Hugging Face no app.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONNOUSERSITE"] = "1"
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        env["HF_HOME"] = AppPaths.applicationSupport.appendingPathComponent("hf-cache").path
        env["MPLBACKEND"] = "Agg"
        return env
    }

    /// Executa um comando do motor. O stream termina quando o processo sai; sai com erro se o
    /// código não for zero ou se o motor emitiu `error`.
    public func run(_ command: String, args: [String]) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let proc = Process()
            proc.executableURL = pythonURL
            proc.arguments = [scriptURL.path, command] + args
            proc.currentDirectoryURL = AppPaths.temporary
            proc.environment = Self.environment()

            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err

            let state = LineBuffer()
            var stderrTail = StderrTail()
            var sawError: String?

            out.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty else { return }
                for line in state.append(data) {
                    guard let ev = EngineEvent.parse(line) else { continue }
                    if case .error(let m) = ev { sawError = m }
                    continuation.yield(ev)
                }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty else { return }
                stderrTail.append(data)
            }

            proc.terminationHandler = { [weak self] p in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                let rest = out.fileHandleForReading.readDataToEndOfFile()
                for line in state.append(rest) + state.flush() {
                    guard let ev = EngineEvent.parse(line) else { continue }
                    if case .error(let m) = ev { sawError = m }
                    continuation.yield(ev)
                }
                stderrTail.append(err.fileHandleForReading.readDataToEndOfFile())
                let wasCancelled = self?.consumeCancelled() ?? false
                EngineLog.append(command: command, status: p.terminationStatus, stderr: stderrTail.text)
                if wasCancelled || p.terminationStatus == 15 || p.terminationStatus == 130 {
                    continuation.finish(throwing: EngineError.cancelled)
                } else if let m = sawError {
                    continuation.finish(throwing: EngineError.failed(m))
                } else if p.terminationStatus != 0 {
                    continuation.finish(throwing: EngineError.exit(p.terminationStatus, stderrTail.lastLines(3)))
                } else {
                    continuation.finish()
                }
            }

            do {
                lock.lock(); cancelled = false; process = proc; lock.unlock()
                try proc.run()
            } catch {
                continuation.finish(throwing: EngineError.failed(error.localizedDescription))
            }
            continuation.onTermination = { [weak self] _ in self?.cancel() }
        }
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
    }

    private func consumeCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let c = cancelled
        process = nil
        return c
    }

    public func health() async throws -> EngineEvent.EngineHealth {
        var found: EngineEvent.EngineHealth?
        // Lê até o fim: sair do laço antes derrubaria o processo (onTermination -> cancel).
        for try await ev in run("health", args: []) {
            if case .health(let h) = ev { found = h }
        }
        guard let found else { throw EngineError.failed("no health event") }
        return found
    }
}

/// Junta pedaços do stdout e devolve linhas completas.
final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let s = String(data: line, encoding: .utf8), !s.isEmpty { lines.append(s) }
        }
        return lines
    }
    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        defer { buffer.removeAll() }
        if let s = String(data: buffer, encoding: .utf8), !s.isEmpty { return [s] }
        return []
    }
}

struct StderrTail {
    private(set) var text = ""
    mutating func append(_ data: Data) {
        guard let s = String(data: data, encoding: .utf8) else { return }
        text += s
        if text.count > 20_000 { text = String(text.suffix(20_000)) }
    }
    func lastLines(_ n: Int) -> String {
        text.split(separator: "\n").suffix(n).joined(separator: " ")
    }
}

/// Diário técnico do motor (Ajuda > Exportar diagnóstico). Nunca vai para a interface.
public enum EngineLog {
    static let url = AppPaths.logs.appendingPathComponent("engine.log")
    static let lock = NSLock()
    static func append(command: String, status: Int32, stderr: String) {
        lock.lock(); defer { lock.unlock() }
        let f = ISO8601DateFormatter()
        var entry = "[\(f.string(from: Date()))] \(command) exit \(status)\n"
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { entry += trimmed.suffix(4000) + "\n" }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(entry.data(using: .utf8)!); try? h.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2_000_000,
           let s = try? String(contentsOf: url, encoding: .utf8) {
            try? String(s.suffix(500_000)).write(to: url, atomically: true, encoding: .utf8)
        }
    }
    public static func contents() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
}
