import Foundation
@testable import MeetyCore
import Testing

/// Guarda o que os envios de mentira receberam (o envio roda fora da thread do teste).
private final class Recorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

/// Tom de 220 Hz a 16 kHz, com silêncio total nos intervalos pedidos (em segundos).
private func tone(seconds: Double, silence: [ClosedRange<Double>] = []) -> [Float] {
    let rate = AudioPrep.sampleRate
    return (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        return silence.contains { $0.contains(t) } ? 0 : Float(sin(2 * .pi * 220 * t)) * 0.4
    }
}

@Suite struct GroqResponses {
    @Test func parsesSegmentsAndLanguageName() {
        let json: [String: Any] = [
            "language": "Portuguese", "duration": 12.5,
            "segments": [
                ["id": 0, "start": 0, "end": 2.5, "text": " Bom dia a todos."],
                ["id": 1, "start": 2.5, "end": 2.5, "text": "   "],
                ["id": 2, "start": 3, "end": 7.25, "text": " Vamos começar."],
            ],
        ]
        let d = Groq.parseDetailed(json, requestedLanguage: nil)
        #expect(d.language == "pt")
        #expect(d.segments == [Groq.Segment(start: 0, end: 2.5, text: "Bom dia a todos."), Groq.Segment(start: 3, end: 7.25, text: "Vamos começar.")])
    }

    @Test func requestedLanguageWinsAndUnknownNamesAreDropped() {
        #expect(Groq.parseDetailed(["language": "english", "segments": []], requestedLanguage: "pt").language == "pt")
        #expect(Groq.languageCode("english") == "en")
        #expect(Groq.languageCode("Spanish") == "es")
        #expect(Groq.languageCode("pt") == "pt")
        #expect(Groq.languageCode("Some Unknown Language") == nil)
        #expect(Groq.languageCode(nil) == nil)
    }
}

@Suite struct GroqChunks {
    @Test func shortAudioIsOnePart() {
        let samples = [Float](repeating: 0.1, count: 16_000 * 60)
        #expect(GroqTranscription.chunkRanges(samples) == [0..<samples.count])
        #expect(GroqTranscription.chunkRanges([]).isEmpty)
    }

    @Test func cutsAtTheQuietestPointBeforeTheLimit() {
        // 100 s de tom, com silêncio entre 33 e 34 s. Partes de 40 s: o primeiro corte cai no silêncio.
        let samples = tone(seconds: 100, silence: [33...34])
        let ranges = GroqTranscription.chunkRanges(samples, chunkSeconds: 40, searchSeconds: 10, minimumTailSeconds: 5)
        #expect(ranges.count == 3)
        #expect(ranges.first?.lowerBound == 0 && ranges.last?.upperBound == samples.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        let firstCut = Double(ranges[0].upperBound) / AudioPrep.sampleRate
        #expect(firstCut > 33 && firstCut < 34)
        #expect(ranges.allSatisfy { Double($0.count) / AudioPrep.sampleRate <= 45 })
    }

    @Test func shortTailStaysWithTheLastPart() {
        // 43 s com partes de 40 s e resto mínimo de 5 s: não vale um envio só para 3 s.
        let ranges = GroqTranscription.chunkRanges(tone(seconds: 43), chunkSeconds: 40, searchSeconds: 10, minimumTailSeconds: 5)
        #expect(ranges.count == 1)
    }
}

@Suite struct GroqMeetings {
    @Test func encodesAPartThatDecodesBack() async throws {
        let data = try GroqTranscription.encodeM4A(tone(seconds: 5)[...])
        #expect(data.count > 1_000 && data.count < 200_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meety-groq-\(UUID().uuidString).m4a")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let back = try await AudioPrep.samples(from: url)
        #expect(abs(Double(back.count) / AudioPrep.sampleRate - 5) < 0.3)
    }

    @Test func addsEachPartsOffsetAndReportsProgress() async throws {
        // 26 min: três partes (10 + 10 + 6). Cada envio devolve um trecho de 1 a 3 s.
        let samples = [Float](repeating: 0, count: Int(AudioPrep.sampleRate) * 60 * 26)
        let languages = Recorder<String?>(), progress = Recorder<Double>()
        let result = try await GroqTranscription.transcribe(samples: samples, language: nil, key: "k", upload: { audio, language, key in
            #expect(!audio.isEmpty && key == "k")
            languages.add(language)
            return Groq.Detailed(language: "pt", segments: [Groq.Segment(start: 1, end: 3, text: "parte")])
        }, progress: { progress.add($0) })
        #expect(result.language == "pt")
        // Cada corte cai a 0,1 s do alvo de 10 min (o centro da janela de silêncio), e a diferença se acumula.
        #expect(result.segments.count == 3)
        for (segment, expected) in zip(result.segments, [1.0, 601, 1201]) {
            #expect(abs(segment.start - expected) < 0.5 && abs(segment.end - segment.start - 2) < 0.001)
        }
        // O idioma detectado na primeira parte é pedido nas seguintes.
        #expect(languages.all == [nil, "pt", "pt"])
        #expect(progress.all.count == 3 && progress.all.last == 1)
    }

