import MeetyCore
import SwiftUI

/// Lista de modelos com estado, download, progresso e remoção.
struct ModelsListView: View {
    @Bindable var model: AppModel
    var modelsToShow: [ModelInfo]
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(modelsToShow) { m in
                row(m)
                if m.id != modelsToShow.last?.id { Divider() }
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    func row(_ m: ModelInfo) -> some View {
        let installed = model.models.isInstalled(m)
        let dl = model.models.downloads[m.id]
        HStack(spacing: 12) {
            Image(systemName: icon(m.kind)).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.name).fontWeight(.medium)
                    if let tag = m.tagTitle { Text(tag).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(.tint.opacity(0.15), in: Capsule()) }
                    if m.minMemoryGB > ModelCatalog.physicalMemoryGB { Text(String(localized: "Needs \(m.minMemoryGB) GB", bundle: .module)).font(.caption2).foregroundStyle(.orange) }
                }
                if !compact { Text(m.description).font(.caption).foregroundStyle(.secondary) }
                if let dl {
                    if let e = dl.error { Text(e).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                    else {
                        ProgressView(value: dl.fraction).controlSize(.small)
                        Text("\(ByteCountFormatter.string(fromByteCount: dl.receivedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: dl.totalBytes, countStyle: .file))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer()
            Text(m.sizeText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let dl {
                if dl.error != nil { Button(String(localized: "Retry", bundle: .module)) { model.models.retry(m) } }
                Button { model.models.cancelDownload(m) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
            } else if installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if !compact {
                    Button { try? model.models.delete(m) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(String(localized: "Delete this model", bundle: .module))
                }
            } else {
                Button(String(localized: "Download", bundle: .module)) { model.models.download(m) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    func icon(_ k: ModelKind) -> String {
        switch k { case .transcription: return "waveform"; case .summary: return "text.alignleft"; case .speakers: return "person.2" }
    }
}
