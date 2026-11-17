import Foundation

extension AppModel {

    func modBlocker(_ g: Game) -> Game? {
        let exe = URL(fileURLWithPath: g.exePath)
        let programs = g.mods.compactMap(\.addedGameID)
        return games.first { e in
            (running.contains(e.id) || preparing.contains(e.id))
                && ModLayout.blocksMods(entry: e.id, exe: URL(fileURLWithPath: e.exePath), game: g.id, gameExe: exe, modPrograms: programs)
        }
    }

    func modBlockerReason(_ blocker: Game) -> String {
        running.contains(blocker.id) ? "Quit \(blocker.name) first." : "\(blocker.name) is busy; try again when it's done."
    }

    func requireModsIdle(_ g: Game) throws {
        if let busy = modBlocker(g) { throw FerryError(modBlockerReason(busy)) }
    }

    func updatedEntry(_ plan: ModPlan, in g: Game) -> Game? {
        let entries = g.mods.compactMap(\.addedGameID).compactMap { game($0) }
        return ModLayout.replaces(plan, anyOf: entries.map { URL(fileURLWithPath: $0.exePath) }).map { entries[$0] }
    }

    private func needed(_ bytes: Int64) -> String {
        DiskUsage.text(bytes > Int64.max - ModSpace.margin ? Int64.max : bytes + ModSpace.margin)
    }

    func checkDownloadSpace(_ name: String, size: Int64?) throws {
        guard let size, size > 0, let free = DiskUsage.free(at: Paths.cache) else { return }
        let need = ModSpace.downloadNeed(size)
        guard ModSpace.enough(free: free, needed: need) else {
            throw FerryError("\(name) needs about \(needed(need)) free to download, unpack and install, and this Mac has \(DiskUsage.text(free)) free.")
        }
    }

    nonisolated static func contentLength(_ link: URL) async -> Int64? {
        var req = URLRequest(url: ModSearch.downloadURL(link), timeoutInterval: 10)
        req.httpMethod = "HEAD"
        req.setValue("Ferry-macOS", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: req), let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), http.expectedContentLength > 0 else { return nil }
        return http.expectedContentLength
    }

    func checkUnpackSpace(_ archive: URL, into dest: URL) async throws {
        let sevenZip = runtimes.sevenZipInstalled
        let tool = sevenZip ? RuntimeManager.sevenZip.path : "/usr/bin/bsdtar"
        let listing = await Shell.capture(tool, sevenZip ? ["l", "-slt", archive.path] : ["-tvf", archive.path])
        let total = await Task.detached {
            sevenZip ? Unpacker.sevenZipTotal(listing.output) : AnalyzerModel.parseListing(listing.output).values.reduce(0, +)
        }.value
        guard total > 0, let free = DiskUsage.free(at: dest), !ModSpace.enough(free: free, needed: Int64(total)) else { return }
        throw FerryError("Unpacking \(archive.lastPathComponent) needs about \(needed(Int64(total))) free, and this Mac has \(DiskUsage.text(free)) free.")
    }

    func checkInstallSpace(_ plan: ModPlan, name: String, game g: Game) async throws {
        let bytes = await Task.detached { ModSpace.installBytes(plan) }.value
        guard let free = DiskUsage.free(at: gameFolders(g).root), !ModSpace.enough(free: free, needed: bytes) else { return }
        throw FerryError("Installing \(name) needs about \(needed(bytes)) free on the drive holding \(g.name), and it has \(DiskUsage.text(free)) free.")
    }

    func clearModWork() {
        let cache = Paths.cache
        try? fm.moveItem(at: modWorkRoot, to: cache.appendingPathComponent("mods-old-\(UUID().uuidString)", isDirectory: true))
        Task.detached(priority: .background) {
            let fm = FileManager.default
            for name in (try? fm.contentsOfDirectory(atPath: cache.path)) ?? [] where name.hasPrefix("mods-old-") {
                try? fm.removeItem(at: cache.appendingPathComponent(name))
            }
        }
    }

    var environmentBuildRunning: Bool {
        setupRunning || updating || installingComponent != nil || !buildStatus.isEmpty || !preparing.isEmpty
    }

    func leftoverWorkItems() -> [StorageItem] {
        var items: [StorageItem] = []
        if !environmentBuildRunning {
            for parent in [Paths.runtimes, Paths.templates] {
                let folders = (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
                for folder in folders where folder.pathExtension == "building" && fm.isDirectory(folder) {
                    items.append(StorageItem(url: folder, group: "Ferry", title: "Interrupted install (\(folder.deletingPathExtension().lastPathComponent))",
                                             note: "An interrupted install; Ferry starts it again from scratch next time.", status: .leftover))
                }
            }
        }
        if !modWorkInUse, !((try? fm.contentsOfDirectory(atPath: modWorkRoot.path)) ?? []).isEmpty {
            items.append(StorageItem(url: modWorkRoot, group: "Ferry", title: "Mod working files",
                                     note: "Left from a mod that was being downloaded or unpacked.", status: .leftover))
        }
        return items
    }

    var modWorkInUse: Bool { modsGame != nil || modWorkInFlight > 0 }

    func leftoverInUse(_ item: StorageItem) -> Bool {
        (item.url.pathExtension == "building" && environmentBuildRunning) || (item.url == modWorkRoot && modWorkInUse)
    }
}
