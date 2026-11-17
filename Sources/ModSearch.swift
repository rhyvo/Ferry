import Foundation

enum AssetPick: Equatable {
    case one(String)
    case ask([String])
    case none
}

enum ModSearch {
    private static let fileExtensions = ["zip", "7z", "rar", "dll", "asi", "exe", "msi"]

    private static let nonRepoOwners: Set<String> = ["user-attachments", "orgs", "settings", "sponsors", "topics", "collections", "marketplace", "features", "login", "about", "search", "explore", "notifications", "pricing", "enterprise", "apps", "users"]

    static func classify(_ link: String) -> ModLink? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        if fileExtensions.contains(url.pathExtension.lowercased()) { return .directFile(url) }
        if host == "github.com" || host == "www.github.com" {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, !nonRepoOwners.contains(parts[0].lowercased()) {
                var repo = parts[1]
                if repo.lowercased().hasSuffix(".git") { repo.removeLast(4) }
                return .githubRepo(owner: parts[0], repo: repo)
            }
        }
        return .webPage(url)
    }

    static func isGitHubHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com" || h.hasSuffix(".github.com")
    }

    static func downloadURL(_ url: URL) -> URL {
        guard isGitHubHost(url.host), var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let blob = c.percentEncodedPath.range(of: "/blob/") else { return url }
        c.percentEncodedPath.replaceSubrange(blob, with: "/raw/")
        return c.url ?? url
    }

    static func fixes(fromWikitext text: String) -> [ModResult] {
        let chars = Array(text)
        var results: [ModResult] = []
        var i = 0
        while let start = find("{{fixbox", in: chars, from: i) {
            guard let end = closing(of: start, in: chars) else { break }
            let inner = String(chars[(start + 2)..<(end - 2)])
            let params = parameters(of: inner)
            let fix = (params["fix"] ?? "").replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n# ", options: .regularExpression)
            let description = clean(params["description"] ?? "")
            let heading = nearestHeading(in: chars, before: start)
            let lines = fix.components(separatedBy: "\n")
            let steps = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("*") }.count
            var body: String
            if steps > 1 {
                var n = 0
                body = clean(lines.map { line in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("#") else { return t.hasPrefix("*") ? "• " + t.drop { $0 == "*" } : line }
                    n += 1
                    return "\(n). " + t.drop { $0 == "#" }
                }.joined(separator: "\n"), keepLines: true)
                if !heading.isEmpty { body = heading + ":\n" + body }
            } else {
                body = clean(fix)
                if body.isEmpty { body = description }
                if !heading.isEmpty { body = body.isEmpty ? heading : heading + ": " + body }
                body = String(body.prefix(200))
            }
            results.append(ModResult(
                id: "pcgw-\(results.count)",
                title: description.isEmpty ? "Fix" : description,
                detail: body,
                source: .pcgamingwiki,
                link: bestLink(in: fix),
                steps: max(steps, 1)))
            i = end
        }
        return results
    }

    static func matches(_ r: ModResult, query: String) -> Bool {
        let haystack = (r.title + " " + r.detail).lowercased()
        return query.lowercased().split(whereSeparator: { $0.isWhitespace }).allSatisfy { haystack.contains($0) }
    }

    private static func find(_ needle: String, in chars: [Character], from: Int) -> Int? {
        let n = Array(needle)
        guard chars.count >= n.count, from <= chars.count - n.count else { return nil }
        for s in from...(chars.count - n.count) {
            var ok = true
            for k in 0..<n.count where chars[s + k].lowercased() != String(n[k]) { ok = false; break }
            if ok { return s }
        }
        return nil
    }

    private static func closing(of start: Int, in chars: [Character]) -> Int? {
        var depth = 0
        var i = start
        while i < chars.count - 1 {
            if chars[i] == "{" && chars[i + 1] == "{" { depth += 1; i += 2 }
            else if chars[i] == "}" && chars[i + 1] == "}" {
                depth -= 1; i += 2
                if depth == 0 { return i }
            } else { i += 1 }
        }
        return nil
    }

    private static func parameters(of inner: String) -> [String: String] {
        let chars = Array(inner)
        var parts: [String] = []
        var current = ""
        var depth = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if (c == "{" && next == "{") || (c == "[" && next == "[") { depth += 1; current += String([c, c]); i += 2; continue }
            if (c == "}" && next == "}") || (c == "]" && next == "]") { depth -= 1; current += String([c, c]); i += 2; continue }
            if c == "|" && depth == 0 { parts.append(current); current = "" } else { current.append(c) }
            i += 1
        }
        parts.append(current)
        var out: [String: String] = [:]
        for p in parts.dropFirst() {
            guard let eq = p.firstIndex(of: "=") else { continue }
            let key = p[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if out[key] == nil { out[key] = String(p[p.index(after: eq)...]) }
        }
        return out
    }

    private static func nearestHeading(in chars: [Character], before index: Int) -> String {
        let lines = String(chars[0..<index]).components(separatedBy: "\n")
        for line in lines.reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count > 2, t.hasPrefix("="), t.hasSuffix("=") {
                return clean(t.trimmingCharacters(in: CharacterSet(charactersIn: "= ")))
            }
        }
        return ""
    }

    private static func bestLink(in raw: String) -> ModLink? {
        let links = regexMatches("https?://[^\\s\\]\\|\\}<>\\)]+", in: raw)
            .compactMap { classify($0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;'\""))) }
        return links.first(where: { if case .webPage = $0 { return false } else { return true } }) ?? links.first
    }

    private static func regexMatches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    private static func replace(_ pattern: String, in s: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static func clean(_ raw: String, keepLines: Bool = false) -> String {
        var s = raw
        s = replace("<ref[^>]*/>", in: s, with: "")
        s = replace("<ref[^>]*>.*?</ref>", in: s, with: "", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let templateRE = try? NSRegularExpression(pattern: "\\{\\{([^{}]*)\\}\\}")
        while let re = templateRE, let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let whole = Range(m.range, in: s), let body = Range(m.range(at: 1), in: s) {
            let pieces = s[body].split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let name = (pieces.first ?? "").lowercased()
            s.replaceSubrange(whole, with: templateText(name: name, args: Array(pieces.dropFirst())))
        }
        s = replace("\\[\\[[^\\]|]*\\|([^\\]]*)\\]\\]", in: s, with: "$1")
        s = replace("\\[\\[([^\\]]*)\\]\\]", in: s, with: "$1")
        s = replace("\\[https?://\\S+\\s+([^\\]]*)\\]", in: s, with: "$1")
        s = replace("\\[https?://[^\\]\\s]*\\]", in: s, with: "")
        s = replace("<[^>]*>", in: s, with: "")
        s = s.replacingOccurrences(of: "'''", with: "").replacingOccurrences(of: "''", with: "")
        for (entity, char) in [("&nbsp;", " "), ("&#124;", "|"), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\"")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        s = replace("^-{4,}\\s*$", in: s, with: "", options: [.anchorsMatchLines])
        s = replace("^[#*:;]+", in: s, with: "", options: [.anchorsMatchLines])
        s = replace("^\\s*notes?:?\\s*$", in: s, with: "", options: [.anchorsMatchLines, .caseInsensitive])
        let collapse = { (t: Substring) in t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        guard keepLines else { return collapse(Substring(s)) }
        return s.split(separator: "\n").map(collapse).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func templateText(name: String, args: [String]) -> String {
        switch name {
        case "code", "file", "folder": return args.joined(separator: ", ")
        case "key", "kbd": return args.joined(separator: "+")
        case "term", "note": return args.first ?? ""
        case "p": return args.first?.lowercased() == "game" ? "game folder" : (args.first ?? "")
        default: return ""
        }
    }

    static func githubResults(fromSearchJSON data: Data) -> [ModResult] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = item["full_name"] as? String else { return nil }
            let parts = name.split(separator: "/").map(String.init)
            guard parts.count == 2 else { return nil }
            return ModResult(id: "gh-" + name, title: name, detail: item["description"] as? String ?? "",
                             source: .github, link: .githubRepo(owner: parts[0], repo: parts[1]))
        }
    }

    static func pickAsset(_ names: [String], is64bit: Bool) -> AssetPick {
        let usable = names.filter { n in
            let l = n.lowercased()
            return fileExtensions.contains((l as NSString).pathExtension) && !l.contains("source") && !l.contains("src")
        }
        if usable.isEmpty { return .none }
        if usable.count == 1 { return .one(usable[0]) }
        let narrowed = usable.filter { n in
            let l = n.lowercased()
            if is64bit { return l.contains("x64") || l.contains("win64") || l.contains("64") }
            return !l.contains("64") && (l.contains("x86") || l.contains("win32") || l.contains("32"))
        }
        return narrowed.count == 1 ? .one(narrowed[0]) : .ask(usable.count == narrowed.count || narrowed.isEmpty ? usable : narrowed)
    }

    static func failureMessage(status: Int?) -> String {
        guard let status else { return "Couldn't reach GitHub. Check your internet connection." }
        if status == 403 || status == 429 { return "GitHub's limit for apps without an account was reached. Try again in a few minutes." }
        return "GitHub didn't answer (error \(status))."
    }

    static func webSearchURL(game: String, query: String) -> URL {
        var c = URLComponents(string: "https://duckduckgo.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: [game, query, "mod"].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " "))]
        return c.url!
    }
}
