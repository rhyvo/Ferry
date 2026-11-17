import Foundation

extension Game {
    var usesGameMode: Bool {
        switch settings.gameMode {
        case 1: return true
        case 2: return false
        default: return graphics != .unknown || !(framework ?? "").isEmpty
        }
    }
}

extension RuntimeManager {
    func gameLauncher(for kind: RuntimeKind, arch: PEArch) -> URL? {
        if kind == .gptk, let hosted = gameHost(for: kind) { return hosted }
        return wine(for: kind, arch: arch)
    }

    func gameHost(for kind: RuntimeKind) -> URL? {
        guard kind == .gptk, let bin = binDir(kind) else { return nil }
        let wineDir = bin.deletingLastPathComponent()
        let app = folder(kind).appendingPathComponent("Ferry Game.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let launcher = macOS.appendingPathComponent("wine64")
        let marker = app.appendingPathComponent("Contents/.ferry-host")
        let stamp = info[kind]?.version ?? "?"
        if FileManager.default.fileExists(atPath: launcher.path),
           (try? String(contentsOf: marker, encoding: .utf8)) == stamp { return launcher }

        let fm = FileManager.default
        let files = ["wine64", "wine64-preloader", "wineserver"]
        guard files.allSatisfy({ fm.fileExists(atPath: bin.appendingPathComponent($0).path) }) else { return nil }
        try? fm.removeItem(at: app)
        do {
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            for name in files {
                try fm.copyItem(at: bin.appendingPathComponent(name), to: macOS.appendingPathComponent(name))
            }
            for name in ["lib", "share"] {
                try fm.createSymbolicLink(at: app.appendingPathComponent("Contents/\(name)"),
                                          withDestinationURL: wineDir.appendingPathComponent(name))
            }
            var plist = embeddedInfoPlist(bin.appendingPathComponent("wine64-preloader")) ?? [:]
            plist["CFBundleExecutable"] = "wine64-preloader"
            plist["CFBundleIdentifier"] = "app.ferry.game.d3dmetal"
            plist["CFBundleName"] = "Ferry Game"
            plist["CFBundleDisplayName"] = "Ferry Game"
            plist["CFBundlePackageType"] = "APPL"
            plist["LSApplicationCategoryType"] = "public.app-category.games"
            plist["NSHighResolutionCapable"] = true
            if plist["NSPrincipalClass"] == nil { plist["NSPrincipalClass"] = "WineApplication" }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
            try stamp.write(to: marker, atomically: true, encoding: .utf8)
            return launcher
        } catch {
            try? fm.removeItem(at: app)
            return nil
        }
    }

    private func embeddedInfoPlist(_ binary: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: binary, options: .alwaysMapped),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        var text = String(decoding: data.subdata(in: start.lowerBound..<end.upperBound), as: UTF8.self)
        text = text.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
        let xml = Data(text.utf8)
        return (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
    }
}
