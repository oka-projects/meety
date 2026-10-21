import MeetyCore
import SwiftUI

/// A aba Resumo: escolhe o tipo e quem escreve, gera, mostra e guarda.
struct SummaryView: View {
    @Bindable var model: AppModel
    let meeting: Meeting
    let transcript: Transcript?

    @State private var template: SummaryTemplate = .minutes
    @State private var customPrompt = ""
    @State private var providers: [ProviderRow] = []
    @State private var selectedProviderID: String = ""
    @State private var generating = false
    @State private var partial = ""
    @State private var error: String?
    @State private var saved: [SummaryDocument] = []
    @State private var selectedDoc: SummaryDocument?
    @State private var docText = ""
    @State private var task: Task<Void, Never>?
    @State private var showCloudConsent = false
    /// Resumo salvo aparece formatado; o lápis abre o Markdown cru para editar.
    @State private var editing = false

    struct ProviderRow: Identifiable {
        let provider: any SummaryProvider
        var availability: ProviderAvailability
        var id: String { provider.id }
    }

    var body: some View {
        HStack(spacing: 0) {
            controls.frame(width: 300)
            Divider().overlay(Color.meety.separator)
            output
            Divider().overlay(Color.meety.separator)
            savedList.frame(width: 220)
        }
        .task { await loadProviders(); reloadSaved() }
        .alert(String(localized: "Send the transcript to the cloud?", bundle: .module), isPresented: $showCloudConsent) {
            Button(String(localized: "Send", bundle: .module)) { model.settings.cloudConsent = true; generate(force: true) }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(String(localized: "This option sends the whole transcript to an outside service to write the summary. Local options keep everything on your Mac.", bundle: .module))
        }
    }

    var selectedRow: ProviderRow? { providers.first { $0.id == selectedProviderID } }

    // MARK: - Coluna da esquerda

