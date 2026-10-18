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
    let accent        = Color(light: 0x0B5CAD, dark: 0x5AA0E8)
    let accentText    = Color(light: 0x0B5CAD, dark: 0x9CC8F2)
    let accentTint    = Color(light: 0x0B5CAD, lightAlpha: 0.12, dark: 0x5AA0E8, darkAlpha: 0.16)

    // Fundos
    let window        = Color(light: 0xEEF3F8, dark: 0x0E1824)
    let sidebar       = Color(light: 0xE3EBF3, dark: 0x14202C)
    let content       = Color(light: 0xFFFFFF, dark: 0x0B141E)
    let elevated      = Color(light: 0xFFFFFF, dark: 0x1A2633)
    let control       = Color(light: 0xFFFFFF, dark: 0x223040)
    let fill          = Color(light: 0x0B2D55, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.07)
    let fillStrong    = Color(light: 0x0B2D55, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.14)
    let hover         = Color(light: 0x0B5CAD, lightAlpha: 0.07, dark: 0x5AA0E8, darkAlpha: 0.10)

    // Texto
    let textPrimary   = Color(light: 0x0D1B2A, dark: 0xE8EEF5)
    let textSecondary = Color(light: 0x4D5B6B, dark: 0x9AABBD)
    let textTertiary  = Color(light: 0x5E6D7E, dark: 0x8A9AAD)

    // Bordas
    let separator     = Color(light: 0x0D2846, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.08)
    let borderStrong  = Color(light: 0x0D2846, lightAlpha: 0.16, dark: 0xFFFFFF, darkAlpha: 0.16)
    let controlBorder = Color(light: 0x0D2846, lightAlpha: 0.14, dark: 0xFFFFFF, darkAlpha: 0.10)

    // Estados. O vermelho é só de gravação.
    let recordFill    = Color(light: 0xD43A30, dark: 0xD43A30)
    let recordText    = Color(light: 0xC7342B, dark: 0xFF6259)
    let recordTint    = Color(light: 0xD43A30, lightAlpha: 0.12, dark: 0xFF6259, darkAlpha: 0.16)
    let success       = Color(light: 0x0D7A68, dark: 0x6FD6C1)
    let successTint   = Color(light: 0x0D7A68, lightAlpha: 0.12, dark: 0x6FD6C1, darkAlpha: 0.14)
    let warning       = Color(light: 0x9A5A00, dark: 0xF0B458)
    let warningTint   = Color(light: 0x9A5A00, lightAlpha: 0.10, dark: 0xF0B458, darkAlpha: 0.12)

    /// Oito cores de falante. A 0 é sempre "Você" e coincide com o destaque.
    let speakers: [Color] = [
        Color(light: 0x0B5CAD, dark: 0x7DB5EE), // Você (azul-oceano)
        Color(light: 0x4A42D6, dark: 0xA9A4FF), // índigo
        Color(light: 0x0B6F8C, dark: 0x6CC9E6), // ciano
        Color(light: 0x0D7A68, dark: 0x6FD6C1), // verde-mar
        Color(light: 0xB0246A, dark: 0xF28BC0), // amora
        Color(light: 0x44597A, dark: 0xA9BDE0), // ardósia
        Color(light: 0x6D4BC8, dark: 0xB39CF5), // violeta
        Color(light: 0x2767A3, dark: 0x80BDF0), // azul-aço
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
