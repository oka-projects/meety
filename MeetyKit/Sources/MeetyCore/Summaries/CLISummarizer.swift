import AppKit
import Foundation

/// Resumo pelo Claude Code ou pelo Codex já instalados no Mac, pelo terminal ou pelos apps.
/// Usa a conta que a pessoa já tem; a transcrição vai para a nuvem do provedor.
public struct CLISummarizer: SummaryProvider {
    public enum Tool: String, Sendable, CaseIterable {
        case claude, codex

        var appBundleID: String { self == .claude ? "com.anthropic.claudefordesktop" : "com.openai.codex" }
        var appName: String { self == .claude ? "Claude" : "ChatGPT" }
        var cliName: String { rawValue }
        public var title: String { self == .claude ? "Claude" : "ChatGPT (Codex)" }
        var vendor: String { self == .claude ? "Anthropic" : "OpenAI" }
    }

    public struct Found: Sendable, Equatable {
        public let url: URL
        public let origin: Origin
        public enum Origin: Sendable, Equatable { case terminal, app }
        public var originTitle: String {
            switch origin {
            case .terminal: return String(localized: "from the terminal", bundle: .module)
            case .app: return String(localized: "from the Mac app", bundle: .module)
            }
        }
    }

    public let tool: Tool
    public var id: String { "cli-\(tool.rawValue)" }
    public var title: String { tool.title }
    public var subtitle: String { String(localized: "Uses your \(tool.appName) account. The transcript is sent to \(tool.vendor).", bundle: .module) }
    public var systemIcon: String { tool == .claude ? "sparkle" : "bubble.left.and.text.bubble.right" }
    public let isCloud = true
    public let contextTokens = 150_000

    public init(tool: Tool) { self.tool = tool }

    // MARK: - Onde está o CLI

    /// Todos os CLIs encontrados: primeiro o do terminal (a pessoa escolheu essa versão), depois o
    /// que vem dentro do app. Se o primeiro falhar (versão velha, sem login), o próximo é tentado.
    public static func candidates(_ tool: Tool) -> [Found] {
        var out: [Found] = []
        if let u = terminalBinary(tool.cliName) { out.append(Found(url: u, origin: .terminal)) }
        if let u = appBinary(tool), !out.contains(where: { $0.url == u }) { out.append(Found(url: u, origin: .app)) }
        return out
    }

    public static func locate(_ tool: Tool) -> Found? { candidates(tool).first }

    static func terminalBinary(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin"]
        dirs += loginShellPath().split(separator: ":").map(String.init)
        for d in dirs {
            let p = "\(d)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p).resolvingSymlinksInPath() }
        }
        return nil
    }

