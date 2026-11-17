import Foundation

extension AppModel {
    private var betaDXVKFolder: URL { Paths.runtimes.appendingPathComponent("dxvk3", isDirectory: true) }

    func betaDXVK32() -> URL? {
        let dll = betaDXVKFolder.appendingPathComponent("x32/d3d9.dll")
        return fm.exists(dll) ? dll : nil
    }

    var betaDXVKVersion: String? {
        try? String(contentsOf: betaDXVKFolder.appendingPathComponent("VERSION"), encoding: .utf8)
    }

    func usesBetaDXVK(_ g: Game, engine: EngineID) -> Bool {
        engine == .mullion && g.settings.dxvkD3D9 && g.settings.dxvkBeta && g.arch == .x86
            && betaDXVK32() != nil && runtimes.kosmicKrispDriver() != nil
    }

    func installBetaDXVK() async throws {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let size: Int; let browser_download_url: URL }
            let tag_name: String
            let assets: [Asset]
        }
        let api = URL(string: "https://api.github.com/repos/doitsujin/dxvk/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: api)
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let asset = release.assets.first(where: { $0.name.hasPrefix("dxvk-") && $0.name.hasSuffix(".tar.gz") && !$0.name.contains("native") })
        else { throw FerryError("Couldn't find DXVK's newest release on GitHub. Check your connection and try again.") }

        status = "Downloading DXVK \(release.tag_name)…"
        let archive = Paths.cache.appendingPathComponent(asset.name)
        try await runtimes.download(asset.browser_download_url, to: archive, expectedBytes: asset.size)

        status = "Unpacking DXVK \(release.tag_name)…"
        let unpacked = Paths.runtimes.appendingPathComponent("dxvk3.new", isDirectory: true)
        fm.removeIfPresent(unpacked)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        guard await Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", unpacked.path]) == 0,
              let x32 = fm.firstItem(under: unpacked, where: { $0.lastPathComponent == "x32" }) else {
            fm.removeIfPresent(unpacked)
            throw FerryError("DXVK's download didn't unpack. Try Install Now again.")
        }
        let top = x32.deletingLastPathComponent()
        let ready = Paths.runtimes.appendingPathComponent("dxvk3.ready", isDirectory: true)
        fm.removeIfPresent(ready)
        try fm.moveItem(at: top, to: ready)
        try? release.tag_name.write(to: ready.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        fm.removeIfPresent(unpacked)
        fm.removeIfPresent(betaDXVKFolder)
        try fm.moveItem(at: ready, to: betaDXVKFolder)
        fm.removeIfPresent(archive)
    }
}
