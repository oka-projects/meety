import AppKit
import MeetyCore
import SwiftUI

final class DictationPanelModel: ObservableObject {
    enum State: Equatable {
        case connecting  // microfone abrindo
        case recording
        case transcribing
        case done(String, String)  // título, detalhe
        case failed(String)
    }

    @Published var state: State = .recording
    @Published var style: DictationWaveStyle = .fluid
    @Published var level: CGFloat = 0  // suavizado
    @Published var bands = [CGFloat](repeating: 0, count: DictationSpectrum.bandCount)
    @Published var seconds = 0
    /// Aviso enquanto transcreve (a Groq falhou e o Mac assumiu).
    @Published var notice = ""
    @Published var shortcut = ""
    @Published var shown = false
}

/// Quadrado de vidro que aparece no centro, embaixo da tela, durante o ditado (o mesmo do OkaMic).
final class DictationPanel {
    let model = DictationPanelModel()
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private var hideWork: DispatchWorkItem?

    private lazy var window: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 230),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = PanelView(model: model, onStop: { [weak self] in self?.onStop?() },
                             onCancel: { [weak self] in self?.onCancel?() })
        panel.contentView = FirstMouseHostingView(rootView: view)
        return panel
    }()

    func show(_ state: DictationPanelModel.State) {
        hideWork?.cancel()
        model.state = state
        if !window.isVisible || !model.shown {
            if !window.isVisible { position() }
            window.alphaValue = 1
            window.orderFrontRegardless()
            DispatchQueue.main.async { self.model.shown = true }  // entra com mola e desfoque
        }
        switch state {
        case .done: hide(after: 1.7)
        case .failed: hide(after: 4)
        default: break
        }
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.shown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !self.model.shown { self.window.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Sobe rápido e desce devagar, para as ondas não tremerem.
    func push(level: Float, bands: [Float]) {
        func smooth(_ old: CGFloat, _ new: Float) -> CGFloat {
            let v = CGFloat(new)
            return old + (v > old ? 0.6 : 0.18) * (v - old)
        }
        model.level = smooth(model.level, level)
        model.bands = zip(model.bands, bands).map { smooth($0, $1) }
    }

    func resetLevels() {
        model.level = 0
        model.bands = [CGFloat](repeating: 0, count: DictationSpectrum.bandCount)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: frame.midX - 115, y: frame.minY + 50))
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct PanelView: View {
    @ObservedObject var model: DictationPanelModel
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            top.frame(height: 88)
            Spacer(minLength: 0)
            bottom.frame(height: 44)
        }
        .padding(EdgeInsets(top: 16, leading: 14, bottom: 14, trailing: 14))
        .frame(width: 184, height: 184)
        .modifier(Glass())
        .scaleEffect(model.shown ? 1 : 0.84)
        .offset(y: model.shown ? 0 : 14)
        .blur(radius: model.shown ? 0 : 8)
        .opacity(model.shown ? 1 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.68), value: model.shown)
        .frame(width: 230, height: 230)
    }

    @ViewBuilder private var top: some View {
        switch model.state {
        case .connecting:
            ConnectingDots()
        case .recording:
            switch model.style {
            case .fluid: FluidWave(level: model.level)
            case .spectrum: SpectrumBars(bands: model.bands)
            }
        case .transcribing: StatusRing(phase: .spinning)
        case .done: StatusRing(phase: .success)
        case .failed: StatusRing(phase: .failure)
        }
    }

    @ViewBuilder private var bottom: some View {
        switch model.state {
        case .connecting:
            HStack(spacing: 10) {
                cancelButton
                Text(String(localized: "Opening the microphone", bundle: .module)).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        case .recording:
            HStack {
                cancelButton
                Spacer()
                Text(String(format: "%d:%02d", model.seconds / 60, model.seconds % 60))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Spacer()
                Button(action: onStop) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 14, height: 14)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.92)))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Stop and transcribe (\(model.shortcut))", bundle: .module))
            }
        case .transcribing:
            if model.notice.isEmpty {
                caption(String(localized: "Transcribing", bundle: .module), " ")
            } else {
                VStack(spacing: 3) {
                    Text(String(localized: "Transcribing on this Mac", bundle: .module)).font(.system(size: 13, weight: .semibold))
                    Text(model.notice).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            }
        case let .done(title, detail):
            caption(title, detail)
        case let .failed(message):
            caption(String(localized: "That didn't work", bundle: .module), message)
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Cancel (Esc)", bundle: .module))
    }

    private func caption(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Ondas

/// Linha de pontos acendendo em sequência enquanto o microfone abre.
struct ConnectingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<7, id: \.self) { i in
                    Circle().fill(.primary)
                        .frame(width: 6, height: 6)
                        .opacity(0.2 + 0.8 * max(0, sin(t * 4 - Double(i) * 0.6)))
                }
            }
        }
    }
}

