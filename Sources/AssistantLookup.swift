import Foundation

enum AssistantLookup {
    enum GameMatch: Equatable {
        case one(UUID)
        case ambiguous([String])
        case none([String])
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    static func matchGame(_ query: String, in games: [(id: UUID, name: String)]) -> GameMatch {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: q), games.contains(where: { $0.id == id }) { return .one(id) }
        let nq = normalized(q)
        guard !nq.isEmpty else { return .none(capped(games.map(\.name), max: 20)) }
        func listed(_ found: [(id: UUID, name: String)]) -> [String] {
            found.map { f in found.filter { $0.name == f.name }.count > 1 ? "\(f.name) (id \(f.id.uuidString))" : f.name }
        }
        let exact = games.filter { normalized($0.name) == nq }
        if exact.count == 1 { return .one(exact[0].id) }
        if exact.count > 1 { return .ambiguous(listed(exact)) }
        let containing = games.filter { normalized($0.name).contains(nq) }
        if containing.count == 1 { return .one(containing[0].id) }
        if containing.count > 1 { return .ambiguous(capped(listed(containing), max: 20)) }
        let words = Set(nq.split(separator: " ").filter { $0.count >= 3 })
        let close = games.filter { g in normalized(g.name).split(separator: " ").contains { words.contains($0) } }
        return .none(capped((close.isEmpty ? games : close).map(\.name), max: 20))
    }

    static func requestedPath(_ path: String, gameFolder: String, driveC: String, home: String, user: String,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        unhidingUser(builtPath(path, gameFolder: gameFolder, driveC: driveC, home: home, user: user), user: user, exists: exists)
    }

    static func unhidingUser(_ path: String, user: String, exists: (String) -> Bool) -> String {
        guard user.count >= 3, user != "user", !exists(path),
              let re = try? NSRegularExpression(pattern: #"\buser\b"#) else { return path }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var built = parts[0]
        for part in parts.dropFirst() {
            let asIs = built + "/" + part
            let range = NSRange(part.startIndex..., in: part)
            guard re.firstMatch(in: part, range: range) != nil, !exists(asIs) else { built = asIs; continue }
            let named = built + "/" + re.stringByReplacingMatches(in: part, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: user))
            built = exists(named) ? named : asIs
        }
        return built
    }

    private static func builtPath(_ path: String, gameFolder: String, driveC: String, home: String, user: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        var parts = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let first = parts.first, first.count == 2, first.lowercased() == "c:" {
            parts.removeFirst()
            if parts.count >= 2, parts[0].lowercased() == "users", parts[1].lowercased() == "user" { parts[1] = user }
            return ([driveC] + parts).joined(separator: "/")
        }
        if p == "~" || p.hasPrefix("~/") { p = home + p.dropFirst() }
        if p.hasPrefix("/") {
            if user != "user" {
                p = p.replacingOccurrences(of: "/drive_c/users/user/", with: "/drive_c/users/\(user)/", options: .caseInsensitive)
            }
            return p
        }
        return gameFolder + "/" + p
    }

    enum PathAccess: Equatable {
        case inside(URL)
        case linkedOutside(URL)
        case refused
    }

    static func access(_ path: String, roots: [URL], userFolders: URL, home: String) -> PathAccess {
        let asked = URL(fileURLWithPath: path).standardizedFileURL
        let real = asked.resolvingSymlinksInPath()
        let realHome = resolved(URL(fileURLWithPath: home))
        let resolvedRoots = roots.map(resolved)
        let bases = roots.map { $0.standardizedFileURL.path } + resolvedRoots
            + [userFolders.standardizedFileURL.path, URL(fileURLWithPath: home).standardizedFileURL.path, realHome]
        if let closest = bases.filter({ isInside(asked.path, $0) }).max(by: { $0.count < $1.count }),
           hidden(asked.path, below: closest) { return .refused }
        if let own = resolvedRoots.first(where: { isInside(real.path, $0) && !isPersonal($0, realHome: realHome) }) {
            return hidden(real.path, below: own) ? .refused : .inside(real)
        }
        let personal = resolvedRoots.contains { isInside(real.path, $0) }
        let linked = isInside(asked.path, userFolders.standardizedFileURL.path) && !hidden(asked.path, below: userFolders.standardizedFileURL.path)
        guard personal || linked, isInside(real.path, realHome), !hidden(real.path, below: realHome) else { return .refused }
        return .linkedOutside(real)
    }

    static func isPersonalFolder(_ folder: URL, home: String) -> Bool {
        isPersonal(resolved(folder), realHome: resolved(URL(fileURLWithPath: home)))
    }

    private static func isPersonal(_ folder: String, realHome: String) -> Bool {
        isInside(realHome, folder) || (folder as NSString).deletingLastPathComponent == realHome
    }

    private static func resolved(_ u: URL) -> String { u.standardizedFileURL.resolvingSymlinksInPath().path }

    static func hidden(_ path: String, below base: String) -> Bool {
        path.dropFirst(base.count).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    static let plainReadExtensions: Set<String> = ["ini", "cfg", "xml", "json", "txt", "conf", "toml", "yaml", "yml",
                                                   "properties", "log"]
    private static let launcherFolders: Set<String> = ["steam", "epicgameslauncher", "epic games", "battle.net", "origin",
                                                        "ea desktop", "electronic arts", "ubisoft game launcher", "gog.com",
                                                        "gog galaxy"]

    static func isLauncherFile(_ path: String, bases: [String]) -> Bool {
        let base = bases.filter { isInside(path, $0) }.max { $0.count < $1.count } ?? ""
        let parts = path.dropFirst(base.count).split(whereSeparator: { $0 == "/" || $0 == "\\" }).map { $0.lowercased() }
        if let last = parts.last, (last as NSString).pathExtension == "vdf" { return true }
        if parts.dropLast().contains(where: launcherFolders.contains) { return true }
        return parts.indices.dropLast(2).contains { parts[$0] == "rockstar games" && parts[$0 + 1] == "launcher" }
    }

    static func plainReadCovers(_ path: String, bases: [String]) -> Bool {
        plainReadExtensions.contains((path as NSString).pathExtension.lowercased()) && !isLauncherFile(path, bases: bases)
    }

    static func walksInto(folderLevel: Int) -> Bool { folderLevel <= 5 }

    private static func isInside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func text(of data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if data.contains(0) { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    static func capped(_ items: [String], max: Int) -> [String] {
        items.count <= max ? items : Array(items.prefix(max)) + ["… and \(items.count - max) more"]
    }

    static func clipped(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + "\n… (\(text.count - maxChars) more characters cut)"
    }
}
