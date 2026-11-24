import Foundation

enum PEArch: String, Codable {
    case x86, x64, arm64, unknown

    var label: String {
        switch self {
        case .x86: return "32-bit"
        case .x64: return "64-bit"
        case .arm64: return "ARM64"
        case .unknown: return "unknown arch"
        }
    }
}

enum GraphicsAPI: String, Codable {
    case dx12, dx11, dx10, dx9, dx8, vulkan, opengl, unknown

    var label: String {
        switch self {
        case .dx12: return "DirectX 12"
        case .dx11: return "DirectX 11"
        case .dx10: return "DirectX 10"
        case .dx9: return "DirectX 9"
        case .dx8: return "DirectX 8"
        case .vulkan: return "Vulkan"
        case .opengl: return "OpenGL"
        case .unknown: return "Graphics unknown"
        }
    }

    var hasDX9Fallback: Bool { self == .dx10 || self == .dx11 }
}

enum RuntimeKind: String, CaseIterable, Codable, Identifiable {
    case gptk, staging, dxvk, arm64, mach9
    case x64

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gptk: return "Game Porting Toolkit (D3DMetal)"
        case .staging: return "Wine Staging"
        case .dxvk: return "DXVK for macOS"
        case .arm64: return "MetalSharp Wine (no Rosetta)"
        case .mach9: return "Mach9 Wine (no Rosetta)"
        case .x64: return "MetalSharp Wine x86_64 (D3DMetal 4, beta)"
        }
    }

    nonisolated(unsafe) static var d3dmetalWine: RuntimeKind = .gptk

    var needsRosetta: Bool { self != .arm64 && self != .mach9 }

    var supports32bit: Bool { self == .staging || self == .mach9 || self == .x64 || (self == .arm64 && Platform.metalSharpRuns32bit) }

    var availableHere: Bool { self != .mach9 || Platform.mach9Available }

    var blurb: String {
        switch self {
        case .gptk: return "Apple's DirectX 11/12 → Metal translator on a CrossOver-based Wine. Fastest for modern 64-bit games."
        case .staging: return "Latest WineHQ build with extra patches. Runs 32- and 64-bit programs, older DirectX and OpenGL."
        case .dxvk: return "DirectX 10/11 → Vulkan → Metal. Used with Wine Staging when D3DMetal can't run a game."
        case .arm64: return "A native Apple-silicon Wine that runs game code through FEX instead of Rosetta, with Mullion (a DXMT fork) for DirectX 10/11/12 → Metal and an OpenGL-on-Metal layer for older games. Runs 32-bit programs on macOS 26.4 and later."
        case .x64: return "MetalSharp's Intel build of Wine 11 with Apple's D3DMetal inside: Game Porting Toolkit 4's D3DMetal on macOS 27 and later, 3.0's before. Runs through Rosetta. When installed, the D3DMetal engine uses it instead of the Game Porting Toolkit's Wine 7.7."
        case .mach9: return "A native Apple-silicon Wine made for launchers: FEX instead of Rosetta, mtld3d for DirectX 9 → Metal, DXMT for DirectX 10/11 → Metal and vkd3d-proton for DirectX 12. Picks the right one per game by itself. macOS 26.4 and later."
        }
    }

    var repo: String {
        switch self {
        case .gptk: return "Gcenx/game-porting-toolkit"
        case .staging: return "Gcenx/macOS_Wine_builds"
        case .dxvk: return "Gcenx/DXVK-macOS"
        case .arm64: return "metalsharp/MetalSharp-Wine"
        case .mach9: return "athei/mach9"
        case .x64: return "metalsharp/MetalSharp-Wine"
        }
    }

    func matches(_ assetName: String) -> Bool {
        let n = assetName.lowercased()
        switch self {
        case .gptk: return n.hasSuffix(".tar.xz")
        case .staging: return n.hasPrefix("wine-staging-") && n.hasSuffix("osx64.tar.xz")
        case .dxvk: return n.contains("dxvk") && !n.contains("async") && (n.hasSuffix(".tar.gz") || n.hasSuffix(".tar.xz"))
        case .arm64: return n.hasPrefix("metalsharp-wine") && n.hasSuffix("arm64.zip")
        case .mach9: return n.hasPrefix("wine-") && n.hasSuffix("-macos-arm64.tar.xz") && !n.contains("symbol") && !n.contains("debug")
        case .x64: return n.hasPrefix("metalsharp-wine") && n.hasSuffix("x86_64.zip")
        }
    }
}