/// A: três fios que ondulam e crescem com a voz, presos nas pontas.
struct FluidWave: View {
    let level: CGFloat

    private static let waves: [(color: Color?, cycles: Double, speed: Double, gain: CGFloat, width: CGFloat)] = [
        (nil, 1.6, 3.2, 1.0, 3),  // nil = cor do texto (escuro no fundo claro, branco no escuro)
        (Color(red: 0.35, green: 0.72, blue: 1), 2.2, -2.3, 0.75, 2.5),
        (Color(red: 1, green: 0.58, blue: 0.42), 1.2, 1.7, 0.6, 2.5),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let mid = size.height / 2
                let amplitude = (0.06 + 0.94 * level) * (size.height / 2 - 4)
                for wave in Self.waves.reversed() {
                    var path = Path()
                    for step in 0...80 {
                        let x = Double(step) / 80
                        let envelope = pow(sin(.pi * x), 2)
                        let y = mid + amplitude * wave.gain * envelope * sin(2 * .pi * wave.cycles * x + t * wave.speed)
                        let point = CGPoint(x: x * size.width, y: y)
                        step == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                    let style = StrokeStyle(lineWidth: wave.width, lineCap: .round, lineJoin: .round)
                    if let color = wave.color {
                        ctx.stroke(path, with: .color(color.opacity(0.9)), style: style)
                    } else {
                        ctx.stroke(path, with: .foreground, style: style)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

/// B: 21 barras espelhadas, graves no meio e agudos nas pontas.
private struct SpectrumBars: View {
    let bands: [CGFloat]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<21, id: \.self) { i in
                let distance = abs(i - 10)
                Capsule()
                    .fill(.primary.opacity(1 - 0.045 * Double(distance)))
                    .frame(width: 3.5, height: 5 + 76 * bands[min(distance, bands.count - 1)])
            }
        }
        .animation(.easeOut(duration: 0.08), value: bands)
    }
}

// MARK: - Círculo de status

/// Contorno girando enquanto transcreve; ao terminar, fecha o círculo, enche de verde
/// (ou laranja, se falhou) e desenha o símbolo.
struct StatusRing: View {
    enum Phase { case spinning, success, failure }
    let phase: Phase

    @State private var trimEnd: CGFloat = 0.7
    @State private var filled = false
    @State private var mark: CGFloat = 0

    private var tint: (top: Color, bottom: Color) {
        phase == .failure
            ? (Color(red: 1, green: 0.72, blue: 0.3), Color(red: 0.93, green: 0.45, blue: 0.1))
            : (Color(red: 0.36, green: 0.89, blue: 0.55), Color(red: 0.06, green: 0.62, blue: 0.33))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
            ZStack {
                Circle().stroke(.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: trimEnd)
                    .stroke(AngularGradient(colors: [.primary.opacity(0.05), .primary], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * trimEnd)),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(angle - 90))
                Circle()
                    .fill(LinearGradient(colors: [tint.top, tint.bottom], startPoint: .top, endPoint: .bottom))
                    .overlay(  // brilho em cima, dá volume
                        Ellipse()
                            .fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 40, height: 24)
                            .offset(y: -13)
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: tint.bottom.opacity(0.55), radius: 10, y: 4)
                    .padding(-2)
                    .scaleEffect(filled ? 1 : 0.3)
                    .opacity(filled ? 1 : 0)
                (phase == .failure ? AnyShape(Exclamation()) : AnyShape(Checkmark()))
                .trim(from: 0, to: mark)
                .stroke(.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            }
            .frame(width: 58, height: 58)
        }
        .onAppear(perform: update)
        .onChange(of: phase) { update() }
    }

    private func update() {
        guard phase != .spinning else {
            trimEnd = 0.7
            filled = false
            mark = 0
            return
        }
        withAnimation(.easeOut(duration: 0.22)) { trimEnd = 1 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.58).delay(0.18)) { filled = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.36)) { mark = 1 }
    }
}

private struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY + rect.height * 0.04))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY - rect.height * 0.18))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.2))
        return p
    }
}

private struct Exclamation: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.1))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.12))
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.1))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.08))
        return p
    }
}

struct Glass: ViewModifier {
    var cornerRadius: CGFloat = 42
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            content.glassEffect(.clear, in: shape)  // o "claro" deixa ver bem o fundo
        } else {
            content.background(.ultraThinMaterial.opacity(0.7), in: shape)
                .overlay(shape.stroke(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        }
    }
}
