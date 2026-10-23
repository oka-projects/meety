import MeetyCore
import SwiftUI

/// A novidade do ditado: aberta pelo botão com selo na barra de ferramentas.
struct WhatsNewView: View {
    /// Muda a cada novidade; o selo do botão aparece até a pessoa abrir esta versão.
    static let id = "dictation-1"

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var keyState: DictationSettings.KeyState = .idle
    @State private var axGranted = Permissions.accessibility == .granted
    @State private var tab = ProcessInfo.processInfo.environment["MEETY_WHATSNEW_TAB"] == "setup" ? 1 : 0
    /// Confere a Acessibilidade enquanto a pessoa vai e volta dos Ajustes.
    private let axTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    BrowserTabs(selection: $tab, tabs: [
                        (String(localized: "What's new", bundle: .module), "sparkles"),
                        (String(localized: "Set up", bundle: .module), "gearshape"),
                    ]) {
                        if tab == 0 {
                            DictationDemo(showKeyboard: model.settings.dictationShortcut == .optionSpace)
                                .padding(14)
                                .frame(maxHeight: .infinity)  // centrada na altura da aba Configurar
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(localized: "New: dictation in any app", bundle: .module)).font(MeetyFont.sectionTitle)
                                    Text(String(localized: "Press \(model.settings.dictationShortcut.title) anywhere, talk, and the text appears where your cursor is. Tap to start and stop, or hold while you talk.", bundle: .module))
                                        .font(MeetyFont.body).foregroundStyle(Color.meety.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                                groq
                                Divider()
                                Label(String(localized: "No key? Meety transcribes on this Mac with a light or medium model, and also uses it when Groq is unavailable.", bundle: .module), systemImage: "laptopcomputer")
                                    .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(20)
                        }
                    }
                }
                .padding(.horizontal, 36).padding(.vertical, 24)
            }
            Divider()
            HStack {
                Button(String(localized: "Not now", bundle: .module)) { dismiss() }.controlSize(.large)
                Spacer()
                if model.settings.dictationEnabled {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                        .controlSize(.large).keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "Turn on dictation", bundle: .module)) {
                        model.settings.dictationEnabled = true
                        model.dictation.applySettings()
                        dismiss()
                    }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 540, height: 620)
        .onReceive(axTimer) { _ in axGranted = Permissions.accessibility == .granted }
        .background(Color.meety.window)
        .onAppear {
            model.settings.whatsNewSeen = Self.id
            key = Groq.apiKey ?? ""
            if !key.isEmpty { keyState = .valid }
        }
    }

    /// A recomendação da Groq: chave gratuita, em três passos, com o campo para colar.
    var groq: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(Color.meety.accentText)
                Text(String(localized: "Recommended: a free Groq key", bundle: .module)).font(MeetyFont.headline)
            }
            Text(String(localized: "Groq transcribes a dictation in about a second, with great accuracy, and its free plan is enough for everyday use.", bundle: .module))
                .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                step(1, String(localized: "Create a free account at console.groq.com", bundle: .module))
                step(2, String(localized: "Open API Keys and click Create API Key", bundle: .module))
                step(3, String(localized: "Paste the key here", bundle: .module))
            }
            HStack(spacing: 8) {
                SecureField(String("gsk_…"), text: $key).textFieldStyle(.roundedBorder)
                Button(String(localized: "Save key", bundle: .module)) { saveKey() }.disabled(key.isEmpty || keyState == .checking)
                Link(String(localized: "Get a key", bundle: .module), destination: Groq.consoleURL)
            }
            switch keyState {
            case .checking: ProgressView().controlSize(.small)
            case .valid: Label(String(localized: "Saved in your Keychain", bundle: .module), systemImage: "checkmark").foregroundStyle(Color.meety.success).font(MeetyFont.callout)
            case .invalid: Label(String(localized: "Groq didn't accept this key", bundle: .module), systemImage: "xmark").foregroundStyle(Color.meety.warning).font(MeetyFont.callout)
            case .idle: EmptyView()
            }
            Divider().padding(.vertical, 2)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(Color.meety.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Paste at the cursor", bundle: .module)).font(MeetyFont.headline)
                    Text(String(localized: "macOS only lets Meety type into other apps after you turn it on in Accessibility.", bundle: .module))
                        .font(MeetyFont.callout).foregroundStyle(Color.meety.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if axGranted {
                    Badge(text: String(localized: "Allowed", bundle: .module), style: .success)
                } else {
                    Button(String(localized: "Open Settings", bundle: .module)) { Permissions.requestAccessibility() }
                }
            }
        }
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(n)").font(MeetyFont.caption.weight(.bold)).foregroundStyle(Color.meety.accentText)
                .frame(width: 18, height: 18).background(Circle().fill(Color.meety.accentTint))
            Text(text).font(MeetyFont.callout)
        }
    }

    func saveKey() {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keyState = .checking
        Task {
            if await Groq.check(key: k) {
                Groq.apiKey = k
                model.settings.dictationUseGroq = true
                keyState = .valid
            } else { keyState = .invalid }
        }
    }
}

/// Botão da barra de ferramentas com o selo de novidade.
struct WhatsNewButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button { model.showWhatsNew = true } label: {
            Image(systemName: "sparkles")
                .overlay(alignment: .topTrailing) {
                    if model.settings.whatsNewSeen != WhatsNewView.id {
                        Circle().fill(Color.meety.accent).frame(width: 7, height: 7).offset(x: 4, y: -3)
                    }
                }
        }
        .help(String(localized: "What's new in Meety", bundle: .module))
    }
}

/// Abas no estilo das do Chrome: a aba escolhida tem a cor do conteúdo e se abre nele com as
/// curvinhas na base; as outras ficam na faixa de trás.
struct BrowserTabs<Content: View>: View {
    @Binding var selection: Int
    let tabs: [(title: String, icon: String)]
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    let selected = i == selection
                    Button { selection = i } label: {
                        Label(tabs[i].title, systemImage: tabs[i].icon)
                            .font(MeetyFont.headline)
                            .foregroundStyle(selected ? Color.meety.textPrimary : Color.meety.textSecondary)
                            .padding(.horizontal, 18).frame(height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selected { BrowserTabShape().fill(Color.meety.elevated).padding(.horizontal, -8) }
                    }
                    .zIndex(selected ? 1 : 0)
                    if i < tabs.count - 1, i != selection, i + 1 != selection {
                        Rectangle().fill(Color.meety.borderStrong).frame(width: 1, height: 16)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 6)
            content
                .frame(maxWidth: .infinity, minHeight: 470, alignment: .top)
                .background(Color.meety.elevated)
        }
        .background(Color.meety.fillStrong)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.meety.separator))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// O formato da aba do Chrome: cantos de cima arredondados e a base que se abre para os lados.
struct BrowserTabShape: Shape {
    var corner: CGFloat = 10
    var flare: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = rect.minX + flare, r = rect.maxX - flare
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: l, y: rect.maxY - flare), control: CGPoint(x: l, y: rect.maxY))
        p.addLine(to: CGPoint(x: l, y: rect.minY + corner))
        p.addQuadCurve(to: CGPoint(x: l + corner, y: rect.minY), control: CGPoint(x: l, y: rect.minY))
        p.addLine(to: CGPoint(x: r - corner, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: r, y: rect.minY + corner), control: CGPoint(x: r, y: rect.minY))
        p.addLine(to: CGPoint(x: r, y: rect.maxY - flare))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: r, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
