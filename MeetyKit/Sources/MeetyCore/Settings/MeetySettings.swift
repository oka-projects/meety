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

    // Ditado
    public var dictationEnabled: Bool { didSet { d.set(dictationEnabled, forKey: "dictationEnabled") } }
    public var dictationShortcut: DictationShortcut { didSet { d.set(dictationShortcut.rawValue, forKey: "dictationShortcut") } }
    /// Groq primeiro quando há chave; desligado, o ditado usa só o modelo do Mac.
    public var dictationUseGroq: Bool { didSet { d.set(dictationUseGroq, forKey: "dictationUseGroq") } }
    /// Modelo local do ditado (e da reserva quando a Groq falha): o leve ou o médio.
    public var dictationModelID: String { didSet { d.set(dictationModelID, forKey: "dictationModelID") } }
    public var dictationWaveStyle: DictationWaveStyle { didSet { d.set(dictationWaveStyle.rawValue, forKey: "dictationWaveStyle") } }
    /// Cola o texto no cursor (precisa de Acessibilidade); desligado, só copia.
    public var dictationPaste: Bool { didSet { d.set(dictationPaste, forKey: "dictationPaste") } }
    /// Última novidade que a pessoa já abriu (o selo do botão some depois disso).
    public var whatsNewSeen: String { didSet { d.set(whatsNewSeen, forKey: "whatsNewSeen") } }

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
        dictationEnabled = d.bool(forKey: "dictationEnabled")
        dictationShortcut = DictationShortcut(rawValue: d.string(forKey: "dictationShortcut") ?? "") ?? .optionSpace
        dictationUseGroq = d.object(forKey: "dictationUseGroq") as? Bool ?? true
        dictationModelID = d.string(forKey: "dictationModelID") ?? (ModelCatalog.physicalMemoryGB >= 8 ? DictationModels.medium : DictationModels.light)
        dictationWaveStyle = DictationWaveStyle(rawValue: d.string(forKey: "dictationWaveStyle") ?? "") ?? .fluid
        dictationPaste = d.object(forKey: "dictationPaste") as? Bool ?? true
        whatsNewSeen = d.string(forKey: "whatsNewSeen") ?? ""
    }

    public var transcriptionOptions: TranscriptionOptions {
        TranscriptionOptions(modelID: transcriptionModelID, language: language, separateSpeakers: separateSpeakers)
    }
}

/// Os dois modelos locais oferecidos para o ditado.
public enum DictationModels {
    public static let light = "whisper-small"
    public static let medium = "whisper-large-v3-turbo"
    public static let all = [light, medium]
    public static func title(_ id: String) -> String {
        id == light ? String(localized: "Light", bundle: .module) : String(localized: "Medium", bundle: .module)
    }
}

/// Atalho global do ditado. Tocar liga e desliga; segurar grava até soltar.
public enum DictationShortcut: String, CaseIterable, Identifiable, Sendable {
    case optionSpace, controlOptionSpace, commandShiftSpace, optionCommandD
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .commandShiftSpace: return "⇧⌘ Space"
        case .optionCommandD: return "⌥⌘ D"
        }
    }
}

public enum DictationWaveStyle: String, CaseIterable, Identifiable, Sendable {
    case fluid, spectrum
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fluid: return String(localized: "Fluid wave", bundle: .module)
        case .spectrum: return String(localized: "Spectrum", bundle: .module)
        }
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
