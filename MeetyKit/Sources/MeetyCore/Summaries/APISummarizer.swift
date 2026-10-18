import Foundation

/// Resumo pela API da Anthropic ou da OpenAI, com a chave da própria pessoa (no Keychain).
public struct APISummarizer: SummaryProvider {
    public enum Vendor: String, CaseIterable, Identifiable, Sendable {
        case anthropic, openai
        public var id: String { rawValue }
        public var title: String { self == .anthropic ? "Anthropic (Claude)" : "OpenAI" }
        public var keychainAccount: String { "api-key-\(rawValue)" }
        public var defaultModel: String { self == .anthropic ? "claude-sonnet-5-5" : "gpt-5.1" }
        public var keyHint: String { self == .anthropic ? "sk-ant-…" : "sk-…" }
        public var consoleURL: URL { URL(string: self == .anthropic ? "https://console.anthropic.com/settings/keys" : "https://platform.openai.com/api-keys")! }
    }

    public let vendor: Vendor
    public let model: String
    public var id: String { "api" }
    public let title = String(localized: "API key", bundle: .module)
    public var subtitle: String { String(localized: "Your own \(vendor.title) key. The transcript is sent to their servers.", bundle: .module) }
    public let systemIcon = "key"
    public let isCloud = true
    public let contextTokens = 150_000

    public init(vendor: Vendor, model: String? = nil) {
        self.vendor = vendor
        self.model = model ?? vendor.defaultModel
    }

    public static func hasKey(_ vendor: Vendor) -> Bool { !(Keychain.get(vendor.keychainAccount) ?? "").isEmpty }

    public func availability() async -> ProviderAvailability {
        guard Self.hasKey(vendor) else {
            return .unavailable(reason: String(localized: "No \(vendor.title) API key saved.", bundle: .module), action: .enterAPIKey)
        }
        return .available(detail: vendor.title)
    }

    public func summarize(system: String, user: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let key = Keychain.get(vendor.keychainAccount), !key.isEmpty else {
            throw SummaryError.unavailable(String(localized: "No API key saved.", bundle: .module))
        }
        var req: URLRequest
        let body: [String: Any]
        switch vendor {
        case .anthropic:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": 4000, "system": system, "messages": [["role": "user", "content": user]]]
        case .openai:
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummaryError.failed(String(localized: "Unexpected answer from \(vendor.title) (HTTP \(status)).", bundle: .module))
        }
        if status == 401 { throw SummaryError.failed(String(localized: "The \(vendor.title) API key was rejected. Check it in Settings.", bundle: .module)) }
        guard (200..<300).contains(status) else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw SummaryError.failed("\(vendor.title): \(msg)")
        }
        switch vendor {
        case .anthropic:
            let blocks = json["content"] as? [[String: Any]] ?? []
            let text = blocks.compactMap { $0["text"] as? String }.joined()
            onPartial(text)
            return text
        case .openai:
            let choices = json["choices"] as? [[String: Any]] ?? []
            let text = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
            onPartial(text)
            return text
        }
    }
}
