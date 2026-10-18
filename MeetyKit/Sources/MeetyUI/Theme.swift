import AppKit
import MeetyCore
import SwiftUI

// Tokens de design do Meety (docs/design/tokens.json). Cada cor tem variante clara e escura e
// resolve pela aparência do sistema. A cor de destaque dos controles nativos vem do
// AccentColor do catálogo de assets, que usa os mesmos valores.

extension Color {
    static let meety = MeetyColors()
}

struct MeetyColors {
    // Destaque (verde petróleo)
    let accent        = Color(light: 0x146C66, dark: 0x1F7F78)
    let accentText    = Color(light: 0x146C66, dark: 0x5FC8C0)
    let accentTint    = Color(light: 0x146C66, lightAlpha: 0.12, dark: 0x5FC8C0, darkAlpha: 0.14)

    // Fundos
    let window        = Color(light: 0xF4F6F6, dark: 0x1E2424)
    let sidebar       = Color(light: 0xECF0F0, dark: 0x262C2C)
    let content       = Color(light: 0xFFFFFF, dark: 0x1A1F1F)
    let elevated      = Color(light: 0xFFFFFF, dark: 0x2A3131)
    let control       = Color(light: 0xFFFFFF, dark: 0x343B3B)
    let fill          = Color(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.07)
    let fillStrong    = Color(light: 0x000000, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.14)
    let hover         = Color(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.06)

    // Texto
    let textPrimary   = Color(light: 0x1A2121, dark: 0xECF0F0)
    let textSecondary = Color(light: 0x5B6868, dark: 0xA6B1B1)
    let textTertiary  = Color(light: 0x5F6C6C, dark: 0x8B9797)

    // Bordas
    let separator     = Color(light: 0x000000, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.09)
    let borderStrong  = Color(light: 0x000000, lightAlpha: 0.14, dark: 0xFFFFFF, darkAlpha: 0.16)
    let controlBorder = Color(light: 0x000000, lightAlpha: 0.13, dark: 0xFFFFFF, darkAlpha: 0.10)

    // Estados. O vermelho é só de gravação.
    let recordFill    = Color(light: 0xD43A30, dark: 0xD43A30)
    let recordText    = Color(light: 0xC7342B, dark: 0xFF6259)
    let recordTint    = Color(light: 0xD43A30, lightAlpha: 0.12, dark: 0xFF6259, darkAlpha: 0.16)
    let success       = Color(light: 0x22743B, dark: 0x5BCB7A)
    let successTint   = Color(light: 0x22743B, lightAlpha: 0.12, dark: 0x5BCB7A, darkAlpha: 0.14)
    let warning       = Color(light: 0x9A5A00, dark: 0xF0B458)
    let warningTint   = Color(light: 0x9A5A00, lightAlpha: 0.10, dark: 0xF0B458, darkAlpha: 0.12)

    /// Oito cores de falante. A 0 é sempre "Você" e coincide com o destaque.
    let speakers: [Color] = [
        Color(light: 0x146C66, dark: 0x5FC8C0), // Você
        Color(light: 0x4453C8, dark: 0x9AA6FF), // índigo
        Color(light: 0x8F5A00, dark: 0xE3AC3F), // ocre
        Color(light: 0x8A3C9E, dark: 0xD193E3), // ameixa
        Color(light: 0xBC3F24, dark: 0xF5907A), // coral
        Color(light: 0x4A7A1A, dark: 0xA4D25E), // oliva
        Color(light: 0x2767A3, dark: 0x80BDF0), // azul aço
        Color(light: 0xB0346A, dark: 0xF094BC), // rosa
    ]

    /// Cor por índice: 0 é "Você"; os demais ciclam pelas outras sete.
    func speaker(_ index: Int) -> Color {
        if index <= 0 { return speakers[0] }
        let others = Array(speakers.dropFirst())
        return others[(index - 1) % others.count]
    }

