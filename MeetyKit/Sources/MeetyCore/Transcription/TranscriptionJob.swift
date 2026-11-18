import Foundation
import Observation

/// Idioma pedido ao Whisper. Forçar o idioma errado faz o modelo traduzir: o padrão é detectar.
public enum TranscriptionLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto, pt, en, es, fr, de, it, ja, zh, ko
    public var id: String { rawValue }
    public var code: String? { self == .auto ? nil : rawValue }
    public var title: String {
        if self == .auto { return String(localized: "Detect automatically", bundle: .module) }
        return Locale.current.localizedString(forLanguageCode: rawValue)?.capitalized ?? rawValue
    }
}

public struct TranscriptionOptions: Sendable {
    /// Modelo principal: o id de um modelo local ou `Groq.backendID`.
    public var modelID: String
    /// Modelo secundário, que assume quando o principal falha; nil = sem reserva.
    public var fallbackID: String?
    public var language: TranscriptionLanguage
    public var separateSpeakers: Bool
    public var expectedSpeakers: Int?
    public init(modelID: String, fallbackID: String? = nil, language: TranscriptionLanguage = .auto, separateSpeakers: Bool = true, expectedSpeakers: Int? = nil) {
        self.modelID = modelID; self.fallbackID = fallbackID
        self.language = language; self.separateSpeakers = separateSpeakers; self.expectedSpeakers = expectedSpeakers
    }

    /// O principal e, se houver e for outro, o secundário, na ordem em que são tentados.
    public var candidates: [String] {
        var out: [String] = []
        for id in [modelID, fallbackID ?? ""] where !id.isEmpty && !out.contains(id) { out.append(id) }
        return out
    }
}

/// Uma transcrição em andamento, com progresso para a tela.
@MainActor
@Observable
public final class TranscriptionJob: Identifiable {
    public enum Stage: Equatable, Sendable {
        case queued, preparing, loadingModel, transcribing, speakers, saving, done, failed(String), cancelled
        public var title: String {
            switch self {
            case .queued: return String(localized: "Waiting…", bundle: .module)
            case .preparing: return String(localized: "Preparing audio…", bundle: .module)
            case .loadingModel: return String(localized: "Loading model…", bundle: .module)
            case .transcribing: return String(localized: "Transcribing…", bundle: .module)
            case .speakers: return String(localized: "Telling speakers apart…", bundle: .module)
            case .saving: return String(localized: "Saving…", bundle: .module)
            case .done: return String(localized: "Done", bundle: .module)
            case .failed: return String(localized: "Failed", bundle: .module)
            case .cancelled: return String(localized: "Cancelled", bundle: .module)
            }
        }
        public var isFinished: Bool {
            switch self { case .done, .failed, .cancelled: return true; default: return false }
        }
    }

    public let id = UUID()
    public let meetingID: String
    public private(set) var stage: Stage = .queued
    /// 0...1 do passo de transcrição; nil quando não se sabe.
    public private(set) var progress: Double?
    public private(set) var estimatedRemaining: TimeInterval?
    /// Quem está transcrevendo agora: o id de um modelo local ou `Groq.backendID`.
    public private(set) var backend: String?
    /// Por que o principal falhou, quando o secundário assumiu.
    public private(set) var fallbackReason: String?
    @ObservationIgnored private var startedTranscribing: Date?
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var engine: EngineRunner?

    init(meetingID: String) { self.meetingID = meetingID }

    public func cancel() {
        engine?.cancel()
        task?.cancel()
    }

    func set(stage: Stage) { self.stage = stage; MeetyLog.transcription.info("\(self.meetingID): \(String(describing: stage))") }
    func set(backend: String) {
        self.backend = backend
        progress = nil; estimatedRemaining = nil; startedTranscribing = nil
    }
    func set(fallbackReason: String) { self.fallbackReason = fallbackReason }
    func set(progress p: Double) {
        progress = p
        if startedTranscribing == nil { startedTranscribing = Date() }
        if let start = startedTranscribing, p > 0.05 {
            let elapsed = Date().timeIntervalSince(start)
            estimatedRemaining = elapsed / p * (1 - p)
        }
    }
}

