import Foundation

/// Decide quem falou em cada frase.
///
/// Camada 1 (gravações do Meety): a trilha do microfone é "Você"; comparando a energia das duas
/// trilhas no intervalo da frase, ela vai para "Você" ou para os participantes.
/// Camada 2: os participantes são separados entre si pela diarização da trilha do sistema
/// (ver `Diarizer`), que entra aqui como uma lista de trechos com rótulo.
public enum SpeakerAttribution {

    public struct LabeledSpan: Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var label: String
        public init(start: Double, end: Double, label: String) { self.start = start; self.end = end; self.label = label }
    }

    /// Rotula cada segmento como `you` ou `p1` quando só há as duas trilhas.
    /// `micGain` compensa microfones baixos: acima de 1 favorece "Você".
    public static func youVersusOthers(segments: [TranscriptSegment], mic: [Float], system: [Float], micGain: Float = 1.0) -> [TranscriptSegment] {
        let micFloor = noiseFloor(mic), sysFloor = noiseFloor(system)
        return segments.map { seg in
            var s = seg
            let m = max(0, AudioPrep.rms(mic, from: seg.start, to: seg.end) - micFloor) * micGain
            let o = max(0, AudioPrep.rms(system, from: seg.start, to: seg.end) - sysFloor)
            s.speaker = m >= o ? Speaker.you : Speaker.participant(1)
            return s
        }
    }

    /// Dá a cada segmento o rótulo do trecho diarizado que mais se sobrepõe a ele.
    /// Segmentos já marcados como `you` são preservados quando `keepYou` é verdadeiro.
    public static func assign(spans: [LabeledSpan], to segments: [TranscriptSegment], keepYou: Bool, prefix: (Int) -> String) -> [TranscriptSegment] {
        // Os rótulos do diarizador viram p1, p2... na ordem em que aparecem.
        var order: [String: String] = [:]
        func mapped(_ label: String) -> String {
            if let m = order[label] { return m }
            let m = prefix(order.count + 1)
            order[label] = m
            return m
        }
        let sorted = spans.sorted { $0.start < $1.start }
        return segments.map { seg in
            var s = seg
            if keepYou && seg.speaker == Speaker.you { return s }
            var best: (String, Double)?
            for span in sorted {
                if span.start >= seg.end { break }
                let overlap = min(span.end, seg.end) - max(span.start, seg.start)
                if overlap > 0, overlap > (best?.1 ?? 0) { best = (span.label, overlap) }
            }
            if let b = best { s.speaker = mapped(b.0) }
            else if s.speaker == nil || s.speaker == Speaker.participant(1) {
                // Sem fala detectada no trecho: fica com o falante anterior, se houver.
                s.speaker = s.speaker ?? prefix(1)
            }
            return s
        }
    }

    /// Reaproveita o rótulo do vizinho para frases que ficaram sem ninguém.
    public static func fillGaps(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var out = segments
        var last: String?
        for i in out.indices {
            if let sp = out[i].speaker { last = sp } else { out[i].speaker = last }
        }
        return out
    }

    /// Mediana da energia em janelas de 0,5 s: uma estimativa do ruído de fundo da trilha.
    static func noiseFloor(_ samples: [Float]) -> Float {
        let window = Int(AudioPrep.sampleRate / 2)
        guard samples.count >= window else { return 0 }
        var values: [Float] = []
        var i = 0
        while i + window <= samples.count {
            var acc: Float = 0
            for j in i..<(i + window) { acc += samples[j] * samples[j] }
            values.append((acc / Float(window)).squareRoot())
            i += window
        }
        values.sort()
        return values[values.count / 4]   // primeiro quartil: silêncio entre falas
    }
}
