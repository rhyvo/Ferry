import Foundation

enum InstalledPrograms {
    struct Snapshot: Equatable {
        var shortcuts: Set<String> = []
        var programFolders: Set<String> = []
    }

    struct Candidate: Equatable {
        let name: String
        let exe: URL
    }

    static let startMenu = "Microsoft/Windows/Start Menu/Programs"
    static let programFiles = ["Program Files", "Program Files (x86)"]

    static func snapshot(driveC: URL) -> Snapshot {
        let fm = FileManager.default
        var snap = Snapshot()
        let users = (try? fm.contentsOfDirectory(atPath: driveC.appendingPathComponent("users").path)) ?? []
        let menus = ["ProgramData/" + startMenu] + users.map { "users/\($0)/AppData/Roaming/" + startMenu }
        for menu in menus {
            guard let walk = fm.enumerator(atPath: driveC.appendingPathComponent(menu).path) else { continue }
            for case let sub as String in walk where sub.lowercased().hasSuffix(".lnk") {
                snap.shortcuts.insert(menu + "/" + sub)
            }
        }
        for top in programFiles {
            let dir = driveC.appendingPathComponent(top)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDir), isDir.boolValue {
                    snap.programFolders.insert(top + "/" + name)
                }
            }
        }
        return snap
    }

    static func candidates(before: Snapshot, after: Snapshot, driveC: URL, installer: URL,
                           productName: (URL) -> String?) -> [Candidate] {
        let fm = FileManager.default
        let installerPath = installer.standardizedFileURL.path.lowercased()
        func usable(_ exe: URL, _ name: String) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: exe.path, isDirectory: &isDir) && !isDir.boolValue
                && exe.standardizedFileURL.path.lowercased() != installerPath
                && !isExcluded(name) && !isExcluded(exe.deletingPathExtension().lastPathComponent)
                && !looksLikeInstaller(exe)
        }

        var found: [Candidate] = []
        for path in after.shortcuts.subtracting(before.shortcuts).sorted(by: { $0.lowercased() < $1.lowercased() }) {
            let shortcut = driveC.appendingPathComponent(path)
            let name = shortcut.deletingPathExtension().lastPathComponent
            guard let data = fm.contents(atPath: shortcut.path), let target = lnkTarget(data),
                  let exe = macURL(target, driveC: driveC), usable(exe, name) else { continue }
            if let i = found.firstIndex(where: { $0.exe.path.lowercased() == exe.path.lowercased() }) {
                if name.count < found[i].name.count { found[i] = Candidate(name: name, exe: exe) }
            } else {
                found.append(Candidate(name: name, exe: exe))
            }
        }
        if found.isEmpty {
            let folders = after.programFolders.subtracting(before.programFolders).sorted {
                ($0.hasPrefix("Program Files (x86)/") ? 1 : 0, $0.lowercased()) < ($1.hasPrefix("Program Files (x86)/") ? 1 : 0, $1.lowercased())
            }
            for folder in folders {
                let dir = driveC.appendingPathComponent(folder)
                let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted { $0.lowercased() < $1.lowercased() }
                for file in files where file.lowercased().hasSuffix(".exe") {
                    let exe = dir.appendingPathComponent(file)
                    guard usable(exe, file) else { continue }
                    found.append(Candidate(name: productName(exe) ?? dir.lastPathComponent, exe: exe))
                }
            }
        }
        return Array(found.prefix(4))
    }

    static func looksLikeInstaller(_ file: URL) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(file.path)|\(date)|\((attrs?[.size] as? NSNumber)?.int64Value ?? -1)"
        cacheLock.lock()
        let known = installerCache[key]
        cacheLock.unlock()
        if let known { return known }
        let answer = ModLayout.looksLikeInstaller(file)
        cacheLock.lock()
        installerCache[key] = answer
        cacheLock.unlock()
        return answer
    }
    private static let cacheLock = NSLock()
    private static var installerCache: [String: Bool] = [:]

    static let skipWords: Set<String> = ["unins", "uninst", "uninstall", "uninstaller", "setup", "install", "installer",
                                         "update", "updater", "report", "reporter", "helper", "readme", "help", "website"]
    static let skipEndings = ["setup", "update", "updater", "reporter", "handler"]

    static func isExcluded(_ name: String) -> Bool {
        let words = words(of: name)
        let pairs = zip(words, words.dropFirst()).map { $0 + $1 }
        return (words + pairs).contains { skipWords.contains($0) } || words.contains { word in
            word.hasPrefix("unins") || (word.hasPrefix("crash") && word != "crash") || skipEndings.contains { word.hasSuffix($0) }
        }
    }

    static func words(of name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character? = nil
        for c in name {
            if " -_.".contains(c) {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                if let p = previous, !current.isEmpty,
                   (p.isLowercase && c.isUppercase) || (p.isLetter && c.isNumber) || (p.isNumber && c.isLetter) {
                    words.append(current)
                    current = ""
                }
                current.append(c)
            }
            previous = c
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    static func lnkTarget(_ data: Data) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[Cc]:\\[^\x00-\x1f"*:<>?|]*?\.[Ee][Xx][Ee]"#) else { return nil }
        func first(_ text: String) -> (location: Int, path: String)? {
            let ns = text as NSString
            guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (m.range.location, ns.substring(with: m.range))
        }
        var best: (offset: Int, path: String)? = nil
        func consider(_ hit: (location: Int, path: String)?, _ offset: (Int) -> Int) {
            if let hit, best == nil || offset(hit.location) < best!.offset { best = (offset(hit.location), hit.path) }
        }
        let bytes = [UInt8](data)
        consider(first(String(decoding: bytes.map { UInt16($0) }, as: UTF16.self)), { $0 })
        for align in 0...1 where bytes.count > align + 1 {
            let units = stride(from: align, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            consider(first(String(decoding: units, as: UTF16.self)), { $0 * 2 + align })
        }
        return best?.path
    }

    static func macURL(_ windowsPath: String, driveC: URL) -> URL? {
        guard windowsPath.lowercased().hasPrefix("c:\\"), !windowsPath.lowercased().hasPrefix("c:\\windows\\") else { return nil }
        let parts = windowsPath.dropFirst(3).split(separator: "\\").map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return parts.reduce(driveC) { $0.appendingPathComponent($1) }
    }
}
