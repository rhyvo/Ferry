import Foundation

enum ChatMarkdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String, depth: Int)
        case numbered(Int, String, depth: Int)
        case rule
        case code(String)
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]?
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            let t = line.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if t.count >= 3, t.allSatisfy({ $0 == "`" }) { out.append(.code(code!.joined(separator: "\n"))); code = nil } else { code!.append(line) }
                continue
            }
            if t.hasPrefix("```"), !t.dropFirst(3).contains("`") { flush(); code = []; continue }
            if t.isEmpty { flush(); continue }
            if let h = heading(t) { flush(); out.append(h); continue }
            if isRule(t) { flush(); out.append(.rule); continue }
            let depth = (line.prefix { $0 == " " }.count) / 2
            if let b = listItem(t, depth: depth) { flush(); out.append(b); continue }
            para.append(t)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }

    private static func heading(_ t: String) -> Block? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let body = rest.trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : .heading(level: hashes, text: body)
    }

    private static func isRule(_ t: String) -> Bool {
        guard t.count >= 3, let c = t.first, "-*_".contains(c) else { return false }
        return t.allSatisfy { $0 == c }
    }

    private static func listItem(_ t: String, depth: Int) -> Block? {
        if let c = t.first, "*-+".contains(c), t.dropFirst().first == " " {
            let body = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return body.isEmpty ? nil : .bullet(body, depth: depth)
        }
        let digits = t.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, let n = Int(digits) {
            let rest = t.dropFirst(digits.count)
            if rest.hasPrefix(". ") {
                let body = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : .numbered(n, body, depth: depth)
            }
        }
        return nil
    }

    private static let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
                                                      "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"]
    private static let sub: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
                                                      "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎"]

    static func plainMath(_ text: String) -> String {
        guard text.contains("$") else { return text }
        guard let spans = try? NSRegularExpression(pattern: #"`[^`\n]*`"#) else { return mathOutsideCode(text) }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in spans.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += mathOutsideCode(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            out += ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        return out + mathOutsideCode(ns.substring(from: last))
    }

    private static func mathOutsideCode(_ text: String) -> String {
        guard text.contains("$") else { return text }
        var s = replace(text, #"\$\$([^$\n]+)\$\$"#) { convert($0) }
        s = replace(s, #"\$([^\s$](?:[^$\n]*[^\s$])?)\$"#) { inner in
            guard inner.contains(where: { "^_\\{".contains($0) }) else { return nil }
            let c = convert(inner)
            return c == inner && !inner.contains("\\") && !inner.contains("{") ? nil : c
        }
        return s
    }

    private static func replace(_ s: String, _ pattern: String, _ f: (String) -> String?) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let whole = ns.substring(with: m.range)
            out += f(ns.substring(with: m.range(at: 1))) ?? whole
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func convert(_ tex: String) -> String {
        script(script(tex, marker: "^", map: sup), marker: "_", map: sub)
    }

    private static func script(_ s: String, marker: String, map: [Character: Character]) -> String {
        let m = NSRegularExpression.escapedPattern(for: marker)
        guard let re = try? NSRegularExpression(pattern: m + #"(?:\{([^{}]*)\}|(\w))"#) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for match in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let g = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            let body = ns.substring(with: g)
            let mapped = body.map { map[$0] }
            out += mapped.contains(where: { $0 == nil }) ? ns.substring(with: match.range) : String(mapped.map { $0! })
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
}
