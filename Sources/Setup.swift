import Foundation

enum SetupStep: Int, CaseIterable, Identifiable {
    case rosetta, gstreamer, sevenZip, gptk, staging, dxvk, arm64, mach9, libraries, stagingTemplate, gptkTemplate, arm64Template, mach9Template

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .rosetta: return "Rosetta 2"
        case .gstreamer: return "GStreamer"
        case .sevenZip: return "7-Zip"
        case .gptk: return "Game Porting Toolkit (D3DMetal)"
        case .staging: return "Wine Staging"
        case .dxvk: return "DXVK"
        case .arm64: return "MetalSharp Wine (no Rosetta)"
        case .mach9: return "Mach9 Wine (no Rosetta)"
        case .libraries: return "Windows libraries"
        case .gptkTemplate: return "Windows environment for D3DMetal"
        case .stagingTemplate: return "Windows environment for Wine Staging"
        case .arm64Template: return "Windows environment for Mullion"
        case .mach9Template: return "Windows environment for Mach9"
        }
    }

    var detail: String {
        switch self {
        case .rosetta: return "Lets Apple silicon run Windows' Intel code"
        case .gstreamer: return "Video cutscenes for Wine Staging games (asks for your password)"
        case .sevenZip: return "Faster unpacking for games that come as archives, including multi-part ones"
        case .gptk: return "DirectX 11/12 → Metal, for modern 64-bit games"
        case .staging: return "32-bit games, older DirectX, OpenGL"
        case .dxvk: return "DirectX 10/11 → Vulkan → Metal"
        case .arm64: return "Native Apple-silicon Wine with Mullion (DXMT); doesn't need Rosetta"
        case .mach9: return "DirectX 9 → Metal (mtld3d) and DirectX 10–12 → Metal (DXMT, vkd3d-proton); doesn't need Rosetta"
        case .libraries: return "Visual C++ 2005–2022, DirectX 2010 and its shader compiler, .NET Framework 2.0–4.8, .NET 6 and 8, XNA 4.0, OpenAL, PhysX, LAV video codecs"
        case .gptkTemplate: return "64-bit Visual C++ (copied from Wine Staging's), the shader compiler and fonts"
        case .stagingTemplate: return "Every library and font, plus DXVK, so new games and apps start instantly (.NET takes several minutes)"
        case .arm64Template: return "Every library and font, including the 32-bit ones (macOS 26.4 and later)"
        case .mach9Template: return "Every library and font, 32- and 64-bit, for DirectX 9–12 games on Metal"
        }
    }
}

enum StepState { case pending, running, done, failed, skipped, off }

extension AppModel {
    static let templateSignature = GameSettings().registrySignature

    func templateURL(_ kind: RuntimeKind) -> URL {
        Paths.templates.appendingPathComponent("windows-\(kind.rawValue)", isDirectory: true)
    }

    private func templateReady(_ kind: RuntimeKind) -> Bool {
        fm.exists(templateURL(kind).appendingPathComponent("system.reg"))
    }

    func refreshSetupState() {
        refreshComponentStatus()
        let finished = UserDefaults.standard.bool(forKey: "setupComplete")
        setupComplete = finished && templateReady(.gptk) && templateReady(.staging)
        let current = "libs\(Self.librarySetVersion)"
        librariesOutdated = setupComplete && [RuntimeKind.gptk, .staging, .arm64, .mach9, .x64].contains { kind in
            guard templateReady(kind) else { return false }
            let marker = (try? String(contentsOf: templateURL(kind).appendingPathComponent(".ferry-template"), encoding: .utf8)) ?? ""
            return !marker.contains(current)
        }
    }

    func downloadEstimates() async -> [Component: Int] {
        var sizes: [Component: Int] = [:]
        for component in Component.allCases {
            guard let kind = component.runtime, runtimes.info[kind] == nil else { continue }
            if let found = try? await GitHub.latestAsset(repo: kind.repo, matching: kind.matches) {
                sizes[component] = found.asset.size
            }
        }
        if !runtimes.gstreamerInstalled, let package = await runtimes.gstreamerPackage() {
            sizes[.gstreamer] = await runtimes.remoteSize(package.url) ?? 0
        }
        return sizes
    }

    static func plannedBytes(measured: [Component: Int]) -> Int {
        Component.allCases.filter(Component.isOn).reduce(0) { $0 + (measured[$1] ?? $1.approxBytes) }
    }