    /// PATH do shell de login: apps abertos pela GUI não herdam o do terminal.
    static func loginShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-c", "echo $PATH"]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appBinary(_ tool: Tool) -> URL? {
        let fm = FileManager.default
        switch tool {
        case .codex:
            // O app do ChatGPT traz o CLI em Contents/Resources/codex-cli/bin/codex.
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.appBundleID) else { return nil }
            let u = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
            return fm.isExecutableFile(atPath: u.path) ? u : nil
        case .claude:
            // O app do Claude baixa o Claude Code em
            // ~/Library/Application Support/Claude/claude-code/<versão>/<hash>/claude.app/Contents/MacOS/claude
            // (a pasta claude-code-vm/ é Linux, para a VM: não serve).
            let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code")
            guard let versions = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return nil }
            let sorted = versions.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            for v in sorted {
                guard let hashes = try? fm.contentsOfDirectory(at: v, includingPropertiesForKeys: nil) else { continue }
                for h in hashes {
                    let bin = h.appendingPathComponent("claude.app/Contents/MacOS/claude")
                    if fm.isExecutableFile(atPath: bin.path) { return bin }
                }
            }
            return nil
        }
    }

    public static func appInstalled(_ tool: Tool) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.appBundleID) != nil
    }

    // MARK: - Disponibilidade

    public func availability() async -> ProviderAvailability {
        guard let found = Self.locate(tool) else {
            let hasApp = Self.appInstalled(tool)
            let reason = hasApp
                ? String(localized: "\(tool.appName) is installed but its command line tool wasn't found. Open \(tool.appName) once so it finishes setting up.", bundle: .module)
                : String(localized: "\(tool.appName) isn't installed on this Mac.", bundle: .module)
            return .unavailable(reason: reason, action: hasApp ? .openApp(bundleID: tool.appBundleID) : nil)
        }
        return .available(detail: found.originTitle)
    }

    /// Chamada curta para saber se está logado. Devolve nil se OK, ou a razão.
    public func probe() async -> String? {
        do {
            _ = try await run(system: "Reply with the single word OK.", user: "OK?", timeout: 90, onPartial: { _ in })
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Execução

    public func summarize(system: String, user: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        try await run(system: system, user: user, timeout: 600, onPartial: onPartial)
    }

    /// Tenta cada CLI encontrado, na ordem; devolve o primeiro que responder.
    func run(system: String, user: String, timeout: TimeInterval, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        let found = Self.candidates(tool)
        guard !found.isEmpty else { throw SummaryError.unavailable(String(localized: "\(tool.appName) isn't available.", bundle: .module)) }
        var lastError: Error?
        for f in found {
            do { return try await run(with: f, system: system, user: user, timeout: timeout, onPartial: onPartial) }
            catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError ?? SummaryError.failed("unknown")
    }

    func run(with found: Found, system: String, user: String, timeout: TimeInterval, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        // Pasta vazia e temporária: o CLI não deve ler nem escrever nada do usuário.
        let work = AppPaths.temporary.appendingPathComponent("cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let p = Process()
        p.executableURL = found.url
        p.currentDirectoryURL = work
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.loginShellPath() + ":/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        // Se o Meety foi aberto de dentro de uma sessão do Claude Code, o CLI acha que está aninhado.
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        p.environment = env
        let lastMessage = work.appendingPathComponent("answer.txt")

        let prompt = user
        switch tool {
        case .claude:
            // Modo não interativo, sem ferramentas: só texto entra e só texto sai.
            p.arguments = ["-p", "--output-format", "text", "--tools", "", "--no-session-persistence",
                           "--append-system-prompt", system, "--disable-slash-commands", prompt]
        case .codex:
            // `codex exec` lê o prompt do stdin quando recebe "-"; só leitura, fora de repositório, sem
            // guardar sessão. A resposta final vai para um arquivo (o stdout tem o diário da execução).
            p.arguments = ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "--ephemeral", "--color", "never",
                           "-o", lastMessage.path, "-"]
        }

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        let collector = OutputCollector()
        let streams = tool == .claude
        stdout.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            collector.append(d)
            if streams { onPartial(collector.text) }
        }
        try p.run()
        if tool == .codex {
            let full = "\(system)\n\n\(prompt)"
            stdin.fileHandleForWriting.write(full.data(using: .utf8)!)
        }
        try? stdin.fileHandleForWriting.close()

        let finished: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                p.terminationHandler = { _ in timer.cancel(); cont.resume(returning: true) }
            }
        } onCancel: { if p.isRunning { p.terminate() } }
        _ = finished
        stdout.fileHandleForReading.readabilityHandler = nil
        collector.append(stdout.fileHandleForReading.readDataToEndOfFile())
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        EngineLog.append(command: "cli-\(tool.rawValue)", status: p.terminationStatus, stderr: err)
        try Task.checkCancellation()
        guard p.terminationStatus == 0 else {
            let tail = err.split(separator: "\n").suffix(3).joined(separator: " ")
            if tail.lowercased().contains("login") || tail.lowercased().contains("auth") || tail.lowercased().contains("not logged") {
                throw SummaryError.failed(String(localized: "\(tool.appName) isn't signed in. Open \(tool.appName), sign in and try again.", bundle: .module))
            }
            throw SummaryError.failed(String(localized: "\(tool.title) failed (code \(p.terminationStatus)). \(tail)", bundle: .module))
        }
        var text = collector.text
        if tool == .codex, let t = try? String(contentsOf: lastMessage, encoding: .utf8) { text = t }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SummaryError.failed(String(localized: "\(tool.title) returned nothing.", bundle: .module)) }
        return text
    }

    /// Plano B: copia o prompt e abre o app, para a pessoa colar.
    public static func sendToApp(_ tool: Tool, system: String, user: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("\(system)\n\n\(user)", forType: .string)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.appBundleID) else { return false }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

final class OutputCollector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
