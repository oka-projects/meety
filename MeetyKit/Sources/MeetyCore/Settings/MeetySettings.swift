import Foundation
import Observation

/// Preferências do usuário (UserDefaults).
@MainActor
@Observable
public final class MeetySettings {
    public static let shared = MeetySettings()
    private let d = UserDefaults.standard

    public var transcriptionModelID: String { didSet { d.set(transcriptionModelID, forKey: "transcriptionModelID") } }
    public var summaryModelID: String { didSet { d.set(summaryModelID, forKey: "summaryModelID") } }
    public var language: TranscriptionLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    public var separateSpeakers: Bool { didSet { d.set(separateSpeakers, forKey: "separateSpeakers") } }
    public var transcribeAfterRecording: Bool { didSet { d.set(transcribeAfterRecording, forKey: "transcribeAfterRecording") } }
    public var summaryProviderID: String { didSet { d.set(summaryProviderID, forKey: "summaryProviderID") } }
    public var summaryLanguage: SummaryLanguage { didSet { d.set(summaryLanguage.rawValue, forKey: "summaryLanguage") } }
    public var microphoneID: String? { didSet { d.set(microphoneID, forKey: "microphoneID") } }
    public var welcomeDone: Bool { didSet { d.set(welcomeDone, forKey: "welcomeDone") } }
    public var cloudConsent: Bool { didSet { d.set(cloudConsent, forKey: "cloudConsent") } }
    public var apiProvider: String { didSet { d.set(apiProvider, forKey: "apiProvider") } }

    public enum SummaryLanguage: String, CaseIterable, Identifiable, Sendable {
        case app, meeting
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .app: return String(localized: "Same as Meety", bundle: .module)
            case .meeting: return String(localized: "Same as the meeting", bundle: .module)
            }
        }
    }

    private init() {
        transcriptionModelID = d.string(forKey: "transcriptionModelID") ?? "whisper-large-v3-turbo"
        summaryModelID = d.string(forKey: "summaryModelID") ?? (ModelCatalog.physicalMemoryGB >= 24 ? "qwen3-8b" : "qwen3-4b")
        language = TranscriptionLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .auto
        separateSpeakers = d.object(forKey: "separateSpeakers") as? Bool ?? true
        transcribeAfterRecording = d.object(forKey: "transcribeAfterRecording") as? Bool ?? true
        summaryProviderID = d.string(forKey: "summaryProviderID") ?? ""
        summaryLanguage = SummaryLanguage(rawValue: d.string(forKey: "summaryLanguage") ?? "") ?? .app
        microphoneID = d.string(forKey: "microphoneID")
        welcomeDone = d.bool(forKey: "welcomeDone")
        cloudConsent = d.bool(forKey: "cloudConsent")
        apiProvider = d.string(forKey: "apiProvider") ?? "anthropic"
    }

    public var transcriptionOptions: TranscriptionOptions {
        TranscriptionOptions(modelID: transcriptionModelID, language: language, separateSpeakers: separateSpeakers)
    }
}

/// Chaves de API no Keychain (nunca em UserDefaults).
public enum Keychain {
    static let service = "dev.oka.meety"

    public static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
