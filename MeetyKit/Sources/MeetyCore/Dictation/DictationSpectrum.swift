import Accelerate

/// Espectro da voz do ditado em 11 faixas (graves → agudos, de 90 Hz a 5 kHz) para o estilo "Espectro".
/// Recebe pedaços de 20 ms a 16 kHz e analisa sempre os últimos 512 pontos (32 ms).
public final class DictationSpectrum {
    public static let bandCount = 11

    private static let size = 512
    private let fft = vDSP.FFT(log2n: 9, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 512, isHalfWindow: false)
    private var samples = [Float](repeating: 0, count: 512)
    private let bandBins: [Range<Int>]
    private var floors = [Float](repeating: 0, count: DictationSpectrum.bandCount)  // 0 dB: a primeira leitura já vira o piso
    private var ceiling: Float = -40

    init() {
        // Faixas em escala logarítmica, como o ouvido percebe. Cada bin tem 31,25 Hz.
        let edges = (0...Self.bandCount).map { 90 * pow(5000 / 90, Float($0) / Float(Self.bandCount)) }
        bandBins = (0..<Self.bandCount).map { i in
            let lo = Int(edges[i] / 31.25)
            return lo..<max(lo + 1, Int(edges[i + 1] / 31.25))
        }
    }

    func reset() {
        samples = [Float](repeating: 0, count: Self.size)
        floors = [Float](repeating: 0, count: Self.bandCount)
        ceiling = -40
    }

    func analyze(_ chunk: ArraySlice<Float>) -> [Float] {
        samples.removeFirst(chunk.count)
        samples.append(contentsOf: chunk)
        let windowed = vDSP.multiply(samples, window)

        let half = Self.size / 2
        var inReal = [Float](repeating: 0, count: half), inImag = inReal
        var outReal = inReal, outImag = inReal
        var power = inReal
        inReal.withUnsafeMutableBufferPointer { ir in
            inImag.withUnsafeMutableBufferPointer { ii in
                outReal.withUnsafeMutableBufferPointer { orp in
                    outImag.withUnsafeMutableBufferPointer { oi in
                        var input = DSPSplitComplex(realp: ir.baseAddress!, imagp: ii.baseAddress!)
                        var output = DSPSplitComplex(realp: orp.baseAddress!, imagp: oi.baseAddress!)
                        windowed.withUnsafeBufferPointer { w in
                            w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                                vDSP_ctoz($0, 2, &input, 1, vDSP_Length(half))
                            }
                        }
                        fft.forward(input: input, output: &output)
                        vDSP.squareMagnitudes(output, result: &power)
                    }
                }
            }
        }

        var values = [Float](repeating: 0, count: Self.bandCount)
        for (i, bins) in bandBins.enumerated() {
            let mean = power[bins].reduce(0, +) / Float(bins.count)
            let db = 10 * log10(mean + 1e-12)
            // Mesmo esquema do nível: piso por faixa que acompanha o ruído, teto comum que decai.
            floors[i] = db < floors[i] ? db : floors[i] + 0.002 * (db - floors[i])
            ceiling = db > ceiling ? db : ceiling - 0.01
            values[i] = min(max((db - floors[i] - 6) / max(ceiling - floors[i], 24), 0), 1)
        }
        return values
    }
}