    var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(String(localized: "What do you need", bundle: .module))
                VStack(spacing: 2) {
                    ForEach(SummaryTemplate.allCases) { t in
                        Button { template = t } label: {
                            HStack(spacing: 10) {
                                Image(systemName: t.systemIcon).frame(width: 18)
                                    .foregroundStyle(template == t ? Color.meety.accentText : Color.meety.textSecondary)
                                Text(t.title).font(.system(size: 14))
                                    .foregroundStyle(template == t ? Color.meety.accentText : Color.meety.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(template == t ? Color.meety.accentTint : .clear, in: RoundedRectangle(cornerRadius: MeetyRadius.row, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(t.subtitle)
                    }
                }
                .padding(.top, 10)
                if template == .custom {
                    TextField(String(localized: "Ask something about this meeting…", bundle: .module), text: $customPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...5).padding(.top, 8)
                }

                SectionLabel(String(localized: "Written by", bundle: .module)).padding(.top, 24)
                VStack(spacing: 8) {
                    ForEach(providers) { row in ProviderCard(row: row, selected: row.id == selectedProviderID, action: actionButton) { selectedProviderID = row.id } }
                }
                .padding(.top, 10)
                .onChange(of: selectedProviderID) { _, v in model.settings.summaryProviderID = v }

                Button {
                    if generating { task?.cancel() } else { generate(force: false) }
                } label: {
                    Group {
                        if generating { Label(String(localized: "Stop", bundle: .module), systemImage: "stop.fill") }
                        else { Label(String(localized: "Generate", bundle: .module), systemImage: "sparkles") }
                    }
                    .labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(transcript == nil || (!generating && !(selectedRow?.availability.isAvailable ?? false)))
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.top, 20)

                if transcript == nil {
                    Label(String(localized: "Transcribe the meeting first.", bundle: .module), systemImage: "info.circle")
                        .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).padding(.top, 10)
                } else if let row = selectedRow {
                    PrivacyLine(cloud: row.provider.isCloud,
                                text: row.provider.isCloud ? String(localized: "Leaves your Mac", bundle: .module) : String(localized: "Stays on your Mac", bundle: .module))
                        .padding(.top, 10)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    func actionButton(_ action: ProviderAction) -> some View {
        switch action {
        case .downloadModel(let id):
            if let m = model.models.catalog.model(id: id) {
                if model.models.isDownloading(m) { ProgressView().controlSize(.small) }
                else { Button(String(localized: "Download", bundle: .module)) { model.models.download(m); Task { try? await Task.sleep(for: .seconds(1)); await loadProviders() } } }
            }
        case .openApp(let bundleID):
            Button(String(localized: "Open app", bundle: .module)) {
                if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { NSWorkspace.shared.openApplication(at: u, configuration: .init()) }
            }
        case .openSettingsSection(let s):
            if s.hasPrefix("x-apple") { Button(String(localized: "Open Settings", bundle: .module)) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } } }
            else { SettingsLink { Text(String(localized: "Open Settings", bundle: .module)) } }
        case .enterAPIKey:
            SettingsLink { Text(String(localized: "Add key", bundle: .module)) }
        }
    }

    // MARK: - Centro

    var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.meety.warning)
                }
                if generating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(partial.isEmpty ? String(localized: "Thinking…", bundle: .module) : String(localized: "Writing…", bundle: .module))
                            .foregroundStyle(Color.meety.textSecondary)
                    }
                    .font(MeetyFont.body)
                    if !partial.isEmpty { MarkdownView(partial) }
                } else if let doc = selectedDoc {
                    HStack(spacing: 12) {
                        Text(verbatim: "\(doc.title) · \(doc.provider) · \(MeetyFormat.dayAndTime(doc.createdAt))")
                            .font(.system(size: 14)).foregroundStyle(Color.meety.textSecondary).lineLimit(1)
                        Spacer()
                        Button { editing.toggle() } label: {
                            if editing { Text(String(localized: "Done", bundle: .module)) } else { Image(systemName: "pencil") }
                        }
                        .help(editing ? String(localized: "Show formatted", bundle: .module) : String(localized: "Edit the text", bundle: .module))
                        Button { copy(docText) } label: { Image(systemName: "doc.on.doc") }.help(String(localized: "Copy", bundle: .module))
                        Button(role: .destructive) { deleteDoc(doc) } label: { Image(systemName: "trash") }.help(String(localized: "Delete this summary", bundle: .module))
                    }
                    .buttonStyle(.borderless).foregroundStyle(Color.meety.textPrimary)
                    if editing {
                        TextEditor(text: $docText)
                            .font(.system(size: 13, design: .monospaced)).lineSpacing(3).scrollContentBackground(.hidden).scrollDisabled(true)
                            .padding(10)
                            .background(Color.meety.control, in: RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous).stroke(Color.meety.controlBorder))
                            .frame(minHeight: 320)
                            .onChange(of: docText) { _, t in try? model.library.updateSummary(doc, text: t, of: meeting) }
                    } else {
                        MarkdownView(docText)
                            .frame(maxWidth: 720, alignment: .leading)
                            .onTapGesture(count: 2) { editing = true }
                    }
                } else if saved.isEmpty {
                    VStack(spacing: 0) {
                        Spacer(minLength: 60)
                        HeroIcon(systemName: "text.alignleft", size: 72)
                        Text(String(localized: "No summary yet", bundle: .module)).font(MeetyFont.sectionTitle).padding(.top, 18)
                        Text(String(localized: "Pick what you need on the left and press Generate.", bundle: .module))
                            .font(.system(size: 14)).foregroundStyle(Color.meety.textSecondary).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Direita

    var savedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(String(localized: "Saved summaries", bundle: .module))
            if saved.isEmpty {
                Text(String(localized: "Nothing saved yet.", bundle: .module)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).padding(.top, 10)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(saved) { doc in
                        Button { selectedDoc = doc } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(doc.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(MeetyFormat.dayAndTime(doc.createdAt)).font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedDoc == doc ? Color.meety.accentTint : .clear, in: RoundedRectangle(cornerRadius: MeetyRadius.row, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(20)
        .onChange(of: selectedDoc) { _, d in editing = false; if let d { docText = model.library.summaryText(d, of: meeting) } }
    }

    // MARK: - Dados

    func reloadSaved() {
        saved = model.library.summaries(of: meeting)
        if selectedDoc == nil { selectedDoc = saved.first; if let d = selectedDoc { docText = model.library.summaryText(d, of: meeting) } }
    }

    func loadProviders() async {
        let list = SummaryRegistry.providers(models: model.models, settings: model.settings)
        var rows: [ProviderRow] = []
        for p in list { rows.append(ProviderRow(provider: p, availability: await p.availability())) }
        providers = rows
        if selectedProviderID.isEmpty {
            if rows.contains(where: { $0.id == model.settings.summaryProviderID }) { selectedProviderID = model.settings.summaryProviderID }
            else { selectedProviderID = rows.first(where: { !$0.provider.isCloud && $0.availability.isAvailable })?.id ?? rows.first?.id ?? "" }
        }
    }

    func generate(force: Bool) {
        guard let row = selectedRow, let transcript else { return }
        if row.provider.isCloud, !model.settings.cloudConsent, !force { showCloudConsent = true; return }
        generating = true; partial = ""; error = nil; selectedDoc = nil
        let lang = model.settings.summaryLanguage == .meeting ? (meeting.language ?? Locale.current.language.languageCode?.identifier ?? "en")
                                                             : (Locale.current.language.languageCode?.identifier ?? "en")
        let provider = row.provider, tpl = template, custom = customPrompt, m = meeting
        task = Task {
            do {
                let text = try await SummaryService.generate(provider: provider, template: tpl, custom: custom, meeting: m, transcript: transcript, languageCode: lang) { p in
                    Task { @MainActor in partial = p }
                }
                let doc = try model.library.saveSummary(text, template: tpl, provider: provider.title, for: m)
                reloadSaved()
                selectedDoc = doc; docText = text
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            generating = false
        }
    }

    func deleteDoc(_ doc: SummaryDocument) {
        try? model.library.deleteSummary(doc, of: meeting)
        selectedDoc = nil
        reloadSaved()
    }

    func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
}

/// Cartão de um provedor de resumo: ícone, nome, estado e ação quando não está pronto.
struct ProviderCard<Action: View>: View {
    let row: SummaryView.ProviderRow
    let selected: Bool
    @ViewBuilder let action: (ProviderAction) -> Action
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.meety.fill)
                    Image(systemName: row.provider.isCloud ? "cloud" : row.provider.systemIcon)
                        .font(.system(size: 15)).foregroundStyle(selected ? Color.meety.accentText : Color.meety.textSecondary)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.provider.title).font(.system(size: 14)).foregroundStyle(Color.meety.textPrimary)
                    switch row.availability {
                    case .available(let detail):
                        Text(detail ?? (row.provider.isCloud ? String(localized: "leaves your Mac", bundle: .module) : String(localized: "on this Mac", bundle: .module)))
                            .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).lineLimit(2)
                    case .unavailable(let reason, _):
                        Text(reason).font(MeetyFont.callout).foregroundStyle(Color.meety.warning).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if case .unavailable(_, let a?) = row.availability { action(a) }
            }
            .padding(10)
            .background(Color.meety.elevated, in: RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous)
                .stroke(selected ? Color.meety.accent : Color.meety.separator, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Markdown dos resumos, em blocos: títulos, parágrafos, listas (com níveis, numeradas e de
/// tarefas), citações, código, linhas e tabelas. A ênfase dentro da linha vem do AttributedString.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    init(_ text: String) { blocks = MarkdownBlock.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                view(block).padding(.top, i == 0 ? 0 : topSpacing(block, after: blocks[i - 1]))
            }
        }
        .font(.system(size: 14)).lineSpacing(4)
        .foregroundStyle(Color.meety.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func topSpacing(_ b: MarkdownBlock, after prev: MarkdownBlock) -> CGFloat {
        switch b {
        case .heading(let level, _): return level <= 2 ? 22 : 14
        case .item, .ordered: if case .item = prev { return 5 }; if case .ordered = prev { return 5 }; return 10
        default: return 10
        }
    }

    @ViewBuilder
    func view(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            switch level {
            case 1: inline(text).font(.system(size: 20, weight: .semibold))
            case 2:
                VStack(alignment: .leading, spacing: 6) {
                    inline(text).font(.system(size: 16, weight: .semibold))
                    Rectangle().fill(Color.meety.separator).frame(height: 1)
                }
            default: inline(text).font(.system(size: 14, weight: .semibold))
            }
        case .paragraph(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        case .item(let level, let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.meety.accentText : Color.meety.textSecondary)
                } else {
                    Circle().fill(level == 0 ? Color.meety.accentText : Color.meety.textTertiary)
                        .frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 4 }
                }
                inline(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4 + CGFloat(level) * 18)
        case .ordered(let level, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(number).").monospacedDigit().foregroundStyle(Color.meety.textSecondary)
                inline(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2 + CGFloat(level) * 18)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.meety.accent.opacity(0.6)).frame(width: 3)
                inline(text).foregroundStyle(Color.meety.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            Text(verbatim: text).font(.system(size: 12.5, design: .monospaced))
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.meety.fill, in: RoundedRectangle(cornerRadius: MeetyRadius.row, style: .continuous))
        case .rule:
            Rectangle().fill(Color.meety.separator).frame(height: 1).padding(.vertical, 4)
        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, c in inline(c).font(.system(size: 13, weight: .semibold)) } }
                    .padding(.vertical, 6)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().overlay(Color.meety.separator)
                    GridRow { ForEach(0..<header.count, id: \.self) { j in inline(j < row.count ? row[j] : "").font(.system(size: 13)) } }
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color.meety.fill, in: RoundedRectangle(cornerRadius: MeetyRadius.row, style: .continuous))
        }
    }

    func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(a) }
        return Text(verbatim: s)
    }
}