    @Test func retriesOnceOnATransientFailure() async throws {
        let calls = Recorder<Int>()
        let result = try await GroqTranscription.transcribe(samples: tone(seconds: 2), language: "pt", key: "k", upload: { _, _, _ in
            calls.add(1)
            if calls.all.count == 1 { throw GroqError.http(503, "busy") }
            return Groq.Detailed(language: "pt", segments: [])
        })
        #expect(calls.all.count == 2 && result.segments.isEmpty)
    }

    @Test func doesNotRetryARefusedKeyOrTheUsageLimit() async {
        for status in [401, 429] {
            let calls = Recorder<Int>()
            await #expect(throws: GroqError.http(status, "no")) {
                try await GroqTranscription.transcribe(samples: tone(seconds: 2), language: nil, key: "k", upload: { _, _, _ in
                    calls.add(1)
                    throw GroqError.http(status, "no")
                })
            }
            #expect(calls.all.count == 1)
        }
    }
}

@Suite struct PrimaryAndBackup {
    @Test func candidatesKeepOrderAndSkipRepeats() {
        #expect(TranscriptionOptions(modelID: "groq", fallbackID: "whisper-small").candidates == ["groq", "whisper-small"])
        #expect(TranscriptionOptions(modelID: "whisper-small", fallbackID: nil).candidates == ["whisper-small"])
        #expect(TranscriptionOptions(modelID: "groq", fallbackID: "groq").candidates == ["groq"])
        #expect(TranscriptionOptions(modelID: "groq", fallbackID: "").candidates == ["groq"])
    }

    /// Biblioteca numa pasta temporária, com uma reunião de 3 s de áudio.
    @MainActor private func makeMeeting() throws -> (MeetingLibrary, Meeting, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meety-queue-\(UUID().uuidString)")
        let library = MeetingLibrary(root: root)
        let meeting = try library.create(title: "Teste", source: .imported)
        try GroqTranscription.encodeM4A(tone(seconds: 3)[...]).write(to: library.folder(for: meeting).audio)
        return (library, meeting, root)
    }

    @MainActor private func wait(for job: TranscriptionJob) async {
        for _ in 0..<200 where !job.stage.isFinished { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @MainActor @Test func groqAsPrimaryTranscribesWithoutTheLocalEngine() async throws {
        let (library, meeting, root) = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: root) }
        let groq = GroqClient(key: { "k" }) { samples, language, _, progress in
            #expect(abs(Double(samples.count) / AudioPrep.sampleRate - 3) < 0.3 && language == "pt")
            progress(1)
            return Groq.Detailed(language: "pt", segments: [Groq.Segment(start: 0, end: 2, text: "Olá")])
        }
        let queue = TranscriptionQueue(library: library, models: ModelManager(), engineFactory: { nil }, groq: groq)
        #expect(queue.isUsable(Groq.backendID))
        let job = queue.enqueue(meeting, options: TranscriptionOptions(modelID: Groq.backendID, language: .pt, separateSpeakers: false))
        await wait(for: job)
        #expect(job.stage == .done && job.backend == Groq.backendID && job.fallbackReason == nil)
        let saved = try #require(library.meetings.first { $0.id == meeting.id })
        #expect(saved.status == .transcribed && saved.modelID == Groq.transcriptModelID && saved.language == "pt")
        #expect(library.transcript(of: saved)?.segments.map(\.text) == ["Olá"])
    }

