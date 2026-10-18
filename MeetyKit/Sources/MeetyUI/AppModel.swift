import AppKit
import Foundation
import MeetyCore
import Observation
import SwiftUI

/// O estado do app inteiro, compartilhado pelas janelas e pela barra de menus.
@MainActor
@Observable
public final class AppModel {
    public let library: MeetingLibrary
    public let models: ModelManager
    public let queue: TranscriptionQueue
    public let recorder = Recorder()
    public let settings = MeetySettings.shared

    public var selectedMeetingID: String?
    public var searchText = ""
    /// Reunião em gravação (pasta já criada).
    public var recordingMeetingID: String?
    public var showWelcome = false
    public var alert: AlertMessage?
    public var engineHealth: EngineEvent.EngineHealth?
    public var engineMissing = false

    public struct AlertMessage: Identifiable, Equatable {
        public let id = UUID()
        public var title: String
        public var message: String
        public init(title: String, message: String) { self.title = title; self.message = message }
    }

    public init() {
        library = MeetingLibrary()
        models = ModelManager()
        queue = TranscriptionQueue(library: library, models: models)
        showWelcome = !settings.welcomeDone
        engineMissing = EngineRunner.bundled() == nil
        Task { await checkEngine() }
    }

    public var selectedMeeting: Meeting? {
        guard let id = selectedMeetingID else { return nil }
        return library.meetings.first { $0.id == id }
    }

    public var filteredMeetings: [Meeting] { library.search(searchText) }

    func checkEngine() async {
        guard let engine = EngineRunner.bundled() else { return }
        engineHealth = try? await engine.health()
    }

    // MARK: - Gravação

    public func startRecording() {
        guard recorder.phase == .idle || recordingMeetingID == nil else { return }
        let title = String(localized: "Meeting \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))", bundle: .module)
        do {
            let meeting = try library.create(title: title, source: .recording)
            recordingMeetingID = meeting.id
            selectedMeetingID = meeting.id
            let folder = library.folder(for: meeting)
            Task {
                await recorder.start(into: folder.url, microphoneID: settings.microphoneID)
                if case .failed(let msg) = recorder.phase {
                    try? library.delete(meeting)
                    recordingMeetingID = nil
                    selectedMeetingID = nil
                    alert = AlertMessage(title: String(localized: "Couldn't start recording", bundle: .module), message: msg)
                    recorder.reset()
                }
            }
        } catch {
            alert = AlertMessage(title: String(localized: "Couldn't create the meeting folder", bundle: .module), message: error.localizedDescription)
        }
    }

    public func stopRecording() {
        guard let id = recordingMeetingID, let meeting = library.meetings.first(where: { $0.id == id }) else { return }
        Task {
            let result = await recorder.stop()
            recordingMeetingID = nil
            guard let result else {
                try? library.delete(meeting)
                if selectedMeetingID == id { selectedMeetingID = nil }
                alert = AlertMessage(title: String(localized: "Nothing was recorded", bundle: .module),
                                     message: String(localized: "No audio reached Meety. Check the microphone and the system audio permission.", bundle: .module))
                return
            }
            let folder = library.folder(for: meeting)
            do {
                try await AudioMixer.mix(tracks: [result.micTrack, result.systemTrack].compactMap { $0 }, output: folder.audio)
                library.update(id) { $0.duration = result.duration; $0.createdAt = result.startedAt; $0.status = .recorded }
                if settings.transcribeAfterRecording, let m = library.meetings.first(where: { $0.id == id }) {
                    transcribe(m)
                }
            } catch {
                library.update(id) { $0.status = .failed; $0.error = error.localizedDescription }
            }
        }
    }

    public func toggleRecording() {
        if recorder.isRecording { stopRecording() } else if recorder.phase == .idle { startRecording() }
    }

    // MARK: - Importar

    public func importFiles(_ urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard AudioPrep.supportedExtensions.contains(ext) else { continue }
            if AudioPrep.unsupportedByAVFoundation.contains(ext) {
                alert = AlertMessage(title: String(localized: "Format not supported yet", bundle: .module),
                                     message: String(localized: "Meety can't open .\(ext) files yet. Convert the file to MP4, M4A, MP3 or WAV and try again.", bundle: .module))
                continue
            }
            Task { await importOne(url) }
        }
    }

    func importOne(_ url: URL) async {
        let title = url.deletingPathExtension().lastPathComponent
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        do {
            let meeting = try library.create(title: title, source: .imported, date: date, originalFileName: url.lastPathComponent)
            let folder = library.folder(for: meeting)
            // Cópia para dentro da biblioteca: a reunião não depende do arquivo original.
            try FileManager.default.copyItem(at: url, to: folder.audio)
            let duration = await AudioPrep.duration(of: folder.audio)
            library.update(meeting.id) { $0.duration = duration }
            selectedMeetingID = meeting.id
            if let m = library.meetings.first(where: { $0.id == meeting.id }) { transcribe(m) }
        } catch {
            alert = AlertMessage(title: String(localized: "Couldn't import \(url.lastPathComponent)", bundle: .module), message: error.localizedDescription)
        }
    }

    public func chooseFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .mp3, .wav, .aiff, .quickTimeMovie]
        panel.message = String(localized: "Choose audio or video files to transcribe", bundle: .module)
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    // MARK: - Transcrever

    public func transcribe(_ meeting: Meeting) {
        guard queue.job(for: meeting.id) == nil else { return }
        let model = models.catalog.model(id: settings.transcriptionModelID)
        guard let model, models.isInstalled(model) else {
            alert = AlertMessage(title: String(localized: "Download a model first", bundle: .module),
                                 message: TranscriptionError.modelNotInstalled.localizedDescription)
            library.update(meeting.id) { $0.status = .recorded }
            return
        }
        queue.enqueue(meeting, options: settings.transcriptionOptions)
    }

    public func delete(_ meeting: Meeting) {
        queue.job(for: meeting.id)?.cancel()
        do {
            try library.delete(meeting)
            if selectedMeetingID == meeting.id { selectedMeetingID = nil }
        } catch {
            alert = AlertMessage(title: String(localized: "Couldn't delete", bundle: .module), message: error.localizedDescription)
        }
    }

    public func revealInFinder(_ meeting: Meeting) {
        NSWorkspace.shared.activateFileViewerSelecting([library.folder(for: meeting).url])
    }
}
