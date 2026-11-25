import AppKit
import Foundation

enum ModPreparation {
    case ready(plan: ModPlan, staging: URL, name: String, source: String, reviewed: Bool)
    case installer(file: URL, name: String, source: String)
    case chooseVariant([URL], file: URL, staging: URL, name: String, source: String, reviewed: Bool, repoPage: URL?)
    case chooseAsset([GHAsset], repo: String)
    case manual(file: URL, reason: String)
    case browser(url: URL, reason: String)
}

struct ModWebPage: LocalizedError {
    let url: URL
    static let reason = "That link leads to a web page, not a download, so it opens in your browser."
    var errorDescription: String? { Self.reason }
}

extension AppModel {
    var modWorkRoot: URL { Paths.cache.appendingPathComponent("mods", isDirectory: true) }

    private func newModWorkFolder() throws -> URL {
        let dir = modWorkRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func modWorkFolder(of url: URL) -> URL? {
        let root = modWorkRoot.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > root.count, Array(parts.prefix(root.count)) == root else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(parts.prefix(root.count + 1))), isDirectory: true)
    }

    func discardModPreparation(_ prep: ModPreparation) {
        let urls: [URL]
        switch prep {
        case .ready(_, let staging, _, _, _): urls = [staging]
        case .installer(let file, _, _): urls = [file]
        case .chooseVariant(_, let file, let staging, _, _, _, _): urls = [file, staging]
        case .chooseAsset, .manual, .browser: urls = []
        }
        for u in urls { if let work = modWorkFolder(of: u) { fm.removeIfPresent(work) } }
    }

    func gameFolders(_ g: Game) -> GameFolders {
        let exeFolder = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
        return GameFolders(exeFolder: exeFolder, root: ModLayout.gameRoot(exeFolder: exeFolder), is64bit: g.arch == .x64)
    }

    func modOverrides(_ g: Game) -> [String] {
        var out: [String] = []
        for o in g.mods.flatMap(\.overrides) where !out.contains(o) { out.append(o) }
        return out
    }

    func downloadModResult(_ r: ModResult, game: Game, asset: GHAsset? = nil) async throws -> ModPreparation {
        modWorkInFlight += 1
        defer { modWorkInFlight -= 1 }
        let url: URL
        let source: String
        var saveAs: String? = nil, repoPage: URL? = nil, size: Int64? = nil
        switch r.link {
        case .githubRepo(let owner, let repo):
            source = "https://github.com/\(owner)/\(repo)"
            var chosen = asset
            if chosen == nil {
                let assets = try await GitHub.latestAssets(repo: "\(owner)/\(repo)").assets
                switch ModSearch.pickAsset(assets.map(\.name), is64bit: game.arch == .x64) {
                case .one(let name): chosen = assets.first { $0.name == name }
                case .ask(let names): return .chooseAsset(assets.filter { names.contains($0.name) }, repo: "\(owner)/\(repo)")
                case .none: break
                }
            }
            if let chosen, let link = URL(string: chosen.browserDownloadUrl) {
                url = link
                size = Int64(chosen.size)
            } else if let page = URL(string: source), let zip = URL(string: source + "/archive/HEAD.zip") {
                url = zip
                saveAs = "\(repo).zip"
                repoPage = page
            } else {
                return .browser(url: URL(string: "https://github.com")!, reason: "Its latest release has no download, so it opens in your browser.")
            }
        case .directFile(let link):
            source = link.absoluteString
            url = link
        default:
            throw FerryError("Ferry can't download this one by itself. Use \"Install Manually\".")
        }
        if size == nil { size = await Self.contentLength(url) }
        try checkDownloadSpace(r.title, size: size)
        let work = try newModWorkFolder()
        let file: URL
        do {
            file = try await fetchModFile(url, into: work, name: saveAs)
        } catch let page as ModWebPage {
            fm.removeIfPresent(work)
            return .browser(url: repoPage ?? page.url, reason: ModWebPage.reason)
        } catch {
            fm.removeIfPresent(work)
            throw error
        }
        return try await prepareModFile(file, name: r.title, source: source, reviewed: r.reviewed, game: game, repoPage: repoPage)
    }

    func saveToDownloads(_ url: URL) async throws -> URL {
        let saved = try await fetchModFile(url, into: fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
        NSWorkspace.shared.activateFileViewerSelecting([saved])
        return saved
    }

    private func fetchModFile(_ link: URL, into folder: URL, name given: String? = nil) async throws -> URL {
        let url = ModSearch.downloadURL(link)
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue("Ferry-macOS", forHTTPHeaderField: "User-Agent")
        let shown = given ?? (link.lastPathComponent.isEmpty ? (link.host ?? "the mod") : link.lastPathComponent)
        guard let (tmp, response) = try? await URLSession.shared.download(for: req) else {
            throw FerryError("Couldn't download \(shown). Check your internet connection.")
        }
        defer { fm.removeIfPresent(tmp) }
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw FerryError("Couldn't download \(shown) (error \(status)).")
        }
        var name = ((given ?? response.suggestedFilename ?? url.lastPathComponent) as NSString).lastPathComponent
        if name.isEmpty || name == "/" { name = "mod download" }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = Self.unusedName(name, in: folder)
        try fm.moveItem(at: tmp, to: dest)
        if Self.isWebPage(dest) {
            fm.removeIfPresent(dest)
            throw ModWebPage(url: link)
        }
        return dest
    }

    private static func isWebPage(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 512)) ?? Data(), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).lowercased()
        return head.hasPrefix("<!doctype") || head.hasPrefix("<html")
    }

    private static func unusedName(_ name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    func prepareModFile(_ file: URL, name: String, source: String, reviewed: Bool, game: Game, repoPage: URL? = nil) async throws -> ModPreparation {
        modWorkInFlight += 1
        defer { modWorkInFlight -= 1 }
        let isFolder = fm.isDirectory(file)
        if !isFolder, await Task.detached(operation: { ModLayout.isModInstaller(file) }).value {
            return .installer(file: file, name: name, source: source)
        }
        if isFolder {
            guard await !Task.detached(operation: { ModLayout.escapes(file) }).value else {
                throw FerryError("This folder holds links to other places, or parts Ferry can't read, so Ferry won't use it.")
            }
            return try await prepareModRoot(ModLayout.contentRoot(file, game: gameFolders(game)), file: file, staging: nil, repoPage: repoPage, name: name, source: source, reviewed: reviewed, game: game)
        }
        let work = try modWorkFolder(of: file) ?? newModWorkFolder()
        do {
            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            fm.removeIfPresent(unpacked)
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            if let set = ArchiveSet.resolve(file) {
                guard set.missing.isEmpty else {
                    throw FerryError("\(file.lastPathComponent) is one part of a set, and these parts aren't next to it: \(set.missing.joined(separator: ", ")).")
                }
                try await checkUnpackSpace(set.first, into: unpacked)
                guard await unpack(set.first, into: unpacked) else {
                    let problem = "\(file.lastPathComponent) couldn't be unpacked. It may be damaged, password-protected, or a format macOS doesn't read."
                    guard modWorkFolder(of: file) != nil else { throw FerryError(problem) }
                    if let repoPage {
                        fm.removeIfPresent(work)
                        return .browser(url: repoPage, reason: problem + " Its repository opens in your browser.")
                    }
                    let kept = try keepInDownloads(file)
                    fm.removeIfPresent(work)
                    return .manual(file: kept, reason: problem + " It's in your Downloads folder.")
                }
            } else {
                try fm.copyItem(at: file, to: unpacked.appendingPathComponent(file.lastPathComponent))
            }
            if await Task.detached(operation: { ModLayout.escapes(unpacked) }).value {
                throw FerryError("This archive tries to put files outside its own folder, so Ferry won't use it.")
            }
            return try await prepareModRoot(ModLayout.contentRoot(unpacked, game: gameFolders(game)), file: file, staging: work, repoPage: repoPage,
                                            name: name, source: source, reviewed: reviewed, game: game)
        } catch {
            fm.removeIfPresent(work)
            throw error
        }
    }

    func prepareModVariant(_ folder: URL, of prep: ModPreparation, game: Game) async throws -> ModPreparation {
        modWorkInFlight += 1
        defer { modWorkInFlight -= 1 }
        guard case .chooseVariant(_, let file, let staging, let name, let source, let reviewed, let repoPage) = prep else {
            throw FerryError("There's no choice to make for this mod.")
        }
        return try await prepareModRoot(ModLayout.contentRoot(folder, game: gameFolders(game)), file: file, staging: staging, variantChosen: true,
                                        repoPage: repoPage, name: name, source: source, reviewed: reviewed, game: game)
    }

    private func prepareModRoot(_ root: URL, file: URL, staging: URL?, variantChosen: Bool = false, repoPage: URL? = nil,
                                name: String, source: String, reviewed: Bool, game: Game) async throws -> ModPreparation {
        let folders = gameFolders(game)
        var root = root
        let whole = root
        if !variantChosen {
            switch await Task.detached(operation: { ModLayout.pickVariant(root, is64bit: folders.is64bit) }).value {
            case .one(let pick): root = ModLayout.contentRoot(pick, game: folders)
            case .ask(let options): return .chooseVariant(options, file: file, staging: staging ?? root, name: name, source: source, reviewed: reviewed, repoPage: repoPage)
            case .none: break
            }
        }
        let modRoot = root
        let asPackage = !variantChosen && modRoot == whole && repoPage == nil && ArchiveSet.resolve(file)?.isMultiPart != true
        if let plan = await Task.detached(operation: {
            ModLayout.plan(modRoot, game: folders) ?? (asPackage ? ModLayout.packagePlan(archive: file, modRoot: modRoot, game: folders) : nil)
        }).value {
            return .ready(plan: plan, staging: staging ?? root, name: name, source: source, reviewed: reviewed)
        }
        defer { if let staging, let work = modWorkFolder(of: staging) { fm.removeIfPresent(work) } }
        if let repoPage {
            let reason = ModLayout.riskyRootReason(folders.root).map { $0 + " Its repository opens in your browser." }
                ?? "Ferry couldn't tell where this repository's files go, so it opens in your browser."
            return .browser(url: repoPage, reason: reason)
        }
        let kept = try keepInDownloads(file)
        if let risky = ModLayout.riskyRootReason(folders.root) {
            return .manual(file: kept, reason: risky + " The mod is in your Downloads folder: move \(game.name) into a folder of its own first, or install it by hand.")
        }
        return .manual(file: kept, reason: "Ferry couldn't tell where this mod goes, so it's in your Downloads folder.")
    }

    private func keepInDownloads(_ file: URL) throws -> URL {
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0].standardizedFileURL
        if file.standardizedFileURL.deletingLastPathComponent() == downloads { return file }
        let parts = fm.isDirectory(file) ? [file] : (ArchiveSet.resolve(file)?.parts ?? [file])
        var first: URL? = nil
        for part in parts {
            let dest = Self.unusedName(part.lastPathComponent, in: downloads)
            if modWorkFolder(of: part) != nil { try fm.moveItem(at: part, to: dest) } else { try fm.copyItem(at: part, to: dest) }
            if part == file || first == nil { first = dest }
        }
        return first ?? file
    }

    private func unpack(_ archive: URL, into dest: URL) async -> Bool {
        if runtimes.sevenZipInstalled {
            return await Shell.run(RuntimeManager.sevenZip.path, ["x", "-y", "-o\(dest.path)", archive.path]) == 0
        }
        if archive.pathExtension.lowercased() == "zip" {
            return await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, dest.path]) == 0
        }
        return await Shell.run("/usr/bin/bsdtar", ["-xf", archive.path, "-C", dest.path]) == 0
    }

    func applyMod(_ prep: ModPreparation, to gameID: UUID) async throws -> InstalledMod {
        modWorkInFlight += 1
        defer { status = nil; modWorkInFlight -= 1 }
        guard var g = game(gameID) else { throw FerryError("That game isn't in the library anymore.") }
        try requireModsIdle(g)
        switch prep {
        case .ready(let plan, _, let name, let source, _):
            let replaced = g.vsyncPlaced.filter { placed in plan.copies.contains { ModLayout.samePath(URL(fileURLWithPath: placed), $0.to) } }
            if !replaced.isEmpty {
                for placed in replaced { fm.removeIfPresent(URL(fileURLWithPath: placed)) }
                g.vsyncPlaced.removeAll { replaced.contains($0) }
                update(g)
            }
            let ferrysOwn = [(g.cncDdrawPlaced, "DirectDraw compatibility (cnc-ddraw)"),
                             (g.dxvkD3D9Placed, "DirectX 9 via DXVK"), (g.hideROVPlaced, "Hide ROV support"),
                             (g.drawCopiesPlaced, "Faster screen copies")]
                + g.placedFiles.flatMap { feature, paths in
                    paths.map { (Optional($0), feature == "dxmt" ? "DXMT (beta)" : "Old 3D game fix (dgVoodoo2)") }
                }
            for copy in plan.copies {
                for case let (placed?, setting) in ferrysOwn where ModLayout.samePath(URL(fileURLWithPath: placed), copy.to) {
                    throw FerryError("\(copy.to.lastPathComponent) is Ferry's own \(setting) file for this game. Turn that setting off first, or install this mod by hand.")
                }
            }
            try await checkInstallSpace(plan, name: name, game: g)
            try requireModsIdle(g)
            preparing.insert(gameID)
            defer { preparing.remove(gameID); discardModPreparation(prep) }
            let updating = updatedEntry(plan, in: g)
            var mod = InstalledMod(name: name, source: source, recipe: plan.recipe, files: [], overrides: plan.overrides, addedGameID: updating?.id)
            let allowed = ModLayout.allowedFolders(plan, game: gameFolders(g))
            let backups = bottleURL(gameID).appendingPathComponent("mod-backups/\(mod.id.uuidString)", isDirectory: true)
            status = "Installing \(name)…"
            do {
                mod.files = try await Task.detached { try ModFiles.apply(plan, backups: backups, within: allowed) }.value
            } catch is ModFiles.Outside {
                throw FerryError("\(name) would put files outside \(g.name)'s folder, so Ferry didn't install it. Nothing was changed.")
            } catch let e as ModFiles.UnreadableFile {
                throw FerryError("Ferry couldn't read \(URL(fileURLWithPath: e.path).lastPathComponent) back after copying it, so it undid the install. Nothing was changed.")
            } catch {
                throw FerryError("Couldn't install \(name): \(error.localizedDescription) Nothing was changed.")
            }
            guard record(mod, in: gameID) else {
                _ = ModFiles.remove(mod.files, later: [])
                throw FerryError("That game isn't in the library anymore, so the mod was taken out again.")
            }
            if updating == nil, plan.recipe == .program, let exe = plan.programExe, let program = ModLayout.programName(plan) {
                mod.addedGameID = await add(exe, launch: false, name: "\(g.name) (\(program))").value
                if var current = game(gameID), let i = current.mods.firstIndex(where: { $0.id == mod.id }) {
                    current.mods[i].addedGameID = mod.addedGameID
                    update(current)
                }
            }
            return mod

        case .installer(let file, let name, let source):
            let args: [String]
            switch file.pathExtension.lowercased() {
            case "msi": args = ["msiexec", "/i", file.path]
            default: args = [file.path]
            }
            let useStaging = !runtimeKind(g).supports32bit && ModLayout.isPE64(file) == false
            let kind: RuntimeKind = useStaging ? .staging : runtimeKind(g)
            let prefix = prefixURL(gameID, kind)
            let busy = games.filter { $0.id != gameID && (running.contains($0.id) || preparing.contains($0.id)) && prefixURL($0.id, kind) == prefix }
            guard busy.isEmpty else {
                let names = ListFormatter.localizedString(byJoining: busy.map(\.name))
                throw FerryError("Quit \(names) first: \(busy.count == 1 ? "it uses" : "they use") the same Windows environment as \(g.name), and the installer needs it to itself.")
            }
            preparing.insert(gameID)
            defer { preparing.remove(gameID); discardModPreparation(prep) }
            let log = logURL(gameID, "mod-installer")
            try? fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            let wine: URL, env: [String: String]
            if useStaging {
                status = "Getting Wine Staging ready for \(name)'s installer…"
                try await runtimes.ensure(.staging)
                guard let w = runtimes.wine(for: .staging, arch: .x86) else {
                    throw FerryError("Wine Staging is installed but its wine program is missing. Reinstall it in Settings ▸ Engines.")
                }
                try fm.createDirectory(at: prefix.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.exists(prefix.appendingPathComponent("system.reg")), fm.exists(templateURL(.staging).appendingPathComponent("system.reg")) {
                    fm.removeIfPresent(prefix)
                    await Shell.run("/bin/cp", ["-cR", templateURL(.staging).path, prefix.path], log: log)
                }
                wine = w
                env = baseEnvironment(prefix: prefix)
            } else {
                let p = try await prepare(gameID)
                wine = p.wine
                env = p.env
            }
            status = "Running \(name)'s installer…"
            let code = await Shell.run(wine.path, args, env: env, cwd: file.deletingLastPathComponent(), log: log)
            if let server = runtimes.wineserver(for: kind) { await Shell.run(server.path, ["-w"], env: env, log: log) }
            guard code == 0 else {
                throw FerryError("\(name)'s installer stopped before finishing (code \(code)), so Ferry didn't list it as installed. Anything it already changed stays.")
            }
            let mod = InstalledMod(name: name, source: source, recipe: .installer, files: [], overrides: [])
            guard record(mod, in: gameID) else { throw FerryError("That game isn't in the library anymore.") }
            return mod

        case .chooseVariant, .chooseAsset, .manual, .browser:
            throw FerryError("There's nothing to install yet for this mod.")
        }
    }

    private func record(_ mod: InstalledMod, in gameID: UUID) -> Bool {
        guard var g = game(gameID) else { return false }
        g.mods.append(mod)
        update(g)
        return true
    }

    func removeMod(_ modID: UUID, from gameID: UUID) async throws -> ModFiles.Removal {
        guard let g = game(gameID), let i = g.mods.firstIndex(where: { $0.id == modID }) else { return ModFiles.Removal() }
        try requireModsIdle(g)
        let mod = g.mods[i]
        if let added = mod.addedGameID, let entry = game(added), !entry.mods.isEmpty {
            throw FerryError("Remove the mods installed on \(entry.name) first.")
        }
        var result = ModFiles.Removal()
        if mod.recipe != .installer {
            guard fm.isDirectory(gameFolders(g).exeFolder) else {
                throw FerryError("Ferry can't reach \(g.name)'s folder, so nothing was removed. Connect the drive holding \(g.name) first, or put the game back where it was.")
            }
            preparing.insert(gameID)
            defer { preparing.remove(gameID) }
            let later = Array(g.mods[(i + 1)...])
            let files = mod.files, laterFiles = later.map(\.files)
            result = await Task.detached { ModFiles.remove(files, later: laterFiles) }.value
            let backups = bottleURL(gameID).appendingPathComponent("mod-backups/\(modID.uuidString)", isDirectory: true)
            if (try? fm.contentsOfDirectory(atPath: backups.path))?.isEmpty == true { fm.removeIfPresent(backups) }
            guard var current = game(gameID) else { return result }
            for (m, files) in zip(later, result.later) where files != m.files {
                if let j = current.mods.firstIndex(where: { $0.id == m.id }) { current.mods[j].files = files }
            }
            current.mods.removeAll { $0.id == modID }
            update(current)
        } else {
            var current = g
            current.mods.remove(at: i)
            update(current)
        }
        if let added = mod.addedGameID, let entry = game(added), !fm.exists(URL(fileURLWithPath: entry.exePath)) {
            remove(added, deleteWindowsFiles: false)
        }
        return result
    }

    func modOwnedPaths(_ g: Game) -> Set<String> {
        Set(g.mods.flatMap(\.files).map { URL(fileURLWithPath: $0.path).standardizedFileURL.path.lowercased() })
    }

    func modOwning(_ url: URL, in g: Game) -> InstalledMod? {
        guard modOwnedPaths(g).contains(url.standardizedFileURL.path.lowercased()) else { return nil }
        return g.mods.first { $0.files.contains { ModLayout.samePath(URL(fileURLWithPath: $0.path), url) } }
    }

    func noteModOwns(_ file: URL, _ mod: InstalledMod, setting: String, game g: Game) {
        guard noticeMessage == nil else { return }
        noticeMessage = "\(file.lastPathComponent) belongs to the mod \"\(mod.name)\", so \(setting) is off for \(g.name) while that mod is installed."
    }
}
