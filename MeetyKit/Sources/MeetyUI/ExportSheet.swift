import MeetyCore
import SwiftUI
import UniformTypeIdentifiers

/// Exportar a transcrição: escolhe o formato, copia ou salva.
struct ExportSheet: View {
    let meeting: Meeting
    let transcript: Transcript
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .markdown
    @State private var copied = false

    var rendered: String { TranscriptExporter.render(transcript, meeting: meeting, format: format) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Export transcript", bundle: .module)).font(MeetyFont.sheetTitle)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Color.meety.textSecondary).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                ForEach(ExportFormat.allCases) { f in
                    Button { format = f } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(format == f ? Color.meety.accent : Color.meety.controlBorder, lineWidth: format == f ? 6 : 1).frame(width: 15, height: 15)
                                Circle().fill(Color.meety.control).frame(width: 15, height: 15).opacity(format == f ? 0 : 1)
                            }
                            Text(f.title).font(.system(size: 14))
                            Text(verbatim: ".\(f.fileExtension)").font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
            ScrollView {
                Text(rendered.prefix(3000) + (rendered.count > 3000 ? "\n…" : ""))
                    .font(.system(size: 12, design: .monospaced)).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .textSelection(.enabled)
            }
            .frame(height: 260)
            .background(Color.meety.control, in: RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous).stroke(Color.meety.separator))
            .padding(.top, 18)
            HStack {
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(rendered, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy", bundle: .module), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Save…", bundle: .module)) { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 18)
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.meety.window)
    }

    var subtitle: String {
        var s = meeting.title
        if let d = meeting.duration { s += " · " + MeetyFormat.duration(d) }
        return s
    }

    func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(meeting.title).\(format.fileExtension)"
        if let t = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? rendered.write(to: url, atomically: true, encoding: .utf8)
        dismiss()
    }
}
