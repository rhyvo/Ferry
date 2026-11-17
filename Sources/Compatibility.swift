import AppKit
import Foundation

struct LaunchFailure: Identifiable {
    let id = UUID()
    let gameID: UUID
    let name: String
    let failed: EngineID
    let next: EngineID?
    let logTail: String
    let findings: [LogFinding]
}

extension AppModel {

    func offerAnotherEngine(for g: Game, failed: EngineID, status: Int32) {
        var next: EngineID? = nil
        if g.sharedWith == nil {
            let order = fallbackOrder(for: g)
            if let i = order.firstIndex(of: failed), i + 1 < order.count { next = order[i + 1] }
        }
        launchFailure = LaunchFailure(gameID: g.id, name: g.name, failed: failed, next: next, logTail: gameLogTail(g.id),
                                      findings: logFindings(g))
    }

    func retry(_ failure: LaunchFailure) {
        guard let next = failure.next, var g = game(failure.gameID) else { return }
        g.settings.engine = next
        update(g)
        play(g.id)
    }

    func gameLogTail(_ id: UUID) -> String {
        guard let data = try? Data(contentsOf: logURL(id, "game")) else { return "" }
        let text = String(decoding: data.suffix(8000), as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline)
            .map { String($0.prefix(160)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let important = lines.filter { $0.contains("err:") || $0.contains("Unhandled") || $0.lowercased().contains("error") }
        return (important.isEmpty ? lines : important).suffix(6).joined(separator: "\n")
    }

    func applyRegistry(_ lines: [String], name: String, wine: URL, env: [String: String], prefix: URL, log: URL) async {
        let file = prefix.appendingPathComponent("drive_c/\(name).reg")
        let text = (["REGEDIT4", ""] + lines + [""]).joined(separator: "\r\n")
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        await Shell.run(wine.path, ["regedit", "/S", "C:\\\(name).reg"], env: env, log: log)
        fm.removeIfPresent(file)
    }

    func applyWindowsSettings(_ s: GameSettings, wine: URL, env: [String: String], prefix: URL, log: URL, kind: RuntimeKind? = nil,
                              dpi: Int = 96) async {
        let logPixels = "dword:" + String(format: "%08x", dpi)
        await Shell.run(wine.path, ["winecfg", "-v", s.windowsVersion], env: env, log: log)
        func yn(_ on: Bool) -> String { on ? "\"y\"" : "\"n\"" }
        await applyRegistry([
            "[HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]",
            "\"RetinaMode\"=\(yn(s.retina))",
            "\"LeftCommandIsCtrl\"=\(yn(s.commandIsCtrl))",
            "\"RightCommandIsCtrl\"=\(yn(s.commandIsCtrl))",
            "\"LeftOptionIsAlt\"=\(yn(s.optionIsAlt))",
            "\"RightOptionIsAlt\"=\(yn(s.optionIsAlt))",
            "\"CaptureDisplaysForFullscreen\"=\(yn(s.captureFullscreen))",
            "\"ForceOpenGLBackingStore\"=\(yn(s.openGLBackingStore))",
            "",
            "[HKEY_CURRENT_USER\\Control Panel\\Desktop]",
            "\"LogPixels\"=\(logPixels)",
            "",
            "[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Hardware Profiles\\Current\\Software\\Fonts]",
            "\"LogPixels\"=\(logPixels)",
        ] + (kind == .mach9 ? [
            "",
            "[HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver]",
            "\"EmulateModeset\"=\(s.captureFullscreen ? "\"N\"" : "\"Y\"")",
        ] : []), name: "ferry-settings", wine: wine, env: env, prefix: prefix, log: log)
    }

    private static let windowsFontFamilies = [
        "Arial", "Times New Roman", "Courier New", "Verdana", "Georgia", "Trebuchet MS", "Comic Sans MS",
        "Impact", "Tahoma", "Webdings", "Wingdings", "Andale Mono", "Microsoft Sans Serif",
    ]

    private static let fontReplacements: [(String, String)] = [
        ("MS Gothic", "Hiragino Sans"), ("MS PGothic", "Hiragino Sans"), ("MS UI Gothic", "Hiragino Sans"),
        ("Meiryo", "Hiragino Sans"), ("Meiryo UI", "Hiragino Sans"), ("Yu Gothic", "Hiragino Sans"),
        ("MS Mincho", "Hiragino Mincho ProN"), ("MS PMincho", "Hiragino Mincho ProN"),
        ("SimSun", "PingFang SC"), ("NSimSun", "PingFang SC"), ("SimHei", "PingFang SC"),
        ("Microsoft YaHei", "PingFang SC"), ("Microsoft YaHei UI", "PingFang SC"),
        ("PMingLiU", "PingFang TC"), ("MingLiU", "PingFang TC"), ("Microsoft JhengHei", "PingFang TC"),
        ("Malgun Gothic", "Apple SD Gothic Neo"), ("Gulim", "Apple SD Gothic Neo"),
        ("Dotum", "Apple SD Gothic Neo"), ("Batang", "AppleMyungjo"),
    ]

    func installFonts(wine: URL, env: [String: String], prefix: URL, log: URL) async {
        let marker = prefix.appendingPathComponent(".ferry-fonts")
        let fontsDir = prefix.appendingPathComponent("drive_c/windows/Fonts")
        guard !fm.exists(marker), fm.isDirectory(fontsDir) else { return }
        let existing = Set(((try? fm.contentsOfDirectory(atPath: fontsDir.path)) ?? []).map { $0.lowercased() })
        for dir in ["/System/Library/Fonts/Supplemental", "/Library/Fonts"] {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files {
                let ext = (file as NSString).pathExtension.lowercased()
                guard ["ttf", "ttc", "otf"].contains(ext),
                      Self.windowsFontFamilies.contains(where: { file.hasPrefix($0) }),
                      !existing.contains(file.lowercased()) else { continue }
                try? fm.createSymbolicLink(atPath: fontsDir.appendingPathComponent(file).path,
                                           withDestinationPath: dir + "/" + file)
            }
        }
        await applyRegistry(
            ["[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]"]
                + Self.fontReplacements.map { "\"\($0.0)\"=\"\($0.1)\"" },
            name: "ferry-fonts", wine: wine, env: env, prefix: prefix, log: log)
        try? "1".write(to: marker, atomically: true, encoding: .utf8)
    }

    func savesURL(_ ownerID: UUID) -> URL { bottleURL(ownerID).appendingPathComponent("saves", isDirectory: true) }
    func shaderCacheURL(_ ownerID: UUID) -> URL { bottleURL(ownerID).appendingPathComponent("shader-cache", isDirectory: true) }

    private static let saveFolders = ["AppData/Roaming", "AppData/Local", "AppData/LocalLow", "Saved Games"]

    func shareSaves(prefix: URL, ownerID: UUID) async {
        let users = prefix.appendingPathComponent("drive_c/users")
        guard let names = try? fm.contentsOfDirectory(atPath: users.path) else { return }
        let shared = savesURL(ownerID)
        for name in names where name != "Public" && !name.hasPrefix(".") {
            let home = users.appendingPathComponent(name)
            guard fm.isDirectory(home) else { continue }
            for folder in Self.saveFolders {
                let here = home.appendingPathComponent(folder)
                let target = shared.appendingPathComponent(folder)
                if (try? fm.destinationOfSymbolicLink(atPath: here.path)) != nil { continue }
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.isDirectory(here) {
                    if !fm.exists(target) {
                        try? fm.moveItem(at: here, to: target)
                    } else {
                        await Shell.run("/usr/bin/ditto", [here.path, target.path])
                        let kept = here.deletingLastPathComponent().appendingPathComponent(here.lastPathComponent + " (before sharing)")
                        fm.removeIfPresent(kept)
                        try? fm.moveItem(at: here, to: kept)
                    }
                }
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                try? fm.createDirectory(at: here.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.createSymbolicLink(at: here, withDestinationURL: target)
            }
        }
    }

    func openSavesFolder(_ id: UUID) {
        guard let g = game(id) else { return }
        let owner = environmentOwner(of: g)
        let saves = savesURL(owner.id)
        if fm.exists(saves) {
            NSWorkspace.shared.open(saves)
        } else {
            errorMessage = "\(owner.name) has no saves folder yet. Play it once first."
        }
    }

    func backupSaves(_ id: UUID) {
        guard let g = game(id) else { return }
        let owner = environmentOwner(of: g)
        let saves = savesURL(owner.id)
        guard fm.exists(saves) else {
            errorMessage = "\(owner.name) has no saves in its Windows environment yet. Some games keep saves next to their own files instead; back those up from the game's folder."
            return
        }
        let folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Ferry Backups", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let safeName = owner.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let zip = folder.appendingPathComponent("\(safeName) saves \(formatter.string(from: Date())).zip")
        Task {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            status = "Backing up \(owner.name)'s saves…"
            let ok = await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", saves.path, zip.path]) == 0
            status = nil
            if ok {
                NSWorkspace.shared.activateFileViewerSelecting([zip])
            } else {
                errorMessage = "Couldn't create the backup in \(folder.path)."
            }
        }
    }

    func clearShaderCache(_ id: UUID) {
        guard let g = game(id) else { return }
        let owner = environmentOwner(of: g)
        Task {
            var cleared = 0
            let ferryCache = shaderCacheURL(owner.id)
            if fm.exists(ferryCache) {
                fm.removeIfPresent(ferryCache)
                cleared += 1
            }
            let exeDir = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
            let exeDirItems = (try? fm.contentsOfDirectory(at: exeDir, includingPropertiesForKeys: nil)) ?? []
            for file in exeDirItems where file.lastPathComponent.hasSuffix(".dxvk-cache") {
                fm.removeIfPresent(file)
                cleared += 1
            }
            let (_, output) = await Shell.capture("/usr/bin/getconf", ["DARWIN_USER_CACHE_DIR"])
            let base = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let exeName = URL(fileURLWithPath: g.exePath).deletingPathExtension().lastPathComponent.lowercased()
            if !base.isEmpty, !exeName.isEmpty {
                let d3dm = URL(fileURLWithPath: base).appendingPathComponent("d3dm")
                let cacheItems = (try? fm.contentsOfDirectory(at: d3dm, includingPropertiesForKeys: nil)) ?? []
                for entry in cacheItems where entry.lastPathComponent.lowercased().contains(exeName) {
                    fm.removeIfPresent(entry)
                    cleared += 1
                }
            }
            noticeMessage = cleared > 0
                ? "Cleared \(g.name)'s shader cache. The first few minutes of play may stutter while it rebuilds."
                : "\(g.name) doesn't have a shader cache Ferry can find."
        }
    }
}