    func runSetup() {
        guard !setupRunning else { return }
        setupRunning = true
        setupError = nil
        for step in SetupStep.allCases { setupSteps[step] = .pending }

        Task {
            defer { setupRunning = false; status = nil; buildStatus = [:] }
            var current = SetupStep.rosetta
            do {
                current = .rosetta
                setupSteps[.rosetta] = .running
                await runtimes.checkRosetta()
                if !runtimes.rosetta { await runtimes.installRosetta() }
                guard runtimes.rosetta else {
                    throw FerryError("Rosetta 2 didn't install. macOS asks for your password to install it; click Try Again and enter it.")
                }
                setupSteps[.rosetta] = .done
                var skipped: [String] = []

                current = .gstreamer
                if Component.isOn(.gstreamer) {
                    setupSteps[.gstreamer] = .running
                    do {
                        try await runtimes.installGStreamer()
                        setupSteps[.gstreamer] = .done
                    } catch {
                        setupSteps[.gstreamer] = .skipped
                        skipped.append("GStreamer (video cutscenes)")
                    }
                } else {
                    setupSteps[.gstreamer] = .off
                }

                current = .sevenZip
                if Component.isOn(.sevenZip) {
                    setupSteps[.sevenZip] = .running
                    do {
                        try await runtimes.installSevenZip()
                        setupSteps[.sevenZip] = .done
                    } catch {
                        setupSteps[.sevenZip] = .skipped
                        skipped.append("7-Zip (faster unpacking)")
                    }
                } else {
                    setupSteps[.sevenZip] = .off
                }

                for (step, kind) in [(SetupStep.gptk, RuntimeKind.gptk), (.staging, .staging)] {
                    current = step
                    setupSteps[step] = .running
                    try await runtimes.ensure(kind)
                    setupSteps[step] = .done
                }
                current = .dxvk
                if Component.isOn(.dxvk) {
                    setupSteps[.dxvk] = .running
                    try await runtimes.ensure(.dxvk)
                    setupSteps[.dxvk] = .done
                } else {
                    setupSteps[.dxvk] = .off
                }

                current = .arm64
                if Component.isOn(.metalSharp) {
                    setupSteps[.arm64] = .running
                    do {
                        try await runtimes.ensure(.arm64)
                        setupSteps[.arm64] = .done
                    } catch {
                        setupSteps[.arm64] = .skipped
                        skipped.append("MetalSharp Wine (\(error.localizedDescription))")
                    }
                } else {
                    setupSteps[.arm64] = .off
                }

                current = .mach9
                if Component.isOn(.mach9) {
                    setupSteps[.mach9] = .running
                    do {
                        try await runtimes.ensure(.mach9)
                        setupSteps[.mach9] = .done
                    } catch {
                        setupSteps[.mach9] = .skipped
                        skipped.append("Mach9 Wine (\(error.localizedDescription))")
                    }
                } else {
                    setupSteps[.mach9] = .off
                }

                current = .libraries
                setupSteps[.libraries] = .running
                skipped += await downloadWindowsLibraries()
                if Component.isOn(.dotNet48) {
                    do { try await installDotNetLoader(); try await installManagedDirectX() } catch { skipped.append(".NET loader and Managed DirectX") }
                }
                setupSteps[.libraries] = .done

                var mullionJob: Task<[String], Never>? = nil
                if runtimes.info[.arm64] != nil && Component.isOn(.metalSharp) {
                    setupSteps[.arm64Template] = .running
                    mullionJob = Task {
                        do {
                            let missed = try await self.buildTemplate(.arm64)
                            self.setupSteps[.arm64Template] = .done
                            return missed
                        } catch {
                            self.setupSteps[.arm64Template] = .skipped
                            return ["the Mullion Windows environment"]
                        }
                    }
                } else {
                    setupSteps[.arm64Template] = Component.isOn(.metalSharp) ? .skipped : .off
                }
                var mach9Job: Task<[String], Never>? = nil
                if runtimes.info[.mach9] != nil && Component.isOn(.mach9) {
                    setupSteps[.mach9Template] = .running
                    mach9Job = Task {
                        do {
                            let missed = try await self.buildTemplate(.mach9)
                            self.setupSteps[.mach9Template] = .done
                            return missed
                        } catch {
                            self.setupSteps[.mach9Template] = .skipped
                            return ["the Mach9 Windows environment"]
                        }
                    }
                } else {
                    setupSteps[.mach9Template] = Component.isOn(.mach9) ? .skipped : .off
                }

                var buildError: Error? = nil
                do {
                    for (step, kind) in [(SetupStep.stagingTemplate, RuntimeKind.staging), (.gptkTemplate, .gptk)] {
                        current = step
                        setupSteps[step] = .running
                        skipped += try await buildTemplate(kind)
                        setupSteps[step] = .done
                    }
                } catch {
                    buildError = error
                }
                if let mullionJob { skipped += await mullionJob.value }
                if let mach9Job { skipped += await mach9Job.value }
                if let buildError { throw buildError }

                if Component.isOn(.webView2) {
                    do { try await installWebView2() } catch { skipped.append("WebView2") }
                }

                UserDefaults.standard.set(true, forKey: "setupComplete")
                refreshSetupState()
                let missing = Array(Set(skipped)).sorted()
                if !missing.isEmpty {
                    noticeMessage = "Setup finished, but these were skipped: \(missing.joined(separator: ", ")). Most games don't need them; use Settings ▸ System ▸ Run Setup Again later to add them."
                }
            } catch {
                setupSteps[current] = .failed
                setupError = error.localizedDescription
                if setupComplete { errorMessage = "Setup didn't finish: \(error.localizedDescription)" }
            }
        }
    }

