import Foundation

/// O motor do ditado: um `meety_engine.py serve` que fica vivo entre um ditado e outro, com o
/// Whisper carregado. Abrir o Python e carregar o modelo a cada ditado custaria vários segundos.
/// O processo sai sozinho depois de 10 minutos parado e volta no próximo ditado.
public final class DictationEngine: @unchecked Sendable {
    public static let shared = DictationEngine()

    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private let idleSeconds = 600

    /// Abre o motor e carrega o modelo, sem esperar. Chamado quando a gravação começa, para o
    /// carregamento acontecer enquanto a pessoa ainda fala.
    public func warmUp(model: URL) {
        Task { _ = try? await send(["model": model.path, "warm": true]) }
    }

    /// Transcreve um PCM float32 16 kHz mono e devolve o texto.
    public func transcribe(pcm: URL, model: URL, language: String?) async throws -> String {
        var request: [String: Any] = ["audio": pcm.path, "model": model.path]
        if let language { request["language"] = language }
        return try await send(request)
    }

    /// Encerra o motor (o modelo deixa a memória).
    public func stop() {
        lock.lock()
        let p = process, input = stdin
        lock.unlock()
        try? input?.close()
        p?.terminate()
    }

    // MARK: - Internos

    private func send(_ request: [String: Any]) async throws -> String {
        let id = UUID().uuidString
        var body = request
        body["id"] = id
        let line = try JSONSerialization.data(withJSONObject: body) + Data([0x0A])
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            do {
                let input = try running()
                pending[id] = continuation
                lock.unlock()
                do { try input.write(contentsOf: line) } catch {
                    lock.lock(); pending.removeValue(forKey: id); lock.unlock()
                    continuation.resume(throwing: error)
                }
            } catch {
                lock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    /// O stdin do processo, abrindo-o se preciso. Chamado com o `lock` tomado.
    private func running() throws -> FileHandle {
        if let process, process.isRunning, let stdin { return stdin }
        guard let runner = EngineRunner.bundled() else { throw EngineError.notBundled }
        let proc = Process()
        proc.executableURL = runner.pythonURL
        proc.arguments = [runner.scriptURL.path, "serve", "--idle", String(idleSeconds)]
        proc.currentDirectoryURL = AppPaths.temporary
        proc.environment = EngineRunner.environment()
        let inPipe = Pipe(), out = Pipe(), err = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = out
        proc.standardError = err

        let lines = LineBuffer()
        var stderrTail = StderrTail()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            for line in lines.append(data) { self?.handle(line) }
        }
        // O stderr precisa ser lido sempre: com o cano cheio, o Python trava.
        err.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty { stderrTail.append(data) }
        }
        proc.terminationHandler = { [weak self] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            EngineLog.append(command: "serve", status: p.terminationStatus, stderr: stderrTail.text)
            self?.ended(p, tail: stderrTail.lastLines(3))
        }
        try proc.run()
        process = proc
        stdin = inPipe.fileHandleForWriting
        return inPipe.fileHandleForWriting
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else { return }
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        switch obj["event"] as? String {
        case "result": continuation?.resume(returning: obj["text"] as? String ?? "")
        case "error": continuation?.resume(throwing: EngineError.failed(obj["message"] as? String ?? "unknown error"))
        default: break
        }
    }

    private func ended(_ p: Process, tail: String) {
        lock.lock()
        let waiting = pending.values
        pending.removeAll()
        if process === p { process = nil; stdin = nil }
        lock.unlock()
        for c in waiting { c.resume(throwing: EngineError.exit(p.terminationStatus, tail)) }
    }
}