enum EngineID: String, Codable, CaseIterable, Identifiable {
    case auto, d3dmetal, mach9, mullion, dxvk, wined3d

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto (best for this game)"
        case .d3dmetal: return "D3DMetal — DirectX 11/12 → Metal"
        case .mach9: return "Mach9 — DirectX 9–12 and Vulkan 1.4 → Metal, no Rosetta"
        case .mullion: return "Mullion (MetalSharp Wine) — DirectX and OpenGL 4.6 → Metal, no Rosetta"
        case .dxvk: return "Wine Staging + DXVK — DirectX 10/11 → Vulkan → Metal"
        case .wined3d: return "Wine Staging (WineD3D) — DirectX 9 and older, OpenGL 4.1, Vulkan"
        }
    }

    var short: String {
        switch self {
        case .auto: return "Auto"
        case .d3dmetal: return "D3DMetal"
        case .mach9: return "Mach9"
        case .mullion: return "Mullion"
        case .dxvk: return "DXVK"
        case .wined3d: return "WineD3D"
        }
    }

    var runtime: RuntimeKind {
        switch self {
        case .auto, .d3dmetal: return RuntimeKind.d3dmetalWine
        case .mullion: return .arm64
        case .mach9: return .mach9
        case .dxvk, .wined3d: return .staging
        }
    }
}

struct GameSettings: Codable, Equatable {
    var engine: EngineID = .auto
    var windowsVersion: String = "win10"
    var retina: Bool = false
    var uiScale: Int = 0
    var gameMode: Int = 0
    var fastSync: Bool = true
    var metalHUD: Bool = false
    var metalFX: Bool = false
    var advertiseAVX: Bool = true
    var arguments: String = ""
    var extraEnv: String = ""
    var commandIsCtrl: Bool = false
    var optionIsAlt: Bool = false
    var captureFullscreen: Bool = false
    var wined3dVulkan: Bool = false
    var openGLBackingStore: Bool = false
    var wined3dSingleThread: Bool = false
    var metalSharpBackend: String = ""
    var metalSharpOpenGL: String = ""
    var mullionVulkan: String = ""
    var mullionRosetta: Bool = false
    var mach9Direct3D: String = ""
    var useDX9: Bool = false
    var fullMemory32: Bool = true
    var macFullScreenButton: Bool = true
    var fpsLimit: Int = 0
    var vsync: Bool = true
    var reportNVIDIA: Bool = false { didSet { if !reportNVIDIA { hideROV = false } } }
    var hideROV: Bool = false { didSet { if hideROV { reportNVIDIA = true } } }
    var dxvkD3D9: Bool = false
    var dxvkVideoMemory: Int = 0
    var drawCopies: Bool? = nil
    var dxvkBeta: Bool = false
    var cncDdraw: Bool = false
    var nativeXAudio2: Bool = true
    var webView2: Bool = false
    var showOnDiscord: Bool = true

    static func defaults() -> GameSettings {
        let d = UserDefaults.standard
        var s = GameSettings()
        s.fastSync = d.object(forKey: "defaultFastSync") as? Bool ?? true
        s.advertiseAVX = d.object(forKey: "defaultAVX") as? Bool ?? true
        s.retina = d.object(forKey: "defaultRetina") as? Bool ?? false
        s.metalFX = d.object(forKey: "defaultMetalFX") as? Bool ?? false
        s.commandIsCtrl = d.object(forKey: "defaultCommandIsCtrl") as? Bool ?? false
        s.vsync = d.object(forKey: "defaultVSync") as? Bool ?? true
        return s
    }
}

