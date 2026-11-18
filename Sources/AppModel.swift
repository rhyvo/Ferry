import AppKit
import Foundation
import UniformTypeIdentifiers

struct PreparedGame {
    let game: Game
    let engine: EngineID
    let kind: RuntimeKind
    let wine: URL
    let prefix: URL
    let env: [String: String]
}

struct PairOffer {
    let gameID: UUID
    let gameName: String
    let program: URL
    let role: ProgramRole
}

struct InstalledOffer {
    let gameID: UUID
    let installer: String
    let engine: EngineID
    let programs: [InstalledPrograms.Candidate]
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let runtimes = RuntimeManager()
    @Published var games: [Game] = []
    @Published var running: Set<UUID> = []
    @Published var preparing: Set<UUID> = []
    @Published var status: String? = nil
    @Published var errorMessage: String? = nil
    @Published var iconRevision = 0
    @Published var showStorage = false
    @Published var lowPowerPrompt: UUID? = nil
    @Published var webView2Installed = false
    @Published var componentStatus: [Component: ComponentStatus] = [:]
    @Published var installingComponent: Component? = nil
    @Published var rovPrompt: UUID? = nil
    @Published var installedOffer: InstalledOffer? = nil
    @Published var pairOffer: PairOffer? = nil
    private let backdrop = FullscreenBackdrop()
    private var installWatches: [UUID: (before: InstalledPrograms.Snapshot, engine: EngineID, driveC: URL)] = [:]
    @Published var troubleshootGame: UUID? = nil
    @Published var modsGame: UUID? = nil
    var modWorkInFlight = 0
    var lowPowerAcknowledged = false
    @Published var storageSuggestion: Int64? = nil

    @Published var setupComplete = false
    @Published var setupRunning = false
    @Published var setupSteps: [SetupStep: StepState] = [:]
    @Published var setupError: String? = nil

    @Published var librariesOutdated = false
    var buildStatus: [RuntimeKind: String] = [:]

    @Published var showUpdatePrompt = false
    @Published var updating = false
    @Published var noticeMessage: String? = nil
    var promptedForUpdates: Set<String> = []

    @Published var launchFailure: LaunchFailure? = nil
    var stopping: Set<UUID> = []
    var discordCurrent: UUID? = nil

    private var processes: [UUID: Process] = [:]
    private var handoffPIDs: [UUID: [Int32]] = [:]
    private var helpers: [UUID: Process] = [:]
    let fm = FileManager.default

    init() {
        Paths.ensure()
        clearModWork()
        load()
        detectMissingFrameworks()
        lookUpUnknownGraphics()
        refreshMissingIcons()
        refreshSetupState()
        finishInterruptedRebuilds()
        if let removed = runtimes.removeIncompatibleD3DMetal() {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                noticeMessage = "D3DMetal \(removed) needs a newer Wine than Ferry's D3DMetal engine has, so games couldn't start with it. Ferry put the bundled D3DMetal back. D3DMetal \(removed) can be imported again once a Game Porting Toolkit 4 build of Wine is released."
            }
        }
        startUpdateChecks()
        startDiscordStatus()
        Task { [weak self] in
            while let self {
                self.backdrop.update(gamesRunning: !self.running.isEmpty)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            checkForReclaimableStorage()
        }
        Task { await endLeftoverWine() }
    }

    func game(_ id: UUID) -> Game? { games.first { $0.id == id } }

    func update(_ game: Game) {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        let old = games[i]
        games[i] = game
        save()
        if game.iconMode == .auto && (old.exePath != game.exePath || old.iconMode != .auto) { refreshAutoIcon(game) }
    }

    private func detectMissingFrameworks() {
        let unchecked = games.filter { $0.framework == nil && fm.exists(URL(fileURLWithPath: $0.exePath)) }
        guard !unchecked.isEmpty else { return }
        let rosetta = runtimes.rosetta
        Task {
            for g in unchecked {
                let exe = URL(fileURLWithPath: g.exePath)
                guard let handle = try? FileHandle(forReadingFrom: exe) else { continue }
                try? handle.close()
                let found = await Task.detached {
                    Analyzer.analyze(exe: exe, root: exe.deletingLastPathComponent(), candidates: [], rosetta: rosetta).framework
                }.value
                guard var current = game(g.id) else { continue }
                current.framework = found ?? ""
                update(current)
            }
        }
    }