    /// Cor pelo identificador do falante ("you", "p1", "s2"...).
    func speaker(id: String) -> Color {
        if id == Speaker.you { return speakers[0] }
        return speaker(Int(id.dropFirst()) ?? 1)
    }
}

enum MeetyRadius {
    static let control: CGFloat = 6
    static let field: CGFloat = 7
    static let row: CGFloat = 7
    static let card: CGFloat = 10
    static let popover: CGFloat = 10
    static let sheet: CGFloat = 12
    static let hero: CGFloat = 28
}

enum MeetyFont {
    static let windowTitle  = Font.system(size: 22, weight: .semibold)
    static let sheetTitle   = Font.system(size: 24, weight: .semibold)
    static let stateTitle   = Font.system(size: 20, weight: .semibold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let headline     = Font.system(size: 13, weight: .semibold)
    static let body         = Font.system(size: 13)
    static let transcript   = Font.system(size: 14)
    static let callout      = Font.system(size: 12)
    static let caption      = Font.system(size: 11)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let timeInline   = Font.system(size: 13, design: .monospaced).monospacedDigit()
    static let timeBlock    = Font.system(size: 17, weight: .medium, design: .monospaced).monospacedDigit()
    static let timeBig      = Font.system(size: 44, weight: .light, design: .monospaced).monospacedDigit()
}

extension Color {
    /// Uma cor com um hex na aparência clara e outro na escura.
    init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Componentes reutilizáveis

/// Rótulo de seção em caixa alta ("WHAT DO YOU NEED").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(MeetyFont.sectionLabel).textCase(.uppercase).tracking(0.5).foregroundStyle(Color.meety.textSecondary)
    }
}

/// O quadrado arredondado com um símbolo, usado nos estados vazios e nas boas-vindas.
struct HeroIcon: View {
    var systemName: String
    var size: CGFloat = 96
    var tint: Color = Color.meety.accentText
    var background: Color = Color.meety.accentTint
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).fill(background)
            Image(systemName: systemName).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// Selo pequeno em pílula ("Recommended", "Allowed").
struct Badge: View {
    enum Style { case accent, neutral, success, warning }
    let text: String
    var style: Style = .neutral
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(background, in: Capsule())
    }
    var foreground: Color {
        switch style {
        case .accent: return Color.meety.accentText
        case .neutral: return Color.meety.textSecondary
        case .success: return Color.meety.success
        case .warning: return Color.meety.warning
        }
    }
    var background: Color {
        switch style {
        case .accent: return Color.meety.accentTint
        case .neutral: return Color.meety.fill
        case .success: return Color.meety.successTint
        case .warning: return Color.meety.warningTint
        }
    }
}

/// Cartão branco com borda fina, o contêiner padrão de listas e blocos.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Color.meety.elevated, in: RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous).stroke(Color.meety.separator))
    }
}

/// Linha "cadeado: fica no Mac" ou "nuvem: sai do Mac".
struct PrivacyLine: View {
    var cloud = false
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: cloud ? "cloud" : "lock.fill").font(.system(size: 11))
            Text(text)
        }
        .font(MeetyFont.callout)
        .foregroundStyle(cloud ? Color.meety.warning : Color.meety.textSecondary)
    }
}

/// Formatação de datas e durações como aparecem na interface.
enum MeetyFormat {
    /// "Today, 14:30", "Yesterday, 10:00", "Oct 15, 16:15".
    static func dayAndTime(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDateInToday(date) { return String(localized: "Today, \(time)", bundle: .module) }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday, \(time)", bundle: .module) }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))), \(time)"
    }

    /// "48 min", "1 h 05 min", "40 s".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return String(localized: "\(h) h \(String(format: "%02d", m)) min", bundle: .module) }
        if m > 0 { return String(localized: "\(m) min", bundle: .module) }
        return String(localized: "\(total) s", bundle: .module)
    }
}
