import MeetyCore
import SwiftUI

/// Lista de modelos com estado, download, progresso e remoção.
struct ModelsListView: View {
    enum Style { case settings, welcome }
    @Bindable var model: AppModel
    var modelsToShow: [ModelInfo]
    var style: Style = .settings

    var body: some View {
        if style == .welcome {
            Card {
                VStack(spacing: 0) {
                    ForEach(modelsToShow) { m in
                        row(m)
                        if m.id != modelsToShow.last?.id { Divider().overlay(Color.meety.separator) }
                    }
                }
            }
        } else {
            ForEach(modelsToShow) { m in row(m) }
        }
    }

    @ViewBuilder
    func row(_ m: ModelInfo) -> some View {
        let installed = model.models.isInstalled(m)
        let dl = model.models.downloads[m.id]
        HStack(spacing: 12) {
            if style == .welcome {
                Text(m.kind.title).foregroundStyle(Color.meety.textSecondary).frame(width: 110, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(m.displayName).font(.system(size: style == .welcome ? 15 : 13, weight: style == .welcome ? .regular : .medium))
                    if let tag = m.tagTitle { Badge(text: tag, style: m.isRecommended ? .accent : .neutral) }
                    if m.minMemoryGB > ModelCatalog.physicalMemoryGB {
                        Badge(text: String(localized: "Needs \(m.minMemoryGB) GB", bundle: .module), style: .warning)
                    }
                }
                if style == .settings { Text(m.displayDescription).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary) }
                if let dl, let e = dl.error { Text(e).font(MeetyFont.callout).foregroundStyle(Color.meety.warning).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let dl, dl.error == nil {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: dl.fraction).progressViewStyle(.linear).tint(Color.meety.accent).frame(width: 120)
                    Text(String(localized: "\(ByteCountFormatter.string(fromByteCount: dl.receivedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: dl.totalBytes, countStyle: .file))", bundle: .module))
                        .font(MeetyFont.caption).foregroundStyle(Color.meety.textSecondary).monospacedDigit()
                }
                Button { model.models.cancelDownload(m) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.borderless).help(String(localized: "Cancel download", bundle: .module))
            } else if let dl, dl.error != nil {
                Button(String(localized: "Retry", bundle: .module)) { model.models.retry(m) }
                Button { model.models.cancelDownload(m) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }.buttonStyle(.borderless)
            } else {
                Text(m.sizeText).font(.system(size: 13)).foregroundStyle(Color.meety.textSecondary).monospacedDigit()
                if installed {
                    ZStack {
                        Circle().fill(Color.meety.successTint).frame(width: 24, height: 24)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.meety.success)
                    }
                    if style == .settings {
                        Button { try? model.models.delete(m) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help(String(localized: "Delete this model", bundle: .module))
                    }
                } else {
                    Button(String(localized: "Download", bundle: .module)) { model.models.download(m) }
                }
            }
        }
        .padding(.horizontal, style == .welcome ? 14 : 0).padding(.vertical, style == .welcome ? 12 : 4)
    }
}