    private func lookUpUnknownGraphics() {
        let unknown = games.filter {
            $0.graphics == .unknown && $0.sharedWith == nil && URL(fileURLWithPath: $0.exePath).pathExtension.lowercased() == "exe"
        }
        guard GameWiki.enabled, !unknown.isEmpty else { return }
        Task {
            for g in unknown {
                let exe = URL(fileURLWithPath: g.exePath)
                guard let handle = try? FileHandle(forReadingFrom: exe) else { continue }
                try? handle.close()
                guard let found = await GameWiki.lookup(exe: exe)?.graphics, var current = game(g.id),
                      current.graphics == .unknown else { continue }
                current.graphics = found
                update(current)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.library) else { return }
        games = (try? JSONDecoder().decode([Game].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(games) { try? data.write(to: Paths.library, options: .atomic) }
    }

    static let acceptedExtensions = ["exe", "msi", "bat"]

    @discardableResult
    func add(_ url: URL, launch: Bool = true, settings: GameSettings? = nil, name: String? = nil) -> Task<UUID?, Never> {
        guard setupComplete, !setupRunning else {
            errorMessage = "Finish setting up Ferry first: click Install in the main window. After that you can drop in games."
            return Task { nil }
        }
        guard Self.acceptedExtensions.contains(url.pathExtension.lowercased()) else {
            errorMessage = "Ferry runs Windows .exe, .msi and .bat files. For a game folder or a .zip, .rar or .7z, use Check Compatibility (⌘K), which finds the program inside."
            return Task { nil }
        }
        if var existing = games.first(where: { $0.exePath == url.path }) {
            if let settings {
                existing.settings = settings
                update(existing)
            }
            if launch { play(existing.id) }
            return Task { existing.id }
        }
        let rosetta = runtimes.rosetta
        return Task {
            let report = await Task.detached {
                await Analyzer.analyzeWithLookup(exe: url, root: url.deletingLastPathComponent(), candidates: [], rosetta: rosetta)
            }.value
            if report.verdict == .wontWork, let blocker = report.findings.first(where: { $0.level == .blocker }) {
                errorMessage = "\(url.lastPathComponent) can't run in Ferry. \(blocker.text)"
                return nil
            }
            var g = Game(name: name ?? Self.friendlyName(for: url), exePath: url.path, arch: report.arch, graphics: report.graphics,
                         settings: settings ?? report.settings)
            g.framework = report.framework ?? ""
            games.insert(g, at: 0)
            save()
            refreshAutoIcon(g)
            if launch { play(g.id) }
            await offerPartnerProgram(for: g)
            return g.id
        }
    }

    static func friendlyName(for url: URL) -> String { Naming.friendlyName(for: url) }

    func sharers(of id: UUID) -> [Game] { games.filter { $0.sharedWith == id } }

    func environmentOwner(of g: Game) -> Game {
        if let ownerID = g.sharedWith, let owner = game(ownerID) { return owner }
        return g
    }

    func remove(_ id: UUID, deleteWindowsFiles: Bool) {
        let ids = [id] + sharers(of: id).map(\.id)
        for gone in ids { stop(gone); installWatches[gone] = nil }
        games.removeAll { ids.contains($0.id) }
        save()
        for gone in ids where deleteWindowsFiles || gone != id {
            fm.removeIfPresent(bottleURL(gone))
        }
        for gone in ids { removeIcons(gone) }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.acceptedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a Windows game, app or installer"
        if panel.runModal() == .OK, let url = panel.url { add(url) }
    }

    func pickExecutable(for game: Game) async -> Game? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.acceptedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose the .exe Ferry should start for \(game.name)"
        let exe = URL(fileURLWithPath: game.exePath)
        let driveC = prefixURL(game.id, runtimeKind(game)).appendingPathComponent("drive_c")
        let installed = !fm.exists(exe) || ModLayout.looksLikeInstaller(exe)
        panel.directoryURL = installed && fm.exists(driveC) ? driveC : programFolder(for: exe)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return await retarget(game, to: url)
    }

    func retarget(_ game: Game, to url: URL) async -> Game {
        let rosetta = runtimes.rosetta
        let report = await Task.detached {
            Analyzer.analyze(exe: url, root: url.deletingLastPathComponent(), candidates: [], rosetta: rosetta)
        }.value
        var changed = game
        changed.exePath = url.path
        changed.arch = report.arch
        changed.graphics = report.graphics
        changed.framework = report.framework ?? ""
        return changed
    }

    func programFolder(for exe: URL) -> URL {
        let folder = exe.deletingLastPathComponent()
        let plumbing = ["bin", "bin32", "bin64", "binaries", "win32", "win64", "x86", "x64", "system", "system32"]
        return plumbing.contains(folder.lastPathComponent.lowercased()) ? folder.deletingLastPathComponent() : folder
    }

    func runtimeKind(_ g: Game) -> RuntimeKind {
        let engine = resolvedEngine(g)
        return engine == .mullion && mullionOnRosetta(g) ? .x64 : engine.runtime
    }

    func mullionOnRosetta(_ g: Game) -> Bool {
        environmentOwner(of: g).settings.mullionRosetta && runtimes.info[.x64] != nil && runtimes.rosetta
    }

    func resolvedEngine(_ g: Game) -> EngineID {
        let own = ownEngine(g)
        let owner = environmentOwner(of: g)
        if owner.id != g.id {
            let ownerEngine = ownEngine(owner)
            if own.runtime != ownerEngine.runtime { return ownerEngine }
        }
        return own
    }

    private func ownEngine(_ g: Game) -> EngineID {
        if g.settings.engine != .auto { return g.settings.engine }
        return recommendedEngine(g)
    }

    func recommendedEngine(_ g: Game) -> EngineID {
        let isExe = URL(fileURLWithPath: g.exePath).pathExtension.lowercased() == "exe"
        let framework = (g.framework?.isEmpty ?? true) ? nil : g.framework
        return EngineAdvisor.pick(arch: g.arch, graphics: g.graphics, framework: framework, isExe: isExe, rosetta: runtimes.rosetta).engine
    }

    static var metalSharpRuns32bit: Bool { Platform.metalSharpRuns32bit }

    static func canRun(_ arch: PEArch, on engine: EngineID) -> Bool {
        guard arch == .x86 else { return true }
        if engine == .d3dmetal { return false }
        if engine == .mullion { return metalSharpRuns32bit }
        return true
    }

    func fallbackOrder(for g: Game) -> [EngineID] {
        EngineAdvisor.fallbacks(after: recommendedEngine(g), arch: g.arch, graphics: g.graphics, rosetta: runtimes.rosetta)
    }

    func subtitle(for g: Game) -> String {
        let engine = resolvedEngine(g)
        let engineText = g.settings.engine == .auto ? "\(engine.short) (auto)" : engine.short
        var parts = [g.graphics.label, g.arch.label, engineText]
        let owner = environmentOwner(of: g)
        if owner.id != g.id { parts.append("in \(owner.name)") }
        return parts.joined(separator: " · ")
    }

    func bottleURL(_ id: UUID) -> URL { Paths.bottles.appendingPathComponent(id.uuidString, isDirectory: true) }

    func prefixURL(_ id: UUID, _ kind: RuntimeKind) -> URL {
        let ownerID = game(id)?.sharedWith ?? id
        return bottleURL(ownerID).appendingPathComponent("windows-\(kind.rawValue)", isDirectory: true)
    }

    func logURL(_ id: UUID, _ name: String) -> URL {
        bottleURL(id).appendingPathComponent("logs/\(name).log")
    }

    func baseEnvironment(prefix: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        env["WINEBOOT_HIDE_DIALOG"] = "1"
        return env
    }

    func environment(for g: Game, engine: EngineID, prefix: URL) -> [String: String] {
        let s = g.settings
        var env = baseEnvironment(prefix: prefix)
        env["WINEDEBUG"] = "fixme-all"
        if s.fastSync { env["WINEMSYNC"] = "1"; env["WINEESYNC"] = "1" }
        if s.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        if s.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        let cap = frameCap(g)
        if s.vsync {
            env["FERRY_VSYNC"] = "1"
            env["FERRY_VSYNC_HZ"] = "\(Platform.displayHz)"
        }

        let ownerID = g.sharedWith ?? g.id
        var overrides: String
        switch engine {
        case .dxvk:
            overrides = "dxgi,d3d10core,d3d11=n,b;d3d9,d3d12=b"
            env["DXVK_LOG_PATH"] = "none"
            try? FileManager.default.createDirectory(at: shaderCacheURL(ownerID), withIntermediateDirectories: true)
            env["DXVK_STATE_CACHE_PATH"] = shaderCacheURL(ownerID).path
            env["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"
            if s.metalHUD { env["DXVK_HUD"] = "fps,devinfo" }
        case .d3dmetal where engine.runtime == .x64:
            overrides = ""
            if usesVSyncD3D12(g, engine: engine) {
                overrides = "d3d12=n,b"
                if !s.hideROV && !watchesForROV(g, engine: engine) { env["FERRY_ROV_MODE"] = "off" }
            }
            env["GRAPHICS_BACKEND"] = "d3dmetal"
            if s.reportNVIDIA && env["D3DM_DEVICE_DESCRIPTION"] == nil {
                env["D3DM_DEVICE_DESCRIPTION"] = "NVIDIA GeForce RTX 3060"
                env["D3DM_VENDOR_ID"] = "0x10DE"
                env["D3DM_DEVICE_ID"] = "0x2503"
            }
            if s.metalFX { env["D3DM_ENABLE_METALFX"] = "1" }
        case .d3dmetal:
            overrides = "dxgi,d3d9,d3d10core,d3d11,d3d12=b"
            if watchesForROV(g, engine: engine) {
                overrides = "dxgi,d3d9,d3d10core,d3d11=b;d3d12=n,b"
                env["FERRY_ROV_MODE"] = "watch"
                env["FERRY_ROV_REPORT"] = "Z:" + rovReportURL(g.id).path.replacingOccurrences(of: "/", with: "\\")
            } else if s.hideROV {
                overrides = "dxgi,d3d9,d3d10core,d3d11=b;d3d12=n,b"
            } else if usesVSyncD3D12(g, engine: engine) {
                overrides = "dxgi,d3d9,d3d10core,d3d11=b;d3d12=n,b"
                env["FERRY_ROV_MODE"] = "off"
            }
            if s.reportNVIDIA && env["D3DM_DEVICE_DESCRIPTION"] == nil {
                env["D3DM_DEVICE_DESCRIPTION"] = "NVIDIA GeForce RTX 3060"
                env["D3DM_VENDOR_ID"] = "0x10DE"
                env["D3DM_DEVICE_ID"] = "0x2503"
            }
            if s.metalFX { env["D3DM_ENABLE_METALFX"] = "1" }
        case .mullion where mullionOnRosetta(g):
            overrides = ""
            env["GRAPHICS_BACKEND"] = s.metalSharpBackend.isEmpty ? "dxmt" : s.metalSharpBackend
            if !s.metalSharpOpenGL.isEmpty { env["OPENGL_BACKEND"] = s.metalSharpOpenGL }
        case .mullion:
            overrides = ""
            if !s.metalSharpBackend.isEmpty { env["GRAPHICS_BACKEND"] = s.metalSharpBackend }
            if !s.metalSharpOpenGL.isEmpty { env["OPENGL_BACKEND"] = s.metalSharpOpenGL }
            if s.mullionVulkan == "kosmickrisp", let driver = runtimes.kosmicKrispDriver() {
                env["VK_DRIVER_FILES"] = driver.path
                env["VK_ICD_FILENAMES"] = driver.path
            }
            let bundled = usesBundledDXVK(g, engine: engine)
            if bundled || usesBetaDXVK(g, engine: engine), let driver = runtimes.kosmicKrispDriver() {
                if bundled && s.metalSharpBackend.isEmpty { env["GRAPHICS_BACKEND"] = "dxvk" }
                env["VK_DRIVER_FILES"] = driver.path
                env["VK_ICD_FILENAMES"] = driver.path
            }
        case .mach9:
            overrides = ""
        case .wined3d, .auto:
            overrides = "dxgi,d3d9,d3d10core,d3d11,d3d12=b"
        }
        if s.cncDdraw { overrides += overrides.isEmpty ? "ddraw=n,b" : ";ddraw=n,b" }
        if s.dxvkD3D9 && engine != .mach9 {
            overrides = overrides.replacingOccurrences(of: "d3d9,", with: "")
            overrides += overrides.isEmpty ? "d3d9=n,b" : ";d3d9=n,b"
            env["DXVK_LOG_PATH"] = "none"
            try? FileManager.default.createDirectory(at: shaderCacheURL(ownerID), withIntermediateDirectories: true)
            env["DXVK_STATE_CACHE_PATH"] = shaderCacheURL(ownerID).path
            env["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"
        }
        if s.dxvkD3D9 && g.arch != .x86 && [EngineID.wined3d, .dxvk, .auto].contains(engine), let resources = Bundle.main.resourcePath,
           fm.exists(URL(fileURLWithPath: resources + "/ferry-vk-layer.json")) {
            env["VK_ADD_LAYER_PATH"] = resources
            env["VK_INSTANCE_LAYERS"] = "VK_LAYER_FERRY_moltenvk_features"
        }
        var dxvkConfig: [String] = []
        if s.dxvkD3D9 && engine != .mach9, let mb = s.dxvkMemoryLimit(macGB: Platform.memoryGB) {
            dxvkConfig.append("d3d9.maxAvailableMemory = \(mb)")
        }
        let dxvkDraws = engine == .dxvk || (s.dxvkD3D9 && engine != .mach9) || (engine == .mullion && s.metalSharpBackend == "dxvk")
        if dxvkDraws, let cap {
            env["DXVK_FRAME_RATE"] = "\(cap)"
            dxvkConfig += ["dxgi.maxFrameRate = \(cap)", "d3d9.maxFrameRate = \(cap)"]
        }
        if dxvkDraws && s.vsync {
            dxvkConfig += ["dxgi.syncInterval = 1", "d3d9.presentInterval = 1"]
        }
        if !dxvkConfig.isEmpty {
            let file = bottleURL(ownerID).appendingPathComponent("dxvk.conf")
            try? (dxvkConfig.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            env["DXVK_CONFIG_FILE"] = "Z:" + file.path.replacingOccurrences(of: "/", with: "\\")
        }
        if engine == .mullion, let cap, ["", "dxmt"].contains(s.metalSharpBackend) {
            env["MULLION_CONFIG"] = ["d3d11.preferredMaxFrameRate=\(cap)", env["MULLION_CONFIG"]].compactMap { $0 }.joined(separator: ";")
        }
        if s.vsync && (engine == .mach9 || env["VK_DRIVER_FILES"] != nil) { env["MESA_VK_WSI_PRESENT_MODE"] = "fifo" }
        if usesD3D9Helper(g) && !drawsCopies(g) { env["FERRY_D3D9_COPIES"] = "off" }
        if usesD3D9Helper(g) && !overrides.contains("d3d9=n,b") {
            overrides = overrides.replacingOccurrences(of: "d3d9,", with: "")
            overrides += overrides.isEmpty ? "d3d9=n,b" : ";d3d9=n,b"
        }
        if usesD3D9Helper(g) && !s.dxvkD3D9 && [EngineID.wined3d, .dxvk, .auto].contains(engine),
           let wine = runtimes.wine(for: .staging, arch: g.arch == .x86 ? .x86 : .x64) {
            let own = wine.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("lib/wine/\(g.arch == .x86 ? "i386" : "x86_64")-windows/d3d9.dll")
            if fm.exists(own) { env["FERRY_D3D9_NEXT"] = "Z:" + own.path.replacingOccurrences(of: "/", with: "\\") }
        }
        if [EngineID.wined3d, .dxvk].contains(engine) {
            var d3d: [String] = []
            if s.wined3dVulkan { d3d.append("renderer=vulkan") }
            if s.wined3dSingleThread { d3d.append("csmt=0") }
            if !d3d.isEmpty { env["WINE_D3D_CONFIG"] = d3d.joined(separator: ",") }
        }

        for name in vsyncHelpers(g, engine: engine) { overrides = Self.nativeFirst(name, in: overrides) }
        for o in nativeXAudio2Overrides(g, engine: engine, prefix: prefix) + modOverrides(g) {
            overrides = overrides.isEmpty ? o : overrides + ";" + o
        }
        for (key, value) in EnvText.pairs(s.extraEnv) {
            if key == "WINEDLLOVERRIDES" {
                overrides = overrides.isEmpty ? value : overrides + ";" + value
            } else {
                env[key] = value
            }
        }
        if engine == .mach9 {
            mach9Environment(&env, settings: s, frameCap: cap, overrides: overrides, graphics: g.graphics, arch: g.arch)
        } else if !overrides.isEmpty {
            env["WINEDLLOVERRIDES"] = overrides
        }
        return env
    }

    private func mach9Environment(_ env: inout [String: String], settings s: GameSettings, frameCap cap: Int?, overrides: String,
                                  graphics: GraphicsAPI, arch: PEArch) {
        env["WINEDLLOVERRIDES"] = nil
        env["WINE_PROF_SERVICE"] = nil
        env["WINEMSYNC"] = s.fastSync ? "1" : "0"
        func escaped(_ value: String) -> String {
            var out = ""
            for scalar in value.unicodeScalars {
                if scalar == "%" || scalar == ";" || scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "%%%02X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
            return out
        }
        var rule = ["exe=*"]
        if s.mach9Direct3D == "wined3d" { rule += ["d3d9=wined3d", "dxgi=wined3d"] }
        if arch == .x86 && s.fullMemory32 { rule.append("large_address_aware=true") }
        if let prefix = env["WINEPREFIX"],
           fm.exists(URL(fileURLWithPath: prefix).appendingPathComponent("drive_c/windows/Microsoft.NET/Framework/v4.0.30319/clr.dll")) {
            rule.append("dll_overrides=mscoree=n,b")
        }
        for group in overrides.split(separator: ";") where group.contains("=") {
            rule.append("dll_overrides=" + escaped(String(group)))
        }
        for (key, value) in EnvText.pairs(s.extraEnv) where key != "WINEDLLOVERRIDES" {
            rule.append("env=" + escaped(key) + "=" + escaped(value))
        }
        if rule.count > 1 { env["WINE_COMPATDB"] = rule.joined(separator: ";") }

        if s.mach9Direct3D == "wined3d" {
            var d3d: [String] = []
            if s.wined3dVulkan { d3d.append("renderer=vulkan") }
            if s.wined3dSingleThread { d3d.append("csmt=0") }
            if !d3d.isEmpty, env["WINE_D3D_CONFIG"] == nil { env["WINE_D3D_CONFIG"] = d3d.joined(separator: ",") }
        } else {
            if s.retina && graphics == .dx9 {
                env["MTLD3D_CONFIG"] = ["display.maxResolutions=32", env["MTLD3D_CONFIG"]].compactMap { $0 }.joined(separator: ";")
            }
        }
        if s.mach9Direct3D != "wined3d", let cap {
            env["MTLD3D_CONFIG"] = ["present.maxFps=\(cap)", env["MTLD3D_CONFIG"]].compactMap { $0 }.joined(separator: ";")
            env["DXMT_CONFIG"] = ["d3d11.preferredMaxFrameRate=\(cap)", env["DXMT_CONFIG"]].compactMap { $0 }.joined(separator: ";")
        }
        if s.mach9Direct3D != "wined3d" && s.vsync {
            env["DXMT_CONFIG"] = ["dxgi.vsync=on", env["DXMT_CONFIG"]].compactMap { $0 }.joined(separator: ";")
        }
        if s.mach9Direct3D != "wined3d" && s.metalFX {
            if graphics == .dx9 {
                env["MTLD3D_CONFIG"] = ["render.scale=0.75", env["MTLD3D_CONFIG"]].compactMap { $0 }.joined(separator: ";")
            } else if env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == nil {
                env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"
            }
        }
    }

    func prepare(_ id: UUID) async throws -> PreparedGame {
        guard var g = game(id) else { throw FerryError("That program isn't in the library anymore.") }
        let engine = resolvedEngine(g)
        let kind = runtimeKind(g)
        if kind.needsRosetta {
            if !runtimes.rosetta { await runtimes.checkRosetta() }
            guard runtimes.rosetta else {
                throw FerryError("Rosetta 2 isn't installed, and \(engine.short) needs it. Open Ferry ▸ Settings ▸ System and click Install Rosetta, or set Translation to Mullion, which doesn't need Rosetta.")
            }
        }
        if engine == .d3dmetal && !Self.canRun(g.arch, on: engine) {
            throw FerryError("D3DMetal only runs 64-bit programs, and \(g.name) is 32-bit. In its settings, set Translation to DXVK, WineD3D or Mullion.")
        }
        if engine == .mach9 && !Platform.mach9Available {
            throw FerryError("Mach9 needs macOS 26.4 or later. In \(g.name)'s settings, set Translation to Auto.")
        }
        if engine == .mullion && !Self.canRun(g.arch, on: engine) {
            throw FerryError("MetalSharp Wine runs 32-bit programs only on macOS 26.4 or later. Set Translation to DXVK or WineD3D.")
        }
        try await runtimes.ensure(kind)
        if engine == .dxvk { try await runtimes.ensure(.dxvk) }
        if engine == .mullion && g.arch == .x86 {
            if runtimes.info[.arm64]?.asset?.lowercased().hasSuffix(".zip") != true {
                status = "Updating MetalSharp Wine to the version that runs 32-bit games…"
                try await runtimes.install(.arm64)
            }
            let asset = runtimes.info[.arm64]?.asset ?? "?"
            let marker = (try? String(contentsOf: templateURL(.arm64).appendingPathComponent(".ferry-template"), encoding: .utf8)) ?? ""
            if !marker.contains(asset) || !marker.contains("libs\(Self.librarySetVersion)") {
                status = "Rebuilding the Mullion Windows environment for 32-bit games…"
                try await buildTemplate(.arm64)
                fm.removeIfPresent(prefixURL(id, .arm64))
                g.applied[RuntimeKind.arm64.rawValue] = nil
            }
        }
        guard let wine = runtimes.wine(for: kind, arch: g.arch) else {
            throw FerryError("\(kind.title) is installed but its wine program is missing. Reinstall it in Settings ▸ Engines.")
        }

        let prefix = prefixURL(id, kind)
        let env = environment(for: g, engine: engine, prefix: prefix)
        let setupLog = logURL(id, "setup")

        if g.sharedWith != nil {
            let owner = environmentOwner(of: g)
            guard fm.exists(prefix.appendingPathComponent("system.reg")) else {
                throw FerryError("\(g.name) runs inside \(owner.name)'s Windows environment, which hasn't been created yet. Start \(owner.name) once first.")
            }
            if engine == .dxvk { installDXVK(into: prefix) }
            return PreparedGame(game: g, engine: engine, kind: kind, wine: wine, prefix: prefix, env: env)
        }

        let template = templateURL(kind)
        if kind == .mach9 || kind == .x64, !fm.exists(prefix.appendingPathComponent("system.reg")),
           !fm.exists(template.appendingPathComponent("system.reg")) {
            status = "Preparing \(kind == .x64 ? "D3DMetal 4's" : "Mach9's") Windows environment (first time only, a few minutes)…"
            try await buildTemplate(kind)
        }
        if !fm.exists(prefix.appendingPathComponent("system.reg")),
           fm.exists(template.appendingPathComponent("system.reg")) {
            status = "Setting up \(g.name)…"
            try? fm.createDirectory(at: bottleURL(id), withIntermediateDirectories: true)
            fm.removeIfPresent(prefix)
            await Shell.run("/bin/cp", ["-cR", template.path, prefix.path], log: setupLog)
            if fm.exists(prefix.appendingPathComponent("system.reg")) {
                g.applied[kind.rawValue] = Self.templateSignature
                if !g.runtimesInstalled.contains(kind.rawValue) { g.runtimesInstalled.append(kind.rawValue) }
                update(g)
            }
        }

        if !fm.exists(prefix.appendingPathComponent("system.reg")) {
            status = "Creating a Windows environment for \(g.name)…"
            try? fm.createDirectory(at: bottleURL(id), withIntermediateDirectories: true)
            await Shell.run(wine.path, ["wineboot", "--init"], env: env, log: setupLog)
            if let server = runtimes.wineserver(for: kind) { await Shell.run(server.path, ["-w"], env: env, log: setupLog) }
            guard fm.exists(prefix.appendingPathComponent("system.reg")) else {
                throw FerryError("Wine couldn't create the Windows environment. Open its settings and click Show Setup Log for details.")
            }
            g.applied[kind.rawValue] = nil
        }

        let dpi = g.settings.windowsDPI(graphics: g.graphics)
        let signature = g.settings.registrySignature + "|dpi\(dpi)" + (kind == .mach9 ? "|virtual-modes" : "")
        if g.applied[kind.rawValue] != signature {
            status = "Applying settings…"
            await applyWindowsSettings(g.settings, wine: wine, env: env, prefix: prefix, log: setupLog, kind: kind, dpi: dpi)
            if kind == .mach9, !running.contains(where: { prefixURL($0, kind) == prefix }),
               let server = runtimes.wineserver(for: kind) {
                await Shell.run(server.path, ["-k"], env: env, log: setupLog)
            }
            g.applied[kind.rawValue] = signature
            update(g)
        }

        await installFonts(wine: wine, env: env, prefix: prefix, log: setupLog)
        await shareSaves(prefix: prefix, ownerID: id)
        if engine == .dxvk { installDXVK(into: prefix) }
        return PreparedGame(game: g, engine: engine, kind: kind, wine: wine, prefix: prefix, env: env)
    }

    func installDXVK(into prefix: URL) {
        let version = runtimes.info[.dxvk]?.version ?? "?"
        let marker = prefix.appendingPathComponent(".ferry-dxvk")
        if (try? String(contentsOf: marker, encoding: .utf8)) == version { return }
        let dirs = runtimes.dxvkFolders()
        let windows = prefix.appendingPathComponent("drive_c/windows")
        for (source, target) in [(dirs.x64, "system32"), (dirs.x32, "syswow64")] {
            guard let source, let dlls = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            let dest = windows.appendingPathComponent(target)
            guard fm.isDirectory(dest) else { continue }
            for dll in dlls where dll.pathExtension.lowercased() == "dll" {
                let out = dest.appendingPathComponent(dll.lastPathComponent)
                fm.removeIfPresent(out)
                try? fm.copyItem(at: dll, to: out)
            }
        }
        try? version.write(to: marker, atomically: true, encoding: .utf8)
    }

    func play(_ id: UUID) {
        guard !running.contains(id), !preparing.contains(id) else { return }
        if ProcessInfo.processInfo.isLowPowerModeEnabled && !lowPowerAcknowledged {
            lowPowerPrompt = id
            return
        }
        guard !updating else {
            errorMessage = "Ferry is installing updates. It can start once they finish."
            return
        }
        preparing.insert(id)
        Task {
            defer { preparing.remove(id); status = nil }
            do {
                let p = try await prepare(id)
                let autoRuntimes = UserDefaults.standard.object(forKey: "autoRuntimes") as? Bool ?? true
                if autoRuntimes && p.game.sharedWith == nil && !p.game.runtimesInstalled.contains(p.kind.rawValue) {
                    _ = await installLibraries(p)
                }
                await applyCncDdraw(p)
                await applyDXVKD3D9(p)
                syncD3DMetal(p)
                applyDrawCopies(p)
                applyHideROV(p)
                applyVSyncHelpers(p)
                let ready = withWebView2(p)
                await watchInstaller(p)
                status = "Starting \(p.game.name)…"
                try launch(ready)
            } catch {
                installWatches[id] = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func rovReportURL(_ id: UUID) -> URL { logURL(id, "rov-detected").deletingPathExtension().appendingPathExtension("txt") }

    func watchesForROV(_ g: Game, engine: EngineID) -> Bool {
        guard engine == .d3dmetal, !g.settings.hideROV, !g.rovSeen, g.rovWatchLaunches < 3, g.sharedWith == nil,
              [.dx12, .unknown].contains(g.graphics), g.exePath.lowercased().hasSuffix(".exe") else { return false }
        let dir = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
        if modOwning(dir.appendingPathComponent("d3d12.dll"), in: g) != nil { return false }
        return !hasAntiCheat(g)
    }

    func hasAntiCheat(_ g: Game) -> Bool {
        let dir = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
        let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            + ((try? fm.contentsOfDirectory(atPath: dir.deletingLastPathComponent().path)) ?? [])
        let antiCheat = ["easyanticheat", "battleye", "beservice", "vgk", "xigncode", "gameguard", "eaanticheat", "ace-base"]
        return names.contains { name in antiCheat.contains { name.lowercased().contains($0) } }
    }

    private func checkROVReport(_ id: UUID) {
        let report = rovReportURL(id)
        guard fm.exists(report), var g = game(id) else { return }
        fm.removeIfPresent(report)
        g.rovSeen = true
        update(g)
        if !g.settings.hideROV && running.isEmpty { rovPrompt = id }
    }

    private func applyHideROV(_ p: PreparedGame) {
        guard var g = game(p.game.id) else { return }
        let target = URL(fileURLWithPath: g.exePath).deletingLastPathComponent().appendingPathComponent("d3d12.dll")
        guard let helper = Bundle.main.url(forResource: "d3d12-hide-rov", withExtension: "dll") else { return }
        if (g.settings.hideROV || watchesForROV(g, engine: p.engine) || usesVSyncD3D12(g, engine: p.engine)) && p.engine == .d3dmetal {
            if g.settings.hideROV, let mod = modOwning(target, in: g) {
                noteModOwns(target, mod, setting: "Hide ROV support", game: g)
                return
            }
            if watchesForROV(g, engine: p.engine) {
                fm.removeIfPresent(rovReportURL(g.id))
                g.rovWatchLaunches += 1
                update(g)
            }
            let ours = fm.contentsEqual(atPath: target.path, andPath: helper.path)
            if ours && g.hideROVPlaced == target.path { return }
            if fm.exists(target) && !ours {
                if g.settings.hideROV {
                    errorMessage = "\(g.name) comes with its own d3d12.dll, so Ferry can't add its ROV helper there. Hide ROV support is off for this game."
                }
                return
            }
            fm.removeIfPresent(target)
            if (try? fm.copyItem(at: helper, to: target)) != nil {
                g.hideROVPlaced = target.path
                update(g)
            }
        } else if let placed = g.hideROVPlaced {
            let url = URL(fileURLWithPath: placed)
            if fm.contentsEqual(atPath: placed, andPath: helper.path) { fm.removeIfPresent(url) }
            g.hideROVPlaced = nil
            update(g)
        }
    }

    private func applyDXVKD3D9(_ p: PreparedGame) async {
        guard var g = game(p.game.id) else { return }
        let target = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
            .appendingPathComponent(usesD3D9Helper(g) ? "d3d9-dxvk.dll" : "d3d9.dll")
        if g.settings.dxvkD3D9 && p.engine != .mach9 && !usesBundledDXVK(g, engine: p.engine) {
            if let mod = modOwning(target, in: g) {
                noteModOwns(target, mod, setting: "DirectX 9 via DXVK", game: g)
                return
            }
            if let placed = g.dxvkD3D9Placed, placed != target.path {
                removeDXVKD3D9(placed, arch: g.arch)
                g.dxvkD3D9Placed = nil
                update(g)
            }
            let dll: URL
            if usesBetaDXVK(g, engine: p.engine), let beta = betaDXVK32() {
                dll = beta
            } else {
                if g.dxvkD3D9Placed == nil || !fm.exists(target) { status = "Adding DXVK's DirectX 9…" }
                try? await runtimes.ensure(.dxvk)
                let dirs = runtimes.dxvkFolders()
                guard let folder = g.arch == .x86 ? dirs.x32 : dirs.x64 else { return }
                dll = folder.appendingPathComponent("d3d9.dll")
                guard fm.exists(dll) else {
                    errorMessage = "This DXVK version doesn't include DirectX 9, so \(g.name) will keep using WineD3D."
                    return
                }
            }
            if g.dxvkD3D9Placed == target.path && fm.exists(target) {
                if fm.contentsEqual(atPath: target.path, andPath: dll.path) { return }
                fm.removeIfPresent(target)
            }
            if isDrawCopiesHelper(target.path) { fm.removeIfPresent(target) }
            guard !fm.exists(target) else { return }
            if (try? fm.copyItem(at: dll, to: target)) != nil {
                g.dxvkD3D9Placed = target.path
                update(g)
            }
        } else if let placed = g.dxvkD3D9Placed {
            removeDXVKD3D9(placed, arch: g.arch)
            g.dxvkD3D9Placed = nil
            update(g)
        }
    }

    func usesBundledDXVK(_ g: Game, engine: EngineID) -> Bool {
        guard engine == .mullion, !mullionOnRosetta(g), g.settings.dxvkD3D9, g.arch != .x86, runtimes.kosmicKrispDriver() != nil,
              let bin = runtimes.binDir(.arm64) else { return false }
        return fm.exists(bin.deletingLastPathComponent().appendingPathComponent("lib/dxvk/x86_64-windows/d3d9.dll"))
    }

    private func removeDXVKD3D9(_ placed: String, arch: PEArch) {
        let dirs = runtimes.dxvkFolders()
        let ours = [(arch == .x86 ? dirs.x32 : dirs.x64)?.appendingPathComponent("d3d9.dll"), arch == .x86 ? betaDXVK32() : nil]
        if ours.contains(where: { $0.map { fm.contentsEqual(atPath: placed, andPath: $0.path) } ?? false }) {
            fm.removeIfPresent(URL(fileURLWithPath: placed))
        }
    }

    func drawsCopies(_ g: Game) -> Bool {
        g.settings.drawCopies ?? (g.graphics == .dx9 || (g.framework == "Clickteam Fusion" && g.graphics == .unknown))
    }

    func usesD3D9Helper(_ g: Game) -> Bool {
        drawsCopies(g) || (g.settings.vsync && g.graphics == .dx9)
    }

    func frameCap(_ g: Game) -> Int? {
        if g.settings.vsync { return Platform.displayHz }
        return g.settings.fpsLimit > 0 ? g.settings.fpsLimit : nil
    }

    func hasFrameLimiter(_ g: Game) -> Bool {
        let engine = resolvedEngine(g), s = g.settings
        if engine == .dxvk || (s.dxvkD3D9 && engine != .mach9) { return true }
        if engine == .mach9 { return s.mach9Direct3D != "wined3d" }
        if engine == .mullion { return [.dx10, .dx11, .dx12].contains(g.graphics) && ["", "dxvk"].contains(s.metalSharpBackend) }
        return false
    }

    func vsyncHelpers(_ g: Game, engine: EngineID) -> [String] {
        guard g.settings.vsync, g.sharedWith == nil, g.exePath.lowercased().hasSuffix(".exe"), !hasAntiCheat(g) else { return [] }
        switch engine {
        case .d3dmetal: return [.dx10, .dx11, .unknown].contains(g.graphics) ? ["d3d11"] : []
        case .wined3d, .auto: return [.dx10, .dx11, .dx12, .unknown].contains(g.graphics) ? ["dxgi"] : []
        default: return []
        }
    }

    func usesVSyncD3D12(_ g: Game, engine: EngineID) -> Bool {
        guard engine == .d3dmetal, g.settings.vsync, g.sharedWith == nil, g.exePath.lowercased().hasSuffix(".exe"),
              [.dx12, .unknown].contains(g.graphics) else { return false }
        return !hasAntiCheat(g)
    }

    static func nativeFirst(_ name: String, in overrides: String) -> String {
        var groups: [String] = overrides.split(separator: ";").compactMap { group in
            let parts = group.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return String(group) }
            let dlls = parts[0].split(separator: ",").filter { $0 != name }
            return dlls.isEmpty ? nil : dlls.joined(separator: ",") + "=" + parts[1]
        }
        groups.append("\(name)=n,b")
        return groups.joined(separator: ";")
    }

    private func vsyncHelper(_ arch: PEArch) -> URL? {
        Bundle.main.url(forResource: arch == .x86 ? "dxgi-vsync-x86" : "dxgi-vsync-x64", withExtension: "dll")
    }

    private func applyVSyncHelpers(_ p: PreparedGame) {
        guard var g = game(p.game.id) else { return }
        let dir = URL(fileURLWithPath: g.exePath).deletingLastPathComponent()
        let wanted = Set(vsyncHelpers(g, engine: p.engine))
        var placed = g.vsyncPlaced
        for name in ["dxgi", "d3d11"] {
            let target = dir.appendingPathComponent("\(name).dll")
            let ours = placed.contains(target.path)
            if wanted.contains(name), let helper = vsyncHelper(g.arch), modOwning(target, in: g) == nil {
                if fm.contentsEqual(atPath: target.path, andPath: helper.path) {
                    if !ours { placed.append(target.path) }
                    continue
                }
                if fm.exists(target) && !ours { continue }
                fm.removeIfPresent(target)
                if (try? fm.copyItem(at: helper, to: target)) != nil, !ours { placed.append(target.path) }
            } else if ours {
                if modOwning(target, in: g) == nil { fm.removeIfPresent(target) }
                placed.removeAll { $0 == target.path }
            }
        }
        if placed != g.vsyncPlaced {
            g.vsyncPlaced = placed
            update(g)
        }
    }

    private func drawCopiesHelper(_ arch: PEArch) -> URL? {
        Bundle.main.url(forResource: arch == .x86 ? "d3d9-ferry-x86" : "d3d9-ferry-x64", withExtension: "dll")
    }

    private func isDrawCopiesHelper(_ path: String) -> Bool {
        [PEArch.x86, .x64].contains { drawCopiesHelper($0).map { fm.contentsEqual(atPath: path, andPath: $0.path) } ?? false }
    }

    private func syncD3DMetal(_ p: PreparedGame) {
        guard p.kind == .gptk else { return }
        let system32 = p.prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard fm.isDirectory(system32) else { return }
        for dll in runtimes.d3dmetalDLLs() {
            let copy = system32.appendingPathComponent(dll.lastPathComponent)
            if fm.contentsEqual(atPath: dll.path, andPath: copy.path) { continue }
            fm.removeIfPresent(copy)
            try? fm.copyItem(at: dll, to: copy)
        }
    }

    private func applyDrawCopies(_ p: PreparedGame) {
        guard var g = game(p.game.id), let helper = drawCopiesHelper(g.arch) else { return }
        let target = URL(fileURLWithPath: g.exePath).deletingLastPathComponent().appendingPathComponent("d3d9.dll")
        if usesD3D9Helper(g) {
            if let mod = modOwning(target, in: g) {
                if g.settings.drawCopies == true { noteModOwns(target, mod, setting: "Faster screen copies", game: g) }
                return
            }
            let current = fm.contentsEqual(atPath: target.path, andPath: helper.path)
            if current && g.drawCopiesPlaced == target.path { return }
            if fm.exists(target) && !current && g.drawCopiesPlaced != target.path {
                if g.settings.drawCopies == true {
                    errorMessage = "\(g.name) comes with its own d3d9.dll, so Ferry can't add its faster screen copies there."
                }
                return
            }
            fm.removeIfPresent(target)
            if (try? fm.copyItem(at: helper, to: target)) != nil {
                g.drawCopiesPlaced = target.path
                update(g)
            }
        } else if let placed = g.drawCopiesPlaced {
            if isDrawCopiesHelper(placed) { fm.removeIfPresent(URL(fileURLWithPath: placed)) }
            g.drawCopiesPlaced = nil
            update(g)
        }
    }

    private func applyCncDdraw(_ p: PreparedGame) async {
        guard var g = game(p.game.id) else { return }
        let target = URL(fileURLWithPath: g.exePath).deletingLastPathComponent().appendingPathComponent("ddraw.dll")
        if g.settings.cncDdraw {
            if let mod = modOwning(target, in: g) {
                noteModOwns(target, mod, setting: "the old 2D game fix", game: g)
                return
            }
            if g.cncDdrawPlaced == target.path && fm.exists(target) { return }
            guard !fm.exists(target) else { return }
            status = "Adding the old 2D game fix…"
            if let dll = await cncDdrawDLL(), (try? fm.copyItem(at: dll, to: target)) != nil {
                g.cncDdrawPlaced = target.path
                update(g)
            }
        } else if let placed = g.cncDdrawPlaced {
            if let dll = cachedCncDdrawDLL(), fm.contentsEqual(atPath: placed, andPath: dll.path) {
                fm.removeIfPresent(URL(fileURLWithPath: placed))
            }
            g.cncDdrawPlaced = nil
            update(g)
        }
    }

    private func launch(_ p: PreparedGame) throws {
        let exe = URL(fileURLWithPath: p.game.exePath)
        guard fm.exists(exe) else {
            throw FerryError("\(exe.lastPathComponent) isn't where it used to be (\(exe.deletingLastPathComponent().path)). If you moved the game, use Change Executable in its settings.")
        }
        var args: [String]
        switch exe.pathExtension.lowercased() {
        case "msi": args = ["msiexec", "/i", exe.path]
        case "bat": args = ["cmd", "/c", exe.path]
        default: args = [exe.path]
        }
        args += splitArguments(p.game.settings.arguments)

        let process = Process()
        let gameMode = (game(p.game.id) ?? p.game).usesGameMode
        process.executableURL = (p.kind == .gptk && gameMode ? runtimes.gameLauncher(for: .gptk, arch: p.game.arch) : nil) ?? p.wine
        process.arguments = args
        process.environment = p.env
        process.currentDirectoryURL = exe.deletingLastPathComponent()
        let log = Shell.openLog(logURL(p.game.id, "game"), truncate: true)
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let id = p.game.id
        let engine = p.engine
        let started = Date()
        process.terminationHandler = { proc in
            try? log?.close()
            let status = proc.terminationStatus
            let seconds = Date().timeIntervalSince(started)
            Task { @MainActor in AppModel.shared.finished(id, status: status, seconds: seconds, engine: engine) }
        }
        try process.run()
        processes[id] = process
        running.insert(id)
        if p.game.settings.macFullScreenButton { startWindowButtonsHelper(p) }
        discordGameStarted(p.game)

        if var g = game(p.game.id) {
            g.lastPlayed = Date()
            update(g)
        }
    }

    private func finished(_ id: UUID, status: Int32, seconds: TimeInterval, engine: EngineID) {
        processes[id] = nil
        if !stopping.contains(id), let g = game(id) {
            let started = Date().addingTimeInterval(-seconds)
            Task {
                var handedOff = false
                while true {
                    let pids = await Self.programsRunning(from: g)
                    self.handoffPIDs[id] = pids
                    if pids.isEmpty { break }
                    handedOff = true
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                self.handoffPIDs[id] = nil
                self.gameEnded(id, status: handedOff ? 0 : status, seconds: Date().timeIntervalSince(started), engine: engine)
            }
            return
        }
        gameEnded(id, status: status, seconds: seconds, engine: engine)
    }

    static func programsRunning(from g: Game) async -> [Int32] {
        let dir = URL(fileURLWithPath: g.exePath).deletingLastPathComponent().path
        let windowsDir = windowsFolder(of: g)
        let needles = [windowsDir.lowercased() + "\\", dir.lowercased() + "/"]
        let (_, output) = await Shell.capture("/bin/ps", ["-axww", "-o", "pid=,command="])
        var pids: [Int32] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let space = text.firstIndex(of: " "), let pid = Int32(text[..<space]) else { continue }
            let command = text[space...].lowercased()
            if command.contains(".exe"), !command.contains("ferry-winbuttons"), needles.contains(where: { command.contains($0) }) { pids.append(pid) }
        }
        return pids
    }

    private func startWindowButtonsHelper(_ p: PreparedGame) {
        guard let helper = Bundle.main.url(forResource: "ferry-winbuttons", withExtension: "exe") else { return }
        let helperProcess = Process()
        helperProcess.executableURL = p.wine
        helperProcess.arguments = [helper.path, Self.windowsFolder(of: p.game)]
        helperProcess.environment = p.env
        helperProcess.standardOutput = FileHandle.nullDevice
        helperProcess.standardError = FileHandle.nullDevice
        helperProcess.standardInput = FileHandle.nullDevice
        if (try? helperProcess.run()) != nil { helpers[p.game.id] = helperProcess }
    }

    static func windowsFolder(of g: Game) -> String {
        let dir = URL(fileURLWithPath: g.exePath).deletingLastPathComponent().path
        if let range = dir.range(of: "/drive_c/") {
            return "C:\\" + dir[range.upperBound...].replacingOccurrences(of: "/", with: "\\")
        }
        return "Z:" + dir.replacingOccurrences(of: "/", with: "\\")
    }

    func endLeftoverWine() async {
        let root = Paths.root.path
        let pids = await Task.detached { TaskList.leftovers(root: root) }.value
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGTERM) }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    private func gameEnded(_ id: UUID, status: Int32, seconds: TimeInterval, engine: EngineID) {
        helpers.removeValue(forKey: id)?.terminate()
        running.remove(id)
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await endLeftoverWine()
        }
        checkROVReport(id)
        discordGameEnded(id)
        let stoppedByUser = stopping.remove(id) != nil
        let crashed = !stoppedByUser && status != 0 && seconds < 20
        if let watch = installWatches.removeValue(forKey: id) {
            Task {
                if await offerInstalledProgram(id, watch) { return }
                checkForReclaimableStorage()
                if crashed, let g = game(id) { offerAnotherEngine(for: g, failed: engine, status: status) }
            }
            return
        }
        checkForReclaimableStorage()
        guard crashed, let g = game(id) else { return }
        offerAnotherEngine(for: g, failed: engine, status: status)
    }

    private func watchInstaller(_ p: PreparedGame) async {
        installWatches[p.game.id] = nil
        guard p.game.sharedWith == nil, !p.game.exePath.hasPrefix(bottleURL(p.game.id).path + "/") else { return }
        let exe = URL(fileURLWithPath: p.game.exePath)
        let driveC = p.prefix.appendingPathComponent("drive_c")
        let before = await Task.detached {
            InstalledPrograms.looksLikeInstaller(exe) ? InstalledPrograms.snapshot(driveC: driveC) : nil
        }.value
        if let before { installWatches[p.game.id] = (before, p.engine, driveC) }
    }

    private func offerInstalledProgram(_ id: UUID, _ watch: (before: InstalledPrograms.Snapshot, engine: EngineID, driveC: URL)) async -> Bool {
        guard let g = game(id) else { return false }
        let installer = URL(fileURLWithPath: g.exePath)
        let programs = await Task.detached {
            InstalledPrograms.candidates(before: watch.before, after: InstalledPrograms.snapshot(driveC: watch.driveC),
                                         driveC: watch.driveC, installer: installer) { PEVersionInfo.string("ProductName", in: $0) }
        }.value
        guard !programs.isEmpty, let current = game(id) else { return false }
        installedOffer = InstalledOffer(gameID: id, installer: current.name, engine: watch.engine, programs: programs)
        return true
    }

    func useInstalledProgram(_ program: InstalledPrograms.Candidate, from offer: InstalledOffer) {
        Task {
            let exe = program.exe
            let (arch, api) = await Task.detached { (PEInspector.arch(of: exe), PEInspector.graphicsAPI(for: exe)) }.value
            guard var g = game(offer.gameID) else { return }
            g.exePath = exe.path
            g.arch = arch
            g.graphics = api
            g.name = program.name
            let engine = arch == .x64 ? EngineID.auto : Self.engine(running: arch, sameEnvironmentAs: offer.engine)
            g.settings.engine = engine ?? .auto
            update(g)
            var text = "\(program.name) is set up. Press Play to start it. You can delete the installer."
            let installer = offer.engine.short
            if engine == .auto, runtimeKind(g) != offer.engine.runtime {
                text = "\(program.name) is 64-bit, so Ferry will start it with \(resolvedEngine(g).short), which runs 64-bit programs best. If it's missing settings its installer made, set its engine to \(installer) in Settings.\n\n" + text
            } else if engine == nil {
                text = "\(program.name) is \(arch.label), which \(installer) can't run, so Ferry will start it with \(resolvedEngine(g).short). It won't see settings its installer made in \(installer)'s environment.\n\n" + text
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            noticeMessage = text
        }
    }

    static func engine(running arch: PEArch, sameEnvironmentAs installer: EngineID) -> EngineID? {
        let sameEnvironment = EngineID.allCases.filter { $0 != .auto && $0 != installer && $0.runtime == installer.runtime }
        return ([installer] + sameEnvironment).first { canRun(arch, on: $0) && $0.runtime.availableHere }
    }

    func stop(_ id: UUID) {
        guard let g = game(id) else { return }
        if running.contains(id) { stopping.insert(id) }
        if g.sharedWith != nil {
            processes[id]?.terminate()
            for pid in handoffPIDs[id] ?? [] { kill(pid, SIGTERM) }
            return
        }
        let kind = runtimeKind(g)
        if let server = runtimes.wineserver(for: kind) {
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = prefixURL(id, kind).path
            Task { await Shell.run(server.path, ["-k"], env: env) }
        }
        processes[id]?.terminate()
    }

    func runTool(_ id: UUID, _ args: [String]) {
        Task {
            do {
                let p = try await prepare(id)
                status = nil
                await Shell.run(p.wine.path, args, env: p.env, log: logURL(id, "setup"))
            } catch {
                status = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func openDriveC(_ id: UUID) {
        guard let g = game(id) else { return }
        let driveC = prefixURL(id, runtimeKind(g)).appendingPathComponent("drive_c")
        if fm.exists(driveC) {
            NSWorkspace.shared.open(driveC)
        } else {
            errorMessage = "\(g.name) doesn't have a Windows environment yet. Press Play once and it'll be created."
        }
    }

    func showGameInFinder(_ id: UUID) {
        guard let g = game(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: g.exePath)])
    }

    func showLog(_ id: UUID, _ name: String) {
        let url = logURL(id, name)
        if fm.exists(url) {
            NSWorkspace.shared.open(url)
        } else {
            errorMessage = "There's no \(name) log yet."
        }
    }

    func addProgram(toEnvironmentOf id: UUID) {
        guard let picked = game(id) else { return }
        let owner = environmentOwner(of: picked)
        let driveC = prefixURL(owner.id, runtimeKind(owner)).appendingPathComponent("drive_c")
        guard fm.exists(driveC) else {
            errorMessage = "\(owner.name) doesn't have a Windows environment yet. Start it once, then add programs to it."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.acceptedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = driveC
        panel.message = "Choose a program inside \(owner.name)'s Windows environment (games Steam installs are in Program Files (x86)/Steam/steamapps/common)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let (arch, api) = await Task.detached { (PEInspector.arch(of: url), PEInspector.graphicsAPI(for: url)) }.value
            var settings = owner.settings
            settings.engine = .auto
            settings.arguments = ""
            var g = Game(name: Self.friendlyName(for: url), exePath: url.path, arch: arch, graphics: api, settings: settings)
            g.sharedWith = owner.id
            let index = (games.lastIndex { $0.id == owner.id || $0.sharedWith == owner.id } ?? -1) + 1
            games.insert(g, at: min(index, games.count))
            save()
        }
    }

    func partnerProgram(of g: Game, among programs: [Analyzer.ProgramCandidate]) -> Analyzer.ProgramCandidate? {
        guard let chosen = programs.firstIndex(where: { $0.url.path == g.exePath }) else { return nil }
        let inLibrary = programs.map { program in games.contains { $0.exePath == program.url.path } }
        return ProgramChoice.partner(of: chosen, roles: programs.map(\.role), inLibrary: inLibrary).map { programs[$0] }
    }

    func offerPartnerProgram(for g: Game) async {
        let exe = URL(fileURLWithPath: g.exePath)
        guard !ModLayout.looksLikeInstaller(exe) else { return }
        let folder = programFolder(for: exe)
        let programs = await Task.detached { Analyzer.rankedPrograms(in: folder) }.value
        guard let partner = partnerProgram(of: g, among: programs) else { return }
        pairOffer = PairOffer(gameID: g.id, gameName: g.name, program: partner.url, role: partner.role)
    }

    func addPartnerProgram(_ offer: PairOffer) {
        guard let owner = game(offer.gameID).map(environmentOwner(of:)) else { return }
        Task {
            let read = await retarget(owner, to: offer.program)
            var settings = owner.settings
            settings.arguments = ""
            var g = Game(name: "\(owner.name) (\(offer.role.label ?? offer.program.lastPathComponent))", exePath: offer.program.path,
                         arch: read.arch, graphics: read.graphics, settings: settings)
            g.framework = read.framework
            g.sharedWith = owner.id
            let index = (games.lastIndex { $0.id == owner.id || $0.sharedWith == owner.id } ?? -1) + 1
            games.insert(g, at: min(index, games.count))
            save()
            refreshAutoIcon(g)
        }
    }

    static let steamInstaller = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
    static let steamArguments = "-cef-disable-gpu -cef-disable-gpu-compositing -no-cef-sandbox"

    func installSteam() {
        guard setupComplete, !setupRunning else {
            errorMessage = "Finish setting up Ferry first, then install Steam."
            return
        }
        let id: UUID
        if let existing = games.first(where: { $0.name == "Steam" && $0.sharedWith == nil }) {
            if !existing.exePath.isEmpty, fm.exists(URL(fileURLWithPath: existing.exePath)) {
                play(existing.id)
                return
            }
            id = existing.id
        } else {
            var settings = GameSettings.defaults()
            settings.engine = .d3dmetal
            settings.arguments = Self.steamArguments
            let steam = Game(name: "Steam", exePath: "", arch: .x64, graphics: .unknown, settings: settings)
            games.insert(steam, at: 0)
            save()
            id = steam.id
        }
        guard !preparing.contains(id), !running.contains(id) else { return }
        preparing.insert(id)
        Task {
            do {
                guard let url = URL(string: Self.steamInstaller) else { return }
                status = "Downloading Steam…"
                let installer = try await runtimes.cachedInstaller(url, name: "SteamSetup.exe")

                var found: URL? = nil
                for engine in [EngineID.d3dmetal, .dxvk] {
                    if var g = game(id) {
                        g.settings.engine = engine
                        update(g)
                    }
                    let p = try await prepare(id)
                    status = "Installing Steam…"
                    await Shell.run(p.wine.path, [installer.path, "/S"], env: p.env, log: logURL(id, "setup"))
                    if let server = runtimes.wineserver(for: p.kind) {
                        await Shell.run(server.path, ["-w"], env: p.env, log: logURL(id, "setup"))
                    }
                    found = fm.firstItem(under: p.prefix.appendingPathComponent("drive_c")) {
                        $0.lastPathComponent.lowercased() == "steam.exe" && $0.deletingLastPathComponent().lastPathComponent == "Steam"
                    }
                    if found != nil { break }
                }

                guard let steamExe = found, var g = game(id) else {
                    throw FerryError("Steam's installer didn't finish. Click Install Steam again to retry; if it keeps failing, open Steam's settings in Ferry and click Show Setup Log.")
                }
                g.exePath = steamExe.path
                g.arch = PEInspector.arch(of: steamExe)
                update(g)
                preparing.remove(id)
                status = nil
                play(id)
            } catch {
                preparing.remove(id)
                status = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func makeShortcut(_ id: UUID) {
        guard let g = game(id) else { return }
        do {
            let safe = g.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let app = Paths.shortcuts.appendingPathComponent("\(safe).app", isDirectory: true)
            let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
            fm.removeIfPresent(app)
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)

            let script = macOS.appendingPathComponent("launch")
            try "#!/bin/sh\nexec /usr/bin/open \"ferry://launch/\(id.uuidString)\"\n".write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

            let plist: [String: Any] = [
                "CFBundleExecutable": "launch",
                "CFBundleIdentifier": "app.ferry.game.\(id.uuidString.lowercased())",
                "CFBundleName": g.name,
                "CFBundleDisplayName": g.name,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "LSUIElement": true,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

            if let icon = self.icon(for: g) ?? NSApp.applicationIconImage {
                NSWorkspace.shared.setIcon(icon, forFile: app.path, options: [])
            }
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            errorMessage = "Couldn't make the shortcut: \(error.localizedDescription)"
        }
    }

    func handle(_ url: URL) {
        guard url.scheme == "ferry", url.host == "launch", let id = UUID(uuidString: url.lastPathComponent) else { return }
        if game(id) != nil { play(id) } else { errorMessage = "That shortcut's program was removed from Ferry." }
    }
}
