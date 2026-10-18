import Foundation
@testable import MeetyCore
import Testing

@Suite struct LibraryNaming {
    @Test func slugRemovesAccentsAndSymbols() {
        #expect(MeetingLibrary.slug("Reunião: Orçamento 2026 / Fábio") == "reuniao-orcamento-2026-fabio")
        #expect(MeetingLibrary.slug("   ") == "")
        #expect(MeetingLibrary.slug(String(repeating: "a", count: 100)).count == 40)
    }

    @Test func folderNameHasDateAndSlug() {
        let d = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "America/Manaus"), year: 2026, month: 10, day: 17, hour: 9, minute: 5, second: 7))!
        let name = MeetingLibrary.folderName(date: d, title: "Kickoff")
        #expect(name.hasSuffix("-kickoff"))
        #expect(name.hasPrefix("2026-10-17-"))
    }
}

@Suite struct EngineEvents {
    @Test func parsesProgressAndResult() {
        let p = EngineEvent.parse(#"{"event":"progress","percent":42.5,"seconds":10.2}"#)
        #expect(p == .progress(percent: 42.5, seconds: 10.2))
        let r = EngineEvent.parse(#"{"event":"result","language":"pt","elapsed":3.2,"segments":[{"start":0,"end":1.5,"text":"Olá"}]}"#)
        guard case .transcript(let lang, let segs, _)? = r else { Issue.record("not a transcript"); return }
        #expect(lang == "pt")
        #expect(segs.count == 1 && segs[0].text == "Olá")
        #expect(EngineEvent.parse("not json") == nil)
        #expect(EngineEvent.parse(#"{"event":"error","message":"boom"}"#) == .error("boom"))
    }

    @Test func lineBufferSplitsChunks() {
        let b = LineBuffer()
        #expect(b.append(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
        #expect(b.append(Data(":2}\n".utf8)) == ["{\"b\":2}"])
        #expect(b.flush().isEmpty)
    }
}

@Suite struct Attribution {
    func tone(seconds: Double, amplitude: Float, at offset: Double, total: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(total * 16000))
        let a = Int(offset * 16000), b = min(out.count, Int((offset + seconds) * 16000))
        for i in a..<b { out[i] = amplitude * sin(Float(i) * 0.05) }
        return out
    }

    @Test func micWinsWhenLouder() {
        // "Você" fala de 0 a 2 s; os outros de 2 a 4 s.
        let mic = tone(seconds: 2, amplitude: 0.5, at: 0, total: 4)
        let sys = tone(seconds: 2, amplitude: 0.5, at: 2, total: 4)
        let segs = [TranscriptSegment(id: 0, start: 0.2, end: 1.8, text: "a"), TranscriptSegment(id: 1, start: 2.2, end: 3.8, text: "b")]
        let out = SpeakerAttribution.youVersusOthers(segments: segs, mic: mic, system: sys)
        #expect(out[0].speaker == Speaker.you)
        #expect(out[1].speaker == Speaker.participant(1))
    }

    @Test func assignsDiarizedSpansKeepingYou() {
        let segs = [TranscriptSegment(id: 0, start: 0, end: 1, text: "a", speaker: Speaker.you),
                    TranscriptSegment(id: 1, start: 1, end: 2, text: "b", speaker: Speaker.participant(1)),
                    TranscriptSegment(id: 2, start: 2, end: 3, text: "c", speaker: Speaker.participant(1))]
        let spans = [SpeakerAttribution.LabeledSpan(start: 1, end: 2, label: "SPK_B"), SpeakerAttribution.LabeledSpan(start: 2, end: 3, label: "SPK_A")]
        let out = SpeakerAttribution.assign(spans: spans, to: segs, keepYou: true, prefix: Speaker.participant)
        #expect(out[0].speaker == Speaker.you)
        #expect(out[1].speaker == "p1")
        #expect(out[2].speaker == "p2")
    }
}

@Suite struct Exporting {
    let meeting = Meeting(id: "x", title: "Teste", createdAt: Date(timeIntervalSince1970: 0), duration: 61, source: .imported, speakerNames: ["you": "Akira"], hasSpeakers: true)
    let transcript = Transcript(language: "pt", segments: [
        TranscriptSegment(id: 0, start: 0, end: 1.5, text: "Olá.", speaker: "you"),
        TranscriptSegment(id: 1, start: 1.5, end: 3, text: "Tudo bem?", speaker: "you"),
        TranscriptSegment(id: 2, start: 3, end: 5.25, text: "Tudo.", speaker: "p1"),
    ])

    @Test func srtTimestamps() {
        let srt = TranscriptExporter.render(transcript, meeting: meeting, format: .srt)
        #expect(srt.contains("00:00:03,000 --> 00:00:05,250"))
        #expect(srt.contains("Participant 1: Tudo."))
    }

    @Test func plainGroupsBySpeaker() {
        let txt = TranscriptExporter.render(transcript, meeting: meeting, format: .txt)
        #expect(txt == "Akira: Olá. Tudo bem?\n\nParticipant 1: Tudo.")
    }

    @Test func clock() {
        #expect(TranscriptExporter.clock(61) == "01:01")
        #expect(TranscriptExporter.clock(3661) == "1:01:01")
    }
}

@Suite struct Summaries {
    @Test func splitsLongText() {
        let para = String(repeating: "palavra ", count: 500)   // ~4000 chars ≈ 1000 tokens
        let text = Array(repeating: para, count: 5).joined(separator: "\n\n")
        let parts = SummaryService.split(text, maxTokens: 1500)
        #expect(parts.count >= 3)
        #expect(parts.allSatisfy { $0.utf8.count <= 1500 * 4 + 10 })
    }

    @Test func stripsThinking() {
        #expect(LocalMLXSummarizer.stripThinking("<think>hmm</think>\n\nResumo.") == "Resumo.")
        #expect(LocalMLXSummarizer.stripThinking("Resumo.") == "Resumo.")
    }

    @Test func recommendedFitsMemory() {
        let c = ModelCatalog.bundled()
        let small = c.recommended(memoryGB: 8)
        #expect(small.contains { $0.id == "whisper-large-v3-turbo" })
        #expect(small.contains { $0.id == "qwen3-4b" })
        let big = c.recommended(memoryGB: 32)
        #expect(big.contains { $0.id == "qwen3-8b" })
    }
}