    @MainActor @Test func backupTakesOverWhenThePrimaryFails() async throws {
        let (library, meeting, root) = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: root) }
        let groq = GroqClient(key: { "k" }) { _, _, _, _ in Groq.Detailed(language: "en", segments: [Groq.Segment(start: 0, end: 1, text: "Hi")]) }
        let queue = TranscriptionQueue(library: library, models: ModelManager(), engineFactory: { nil }, groq: groq)
        // O principal é um modelo local que não está baixado: falha, e a Groq (secundário) assume.
        let options = TranscriptionOptions(modelID: "modelo-que-nao-existe", fallbackID: Groq.backendID, separateSpeakers: false)
        let job = queue.enqueue(meeting, options: options)
        await wait(for: job)
        #expect(job.stage == .done && job.backend == Groq.backendID)
        #expect(job.fallbackReason == TranscriptionError.modelNotInstalled.localizedDescription)
        #expect(library.meetings.first { $0.id == meeting.id }?.modelID == Groq.transcriptModelID)
    }

    @MainActor @Test func failsWithTheLastErrorWhenBothFail() async throws {
        let (library, meeting, root) = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: root) }
        let groq = GroqClient(key: { "k" }) { _, _, _, _ in throw GroqError.http(429, "limit") }
        let queue = TranscriptionQueue(library: library, models: ModelManager(), engineFactory: { nil }, groq: groq)
        let job = queue.enqueue(meeting, options: TranscriptionOptions(modelID: Groq.backendID, fallbackID: "modelo-que-nao-existe", separateSpeakers: false))
        await wait(for: job)
        #expect(job.stage == .failed(TranscriptionError.modelNotInstalled.localizedDescription))
        #expect(job.fallbackReason == GroqError.http(429, "limit").localizedDescription)
        #expect(library.meetings.first { $0.id == meeting.id }?.status == .failed)
    }

    @MainActor @Test func groqWithoutAKeyIsNotUsable() async throws {
        let (library, meeting, root) = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: root) }
        let groq = GroqClient(key: { nil }) { _, _, _, _ in Issue.record("não devia enviar sem chave"); return Groq.Detailed(language: nil, segments: []) }
        let queue = TranscriptionQueue(library: library, models: ModelManager(), engineFactory: { nil }, groq: groq)
        #expect(!queue.isUsable(Groq.backendID) && !queue.isUsable("modelo-que-nao-existe"))
        let job = queue.enqueue(meeting, options: TranscriptionOptions(modelID: Groq.backendID, separateSpeakers: false))
        await wait(for: job)
        #expect(job.stage == .failed(GroqError.noKey.localizedDescription))
    }
}

@Suite struct OpusImport {
    /// `amostra.opus` é uma fala sintética de 7,5 s em Ogg Opus, o formato do áudio do WhatsApp.
    @Test func convertsOggOpusToM4A() async throws {
        let source = try #require(Bundle.module.url(forResource: "amostra", withExtension: "opus", subdirectory: "Fixtures"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("meety-opus-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: output) }
        try await AudioPrep.convertToM4A(from: source, to: output)
        let samples = try await AudioPrep.samples(from: output)
        #expect(abs(Double(samples.count) / AudioPrep.sampleRate - 7.46) < 0.3)
        #expect(samples.contains { abs($0) > 0.01 })
    }

    @Test func oggAndOpusAreImportableNow() {
        for ext in ["opus", "ogg"] {
            #expect(AudioPrep.supportedExtensions.contains(ext) && AudioPrep.needsConversion.contains(ext))
            #expect(!AudioPrep.unsupportedByAVFoundation.contains(ext))
        }
    }

    @Test func aFileThatIsNotAudioIsRefused() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("meety-fake-\(UUID().uuidString).opus")
        try Data("isto não é áudio".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = source.deletingPathExtension().appendingPathExtension("m4a")
        await #expect(throws: AudioPrep.PrepError.self) { try await AudioPrep.convertToM4A(from: source, to: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

/// Chamada de verdade à Groq com a amostra em Opus. Só roda com rede e chave informadas:
///   MEETY_NETWORK=1 MEETY_GROQ_KEY=gsk_... swift test --filter GroqLive
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEETY_NETWORK"] == "1" && ProcessInfo.processInfo.environment["MEETY_GROQ_KEY"] != nil))
struct GroqLive {
    @Test func transcribesTheOpusSampleWithTimestamps() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["MEETY_GROQ_KEY"])
        let source = try #require(Bundle.module.url(forResource: "amostra", withExtension: "opus", subdirectory: "Fixtures"))
        let m4a = FileManager.default.temporaryDirectory.appendingPathComponent("meety-live-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: m4a) }
        try await AudioPrep.convertToM4A(from: source, to: m4a)
        let samples = try await AudioPrep.samples(from: m4a)
        let result = try await GroqTranscription.transcribe(samples: samples, language: nil, key: key)
        #expect(result.language == "pt")
        #expect(!result.segments.isEmpty)
        #expect(result.segments.allSatisfy { $0.start >= 0 && $0.end <= 8 && $0.end >= $0.start })
        let text = result.segments.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("reunião") && text.contains("dezembro"))
    }
}
