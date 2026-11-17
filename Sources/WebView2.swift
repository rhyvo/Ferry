import Foundation

extension AppModel {
    static let webView2Prefix = Paths.runtimes.appendingPathComponent("webview2", isDirectory: true)

    func webView2Folder() -> URL? {
        let driveC = Self.webView2Prefix.appendingPathComponent("drive_c", isDirectory: true)
        for programFiles in ["Program Files (x86)", "Program Files"] {
            let app = driveC.appendingPathComponent("\(programFiles)/Microsoft/EdgeWebView/Application", isDirectory: true)
            let versions = ((try? fm.contentsOfDirectory(atPath: app.path)) ?? [])
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            if let v = versions.first(where: { fm.exists(app.appendingPathComponent("\($0)/msedgewebview2.exe")) }) {
                return app.appendingPathComponent(v, isDirectory: true)
            }
        }
        return nil
    }

    func installWebView2() async throws {
        if webView2Folder() != nil { webView2Installed = true; return }
        guard let wine = runtimes.wine(for: .staging, arch: .x64), fm.isDirectory(templateURL(.staging)) else {
            throw FerryError("WebView2 is installed with the Wine Staging engine, which isn't set up. Use Settings ▸ Components ▸ Run Setup Again.")
        }
        status = "Downloading WebView2 (about 215 MB, only once)…"
        guard let installer = await webView2Installer() else {
            throw FerryError("WebView2 couldn't be downloaded. Check your connection and try again.")
        }

        let building = Paths.runtimes.appendingPathComponent("webview2.building", isDirectory: true)
        let log = Paths.logs.appendingPathComponent("webview2.log")
        fm.removeIfPresent(building)
        _ = Shell.openLog(log, truncate: true).map { try? $0.close() }
        await Shell.run("/bin/cp", ["-cR", templateURL(.staging).path, building.path])
        let env = baseEnvironment(prefix: building)
        let server = runtimes.wineserver(for: .staging)

        status = "Installing WebView2 (only once, usually a couple of minutes)…"
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
            if !Task.isCancelled, let server { await Shell.run(server.path, ["-k"], env: env, log: log) }
        }
        await Shell.run(wine.path, [installer.path, "/silent", "/install"], env: env, log: log)
        watchdog.cancel()
        if let server { await Shell.run(server.path, ["-k"], env: env, log: log) }

        fm.removeIfPresent(Self.webView2Prefix)
        try fm.moveItem(at: building, to: Self.webView2Prefix)
        guard webView2Folder() != nil else {
            fm.removeIfPresent(Self.webView2Prefix)
            throw FerryError("WebView2 didn't install. Details are in \(log.path).")
        }
        webView2Installed = true
    }

    func withWebView2(_ p: PreparedGame) -> PreparedGame {
        guard let g = game(p.game.id), g.settings.webView2, let folder = webView2Folder() else { return p }
        var env = p.env
        env["WEBVIEW2_BROWSER_EXECUTABLE_FOLDER"] = "Z:" + folder.path.replacingOccurrences(of: "/", with: "\\")
        return PreparedGame(game: p.game, engine: p.engine, kind: p.kind, wine: p.wine, prefix: p.prefix, env: env)
    }
}
