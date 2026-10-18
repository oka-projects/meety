import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt, markdown, srt, vtt, json
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .txt: return String(localized: "Plain text", bundle: .module)
        case .markdown: return "Markdown"
        case .srt: return String(localized: "Subtitles (SRT)", bundle: .module)
        case .vtt: return String(localized: "Subtitles (VTT)", bundle: .module)
        case .json: return "JSON"
        }
    }
    public var fileExtension: String { self == .markdown ? "md" : rawValue }
}

public enum TranscriptExporter {
    public static func render(_ transcript: Transcript, meeting: Meeting, format: ExportFormat) -> String {
        switch format {
        case .txt: return plain(transcript, meeting: meeting, timestamps: false)
        case .markdown: return markdown(transcript, meeting: meeting)
        case .srt: return srt(transcript, meeting: meeting)
        case .vtt: return "WEBVTT\n\n" + cues(transcript, meeting: meeting, numbered: false, separator: ".")
        case .json:
            let data = (try? JSON.encoder.encode(ExportEnvelope(meeting: meeting, transcript: transcript))) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    struct ExportEnvelope: Codable { var meeting: Meeting; var transcript: Transcript }

    /// Texto corrido, com o nome de quem fala no começo de cada bloco.
    public static func plain(_ t: Transcript, meeting: Meeting, timestamps: Bool) -> String {
        var out: [String] = []
        var current: String?
        var buffer: [String] = []
        func flush() {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: " ")
            if let c = current, meeting.hasSpeakers { out.append("\(meeting.displayName(for: c)): \(text)") } else { out.append(text) }
            buffer = []
        }
        for s in t.segments {
            if s.speaker != current { flush(); current = s.speaker }
            buffer.append(timestamps ? "[\(clock(s.start))] \(s.text)" : s.text)
        }
        flush()
        return out.joined(separator: "\n\n")
    }

    public static func markdown(_ t: Transcript, meeting: Meeting) -> String {
        var md = "# \(meeting.title)\n\n"
        md += "\(DateFormatter.localizedString(from: meeting.createdAt, dateStyle: .long, timeStyle: .short))"
        if let d = meeting.duration { md += " · \(clock(d))" }
        md += "\n\n"
        var current: String?
        for s in t.segments {
            if meeting.hasSpeakers, s.speaker != current {
                current = s.speaker
                md += "\n**\(meeting.displayName(for: current ?? ""))** · \(clock(s.start))\n\n"
            }
            md += s.text + " "
        }
        return md.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func srt(_ t: Transcript, meeting: Meeting) -> String { cues(t, meeting: meeting, numbered: true, separator: ",") }

    static func cues(_ t: Transcript, meeting: Meeting, numbered: Bool, separator: String) -> String {
        var out = ""
        for (i, s) in t.segments.enumerated() {
            if numbered { out += "\(i + 1)\n" }
            out += "\(stamp(s.start, separator)) --> \(stamp(s.end, separator))\n"
            if meeting.hasSpeakers, let sp = s.speaker { out += "\(meeting.displayName(for: sp)): " }
            out += s.text + "\n\n"
        }
        return out
    }

    static func stamp(_ t: Double, _ sep: String) -> String {
        let ms = Int((t - floor(t)) * 1000)
        let s = Int(t)
        return String(format: "%02d:%02d:%02d%@%03d", s / 3600, (s % 3600) / 60, s % 60, sep, ms)
    }

    public static func clock(_ t: Double) -> String {
        let s = Int(t.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
