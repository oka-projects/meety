import MeetyCore
import SwiftUI

/// A transcrição, em blocos por falante. Clicar numa frase pula o áudio para lá.
struct TranscriptView: View {
    let model: AppModel
    let meeting: Meeting
    let transcript: Transcript
    @Bindable var player: AudioPlayer
    @State private var renaming: String?
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
                LazyVStack(alignment: .leading, spacing: 18) {
                    if meeting.hasSpeakers { speakersLegend }
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                if meeting.hasSpeakers, let sp = block.speaker {
                                    Button { renaming = sp; newName = meeting.speakerNames[sp] ?? "" } label: {
                                        Text(meeting.displayName(for: sp)).font(.subheadline.weight(.semibold)).foregroundStyle(SpeakerColor.color(for: sp))
                                    }
                                    .buttonStyle(.plain).help(String(localized: "Rename this speaker", bundle: .module))
                                }
                                Button(TranscriptExporter.clock(block.start)) { player.seek(to: block.start, andPlay: true) }
                                    .buttonStyle(.plain).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            // Cada frase é um Text próprio para o clique levar ao momento certo.
                            FlowText(segments: block.segments, currentTime: player.currentTime) { seg in
                                player.seek(to: seg.start, andPlay: true)
                            }
                        }
                        .id(block.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .onChange(of: currentBlockID) { _, id in
                if let id, player.isPlaying { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .popover(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            renamePopover
        }
    }

    var currentBlockID: Int? {
        blocks.last { $0.start <= player.currentTime }?.id
    }

    var speakersLegend: some View {
        HStack(spacing: 10) {
            ForEach(transcript.speakerIDs, id: \.self) { sp in
                Button { renaming = sp; newName = meeting.speakerNames[sp] ?? "" } label: {
                    HStack(spacing: 5) {
                        Circle().fill(SpeakerColor.color(for: sp)).frame(width: 8, height: 8)
                        Text(meeting.displayName(for: sp)).font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    var renamePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Who is this?", bundle: .module)).font(.headline)
            TextField(renaming.map { Speaker.defaultName(for: $0) } ?? "", text: $newName)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { commitRename() }
            HStack {
                Button(String(localized: "Cancel", bundle: .module)) { renaming = nil }
                Spacer()
                Button(String(localized: "Rename", bundle: .module)) { commitRename() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
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

/// As frases de um bloco como um parágrafo só. Cada frase é um link `meety://seek?t=<s>`:
/// o texto flui e quebra como texto normal, e o clique leva ao momento certo.
struct FlowText: View {
    let segments: [TranscriptSegment]
    let currentTime: Double
    let onTap: (TranscriptSegment) -> Void

    var body: some View {
        Text(attributed)
            .font(.body)
            .lineSpacing(3)
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
            piece.foregroundColor = .primary
            if isCurrent(seg) { piece.backgroundColor = Color.accentColor.opacity(0.18) }
            out += piece
        }
        return out
    }

    func isCurrent(_ s: TranscriptSegment) -> Bool { currentTime >= s.start && currentTime < s.end }
}

enum SpeakerColor {
    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
    static func color(for id: String) -> Color {
        if id == Speaker.you { return .blue }
        let n = Int(id.dropFirst()) ?? 0
        return palette[(n) % palette.count]
    }
}