    func report(_ text: String?, for kind: RuntimeKind) {
        buildStatus[kind] = text
        let labels: [RuntimeKind: String] = [.staging: "Wine Staging", .gptk: "D3DMetal", .arm64: "Mullion", .mach9: "Mach9",
                                             .x64: "D3DMetal 4"]
        let active = [RuntimeKind.staging, .gptk, .arm64, .mach9, .x64].compactMap { k in buildStatus[k].map { (labels[k] ?? k.title, $0) } }
        switch active.count {
        case 0: status = nil
        case 1: status = active[0].1
        default: status = active.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        }
    }

    @discardableResult
    func buildTemplate(_ kind: RuntimeKind) async throws -> [String] {
        guard let wine = runtimes.wine(for: kind, arch: .x64) else {
            throw FerryError("\(kind.title) isn't installed.")
        }
        let destination = templateURL(kind)
        let kept = Self.checkableLibraries.filter { libraryInstalled($0, in: kind) }.map(\.rawValue)
        let building = Paths.templates.appendingPathComponent("windows-\(kind.rawValue).building", isDirectory: true)
        let log = Paths.logs.appendingPathComponent("setup-\(kind.rawValue).log")
        fm.removeIfPresent(building)
        _ = Shell.openLog(log, truncate: true).map { try? $0.close() }

        let env = baseEnvironment(prefix: building)
        let server = runtimes.wineserver(for: kind)
        func waitForWine() async {
            if let server { await Shell.run(server.path, ["-w"], env: env, log: log) }
        }

        let label: String
        switch kind {
        case .gptk: label = "D3DMetal"
        case .arm64: label = "Mullion"
        case .mach9: label = "Mach9"
        case .x64: label = "D3DMetal 4"
        default: label = "Wine Staging"
        }
        report("Creating the \(label) Windows environment…", for: kind)
        await Shell.run(wine.path, ["wineboot", "--init"], env: env, log: log)
        await waitForWine()
        guard fm.exists(building.appendingPathComponent("system.reg")) else {
            throw FerryError("Wine couldn't create a Windows environment. Details are in \(log.path).")
        }

        report("Applying default settings…", for: kind)
        await applyWindowsSettings(GameSettings(), wine: wine, env: env, prefix: building, log: log, kind: kind)

        let skipped = await installWindowsLibraries(wine: wine, env: env, prefix: building, kind: kind, log: log)
        report("Adding fonts…", for: kind)
        await installFonts(wine: wine, env: env, prefix: building, log: log)
        if kind == .staging, runtimes.info[.dxvk] != nil { installDXVK(into: building) }
        await waitForWine()

        try? "\(runtimes.info[kind]?.version ?? "?") \(runtimes.info[kind]?.asset ?? "") libs\(Self.librarySetVersion)".write(to: building.appendingPathComponent(".ferry-template"),
                                                          atomically: true, encoding: .utf8)
        try? kept.joined(separator: " ").write(to: building.appendingPathComponent(".ferry-keep"), atomically: true, encoding: .utf8)
        fm.removeIfPresent(destination)
        try fm.moveItem(at: building, to: destination)
        await fillMissingLibraries(kind)
        report(nil, for: kind)
        return skipped
    }

    func updateEngine(_ kind: RuntimeKind) async throws {
        guard running.isEmpty else {
            throw FerryError("Quit the games and apps running in Ferry first. Updating Wine underneath a running program can crash it.")
        }
        guard !updating else { return }
        updating = true
        defer { updating = false; status = nil }
        try await runtimes.install(kind)
        let templateKind: RuntimeKind = kind == .dxvk ? .staging : kind
        if runtimes.info[templateKind] != nil {
            try await buildTemplate(templateKind)
        }
        refreshSetupState()
    }

    func removeEngine(_ kind: RuntimeKind) {
        runtimes.remove(kind)
        if kind != .dxvk { fm.removeIfPresent(templateURL(kind)) }
        refreshSetupState()
    }
}
