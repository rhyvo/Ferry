import Foundation

enum AssistantText {
    private static let nameEnd = #"(?![A-Za-z0-9_]|[.-][A-Za-z0-9_])"#

    private static func replacing(_ text: String, pattern: String, template: String, ignoringCase: Bool) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: ignoringCase ? .caseInsensitive : []) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func replacing(_ text: String, _ needle: String, with new: String, ignoringCase: Bool = true) -> String {
        guard !needle.isEmpty else { return text }
        return replacing(text, pattern: NSRegularExpression.escapedPattern(for: needle) + nameEnd,
                         template: NSRegularExpression.escapedTemplate(for: new), ignoringCase: ignoringCase)
    }

    static func scrub(_ text: String, home: String, user: String, gameFolder: String?) -> String {
        var s = text
        if let g = gameFolder {
            let parts = g.split(separator: "/").map(String.init)
            if !parts.isEmpty {
                for (prefix, sep, ignoringCase) in [("/", "/", false), ("Z:\\", "\\", true), ("Z:\\\\", "\\\\", true)] {
                    let form = prefix + parts.joined(separator: sep)
                    s = s.replacingOccurrences(of: form + sep, with: "", options: ignoringCase ? .caseInsensitive : [])
                    s = replacing(s, form, with: ".", ignoringCase: ignoringCase)
                }
            }
        }
        if !home.isEmpty {
            s = replacing(s, pattern: #"(?<![A-Za-z]:)"# + NSRegularExpression.escapedPattern(for: home) + nameEnd,
                          template: "~", ignoringCase: false)
        }
        if !user.isEmpty {
            s = replacing(s, pattern: #"users([\\/]+)"# + NSRegularExpression.escapedPattern(for: user) + nameEnd,
                          template: "users$1user", ignoringCase: true)
            if user.count >= 3 {
                s = replacing(s, pattern: #"\b"# + NSRegularExpression.escapedPattern(for: user) + #"\b"#,
                              template: "user", ignoringCase: false)
            }
        }
        return s
    }

    private static let saveExtensions: Set<String> = ["sav", "save", "sv"]

    static func isSaveFile(_ relativePath: String) -> Bool {
        let parts = relativePath.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map { String($0).lowercased() }
        if parts.contains(where: { $0.contains("save") }) { return true }
        if let last = parts.last, saveExtensions.contains((last as NSString).pathExtension) { return true }
        if parts.contains("remote") { return true }
        for i in parts.indices.dropLast() where parts[i] == "steam" && parts[i + 1] == "userdata" { return true }
        return false
    }

    private static let markers = ["err:", "warn:", "unhandled", "crash", "failed", "unimplemented function",
                                  "mono is not installed", "c000007b", "steamapi_init", "wait timed out"]

    static func focusLog(_ log: String, search: String?, maxLines: Int) -> String {
        let lines = log.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var keep = Set<Int>()
        let needle = (search ?? "").lowercased()
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            if markers.contains(where: lower.contains) { keep.insert(i) }
            if !needle.isEmpty, lower.contains(needle) {
                keep.formUnion(max(0, i - 3)...min(lines.count - 1, i + 3))
            }
        }
        keep.formUnion(max(0, lines.count - 15)..<lines.count)
        var seen = Set<String>()
        var out: [String] = []
        for i in keep.sorted() where seen.insert(lines[i]).inserted { out.append(lines[i]) }
        return out.suffix(max(0, maxLines)).joined(separator: "\n")
    }
}