extension GameSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        engine = (try? c.decodeIfPresent(EngineID.self, forKey: .engine)) ?? d.engine
        windowsVersion = (try? c.decodeIfPresent(String.self, forKey: .windowsVersion)) ?? d.windowsVersion
        retina = (try? c.decodeIfPresent(Bool.self, forKey: .retina)) ?? d.retina
        uiScale = (try? c.decodeIfPresent(Int.self, forKey: .uiScale)) ?? d.uiScale
        gameMode = (try? c.decodeIfPresent(Int.self, forKey: .gameMode)) ?? d.gameMode
        fastSync = (try? c.decodeIfPresent(Bool.self, forKey: .fastSync)) ?? d.fastSync
        metalHUD = (try? c.decodeIfPresent(Bool.self, forKey: .metalHUD)) ?? d.metalHUD
        metalFX = (try? c.decodeIfPresent(Bool.self, forKey: .metalFX)) ?? d.metalFX
        advertiseAVX = (try? c.decodeIfPresent(Bool.self, forKey: .advertiseAVX)) ?? d.advertiseAVX
        arguments = (try? c.decodeIfPresent(String.self, forKey: .arguments)) ?? d.arguments
        extraEnv = (try? c.decodeIfPresent(String.self, forKey: .extraEnv)) ?? d.extraEnv
        commandIsCtrl = (try? c.decodeIfPresent(Bool.self, forKey: .commandIsCtrl)) ?? d.commandIsCtrl
        optionIsAlt = (try? c.decodeIfPresent(Bool.self, forKey: .optionIsAlt)) ?? d.optionIsAlt
        captureFullscreen = (try? c.decodeIfPresent(Bool.self, forKey: .captureFullscreen)) ?? d.captureFullscreen
        wined3dVulkan = (try? c.decodeIfPresent(Bool.self, forKey: .wined3dVulkan)) ?? d.wined3dVulkan
        openGLBackingStore = (try? c.decodeIfPresent(Bool.self, forKey: .openGLBackingStore)) ?? d.openGLBackingStore
        wined3dSingleThread = (try? c.decodeIfPresent(Bool.self, forKey: .wined3dSingleThread)) ?? d.wined3dSingleThread
        metalSharpBackend = (try? c.decodeIfPresent(String.self, forKey: .metalSharpBackend)) ?? d.metalSharpBackend
        metalSharpOpenGL = (try? c.decodeIfPresent(String.self, forKey: .metalSharpOpenGL)) ?? d.metalSharpOpenGL
        mullionVulkan = (try? c.decodeIfPresent(String.self, forKey: .mullionVulkan)) ?? d.mullionVulkan
        mullionRosetta = (try? c.decodeIfPresent(Bool.self, forKey: .mullionRosetta)) ?? d.mullionRosetta
        mach9Direct3D = (try? c.decodeIfPresent(String.self, forKey: .mach9Direct3D)) ?? d.mach9Direct3D
        useDX9 = (try? c.decodeIfPresent(Bool.self, forKey: .useDX9)) ?? d.useDX9
        fullMemory32 = (try? c.decodeIfPresent(Bool.self, forKey: .fullMemory32)) ?? d.fullMemory32
        macFullScreenButton = (try? c.decodeIfPresent(Bool.self, forKey: .macFullScreenButton)) ?? d.macFullScreenButton
        fpsLimit = (try? c.decodeIfPresent(Int.self, forKey: .fpsLimit)) ?? d.fpsLimit
        vsync = (try? c.decodeIfPresent(Bool.self, forKey: .vsync)) ?? d.vsync
        hideROV = (try? c.decodeIfPresent(Bool.self, forKey: .hideROV)) ?? d.hideROV
        reportNVIDIA = (try? c.decodeIfPresent(Bool.self, forKey: .reportNVIDIA)) ?? hideROV
        dxvkD3D9 = (try? c.decodeIfPresent(Bool.self, forKey: .dxvkD3D9)) ?? d.dxvkD3D9
        dxvkVideoMemory = (try? c.decodeIfPresent(Int.self, forKey: .dxvkVideoMemory)) ?? d.dxvkVideoMemory
        drawCopies = (try? c.decodeIfPresent(Bool.self, forKey: .drawCopies)) ?? d.drawCopies
        dxvkBeta = (try? c.decodeIfPresent(Bool.self, forKey: .dxvkBeta)) ?? d.dxvkBeta
        cncDdraw = (try? c.decodeIfPresent(Bool.self, forKey: .cncDdraw)) ?? d.cncDdraw
        showOnDiscord = (try? c.decodeIfPresent(Bool.self, forKey: .showOnDiscord)) ?? d.showOnDiscord
        webView2 = (try? c.decodeIfPresent(Bool.self, forKey: .webView2)) ?? d.webView2
        nativeXAudio2 = (try? c.decodeIfPresent(Bool.self, forKey: .nativeXAudio2)) ?? d.nativeXAudio2
    }
}

