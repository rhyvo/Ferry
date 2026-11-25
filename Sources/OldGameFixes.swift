import Foundation

extension AppModel {

    static let directMusicFiles = ["dmband.dll", "dmcompos.dll", "dmime.dll", "dmloader.dll", "dmscript.dll",
                                   "dmstyle.dll", "dmsynth.dll", "dmusic.dll", "dswave.dll"]
    static let directPlayFiles = ["dplayx.dll", "dpmodemx.dll", "dpnet.dll", "dpnhpast.dll", "dpnhupnp.dll", "dpwsockx.dll",
                                  "dplaysvr.exe", "dpnsvr.exe"]
    private static let registeredFiles: Set<String> = ["dmband.dll", "dmcompos.dll", "dmime.dll", "dmloader.dll", "dmscript.dll",
                                                       "dmstyle.dll", "dmsynth.dll", "dmusic.dll", "dswave.dll",
                                                       "dplayx.dll", "dpnet.dll", "dpnhpast.dll", "dpnhupnp.dll"]

    static func loadOrderNames(_ files: [String]) -> [String] {
        files.map { $0.hasSuffix(".dll") ? String($0.dropLast(4)) : $0 }
    }

    private var legacyDirectXFolder: URL { Paths.cache.appendingPathComponent("directx-legacy", isDirectory: true) }

    func cachedLegacyDirectX() -> URL? {
        (Self.directMusicFiles + Self.directPlayFiles).allSatisfy { fm.exists(legacyDirectXFolder.appendingPathComponent($0)) }
            ? legacyDirectXFolder : nil
    }

    func installLegacyDirectX() async throws {
        if cachedLegacyDirectX() != nil { return }
        guard let lib = Self.windowsLibraries.first(where: { $0.component == .legacyDirectX }) else { return }
        if !runtimes.isCached(lib.file) { status = "Downloading DirectMusic and DirectPlay (about 105 MB)…" }
        guard let package = await cachedFile(for: lib) else {
            throw FerryError("DirectMusic and DirectPlay couldn't be downloaded. Check your connection and try again.")
        }
        if !runtimes.sevenZipInstalled { try await runtimes.installSevenZip() }
        status = "Unpacking DirectMusic and DirectPlay…"
        let work = Paths.cache.appendingPathComponent("directx-legacy.new", isDirectory: true)
        let cabs = work.appendingPathComponent("cab", isDirectory: true)
        fm.removeIfPresent(work)
        try fm.createDirectory(at: cabs, withIntermediateDirectories: true)
        defer { fm.removeIfPresent(work) }
        let zip = RuntimeManager.sevenZip.path
        await Shell.run(zip, ["e", "-y", "-o" + cabs.path, package.path, "dxnt.cab"])
        await Shell.run(zip, ["e", "-y", "-o" + cabs.path, cabs.appendingPathComponent("dxnt.cab").path])
        let unpacked = (try? fm.contentsOfDirectory(atPath: cabs.path)) ?? []
        let ready = work.appendingPathComponent("ready", isDirectory: true)
        try fm.createDirectory(at: ready, withIntermediateDirectories: true)
        for wanted in Self.directMusicFiles + Self.directPlayFiles {
            guard let found = unpacked.first(where: { $0.lowercased() == wanted }) else {
                throw FerryError("Microsoft's DirectX package didn't have \(wanted). Try Install Now again.")
            }
            try fm.moveItem(at: cabs.appendingPathComponent(found), to: ready.appendingPathComponent(wanted))
        }
        fm.removeIfPresent(legacyDirectXFolder)
        try fm.moveItem(at: ready, to: legacyDirectXFolder)
        fm.removeIfPresent(package)
    }

    func applyLegacyDirectX(_ p: PreparedGame) async {
        let s = p.game.settings
        guard p.game.arch == .x86, s.nativeDirectMusic || s.nativeDirectPlay else { return }
        let system = p.prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        guard fm.isDirectory(system) else { return }
        do { try await installLegacyDirectX() } catch {
            errorMessage = "\(error.localizedDescription) \(p.game.name) will use Wine's DirectMusic and DirectPlay."
            return
        }
        guard let source = cachedLegacyDirectX() else { return }
        let files = (s.nativeDirectMusic ? Self.directMusicFiles : []) + (s.nativeDirectPlay ? Self.directPlayFiles : [])
        var added: [String] = []
        for file in files {
            let from = source.appendingPathComponent(file), to = system.appendingPathComponent(file)
            if fm.exists(to) && fm.contentsEqual(atPath: to.path, andPath: from.path) { continue }
            fm.removeIfPresent(to)
            if (try? fm.copyItem(at: from, to: to)) != nil { added.append(file) }
        }
        for file in added where Self.registeredFiles.contains(file) {
            await Shell.run(p.wine.path, ["regsvr32", "/s", "C:\\windows\\syswow64\\" + file], env: p.env,
                            log: logURL(p.game.id, "setup"))
        }
    }

