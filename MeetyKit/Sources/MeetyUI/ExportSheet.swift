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
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Export transcript", bundle: .module)).font(.title2.weight(.semibold))
            Picker(String(localized: "Format", bundle: .module), selection: $format) {
                ForEach(ExportFormat.allCases) { f in Text(f.title).tag(f) }
            }
            .pickerStyle(.radioGroup)
            ScrollView {
                Text(rendered.prefix(3000) + (rendered.count > 3000 ? "\n…" : "")).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .frame(height: 180).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy", bundle: .module)) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(rendered, forType: .string)
                    copied = true
                }
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Save…", bundle: .module)) { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
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
