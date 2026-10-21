import Foundation

/// Blocos de Markdown dos resumos (o MeetyUI desenha; aqui só o recorte, para poder testar).
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case item(level: Int, checked: Bool?, text: String)
    case ordered(level: Int, number: Int, text: String)
    case quote(String)
    case code(String)
    case rule
    case table(header: [String], rows: [[String]])

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var para: [String] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        func cells(_ l: String) -> [String] {
            var t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func isSeparator(_ l: String) -> Bool {
            let t = l.trimmingCharacters(in: .whitespaces)
            return t.contains("-") && t.allSatisfy { "|-: ".contains($0) }
        }
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let level = min(indent / 2, 4)

            if line.hasPrefix("```") {
                flush(); var code: [String] = []; i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                out.append(.code(code.joined(separator: "\n"))); i += 1; continue
            }
            if line.isEmpty { flush(); i += 1; continue }
            if line.hasPrefix("|"), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                flush(); let header = cells(line); var rows: [[String]] = []; i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(cells(lines[i])); i += 1 }
                out.append(.table(header: header, rows: rows)); continue
            }
            if let m = line.firstMatch(of: #/^(#{1,6})\s+(.*)$/#) {
                flush(); out.append(.heading(level: m.1.count, text: String(m.2).trimmingCharacters(in: CharacterSet(charactersIn: "# ")))); i += 1; continue
            }
            if line.count >= 3, Set(line.replacingOccurrences(of: " ", with: "")).count == 1, "-*_".contains(line.first!) {
                flush(); out.append(.rule); i += 1; continue
            }
            if let m = line.firstMatch(of: #/^[-*+]\s+\[( |x|X)\]\s+(.*)$/#) {
                flush(); out.append(.item(level: level, checked: m.1 != " ", text: String(m.2))); i += 1; continue
            }
            if let m = line.firstMatch(of: #/^[-*+]\s+(.*)$/#) {
                flush(); out.append(.item(level: level, checked: nil, text: String(m.1))); i += 1; continue
            }
            if let m = line.firstMatch(of: #/^(\d{1,3})[.)]\s+(.*)$/#) {
                flush(); out.append(.ordered(level: level, number: Int(m.1) ?? 1, text: String(m.2))); i += 1; continue
            }
            if line.hasPrefix(">") {
                flush(); var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                out.append(.quote(q.joined(separator: " "))); continue
            }
            para.append(line); i += 1
        }
        flush()
        return out
    }
}
