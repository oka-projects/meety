import Foundation

/// A lista de provedores que o Meety conhece, na ordem em que aparecem.
public enum SummaryRegistry {
    @MainActor
    public static func providers(models: ModelManager, settings: MeetySettings) -> [any SummaryProvider] {
        let summaryModel = models.catalog.model(id: settings.summaryModelID)
        var list: [any SummaryProvider] = []
        if AppleIntelligenceSummarizer.isSupported { list.append(AppleIntelligenceSummarizer()) }
        list.append(LocalMLXSummarizer(model: summaryModel, installed: summaryModel.map(models.isInstalled) ?? false))
        list.append(CLISummarizer(tool: .claude))
        list.append(CLISummarizer(tool: .codex))
        list.append(APISummarizer(vendor: APISummarizer.Vendor(rawValue: settings.apiProvider) ?? .anthropic))
        return list
    }

    /// O provedor escolhido nas preferências, ou o primeiro local que estiver pronto.
    @MainActor
    public static func preferred(models: ModelManager, settings: MeetySettings) async -> (any SummaryProvider)? {
        let all = providers(models: models, settings: settings)
        if let chosen = all.first(where: { $0.id == settings.summaryProviderID }) { return chosen }
        for p in all where !p.isCloud {
            if await p.availability().isAvailable { return p }
        }
        return nil
    }
}