struct Game: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var exePath: String
    var arch: PEArch = .unknown
    var graphics: GraphicsAPI = .unknown
    var settings: GameSettings = GameSettings()
    var drawsWith: GraphicsAPI { settings.useDX9 && graphics.hasDX9Fallback ? .dx9 : graphics }
    var runtimesInstalled: [String] = []
    var applied: [String: String] = [:]
    var createdAt: Date = Date()
    var lastPlayed: Date? = nil
    var sharedWith: UUID? = nil
    var cncDdrawPlaced: String? = nil
    var dxvkD3D9Placed: String? = nil
    var hideROVPlaced: String? = nil
    var drawCopiesPlaced: String? = nil
    var vsyncPlaced: [String] = []
    var rovSeen: Bool = false
    var rovWatchLaunches: Int = 0
    var stallPrompted: Bool = false
    var iconMode: IconMode = .auto
    var framework: String? = nil
    var mods: [InstalledMod] = []
}

extension Game {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        exePath = try c.decode(String.self, forKey: .exePath)
        arch = (try? c.decodeIfPresent(PEArch.self, forKey: .arch)) ?? .unknown
        graphics = (try? c.decodeIfPresent(GraphicsAPI.self, forKey: .graphics)) ?? .unknown
        settings = (try? c.decodeIfPresent(GameSettings.self, forKey: .settings)) ?? GameSettings()
        runtimesInstalled = (try? c.decodeIfPresent([String].self, forKey: .runtimesInstalled)) ?? []
        applied = (try? c.decodeIfPresent([String: String].self, forKey: .applied)) ?? [:]
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        lastPlayed = try? c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        sharedWith = try? c.decodeIfPresent(UUID.self, forKey: .sharedWith)
        cncDdrawPlaced = try? c.decodeIfPresent(String.self, forKey: .cncDdrawPlaced)
        dxvkD3D9Placed = try? c.decodeIfPresent(String.self, forKey: .dxvkD3D9Placed)
        hideROVPlaced = try? c.decodeIfPresent(String.self, forKey: .hideROVPlaced)
        drawCopiesPlaced = try? c.decodeIfPresent(String.self, forKey: .drawCopiesPlaced)
        vsyncPlaced = (try? c.decodeIfPresent([String].self, forKey: .vsyncPlaced)) ?? []
        rovSeen = (try? c.decodeIfPresent(Bool.self, forKey: .rovSeen)) ?? false
        rovWatchLaunches = (try? c.decodeIfPresent(Int.self, forKey: .rovWatchLaunches)) ?? 0
        stallPrompted = (try? c.decodeIfPresent(Bool.self, forKey: .stallPrompted)) ?? false
        iconMode = (try? c.decodeIfPresent(IconMode.self, forKey: .iconMode)) ?? .auto
        framework = try? c.decodeIfPresent(String.self, forKey: .framework)
        mods = (try? c.decodeIfPresent(LossyList<InstalledMod>.self, forKey: .mods))?.items ?? []
    }
}

extension GameSettings {
    func windowsDPI(graphics: GraphicsAPI) -> Int {
        switch uiScale {
        case 100: return 96
        case 200: return 192
        default: return retina && graphics == .unknown ? 192 : 96
        }
    }

    var registrySignature: String {
        "\(windowsVersion)|\(retina)|\(commandIsCtrl)|\(optionIsAlt)|\(captureFullscreen)|\(openGLBackingStore)"
    }
}

enum ArgsText {
    static func options(_ text: String) -> [String] {
        var out: [String] = []
        for word in splitArguments(text) {
            let shown = word.contains(where: \.isWhitespace) || word.isEmpty ? "\"\(word)\"" : word
            if let first = word.first, "-+/".contains(first) || out.isEmpty {
                out.append(shown)
            } else {
                out[out.count - 1] += " " + shown
            }
        }
        return out
    }
}

enum EnvText {
    static func pairs(_ text: String) -> [(key: String, value: String)] {
        var out: [(key: String, value: String)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            var current = ""
            for word in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                if startsPair(word), !current.isEmpty { add(current, to: &out); current = "" }
                current += current.isEmpty ? String(word) : " " + word
            }
            add(current, to: &out)
        }
        return out
    }

    static func text(_ pairs: [(key: String, value: String)]) -> String {
        pairs.filter { !$0.key.isEmpty }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    private static func startsPair(_ word: Substring) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex, !word.first!.isNumber else { return false }
        return word[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func add(_ s: String, to out: inout [(key: String, value: String)]) {
        let parts = s.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty else { return }
        out.append((parts[0], parts[1]))
    }
}

extension GameSettings {
    func dxvkMemoryLimit(macGB: Int) -> Int? {
        switch dxvkVideoMemory {
        case 0: return macGB <= 8 ? 1024 : nil
        case ..<0: return nil
        default: return dxvkVideoMemory
        }
    }
}
