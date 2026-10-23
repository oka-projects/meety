import MeetyCore
import SwiftUI

/// A demonstração do ditado na tela de novidade: um Mac visto de frente (tela em cima, teclado
/// embaixo). ⌥ Space acende, o painel abre e grava; acende de novo, o painel transcreve e mostra
/// o "colado"; tudo recomeça.
struct DictationDemo: View {
    /// Mostra o teclado só quando o atalho é ⌥ Space (as teclas desenhadas são essas).
    var showKeyboard = true

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Storyboard.cycle)
            let s = Storyboard(t: t)
            VStack(spacing: 0) {
                Screen(s: s)
                if showKeyboard { Keyboard(s: s) }
            }
        }
        .frame(width: 440)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .light)
    }
}

/// O roteiro: tudo que muda com o tempo, num lugar só.
private struct Storyboard {
    static let cycle = 9.0
    let t: Double

    // Momentos (segundos dentro do ciclo).
    static let press1 = 1.15, open = 1.35, micOpen = 1.8
    static let press2 = 4.8, done = 6.1, panelOut = 7.6

    /// Quanto as teclas estão apertadas (0...1): duas batidas.
    var pressed: Double { tap(Self.press1) + tap(Self.press2) }

    private func tap(_ start: Double) -> Double {
        let down = 0.12, hold = 0.22, up = 0.16
        let x = t - start
        if x < 0 || x > down + hold + up { return 0 }
        if x < down { return x / down }
        if x < down + hold { return 1 }
        return 1 - (x - down - hold) / up
    }

    enum Panel: Equatable { case hidden, connecting, recording, transcribing, done }
    var panel: Panel {
        switch t {
        case ..<Self.open: return .hidden
        case ..<Self.micOpen: return .connecting
        case ..<(Self.press2 + 0.12): return .recording
        case ..<Self.done: return .transcribing
        case ..<Self.panelOut: return .done
        default: return .hidden
        }
    }

    /// Segundos do cronômetro do painel.
    var seconds: Int { max(0, Int(t - Self.micOpen)) }

    /// Nível da voz enquanto grava: sílabas dentro de frases, com respiros.
    var level: Double {
        guard panel == .recording else { return 0 }
        let phrase = min(1, max(0, sin((t - Self.micOpen) * 1.6) + 0.6))
        return phrase * (0.3 + 0.7 * abs(sin(t * 5.3)) * abs(sin(t * 2.1 + 1)))
    }
}

// MARK: - Tela

private struct Screen: View {
    let s: Storyboard

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.18, blue: 0.38), Color(red: 0.16, green: 0.42, blue: 0.68), Color(red: 0.55, green: 0.42, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            DemoPanel(s: s)
                .scaleEffect(s.panel == .hidden ? 0.84 : 1)
                .opacity(s.panel == .hidden ? 0 : 1)
                .blur(radius: s.panel == .hidden ? 8 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.68), value: s.panel == .hidden)
        }
        .frame(height: 168)
    }
}

/// O painel do ditado em miniatura, com os mesmos estados do de verdade.
private struct DemoPanel: View {
    let s: Storyboard

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch s.panel {
                case .hidden, .connecting: ConnectingDots().scaleEffect(0.8)
                case .recording: FluidWave(level: CGFloat(s.level))
                case .transcribing: StatusRing(phase: .spinning).scaleEffect(0.8)
                case .done: StatusRing(phase: .success).scaleEffect(0.8)
                }
            }
            .frame(height: 62)
            Spacer(minLength: 0)
            Group {
                switch s.panel {
                case .hidden, .connecting:
                    caption(String(localized: "Opening the microphone", bundle: .module), nil)
                case .recording:
                    HStack {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30).background(Circle().fill(.primary.opacity(0.12)))
                        Spacer()
                        Text(String(format: "%d:%02d", s.seconds / 60, s.seconds % 60)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                        Spacer()
                        RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: 10, height: 10)
                            .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.92)))
                    }
                case .transcribing:
                    caption(String(localized: "Transcribing", bundle: .module), nil)
                case .done:
                    caption(String(localized: "Pasted", bundle: .module), String(localized: "and copied · \(String(localized: "via \("Groq")", bundle: .module))", bundle: .module))
                }
            }
            .frame(height: 30)
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
        .frame(width: 136, height: 136)
        .modifier(Glass(cornerRadius: 31))
        .environment(\.colorScheme, .dark)
    }

    private func caption(_ title: String, _ detail: String?) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 11, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

// MARK: - Teclado

private enum Palette {
    static let lit = Color(red: 0.30, green: 0.76, blue: 0.93)
    static let litDeep = Color(red: 0.12, green: 0.58, blue: 0.84)
}

private struct Keyboard: View {
    let s: Storyboard

    // Fileira de baixo: x da esquerda e largura.
    static let row: [(label: String, symbol: String, x: CGFloat, w: CGFloat)] = [
        ("fn", "globe", 18, 44), ("control", "⌃", 68, 44), ("option", "⌥", 118, 44),
        ("command", "⌘", 168, 50), ("", "", 224, 202),
    ]
    static let upperY: CGFloat = 16
    static let rowY: CGFloat = 66
    static let keyH: CGFloat = 44
    static let height: CGFloat = 132

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(white: 0.90), Color(white: 0.82)], startPoint: .top, endPoint: .bottom)
            ForEach(Array(["shift", "Z", "X", "C", "V", "B", "N"].enumerated()), id: \.offset) { i, label in
                Key(label: label, symbol: "", width: i == 0 ? 68 : 44, pressed: 0)
                    .offset(x: i == 0 ? 18 : 92 + CGFloat(i - 1) * 50, y: Self.upperY)
            }
            ForEach(Self.row.indices, id: \.self) { i in
                let k = Self.row[i]
                Key(label: k.label, symbol: k.symbol, width: k.w, pressed: i == 2 || i == 4 ? s.pressed : 0)
                    .offset(x: k.x, y: Self.rowY)
            }
        }
        .frame(width: 440, height: Self.height)
    }
}

/// Tecla clara de Mac; acende em azul-claro quando apertada.
private struct Key: View {
    let label: String
    let symbol: String
    let width: CGFloat
    let pressed: Double

    var body: some View {
        let depth = 4 * (1 - pressed)
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(white: 0.70))
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(pressed > 0
                      ? AnyShapeStyle(LinearGradient(colors: [Palette.lit.opacity(0.35 + 0.65 * pressed), Palette.litDeep.opacity(0.35 + 0.65 * pressed)], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.94)], startPoint: .top, endPoint: .bottom)))
                .overlay(alignment: symbol.isEmpty ? .center : .topTrailing) {
                    if symbol == "globe" {
                        Image(systemName: "globe").font(.system(size: 10)).padding(6)
                    } else if !symbol.isEmpty {
                        Text(verbatim: symbol).font(.system(size: 11)).padding(6)
                    }
                }
                .overlay(alignment: symbol.isEmpty ? .center : .bottomLeading) {
                    Text(verbatim: label).font(.system(size: symbol.isEmpty ? 12 : 9, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.7).padding(symbol.isEmpty ? 0 : 6)
                }
                .foregroundStyle(pressed > 0.5 ? Color.white : Color(white: 0.35))
                .offset(y: 4 - depth)
        }
        .frame(width: width, height: Keyboard.keyH)
    }
}
