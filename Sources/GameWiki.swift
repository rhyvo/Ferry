import Foundation

enum PEVersionInfo {
    static func string(_ key: String, in exe: URL) -> String? {
        guard let block = versionResource(in: exe) else { return nil }
        let bytes = [UInt8](block)
        let needle = Array((key + "\0").utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        guard needle.count < bytes.count else { return nil }
        var i = 0
        while i <= bytes.count - needle.count {
            if bytes[i] == needle[0], Array(bytes[i..<(i + needle.count)]) == needle {
                var at = i + needle.count
                while at + 1 < bytes.count, bytes[at] == 0, bytes[at + 1] == 0 { at += 2 }
                var units: [UInt16] = []
                while at + 1 < bytes.count {
                    let unit = UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
                    if unit == 0 || units.count > 200 { break }
                    units.append(unit)
                    at += 2
                }
                let value = String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            i += 2
        }
        return nil
    }

    private static func versionResource(in exe: URL) -> Data? {
        guard let data = try? Data(contentsOf: exe, options: .alwaysMapped), data.count > 64 else { return nil }
        let base = data.startIndex
        func u16(_ o: Int) -> Int? { o >= 0 && o + 2 <= data.count ? Int(data[base + o]) | Int(data[base + o + 1]) << 8 : nil }
        func u32(_ o: Int) -> Int? {
            guard let lo = u16(o), let hi = u16(o + 2) else { return nil }
            return lo | hi << 16
        }
        guard u16(0) == 0x5A4D, let pe = u32(0x3C), u32(pe) == 0x0000_4550,
              let sectionCount = u16(pe + 6), let optionalSize = u16(pe + 20), let magic = u16(pe + 24) else { return nil }
        let opt = pe + 24
        guard let resourceRVA = u32(opt + (magic == 0x20B ? 112 : 96) + 16), resourceRVA != 0 else { return nil }
        var sections: [(va: Int, size: Int, raw: Int)] = []
        for i in 0..<min(sectionCount, 96) {
            let s = opt + optionalSize + i * 40
            guard let vsize = u32(s + 8), let va = u32(s + 12), let rawSize = u32(s + 16), let raw = u32(s + 20) else { break }
            sections.append((va, vsize > 0 ? vsize : rawSize, raw))
        }
        func offset(_ rva: Int) -> Int? {
            for s in sections where rva >= s.va && rva < s.va + s.size { return rva - s.va + s.raw }
            return nil
        }
        guard let root = offset(resourceRVA) else { return nil }
        func entries(_ dir: Int) -> [(id: Int?, target: Int, isDir: Bool)] {
            guard let named = u16(dir + 12), let numbered = u16(dir + 14) else { return [] }
            return (0..<min(named + numbered, 4096)).compactMap { i in
                guard let name = u32(dir + 16 + i * 8), let target = u32(dir + 20 + i * 8) else { return nil }
                return (name & 0x8000_0000 == 0 ? name : nil, target & 0x7FFF_FFFF, target & 0x8000_0000 != 0)
            }
        }
        var node = entries(root).first { $0.id == 16 && $0.isDir }
        for _ in 0..<3 {
            guard let current = node else { return nil }
            if !current.isDir {
                guard let rva = u32(root + current.target), let size = u32(root + current.target + 4),
                      let start = offset(rva), size > 0, start + size <= data.count else { return nil }
                return data.subdata(in: (base + start)..<(base + start + size))
            }
            node = entries(root + current.target).first
        }
        return nil
    }
}

enum GameWiki {
    struct Info: Codable, Equatable {
        var page: String
        var graphics: GraphicsAPI?
        var antiCheat: String?

        var url: String {
            let title = page.replacingOccurrences(of: " ", with: "_")
            return "https://www.pcgamingwiki.com/wiki/" + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)
        }
    }

    static let defaultsKey = "onlineGameLookup"
    static var enabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    private static let api = "https://www.pcgamingwiki.com/w/api.php"
    private static let cacheURL = Paths.root.appendingPathComponent("game-lookups.json")

    private struct Entry: Codable {
        var info: Info?
        var date: Date
    }

    static func names(for exe: URL) -> [String] {
        let folder = exe.deletingLastPathComponent()
        let raw = [PEVersionInfo.string("ProductName", in: exe), PEVersionInfo.string("FileDescription", in: exe),
                   Naming.friendlyName(for: exe), cleanFolderName(folder.lastPathComponent),
                   cleanFolderName(folder.deletingLastPathComponent().lastPathComponent)]
        var out: [String] = []
        for name in raw.compactMap({ $0 }) {
            let words = comparable(name)
            if words.count >= 3, !out.contains(where: { comparable($0) == words }) { out.append(name) }
        }
        return out
    }

    static func cleanFolderName(_ name: String) -> String? {
        let words = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
            .filter { !$0.contains(".") && $0.range(of: #"^[vV]\d"#, options: .regularExpression) == nil }
        let cleaned = words.joined(separator: " ")
        return cleaned.isEmpty || ["Games", "Downloads", "Desktop", "Applications"].contains(cleaned) ? nil : cleaned
    }

    static func spacedOut(_ name: String) -> String {
        var out = ""
        var previous: Character? = nil
        for ch in name {
            if let p = previous, ch != " ", p != " ",
               (p.isLowercase && ch.isUppercase) || (p.isLetter && ch.isNumber) || (p.isNumber && ch.isLetter) {
                out.append(" ")
            }
            out.append(ch)
            previous = ch
        }
        return out
    }

    static func comparable(_ name: String) -> String {
        var s = name.lowercased()
        for mark in ["(r)", "(tm)", "®", "™", "©"] { s = s.replacingOccurrences(of: mark, with: "") }
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func lookup(exe: URL) async -> Info? {
        guard enabled else { return nil }
        let candidates = names(for: exe)
        guard let key = candidates.first.map(comparable), !key.isEmpty else { return nil }

        var cache = loadCache()
        if let hit = cache[key] {
            if hit.info != nil || Date().timeIntervalSince(hit.date) < 14 * 86_400 { return hit.info }
        }
        var found: Info? = nil
        for name in candidates {
            if let page = await matchingPage(for: name), let info = await facts(page: page) {
                found = info
                break
            }
        }
        cache[key] = Entry(info: found, date: Date())
        saveCache(cache)
        return found
    }

    private static func get(_ items: [URLQueryItem]) async -> [String: Any]? {
        var parts = URLComponents(string: api)!
        parts.queryItems = items + [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "formatversion", value: "2")]
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Ferry (macOS game launcher)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func matchingPage(for name: String) async -> String? {
        guard let json = await get([
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: spacedOut(name)), URLQueryItem(name: "srlimit", value: "5"),
            URLQueryItem(name: "srnamespace", value: "0"),
        ]), let results = (json["query"] as? [String: Any])?["search"] as? [[String: Any]] else { return nil }
        let wanted = comparable(name)
        return results.compactMap { $0["title"] as? String }.first { comparable($0) == wanted }
    }

    private static func pageText(_ page: String) async -> (page: String, text: String)? {
        guard let json = await get([
            URLQueryItem(name: "action", value: "parse"), URLQueryItem(name: "page", value: page),
            URLQueryItem(name: "prop", value: "wikitext"), URLQueryItem(name: "redirects", value: "1"),
        ]), let parse = json["parse"] as? [String: Any], let text = parse["wikitext"] as? String else { return nil }
        return ((parse["title"] as? String) ?? page, text)
    }

    private static func facts(page: String) async -> Info? {
        guard let found = await pageText(page) else { return nil }
        return Info(page: found.page, graphics: graphics(from: found.text), antiCheat: antiCheat(from: found.text))
    }

    @MainActor private static var pages: [String: (page: String, text: String)] = [:]

    @MainActor static func wikitext(exe: URL) async -> (page: String, text: String)? {
        if let hit = pages[exe.path] { return hit }
        for name in names(for: exe) {
            if let page = await matchingPage(for: name), let found = await pageText(page) {
                pages[exe.path] = found
                return found
            }
        }
        return nil
    }

    private static func fields(of template: String, in text: String) -> [String: String] {
        guard let start = text.range(of: "{{" + template, options: .caseInsensitive) else { return [:] }
        var out: [String: String] = [:]
        for line in text[start.upperBound...].split(separator: "\n").prefix(200) {
            if line.hasPrefix("}}") { break }
            guard line.hasPrefix("|"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.index(after: line.startIndex)..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: eq)...])
            value = value.replacingOccurrences(of: #"<ref[^>]*/>|<ref[^>]*>.*?</ref>|\{\{[^}]*\}\}|\[\[|\]\]"#, with: "", options: .regularExpression)
            out[key] = value.trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    private static func listed(_ value: String?) -> Bool {
        guard let v = value?.lowercased(), !v.isEmpty else { return false }
        return !["false", "unknown", "n/a", "na", "no"].contains(v)
    }

    static func graphics(from text: String) -> GraphicsAPI? {
        let api = fields(of: "API", in: text)
        if let d3d = api["direct3d versions"], listed(d3d) {
            let versions = d3d.split(whereSeparator: { !$0.isNumber && $0 != "." })
                .compactMap { Double($0) }.map { Int($0) }
            switch versions.max() ?? 0 {
            case 12...: return .dx12
            case 11: return .dx11
            case 10: return .dx10
            case 9: return .dx9
            case 8: return .dx8
            default: break
            }
        }
        if listed(api["vulkan versions"]) { return .vulkan }
        if listed(api["opengl versions"]) { return .opengl }
        return nil
    }

    static func antiCheat(from text: String) -> String? {
        let value = fields(of: "Middleware", in: text)["anticheat"]
        return listed(value) ? value : nil
    }

    private static func loadCache() -> [String: Entry] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func saveCache(_ cache: [String: Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }
}

extension Analyzer {
    static func analyzeWithLookup(exe: URL, root: URL, candidates: [URL], rosetta: Bool) async -> AnalysisReport {
        let report = analyze(exe: exe, root: root, candidates: candidates, rosetta: rosetta)
        guard report.graphics == .unknown, exe.pathExtension.lowercased() == "exe", !report.isInstaller,
              let info = await GameWiki.lookup(exe: exe) else { return report }
        var better = info.graphics.map { analyze(exe: exe, root: root, candidates: candidates, rosetta: rosetta, knownGraphics: $0) } ?? report
        if let graphics = info.graphics {
            better.reasons.insert("Graphics: \(graphics.label), from PCGamingWiki's page for \(info.page) (\(info.url)). Ferry couldn't tell from the program itself.", at: 0)
        }
        if let antiCheat = info.antiCheat, !better.findings.contains(where: { $0.text.lowercased().contains("anti-cheat") }) {
            better.findings.append(Finding(level: .warning, text: "PCGamingWiki lists \(antiCheat) for \(info.page). Anti-cheat usually blocks online play under Wine on Mac; single-player or offline modes may still work."))
        }
        return better
    }
}
