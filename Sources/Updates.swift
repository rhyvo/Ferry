import Foundation

extension AppModel {
    func startUpdateChecks() {
        Task {
            var opening = true
            while true {
                await checkForUpdatesIfDue(opening: opening)
                opening = false
                try? await Task.sleep(nanoseconds: 3_600 * 1_000_000_000)
            }
        }
    }

    private func checkForUpdatesIfDue(opening: Bool) async {
        guard setupComplete, !setupRunning, !updating else { return }
        let defaults = UserDefaults.standard
        let daily = defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true
        let onOpen = opening && (defaults.object(forKey: "checkOnLaunch") as? Bool ?? true)
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        if onOpen || (daily && (lastFerryCheck ?? .distantPast) < dayAgo) { await checkFerryVersion() }
        if onOpen || (daily && (runtimes.lastUpdateCheck ?? .distantPast) < dayAgo) { await runtimes.checkForUpdates() }
        promptIfNew()
    }

    var lastFerryCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastFerryCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastFerryCheck") }
    }

    private func promptIfNew() {
        let pending = runtimes.availableUpdates
        guard !pending.isEmpty else { return }
        let key = Set(pending.map { "\($0.rawValue)=\(runtimes.latest[$0] ?? "")" })
        guard !key.isSubset(of: promptedForUpdates) else { return }
        promptedForUpdates.formUnion(key)
        showUpdatePrompt = true
    }

    func checkForUpdatesNow() {
        guard setupComplete else {
            errorMessage = "Finish Ferry's setup first; it installs the newest versions of everything."
            return
        }
        Task {
            await checkFerryVersion()
            ferryUpdateHidden = false
            guard await runtimes.checkForUpdates() else {
                errorMessage = "Couldn't reach GitHub to check for updates. Check your internet connection and try again."
                return
            }
            if runtimes.availableUpdates.isEmpty {
                noticeMessage = ferryUpdate.map { "Ferry \($0) is available. Download it from the banner at the top of Ferry's window." }
                    ?? "Everything is up to date."
            } else {
                showUpdatePrompt = true
            }
        }
    }

    static let releasesPage = URL(string: "https://github.com/rhyvo/Ferry/releases/latest")!

    func checkFerryVersion() async {
        guard let (tag, _) = try? await GitHub.latestAssets(repo: "rhyvo/Ferry"), !tag.isEmpty else { return }
        lastFerryCheck = Date()
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let mine = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        ferryUpdate = Self.isNewer(latest, than: mine) ? latest : nil
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    var updateSummary: String {
        var lines = runtimes.availableUpdates.map { kind in
            "\(kind.title): \(runtimes.info[kind]?.version ?? "?") → \(runtimes.latest[kind] ?? "?")"
        }
        if runtimes.availableUpdates.contains(.gptk), runtimes.info[.gptk]?.d3dmetalImported != nil {
            lines.append("\nUpdating Game Porting Toolkit replaces the D3DMetal you imported; import it again afterwards if you still need it.")
        }
        lines.append("\nYour games, apps, settings and saves are kept.")
        return lines.joined(separator: "\n")
    }

    func finishInterruptedRebuilds() {
        guard setupComplete, !updating, !setupRunning, running.isEmpty else { return }
        let stale = [RuntimeKind.staging, .gptk, .arm64, .mach9, .x64].filter { kind in
            guard let installed = runtimes.info[kind]?.version,
                  fm.exists(templateURL(kind).appendingPathComponent("system.reg")) else { return false }
            let marker = (try? String(contentsOf: templateURL(kind).appendingPathComponent(".ferry-template"), encoding: .utf8)) ?? ""
            return marker.split(separator: " ").first.map(String.init) != installed
        }
        let unfilled = [RuntimeKind.staging, .gptk, .arm64, .mach9, .x64].filter { runtimes.info[$0] != nil && !stale.contains($0) && needsFilling($0) }
        guard !stale.isEmpty || !unfilled.isEmpty else { return }
        updating = true
        Task {
            defer { updating = false; status = nil }
            for kind in stale { _ = try? await buildTemplate(kind) }
            for kind in unfilled { await fillMissingLibraries(kind) }
            refreshSetupState()
            refreshComponentStatus()
        }
    }

    func installUpdates() {
        guard !updating, !setupRunning else { return }
        guard running.isEmpty else {
            errorMessage = "Quit the games and apps running in Ferry first, then update. Updating Wine underneath a running program can crash it."
            return
        }
        let kinds = runtimes.availableUpdates
        guard !kinds.isEmpty else { return }
        updating = true
        Task {
            defer { updating = false; status = nil }
            do {
                for kind in kinds { try await runtimes.install(kind) }
                let rebuild = Set(kinds.map { $0 == .dxvk ? RuntimeKind.staging : $0 })
                for kind in [RuntimeKind.staging, .gptk, .arm64, .mach9, .x64] where rebuild.contains(kind) && runtimes.info[kind] != nil {
                    try await buildTemplate(kind)
                }
                refreshSetupState()
                noticeMessage = "Updated \(kinds.map(\.title).joined(separator: ", ")). Games and apps pick up the new version the next time they start."
            } catch {
                errorMessage = "The update didn't finish: \(error.localizedDescription)"
            }
        }
    }
}