    private var dgVoodooFolder: URL { Paths.cache.appendingPathComponent("dgVoodoo2", isDirectory: true) }

    func dgVoodooFiles() -> [(name: String, from: URL)]? {
        let parts = [("DDraw.dll", "MS/x86/DDraw.dll"), ("D3DImm.dll", "MS/x86/D3DImm.dll"),
                     ("Glide.dll", "3Dfx/x86/Glide.dll"), ("Glide2x.dll", "3Dfx/x86/Glide2x.dll"),
                     ("Glide3x.dll", "3Dfx/x86/Glide3x.dll"), ("dgVoodoo.conf", "dgVoodoo.conf")]
        let files = parts.map { (name: $0.0, from: dgVoodooFolder.appendingPathComponent($0.1)) }
        return files.allSatisfy { fm.exists($0.from) } ? files : nil
    }

    func installDgVoodoo() async throws {
        if dgVoodooFiles() != nil { return }
        guard let lib = Self.windowsLibraries.first(where: { $0.component == .dgVoodoo }) else { return }
        status = "Downloading dgVoodoo2…"
        guard let zip = await cachedFile(for: lib) else {
            throw FerryError("dgVoodoo2 couldn't be downloaded. Check your connection and try again.")
        }
        let work = Paths.cache.appendingPathComponent("dgVoodoo2.new", isDirectory: true)
        fm.removeIfPresent(work)
        defer { fm.removeIfPresent(work) }
        await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let conf = work.appendingPathComponent("dgVoodoo.conf")
        guard let text = try? String(contentsOf: conf, encoding: .utf8) else {
            throw FerryError("dgVoodoo2's download didn't unpack. Try Install Now again.")
        }
        try Self.dgVoodooConfig(text).write(to: conf, atomically: true, encoding: .utf8)
        fm.removeIfPresent(dgVoodooFolder)
        try fm.moveItem(at: work, to: dgVoodooFolder)
        fm.removeIfPresent(zip)
    }