/// Fila de transcrições: uma por vez (a GPU é uma só), as outras esperam.
@MainActor
@Observable
public final class TranscriptionQueue {
    public private(set) var jobs: [TranscriptionJob] = []
    private let library: MeetingLibrary
    private let models: ModelManager
    private let engineFactory: () -> EngineRunner?
    private let groq: GroqClient
    @ObservationIgnored private var running = false

    public init(library: MeetingLibrary, models: ModelManager, engineFactory: @escaping () -> EngineRunner? = { EngineRunner.bundled() },
                groq: GroqClient = .live) {
        self.library = library; self.models = models; self.engineFactory = engineFactory; self.groq = groq
    }

    /// Dá para transcrever com esta opção agora: a Groq com chave salva, ou um modelo local baixado.
    public func isUsable(_ id: String) -> Bool {
        if id == Groq.backendID { return groq.key() != nil }
        guard let model = models.catalog.model(id: id) else { return false }
        return models.isInstalled(model)
    }

    public func job(for meetingID: String) -> TranscriptionJob? {
        jobs.last { $0.meetingID == meetingID && !$0.stage.isFinished }
    }

    public var isBusy: Bool { jobs.contains { !$0.stage.isFinished } }

    /// Coloca a reunião na fila. O áudio tem de estar em `audio.m4a` (importado ou mixado).
    @discardableResult
    public func enqueue(_ meeting: Meeting, options: TranscriptionOptions) -> TranscriptionJob {
        let job = TranscriptionJob(meetingID: meeting.id)
        jobs.append(job)
        library.update(meeting.id) { $0.status = .transcribing; $0.error = nil }
        job.task = Task { [weak self] in
            guard let self else { return }
            while self.running { try? await Task.sleep(for: .milliseconds(300)); if Task.isCancelled { break } }
            if Task.isCancelled { job.set(stage: .cancelled); self.library.update(meeting.id) { $0.status = .recorded }; return }
            self.running = true
            defer { self.running = false }
            await self.run(job, meeting: meeting, options: options)
        }
        return job
    }

    public func clearFinished() { jobs.removeAll { $0.stage.isFinished } }

