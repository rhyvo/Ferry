import Foundation

enum ModLayout {
    static let proxyDLLs: Set<String> = [
        "dinput8", "dinput", "d3d8", "d3d9", "d3d10", "d3d10_1", "d3d11", "d3d12", "dxgi",
        "ddraw", "dsound", "winmm", "version", "xinput1_3", "xinput1_4", "xinput9_1_0",
        "winhttp", "wininet", "opengl32",
    ]

    private static func entries(_ dir: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0 != "__MACOSX" && !$0.hasPrefix(".") }.map { dir.appendingPathComponent($0) }
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func samePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path.lowercased() == b.standardizedFileURL.path.lowercased()
    }

    static func contentRoot(_ unpacked: URL, game: GameFolders) -> URL {
        let gameNames = Set((entries(game.root.standardizedFileURL) + entries(game.exeFolder.standardizedFileURL)).map { $0.lastPathComponent.lowercased() })
        var cur = unpacked.standardizedFileURL
        while true {
            let e = entries(cur)
            guard e.count == 1, isFolder(e[0]), !gameNames.contains(e[0].lastPathComponent.lowercased()) else { return cur }
            cur = e[0].standardizedFileURL
        }
    }

    static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    static func programName(_ plan: ModPlan) -> String? {
        plan.programExe.map { safeName($0.deletingPathExtension().lastPathComponent) }
    }

    static func riskyRootReason(_ root: URL) -> String? {
        let path = root.standardizedFileURL.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let named: [(URL, String)] = [(home, "your home folder"), (home.appendingPathComponent("Downloads"), "your Downloads folder"),
                                      (home.appendingPathComponent("Desktop"), "your Desktop"), (home.appendingPathComponent("Documents"), "your Documents folder"),
                                      (URL(fileURLWithPath: "/Applications"), "the Applications folder")]
        if let hit = named.first(where: { $0.0.path.lowercased() == path }) {
            return "The game's folder is \(hit.1), so Ferry won't add a mod's files there."
        }
        let parts = root.standardizedFileURL.pathComponents
        let isVolumeRoot = parts.count == 1 || (parts.count == 3 && parts[1] == "Volumes")
            || (try? root.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true
        return isVolumeRoot ? "The game sits at the top of a drive rather than in a folder of its own, so Ferry won't add a mod's files there." : nil
    }

    private static func isProxyDLL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "dll" && proxyDLLs.contains(url.deletingPathExtension().lastPathComponent.lowercased())
    }

    static func dropInPlan(_ modRoot: URL, game: GameFolders) -> ModPlan? {
        let root = modRoot.standardizedFileURL
        let top = entries(root).filter { !isFolder($0) }
        let proxies = top.filter(isProxyDLL)
        guard top.contains(where: { $0.pathExtension.lowercased() == "asi" }) || !proxies.isEmpty else { return nil }

        let dest = game.exeFolder.standardizedFileURL
        var copies: [ModCopy] = []
        func walk(_ dir: URL, _ rel: [String]) {
            for e in entries(dir).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let r = rel + [e.lastPathComponent]
                if isFolder(e) { walk(e, r) }
                else { copies.append(ModCopy(from: e, to: r.reduce(dest) { $0.appendingPathComponent($1) })) }
            }
        }
        walk(root, [])

        let overrides = proxies.map { $0.deletingPathExtension().lastPathComponent.lowercased() + "=n,b" }.sorted()
        return ModPlan(recipe: .dropIn, copies: copies, overrides: overrides, programExe: nil)
    }

    private static let rootFolderNames: Set<String> = ["binaries", "bin", "win32", "win64", "x64", "x86", "system", "exe"]

    static func gameRoot(exeFolder: URL) -> URL {
        var cur = exeFolder
        for _ in 0..<3 where rootFolderNames.contains(cur.lastPathComponent.lowercased()) {
            cur = cur.deletingLastPathComponent()
        }
        return cur
    }

    static func isModInstaller(_ file: URL) -> Bool {
        ["exe", "msi"].contains(file.pathExtension.lowercased()) && looksLikeInstaller(file)
    }

    static func looksLikeInstaller(_ file: URL) -> Bool {
        if file.pathExtension.lowercased() == "msi" { return true }
        let name = file.deletingPathExtension().lastPathComponent.lowercased()
        if name.contains("setup") || name.contains("install") { return true }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 32_000_000) else { return false }
        return ["Inno Setup", "Nullsoft Install", "InstallShield"].contains { bytes.range(of: Data($0.utf8)) != nil }
    }

    static func isPE64(_ file: URL) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64), head.count == 64, head[0] == 0x4D, head[1] == 0x5A else { return nil }
        let offset = UInt64(head[0x3c]) | UInt64(head[0x3d]) << 8 | UInt64(head[0x3e]) << 16 | UInt64(head[0x3f]) << 24
        guard (try? handle.seek(toOffset: offset)) != nil, let pe = try? handle.read(upToCount: 6), pe.count == 6,
              pe[0] == 0x50, pe[1] == 0x45, pe[2] == 0, pe[3] == 0 else { return nil }
        switch UInt16(pe[4]) | UInt16(pe[5]) << 8 {
        case 0x8664: return true
        case 0x14c: return false
        default: return nil
        }
    }

    enum VariantPick: Equatable { case one(URL); case ask([URL]); case none }

    private static let docExtensions: Set<String> = ["txt", "md", "pdf", "url", "html"]
    private static let codeExtensions: Set<String> = ["exe", "dll", "asi"]

    static func pickVariant(_ modRoot: URL, is64bit: Bool) -> VariantPick {
        let top = entries(modRoot.standardizedFileURL)
        let folders = top.filter(isFolder).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let files = top.filter { !isFolder($0) }
        guard folders.count >= 2, files.allSatisfy({ docExtensions.contains($0.pathExtension.lowercased()) }) else { return .none }

        func words(_ folder: URL) -> [String] {
            folder.lastPathComponent.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        func bitness(_ folder: URL) -> Bool? {
            let w = words(folder)
            if w.contains(where: { ["x64", "win64", "64"].contains($0) }) { return true }
            if w.contains(where: { ["x86", "win32", "32"].contains($0) }) { return false }
            return nil
        }
        let optionWords: Set<String> = ["option", "version", "variant", "alternative", "alt", "choice", "type"]

        if folders.contains(where: { bitness($0) != nil }) {
            let matches = folders.filter { bitness($0) == is64bit }
            return matches.count == 1 ? .one(matches[0]) : .ask(folders)
        }
        if folders.contains(where: { words($0).contains(where: optionWords.contains) }) { return .ask(folders) }
        return .none
    }

    private static func allFiles(_ dir: URL) -> [(url: URL, rel: [String])] {
        var out: [(URL, [String])] = []
        func walk(_ d: URL, _ rel: [String]) {
            for e in entries(d).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if isFolder(e) { walk(e, rel + [e.lastPathComponent]) } else { out.append((e, rel + [e.lastPathComponent])) }
            }
        }
        walk(dir, [])
        return out
    }

    static func plan(_ modRoot: URL, game: GameFolders) -> ModPlan? {
        let root = modRoot.standardizedFileURL
        if let p = dropInPlan(root, game: game) { return p }
        guard riskyRootReason(game.root) == nil else { return nil }

        let files = allFiles(root)
        let gameRoot = game.root.standardizedFileURL
        let exeFolder = game.exeFolder.standardizedFileURL

        let ext = { (u: URL) in u.pathExtension.lowercased() }

        let rootNames = Set(entries(gameRoot).map { $0.lastPathComponent.lowercased() })
        let existing = rootNames.union(entries(exeFolder).map { $0.lastPathComponent.lowercased() })
        let exes = files.filter { ext($0.url) == "exe" && !looksLikeInstaller($0.url) && !existing.contains($0.url.lastPathComponent.lowercased()) }
        if let main = exes.max(by: { fileSize($0.url) < fileSize($1.url) }) {
            let clashes = entries(root).contains { rootNames.contains($0.lastPathComponent.lowercased()) }
            let name = safeName(main.url.deletingPathExtension().lastPathComponent)
            let dest = clashes ? besideFolder(gameRoot: gameRoot, program: name) : gameRoot
            let copies = files.map { ModCopy(from: $0.url, to: $0.rel.reduce(dest) { $0.appendingPathComponent($1) }) }
            return ModPlan(recipe: .program, copies: copies, overrides: [], programExe: main.rel.reduce(dest) { $0.appendingPathComponent($1) })
        }

        let topNames = Set(entries(root).map { $0.lastPathComponent.lowercased() })
        func hasTopLevel(in base: URL) -> Bool { entries(base).contains { topNames.contains($0.lastPathComponent.lowercased()) } }
        let mirrorBase = hasTopLevel(in: gameRoot) ? gameRoot : (hasTopLevel(in: exeFolder) ? exeFolder : nil)
        if let base = mirrorBase {
            let copies = files.map { ModCopy(from: $0.url, to: $0.rel.reduce(base) { $0.appendingPathComponent($1) }) }
            let overrides = Set(copies.filter { isProxyDLL($0.to) && samePath($0.to.deletingLastPathComponent(), exeFolder) }
                .map { $0.to.deletingPathExtension().lastPathComponent.lowercased() + "=n,b" }).sorted()
            return ModPlan(recipe: .mirror, copies: copies, overrides: overrides, programExe: nil)
        }

        let data = files.filter { !docExtensions.contains(ext($0.url)) }
        if !data.isEmpty, !files.contains(where: { codeExtensions.contains(ext($0.url)) }) {
            var counts: [String: [URL: Int]] = [:]
            func scan(_ dir: URL, _ depth: Int) {
                for e in entries(dir) {
                    if isFolder(e) { if depth < 3 { scan(e, depth + 1) } }
                    else { counts[ext(e), default: [:]][dir, default: 0] += 1 }
                }
            }
            scan(gameRoot, 0)
            let homes = data.map { f in
                counts[ext(f.url)]?.sorted { ($0.value, $1.key.path) > ($1.value, $0.key.path) }.first?.key
            }
            if !homes.contains(where: { $0 == nil }) {
                let copies = zip(data, homes).map { ModCopy(from: $0.url, to: $1!.appendingPathComponent($0.url.lastPathComponent)) }
                guard Set(copies.map { $0.to.path.lowercased() }).count == copies.count else { return nil }
                return ModPlan(recipe: .dataFiles, copies: copies, overrides: [], programExe: nil)
            }
        }

        return nil
    }

    static func isZip(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    static func packagePlan(archive: URL, modRoot: URL, game: GameFolders) -> ModPlan? {
        guard riskyRootReason(game.root) == nil, isZip(archive),
              !allFiles(modRoot.standardizedFileURL).contains(where: { codeExtensions.contains($0.url.pathExtension.lowercased()) })
        else { return nil }
        var groups: [String: [URL]] = [:]
        func scan(_ dir: URL, _ depth: Int) {
            for e in entries(dir) {
                if isFolder(e) { if depth < 3 { scan(e, depth + 1) } }
                else if !e.pathExtension.isEmpty { groups[dir.path + "|" + e.pathExtension.lowercased(), default: []].append(e) }
            }
        }
        scan(game.root.standardizedFileURL, 0)
        let best = groups.compactMap { _, files -> (folder: URL, ext: String, count: Int)? in
            guard files.count >= 2 else { return nil }
            let zips = files.filter(isZip).count
            return zips >= 2 ? (files[0].deletingLastPathComponent(), files[0].pathExtension.lowercased(), zips) : nil
        }.max { ($0.count, $1.folder.path, $1.ext) < ($1.count, $0.folder.path, $0.ext) }
        guard let best else { return nil }
        let name = safeName(archive.deletingPathExtension().lastPathComponent) + "." + best.ext
        return ModPlan(recipe: .dataFiles, copies: [ModCopy(from: archive, to: best.folder.appendingPathComponent(name))], overrides: [], programExe: nil)
    }

    static func isInside(_ path: URL, _ folder: URL) -> Bool {
        let p = path.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let f = folder.standardizedFileURL.pathComponents.map { $0.lowercased() }
        return p.count > f.count && Array(p.prefix(f.count)) == f
    }

    static func escapes(_ root: URL) -> Bool {
        let fm = FileManager.default
        let base = root.standardizedFileURL
        func bad(_ dir: URL) -> Bool {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return true }
            for name in names {
                let e = dir.appendingPathComponent(name)
                guard isInside(e, base), let type = (try? fm.attributesOfItem(atPath: e.path))?[.type] as? FileAttributeType,
                      type != .typeSymbolicLink else { return true }
                if type == .typeDirectory, bad(e) { return true }
            }
            return false
        }
        return bad(base)
    }

    static func besideFolder(gameRoot: URL, program name: String) -> URL {
        gameRoot.deletingLastPathComponent().appendingPathComponent("\(safeName(gameRoot.lastPathComponent)) (\(name))")
    }

    static func allowedFolders(_ plan: ModPlan, game: GameFolders) -> [URL] {
        let root = game.root.standardizedFileURL
        guard plan.recipe == .program, let name = programName(plan) else { return [root] }
        return [root, besideFolder(gameRoot: root, program: name)]
    }

    static func sharesGameFolder(_ exe: URL, with gameExe: URL) -> Bool {
        isInside(exe, gameRoot(exeFolder: gameExe.deletingLastPathComponent()))
    }

    static func blocksMods(entry: UUID, exe: URL, game: UUID, gameExe: URL, modPrograms: [UUID]) -> Bool {
        entry == game || modPrograms.contains(entry) || sharesGameFolder(exe, with: gameExe)
    }

    static func replaces(_ plan: ModPlan, anyOf exes: [URL]) -> Int? {
        exes.firstIndex { exe in plan.copies.contains { samePath($0.to, exe) } }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