    static func dgVoodooConfig(_ text: String) -> String {
        let wanted = ["OutputAPI": "d3d11_fl10_1", "3DfxWatermark": "false", "dgVoodooWatermark": "false"]
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let key = line.split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard line.contains("="), !line.hasPrefix(";"), let value = wanted[key] else { return line }
            return key.padding(toLength: max(key.count, 37), withPad: " ", startingAt: 0) + "= " + value
                + (line.hasSuffix("\r") ? "\r" : "")
        }
        return lines.joined(separator: "\n")
    }

    private var upstreamDXMTFolder: URL { Paths.runtimes.appendingPathComponent("dxmt", isDirectory: true) }

    var upstreamDXMTVersion: String? {
        (try? String(contentsOf: upstreamDXMTFolder.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func upstreamDXMTInstalled() -> Bool {
        fm.exists(upstreamDXMTFolder.appendingPathComponent("x86_64-unix/winemetal.so"))
    }

    func usesUpstreamDXMT(_ g: Game, engine: EngineID) -> Bool {
        g.settings.dxmtUpstream && [EngineID.dxvk, .wined3d, .auto].contains(engine)
            && [GraphicsAPI.dx10, .dx11].contains(g.drawsWith) && upstreamDXMTInstalled()
            && dxmtBlockedBy(g) == nil
    }

    static let dxmtFiles = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]

    func dxmtBlockedBy(_ g: Game) -> String? {
        let folder = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
        let ferrys = (g.placedFiles["dxmt"] ?? []) + g.vsyncPlaced
        return Self.dxmtFiles.first { name in
            let to = folder.appendingPathComponent(name)
            return fm.exists(to) && !ferrys.contains { ModLayout.samePath(URL(fileURLWithPath: $0), to) }
        }
    }

    func installUpstreamDXMT() async throws {
        let release = try await GitHub.latestAsset(repo: "3Shain/dxmt", matching: { $0.hasPrefix("dxmt-") && $0.hasSuffix(".tar.gz") })
        guard let url = URL(string: release.asset.browserDownloadUrl) else {
            throw FerryError("Couldn't find DXMT's newest release on GitHub. Check your connection and try again.")
        }
        status = "Downloading DXMT…"
        let archive = Paths.cache.appendingPathComponent(release.asset.name)
        try await runtimes.download(url, to: archive, expectedBytes: 0)
        defer { fm.removeIfPresent(archive) }
        status = "Unpacking DXMT…"
        let unpacked = Paths.runtimes.appendingPathComponent("dxmt.new", isDirectory: true)
        fm.removeIfPresent(unpacked)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { fm.removeIfPresent(unpacked) }
        guard await Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", unpacked.path]) == 0,
              let unix = fm.firstItem(under: unpacked, where: { $0.lastPathComponent == "x86_64-unix" }) else {
            throw FerryError("DXMT's download didn't unpack. Try Install Now again.")
        }
        let top = unix.deletingLastPathComponent()
        try? release.tag.write(to: top.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        fm.removeIfPresent(upstreamDXMTFolder)
        try fm.moveItem(at: top, to: upstreamDXMTFolder)
    }

    func applyUpstreamDXMT(_ p: PreparedGame) {
        var files: [(name: String, from: URL)]? = nil
        if usesUpstreamDXMT(p.game, engine: p.engine), let wine = runtimes.wine(for: .staging, arch: .x64) {
            let unixLib = wine.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("lib/wine/x86_64-unix/winemetal.so")
            let ours = upstreamDXMTFolder.appendingPathComponent("x86_64-unix/winemetal.so")
            if !fm.contentsEqual(atPath: unixLib.path, andPath: ours.path) {
                fm.removeIfPresent(unixLib)
                try? fm.copyItem(at: ours, to: unixLib)
            }
            let dlls = upstreamDXMTFolder.appendingPathComponent(p.game.arch == .x86 ? "i386-windows" : "x86_64-windows")
            files = Self.dxmtFiles.map { (name: $0, from: dlls.appendingPathComponent($0)) }
        } else if p.game.settings.dxmtUpstream, let name = dxmtBlockedBy(p.game) {
            errorMessage = "\(p.game.name) has its own \(name), so it starts without DXMT (beta): DXMT needs all four of its DLLs next to the \(p.game.noun). Turn DXMT off in its settings to stop this message."
        }
        placeBesideGame("dxmt", files, gameID: p.game.id, setting: "DXMT (beta)")
    }

    func placeBesideGame(_ feature: String, _ files: [(name: String, from: URL)]?, gameID: UUID, setting: String) {
        guard var g = game(gameID) else { return }
        let folder = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
        var placed = g.placedFiles[feature] ?? []
        var hashes = g.placedHashes
        func forget(_ path: String) { placed.removeAll { $0 == path }; hashes[path] = nil }
        func unchanged(_ path: String) -> Bool {
            guard let h = hashes[path], fm.exists(URL(fileURLWithPath: path)) else { return true }
            return ModFiles.sha256(URL(fileURLWithPath: path)) == h
        }
        if let files {
            for file in files {
                let to = folder.appendingPathComponent(file.name)
                let entry = placed.first { ModLayout.samePath(URL(fileURLWithPath: $0), to) }
                if let entry {
                    if fm.contentsEqual(atPath: to.path, andPath: file.from.path) { continue }
                    guard unchanged(entry), modOwning(to, in: g) == nil else { forget(entry); continue }
                    fm.removeIfPresent(to)
                    forget(entry)
                } else if fm.exists(to) {
                    if let mod = modOwning(to, in: g) { noteModOwns(to, mod, setting: setting, game: g) }
                    continue
                }
                if (try? fm.copyItem(at: file.from, to: to)) != nil {
                    placed.append(to.path)
                    hashes[to.path] = ModFiles.sha256(to)
                }
            }
        } else {
            for path in placed {
                if modOwning(URL(fileURLWithPath: path), in: g) == nil && unchanged(path) {
                    fm.removeIfPresent(URL(fileURLWithPath: path))
                }
                hashes[path] = nil
            }
            placed = []
        }
        guard placed != (g.placedFiles[feature] ?? []) || hashes != g.placedHashes else { return }
        g.placedFiles[feature] = placed.isEmpty ? nil : placed
        g.placedHashes = hashes
        update(g)
    }

    func applyDDrawFixes(_ p: PreparedGame) async {
        let s = p.game.settings
        let wantsDgVoodoo = s.dgVoodoo && p.game.arch == .x86
        if !wantsDgVoodoo { placeBesideGame("dgvoodoo", nil, gameID: p.game.id, setting: "the old 3D game fix") }
        await applyCncDdraw(p)
        guard wantsDgVoodoo else { return }
        do { try await installDgVoodoo() } catch {
            errorMessage = "\(error.localizedDescription) \(p.game.name) will start without the old 3D game fix."
            return
        }
        placeBesideGame("dgvoodoo", dgVoodooFiles(), gameID: p.game.id, setting: "the old 3D game fix")
    }
}