    private func run(_ job: TranscriptionJob, meeting: Meeting, options: TranscriptionOptions) async {
        let folder = library.folder(for: meeting)
        do {
            // 1. Áudio em PCM 16 kHz. Nas gravações, as duas trilhas separadas também.
            job.set(stage: .preparing)
            let mixed = try await AudioPrep.samples(from: folder.audio)
            var micSamples: [Float]? = nil, systemSamples: [Float]? = nil
            if folder.hasTracks {
                micSamples = try? await AudioPrep.samples(from: folder.micTrack)
                systemSamples = try? await AudioPrep.samples(from: folder.systemTrack)
            }
            try Task.checkCancellation()

            // 2. Whisper: no modelo principal e, se ele falhar, no secundário.
            let candidates = options.candidates
            var result: (language: String?, segments: [TranscriptSegment], modelID: String)?
            var lastError: Error = TranscriptionError.modelNotInstalled
            for (i, id) in candidates.enumerated() {
                do {
                    job.set(backend: id)
                    result = id == Groq.backendID
                        ? try await transcribeOnGroq(job, samples: mixed, options: options)
                        : try await transcribeLocally(job, meetingID: meeting.id, samples: mixed, modelID: id, options: options)
                    break
                } catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    if case EngineError.cancelled = error { throw error }
                    lastError = error
                    guard i + 1 < candidates.count else { break }
                    MeetyLog.transcription.info("\(meeting.id): \(id) failed, trying \(candidates[i + 1]): \(error.localizedDescription)")
                    job.set(fallbackReason: error.localizedDescription)
                }
            }
            guard let result else { throw lastError }
            var segments = result.segments
            let language = result.language
            try Task.checkCancellation()

            // 3. Quem falou.
            var hasSpeakers = false
            if options.separateSpeakers, !segments.isEmpty {
                job.set(stage: .speakers)
                if let mic = micSamples, let sys = systemSamples {
                    segments = SpeakerAttribution.youVersusOthers(segments: segments, mic: mic, system: sys)
                    hasSpeakers = true
                    if Diarizer.isInstalled {
                        // Só a trilha do sistema vai ao diarizador: a sua voz já está fora dela.
                        if let spans = try? await Diarizer.shared.diarize(sys, expectedSpeakers: options.expectedSpeakers) {
                            segments = SpeakerAttribution.assign(spans: spans, to: segments, keepYou: true, prefix: Speaker.participant)
                        }
                    }
                } else if Diarizer.isInstalled {
                    if let spans = try? await Diarizer.shared.diarize(mixed, expectedSpeakers: options.expectedSpeakers) {
                        segments = SpeakerAttribution.assign(spans: spans, to: segments, keepYou: false, prefix: Speaker.speaker)
                        hasSpeakers = true
                    }
                }
                segments = SpeakerAttribution.fillGaps(segments)
            }

            // 4. Salvar.
            job.set(stage: .saving)
            let transcript = Transcript(language: language, segments: segments, model: result.modelID)
            try library.save(transcript: transcript, for: meeting)
            let duration = Double(mixed.count) / AudioPrep.sampleRate
            library.update(meeting.id) {
                $0.status = .transcribed; $0.language = language; $0.modelID = result.modelID
                $0.duration = duration; $0.hasSpeakers = hasSpeakers; $0.error = nil
            }
            job.set(stage: .done)
        } catch is CancellationError {
            job.set(stage: .cancelled)
            library.update(meeting.id) { $0.status = .recorded }
        } catch EngineError.cancelled {
            job.set(stage: .cancelled)
            library.update(meeting.id) { $0.status = .recorded }
        } catch {
            job.set(stage: .failed(error.localizedDescription))
            library.update(meeting.id) { $0.status = .failed; $0.error = error.localizedDescription }
        }
    }

    /// Whisper no motor embutido, com um modelo baixado.
    private func transcribeLocally(_ job: TranscriptionJob, meetingID: String, samples: [Float], modelID: String,
                                   options: TranscriptionOptions) async throws -> (language: String?, segments: [TranscriptSegment], modelID: String) {
        guard let model = models.catalog.model(id: modelID), models.isInstalled(model) else { throw TranscriptionError.modelNotInstalled }
        guard let engine = engineFactory() else { throw EngineError.notBundled }
        job.engine = engine
        defer { job.engine = nil }
        let pcm = AppPaths.temporary.appendingPathComponent("\(meetingID).f32")
        try AudioPrep.write(samples, to: pcm)
        defer { try? FileManager.default.removeItem(at: pcm) }

        job.set(stage: .loadingModel)
        var args = ["--audio", pcm.path, "--model", model.folder.path]
        if let code = options.language.code { args += ["--language", code] }
        var segments: [TranscriptSegment] = []
        var language: String?
        for try await ev in engine.run("transcribe", args: args) {
            switch ev {
            case .stage(let s): if s == "transcribing" { job.set(stage: .transcribing) }
            case .progress(let p, _): job.set(progress: p / 100)
            case .transcript(let lang, let segs, _):
                language = lang
                segments = segs.enumerated().map { i, s in TranscriptSegment(id: i, start: s.start, end: s.end, text: s.text) }
            default: break
            }
        }
        return (language, segments, model.id)
    }

    /// Whisper na Groq: o áudio sai do Mac, em partes.
    private func transcribeOnGroq(_ job: TranscriptionJob, samples: [Float],
                                  options: TranscriptionOptions) async throws -> (language: String?, segments: [TranscriptSegment], modelID: String) {
        guard let key = groq.key() else { throw GroqError.noKey }
        job.set(stage: .transcribing)
        job.set(progress: 0)
        let detailed = try await groq.transcribe(samples, options.language.code, key) { p in
            Task { @MainActor in job.set(progress: p) }
        }
        let segments = detailed.segments.enumerated().map { i, s in TranscriptSegment(id: i, start: s.start, end: s.end, text: s.text) }
        return (detailed.language, segments, Groq.transcriptModelID)
    }
}

public enum TranscriptionError: LocalizedError {
    case modelNotInstalled
    case nothingUsable
    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled: return String(localized: "The transcription model isn't downloaded yet. Open Settings > Models to download it.", bundle: .module)
        case .nothingUsable: return String(localized: "Neither transcription option is ready. Open Settings > Models to add a Groq key or download a model.", bundle: .module)
        }
    }
}
