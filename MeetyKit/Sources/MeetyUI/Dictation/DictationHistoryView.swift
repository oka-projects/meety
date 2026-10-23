import MeetyCore
import SwiftUI

/// Histórico dos ditados, aberto pela barra de menus e pelas Configurações.
public struct DictationHistoryView: View {
    let dictation: DictationController
    @State private var search = ""
    public init(dictation: DictationController) { self.dictation = dictation }

    private var filtered: [Dictation] {
        let items = dictation.history.items
        return search.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    public var body: some View {
        List(filtered) { item in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    Text(verbatim: "· \(item.origin.title)")
                    Spacer()
                    Button(String(localized: "Copy", bundle: .module)) { dictation.copy(item) }
                    Button(role: .destructive) { dictation.history.remove(item) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Delete", bundle: .module))
                }
                .font(MeetyFont.caption)
                .foregroundStyle(Color.meety.textSecondary)
                Text(item.text).textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
        .searchable(text: $search, placement: .toolbar, prompt: String(localized: "Search", bundle: .module))
        .overlay {
            if filtered.isEmpty {
                Text(dictation.history.items.isEmpty
                     ? String(localized: "Your dictations will appear here.", bundle: .module)
                     : String(localized: "Nothing found", bundle: .module))
                    .foregroundStyle(Color.meety.textSecondary)
            }
        }
        .frame(minWidth: 460, minHeight: 400)
    }
}
