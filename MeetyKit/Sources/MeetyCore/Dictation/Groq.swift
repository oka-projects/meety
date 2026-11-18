import Foundation

/// Transcrição na Groq, com a chave da própria pessoa (guardada no Keychain).
/// O ditado usa a Groq quando há chave. As reuniões só vão para lá se a pessoa escolher a Groq
/// como modelo principal ou secundário em Ajustes > Modelos; o padrão é transcrever no Mac.
public enum Groq {
    static let keychainAccount = "groq"
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let model = "whisper-large-v3-turbo"
    public static let consoleURL = URL(string: "https://console.groq.com/keys")!

    /// Valor de `transcriptionModelID` (ou do secundário) quando a escolha é a Groq.
    public static let backendID = "groq"
    /// O que fica gravado na reunião como modelo usado.
    public static let transcriptModelID = "groq/\(model)"

    public static var apiKey: String? {
        get { Keychain.get(keychainAccount).flatMap { $0.isEmpty ? nil : $0 } }
        set { Keychain.set(newValue, for: keychainAccount) }
    }

    /// Um trecho devolvido pela Groq, com o tempo relativo ao áudio enviado.
    public struct Segment: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
        public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text }
    }

    public struct Detailed: Equatable, Sendable {
        /// Código do idioma ("pt"), quando a Groq informa.
        public var language: String?
        public var segments: [Segment]
        public init(language: String?, segments: [Segment]) { self.language = language; self.segments = segments }
    }

    /// Manda o áudio (m4a) e devolve o texto. É o caminho do ditado.
    public static func transcribe(_ file: URL, language: String?, key: String) async throws -> String {
        // Prazo curto: se a Groq demorar, vale mais cair para o modelo do Mac.
        let json = try await post(audio: try Data(contentsOf: file), format: "json", language: language, key: key, timeout: 45)
        guard let text = json["text"] as? String else { throw GroqError.http(200, "no text") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Manda o áudio (m4a) e devolve os trechos com início e fim. É o caminho das reuniões.
    public static func transcribeDetailed(_ audio: Data, language: String?, key: String, timeout: TimeInterval = 180) async throws -> Detailed {
        let json = try await post(audio: audio, format: "verbose_json", language: language, key: key, timeout: timeout)
        return parseDetailed(json, requestedLanguage: language)
    }

    static func parseDetailed(_ json: [String: Any], requestedLanguage: String?) -> Detailed {
        let segments = (json["segments"] as? [[String: Any]] ?? []).compactMap { s -> Segment? in
            guard let start = (s["start"] as? NSNumber)?.doubleValue, let end = (s["end"] as? NSNumber)?.doubleValue,
                  let text = (s["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return Segment(start: start, end: max(end, start), text: text)
        }
        return Detailed(language: requestedLanguage ?? languageCode(json["language"] as? String), segments: segments)
    }

    /// A resposta detalhada traz o idioma por extenso em inglês ("Portuguese"); o Meety guarda o código.
    static func languageCode(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        if let code = languageCodes[name] { return code }
        return name.count <= 3 ? name : nil
    }

    private static let languageCodes: [String: String] = {
        let english = Locale(identifier: "en")
        var map: [String: String] = [:]
        for code in ["en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi",
                     "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no", "th", "ur", "hr", "bg", "lt", "la", "ml", "cy", "sk", "te",
                     "fa", "lv", "bn", "sr", "az", "sl", "kn", "et", "mk", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw", "gl", "mr",
                     "pa", "si", "km", "af", "ka", "be", "gu", "am", "lo", "uz", "mt", "my", "tl"] {
            if let name = english.localizedString(forLanguageCode: code)?.lowercased() { map[name] = code }
        }
        map["mandarin"] = "zh"; map["cantonese"] = "yue"; map["castilian"] = "es"; map["flemish"] = "nl"
        return map
    }()

    private static func post(audio: Data, format: String, language: String?, key: String, timeout: TimeInterval) async throws -> [String: Any] {
        let boundary = UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", format)
        if let language { field("language", language) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let json else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw GroqError.http(status, message)
        }
        return json
    }

    /// Confere a chave listando os modelos (não gasta cota de transcrição).
    public static func check(key: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

public enum GroqError: LocalizedError, Sendable, Equatable {
    case http(Int, String)
    case noKey

    public var errorDescription: String? {
        switch self {
        case .http(401, _): return String(localized: "Groq didn't accept the API key.", bundle: .module)
        case .http(429, _): return String(localized: "Groq's usage limit was reached.", bundle: .module)
        case .http(_, let message): return String(localized: "Groq: \(message)", bundle: .module)
        case .noKey: return String(localized: "There's no Groq key saved. Add one in Settings > Models.", bundle: .module)
        }
    }

    /// Vale tentar de novo: erro do servidor da Groq, não da chave nem do limite.
    var isTransient: Bool {
        if case .http(let status, _) = self { return status >= 500 }
        return false
    }
}
