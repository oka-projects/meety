import Foundation

/// Transcrição do ditado na Groq, com a chave da própria pessoa (guardada no Keychain).
/// Só o ditado usa a Groq: as reuniões são sempre transcritas no Mac.
public enum Groq {
    static let keychainAccount = "groq"
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let model = "whisper-large-v3-turbo"
    public static let consoleURL = URL(string: "https://console.groq.com/keys")!

    public static var apiKey: String? {
        get { Keychain.get(keychainAccount).flatMap { $0.isEmpty ? nil : $0 } }
        set { Keychain.set(newValue, for: keychainAccount) }
    }

    /// Manda o áudio (m4a) e devolve o texto.
    public static func transcribe(_ file: URL, language: String?, key: String) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        if let language { field("language", language) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: file))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Prazo curto: se a Groq demorar, vale mais cair para o modelo do Mac.
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let text = json?["text"] as? String else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw GroqError.http(status, message)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Confere a chave listando os modelos (não gasta cota de transcrição).
    public static func check(key: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

public enum GroqError: LocalizedError, Sendable {
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .http(401, _): return String(localized: "Groq didn't accept the API key.", bundle: .module)
        case .http(429, _): return String(localized: "Groq's usage limit was reached.", bundle: .module)
        case .http(_, let message): return String(localized: "Groq: \(message)", bundle: .module)
        }
    }
}
