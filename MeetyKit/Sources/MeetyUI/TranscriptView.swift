import MeetyCore
import SwiftUI

/// A transcrição, em blocos por falante. Clicar numa frase pula o áudio para lá.
struct TranscriptView: View {
    let model: AppModel
    let meeting: Meeting
    let transcript: Transcript
    @Bindable var player: AudioPlayer
    @Binding var renaming: String?
    @State private var newName = ""

    struct Block: Identifiable {
        let id: Int
        let speaker: String?
        let segments: [TranscriptSegment]
        var start: Double { segments.first?.start ?? 0 }
    }

    var blocks: [Block] {
        var out: [Block] = []
        var current: [TranscriptSegment] = []
        var speaker: String?
        for s in transcript.segments {
            if s.speaker != speaker, !current.isEmpty {
                out.append(Block(id: out.count, speaker: speaker, segments: current)); current = []
            }
            speaker = s.speaker
            current.append(s)
        }
        if !current.isEmpty { out.append(Block(id: out.count, speaker: speaker, segments: current)) }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                if meeting.hasSpeakers, let sp = block.speaker {
                                    Button { renaming = sp } label: {
                                        Text(meeting.displayName(for: sp)).font(MeetyFont.headline).foregroundStyle(Color.meety.speaker(id: sp))
                                    }
                                    .buttonStyle(.plain).help(String(localized: "Rename this speaker", bundle: .module))
                                }
                                Button(TranscriptExporter.clock(block.start)) { player.seek(to: block.start, andPlay: true) }
                                    .buttonStyle(.plain).font(MeetyFont.timeInline).foregroundStyle(Color.meety.textSecondary)
                            }
                            FlowText(segments: block.segments, currentTime: player.currentTime) { seg in
                                player.seek(to: seg.start, andPlay: true)
                            }
                        }
                        .id(block.id)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .onChange(of: currentBlockID) { _, id in
                if let id, player.isPlaying { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .popover(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), arrowEdge: .top) {
            renamePopover
        }
        .onChange(of: renaming) { _, sp in if let sp { newName = meeting.speakerNames[sp] ?? "" } }
    }

    var currentBlockID: Int? {
        blocks.last { $0.start <= player.currentTime }?.id
    }

    var renamePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(renaming.map { Color.meety.speaker(id: $0) } ?? .clear).frame(width: 9, height: 9)
                Text(String(localized: "Who is this?", bundle: .module)).font(MeetyFont.headline)
            }
            TextField(renaming.map { Speaker.defaultName(for: $0) } ?? "", text: $newName)
                .textFieldStyle(.roundedBorder).frame(width: 260)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { renaming = nil }
                Button(String(localized: "Rename", bundle: .module)) { commitRename() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    func commitRename() {
        guard let sp = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        model.library.update(meeting.id) { m in
            if name.isEmpty { m.speakerNames.removeValue(forKey: sp) } else { m.speakerNames[sp] = name }
        }
        renaming = nil
    }
}

/// Os chips dos falantes (bolinha colorida + nome). Clicar abre o renomear.
struct SpeakerChips: View {
    let meeting: Meeting
    let speakerIDs: [String]
    @Binding var renaming: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(speakerIDs, id: \.self) { sp in
                Button { renaming = sp } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.meety.speaker(id: sp)).frame(width: 8, height: 8)
                        Text(meeting.displayName(for: sp)).font(MeetyFont.body).foregroundStyle(Color.meety.textPrimary)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Color.meety.control, in: Capsule())
                    .overlay(Capsule().stroke(Color.meety.controlBorder))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Rename this speaker", bundle: .module))
            }
        }
    }
}

/// As frases de um bloco como um parágrafo só. Cada frase é um link `meety://seek?t=<s>`:
/// o texto flui e quebra como texto normal, e o clique leva ao momento certo.
struct FlowText: View {
    let segments: [TranscriptSegment]
    let currentTime: Double
    let onTap: (TranscriptSegment) -> Void

    var body: some View {
        Text(attributed)
            .font(MeetyFont.transcript)
            .lineSpacing(5)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "meety", let t = Double(url.query()?.replacingOccurrences(of: "t=", with: "") ?? "") else { return .systemAction }
                if let seg = segments.first(where: { abs($0.start - t) < 0.001 }) { onTap(seg) }
                return .handled
            })
    }

    var attributed: AttributedString {
        var out = AttributedString()
        for seg in segments {
            var piece = AttributedString(seg.text + " ")
            piece.link = URL(string: "meety://seek?t=\(seg.start)")
            piece.foregroundColor = Color.meety.textPrimary
            if isCurrent(seg) { piece.backgroundColor = Color.meety.accentTint }
            out += piece
        }
        return out
    }

    func isCurrent(_ s: TranscriptSegment) -> Bool { currentTime >= s.start && currentTime < s.end }
}
