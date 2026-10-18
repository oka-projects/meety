import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Resumo com o modelo do próprio sistema (Apple Intelligence, macOS 26+). Sem download, no aparelho.
public struct AppleIntelligenceSummarizer: SummaryProvider {
    public let id = "apple-intelligence"
    public let title = "Apple Intelligence"
    public let subtitle = String(localized: "The model built into macOS. Nothing leaves your Mac.", bundle: .module)
    public let systemIcon = "apple.intelligence"
    public let isCloud = false
    /// O modelo do sistema tem janela curta: resume por partes.
    public let contextTokens = 4_000

    public init() {}

    public static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    public func availability() async -> ProviderAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available(detail: nil)
            case .unavailable(let reason):
                let text: String
                switch reason {
                case .deviceNotEligible: text = String(localized: "This Mac doesn't support Apple Intelligence.", bundle: .module)
                case .appleIntelligenceNotEnabled: text = String(localized: "Apple Intelligence is turned off. Turn it on in System Settings > Apple Intelligence & Siri.", bundle: .module)
                case .modelNotReady: text = String(localized: "Apple Intelligence is still downloading its model. Try again in a while.", bundle: .module)
                @unknown default: text = String(localized: "Apple Intelligence isn't available right now.", bundle: .module)
                }
                return .unavailable(reason: text, action: .openSettingsSection("x-apple.systempreferences:com.apple.Siri-Settings.extension"))
            }
        }
        #endif
        return .unavailable(reason: String(localized: "Needs macOS 26 or later.", bundle: .module), action: nil)
    }

    public func summarize(system: String, user: String, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(instructions: system)
            var acc = ""
            let stream = session.streamResponse(to: user)
            for try await partial in stream {
                acc = partial.content
                onPartial(acc)
            }
            return acc
        }
        #endif
        throw SummaryError.unavailable(String(localized: "Needs macOS 26 or later.", bundle: .module))
    }
}
