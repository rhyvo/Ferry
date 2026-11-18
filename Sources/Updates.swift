import Foundation

extension AppModel {
    func startUpdateChecks() {
        Task {
            while true {
                await checkForUpdatesIfDue()
                try? await Task.sleep(nanoseconds: 3_600 * 1_000_000_000)
            }
        }
    }

    private func checkForUpdatesIfDue() async {
        guard setupComplete, !setupRunning, !updating else { return }
        guard UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true else { return }
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        if (runtimes.lastUpdateCheck ?? .distantPast) < dayAgo {
            await runtimes.checkForUpdates()
        }
        promptIfNew()
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
            guard await runtimes.checkForUpdates() else {
                errorMessage = "Couldn't reach GitHub to check for updates. Check your internet connection and try again."
                return
            }
            if runtimes.availableUpdates.isEmpty {
                noticeMessage = "Everything is up to date."
            } else {
                showUpdatePrompt = true
            }
        }
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
