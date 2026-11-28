import Foundation

struct SettingContext {
    var settings: GameSettings
    var engine: EngineID
    var graphics: GraphicsAPI
    var arch: PEArch
    var dgVoodooInstalled: Bool
    var kosmicKrispAvailable: Bool
    var intelMullionInstalled: Bool
    var mach9Available: Bool
    var sharedEnvironmentOwner: String?
    var noun: String
    var rosettaAvailable: Bool
    var betaDXVKInstalled: Bool
    var dxmtInstalled: Bool
    var legacyDirectXInstalled: Bool
    var webView2Installed: Bool
    var usesSDKXAudio2: Bool
    var hasFrameLimiter: Bool
    var displayHz: Int
    var betaDXVKVersion: String?
    var upstreamDXMTVersion: String?

    var hasDX9Fallback: Bool { graphics.hasDX9Fallback }
    var drawsWith: GraphicsAPI { settings.useDX9 && graphics.hasDX9Fallback ? .dx9 : graphics }
    var onRosetta: Bool { settings.mullionRosetta && intelMullionInstalled && rosettaAvailable }

    private func entry(_ key: String) -> SettingEntry {
        guard let e = SettingsCatalog.entry(key) else { preconditionFailure("No setting \(key)") }
        return e
    }

    func applies(_ key: String) -> Bool { entry(key).appliesTo(self) }
    func needs(_ key: String) -> String? { entry(key).needs(self) }
    func title(_ key: String) -> String { let e = entry(key); return fill(e.shownTitle(self) ?? e.title) }
    func info(_ key: String) -> String { let e = entry(key); return fill(e.shownInfo(self) ?? e.info) }

    func fill(_ text: String) -> String {
        guard text.contains("{") else { return text }
        return text.replacingOccurrences(of: "{noun}", with: noun)
            .replacingOccurrences(of: "{hz}", with: "\(displayHz)")
            .replacingOccurrences(of: "{dxvkVersion}", with: betaDXVKVersion ?? "3.x")
            .replacingOccurrences(of: "{dxmtVersion}", with: upstreamDXMTVersion.map { " (\($0))" } ?? "")
    }
}

enum SettingValue: Equatable {
    case bool(Bool), int(Int), string(String)

    var text: String {
        switch self {
        case .bool(let b): return b ? "on" : "off"
        case .int(let i): return String(i)
        case .string(let s): return s
        }
    }

    init?(text: String, like: SettingValue) {
        let t = text.trimmingCharacters(in: .whitespaces)
        switch like {
        case .bool:
            switch t.lowercased() {
            case "on", "true", "yes", "1": self = .bool(true)
            case "off", "false", "no", "0": self = .bool(false)
            default: return nil
            }
        case .int:
            guard let i = Int(t) else { return nil }
            self = .int(i)
        case .string:
            self = .string(text)
        }
    }
}

struct SettingEntry {
    let key: String
    let title: String
    let info: String
    let section: String
    let appliesTo: (SettingContext) -> Bool
    let needs: (SettingContext) -> String?
    let choices: [(value: SettingValue, label: String)]
    let needsTexts: [String]
    let get: (GameSettings) -> SettingValue
    let set: (inout GameSettings, SettingValue) -> Void
    let shownTitle: (SettingContext) -> String?
    let shownInfo: (SettingContext) -> String?
}

enum SettingsCatalog {
    static let autoTessellationStart = 28
    static let tessellationLevels = [4, 8, 16, 24, 32, 48, 64]

    static func entry(_ key: String) -> SettingEntry? { byKey[key] }
    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    private typealias Access = (get: (GameSettings) -> SettingValue, set: (inout GameSettings, SettingValue) -> Void)

    private static func bool(_ kp: WritableKeyPath<GameSettings, Bool>) -> Access {
        ({ .bool($0[keyPath: kp]) }, { s, v in if case .bool(let b) = v { s[keyPath: kp] = b } })
    }
    private static func int(_ kp: WritableKeyPath<GameSettings, Int>) -> Access {
        ({ .int($0[keyPath: kp]) }, { s, v in if case .int(let i) = v { s[keyPath: kp] = i } })
    }
    private static func string(_ kp: WritableKeyPath<GameSettings, String>) -> Access {
        ({ .string($0[keyPath: kp]) }, { s, v in if case .string(let t) = v { s[keyPath: kp] = t } })
    }

    private static func make(_ key: String, _ title: String, _ section: String, _ access: Access, info: String,
                             appliesTo: @escaping (SettingContext) -> Bool = { _ in true },
                             needs: @escaping (SettingContext) -> String? = { _ in nil }, needsTexts: [String] = [],
                             choices: [(value: SettingValue, label: String)] = [],
                             shownTitle: @escaping (SettingContext) -> String? = { _ in nil },
                             shownInfo: @escaping (SettingContext) -> String? = { _ in nil }) -> SettingEntry {
        SettingEntry(key: key, title: title, info: info, section: section, appliesTo: appliesTo, needs: needs,
                     choices: choices, needsTexts: needsTexts, get: access.get, set: access.set,
                     shownTitle: shownTitle, shownInfo: shownInfo)
    }

    private static let engineSection = "General ▸ Engine"
    private static let graphicsSection = "Graphics"
    private static let advancedSection = "Graphics ▸ Advanced"
    private static let compatibilitySection = "Compatibility"

    private static let ownerText = "Set in {owner}'s settings, whose Windows environment this uses."
    private static func owner(_ c: SettingContext) -> String? {
        c.sharedEnvironmentOwner.map { ownerText.replacingOccurrences(of: "{owner}", with: $0) }
    }
    private static func dx9Capable(_ c: SettingContext) -> Bool {
        [GraphicsAPI.dx9, .unknown].contains(c.graphics) || c.graphics.hasDX9Fallback
    }
    private static let dx9Text = "Needs Use DirectX 9 on."
    private static func dx9Needs(_ c: SettingContext) -> String? {
        [GraphicsAPI.dx9, .unknown].contains(c.drawsWith) ? nil : dx9Text
    }
    private static let dxvkText = "Needs DirectX 9 via DXVK on."
    private static func dxvkNeeds(_ c: SettingContext) -> String? {
        dx9Needs(c) ?? (c.settings.dxvkD3D9 ? nil : dxvkText)
    }
    private static func usesWineD3D(_ c: SettingContext) -> Bool { [EngineID.wined3d, .dxvk, .mach9].contains(c.engine) }
    private static let wined3dText = "Needs Mach9 renderer set to WineD3D."
    private static func wined3dNeeds(_ c: SettingContext) -> String? {
        c.engine == .mach9 && c.settings.mach9Direct3D != "wined3d" ? wined3dText : nil
    }
    private static let turnOffDX9 = "Turn off Use DirectX 9 first."

    static let all: [SettingEntry] = [
        make("engine", "Graphics engine", engineSection,
             ({ .string($0.engine.rawValue) }, { s, v in if case .string(let t) = v, let e = EngineID(rawValue: t) { s.engine = e } }),
             info: "Which translator runs this {noun}. Automatic picks the best one for its graphics and architecture; the compatibility check shows why.",
             choices: EngineID.allCases.map { (.string($0.rawValue), $0.title) }),

        make("useDX9", "Use DirectX 9", graphicsSection, bool(\.useDX9),
             info: "Makes a DirectX 10 or 11 {noun} use its older DirectX 9 renderer, for games with no setting of their own to switch. Ferry hides DirectX 10 and 11 from it and starts it with -dx9. Try it if the {noun} crashes or draws wrong; turn it off if it won't start, since not every game still has a DirectX 9 renderer.",
             appliesTo: { $0.graphics.hasDX9Fallback }),
        make("metalFX", "DLSS via MetalFX", graphicsSection, bool(\.metalFX),
             info: "When DLSS is selected in the {noun}'s graphics options, D3DMetal upscales with Apple's MetalFX instead.",
             shownTitle: { $0.engine == .mach9 ? "MetalFX upscaling" : nil },
             shownInfo: { $0.engine == .mach9 ? "Renders at 75% resolution and upscales with MetalFX for a higher frame rate." : nil }),
        make("retina", "Retina resolution", graphicsSection, bool(\.retina),
             info: "Renders at the display's full pixel resolution. Sharper, but slower.",
             needs: owner, needsTexts: [ownerText]),
        make("gameMode", "macOS Game Mode", graphicsSection, int(\.gameMode),
             info: "Game Mode gives a game more of the processor and graphics and lowers controller and AirPods latency. Automatic turns it on for programs where Ferry found game graphics or a game engine, and off for apps.",
             appliesTo: { $0.engine == .d3dmetal }, needs: owner, needsTexts: [ownerText],
             choices: [(.int(0), "Automatic"), (.int(1), "On"), (.int(2), "Off")]),
        make("uiScale", "Interface size", graphicsSection, int(\.uiScale),
             info: "Windows' scaling for menus, text and buttons. Automatic uses 200% with Retina for apps (so they're sharp at their usual size) and 100% for games, which handle their own resolution.",
             needs: owner, needsTexts: [ownerText],
             choices: [(.int(0), "Automatic"), (.int(100), "Normal (100%)"), (.int(200), "Large (200%)")]),
        make("metalHUD", "Performance HUD", graphicsSection, bool(\.metalHUD),
             info: "Shows the frame rate and GPU statistics (Metal HUD) over the {noun}."),
        make("fpsLimit", "Frame rate limit", graphicsSection, int(\.fpsLimit),
             info: "Caps the frame rate. Lower limits keep frame pacing even, leave the processor room for sound, and run cooler on battery.",
             appliesTo: { $0.hasFrameLimiter },
             choices: [(.int(0), "Off (the display's rate with VSync on)")] + [30, 40, 45, 60, 90, 120].map { (.int($0), "\($0) FPS") },
             shownInfo: { c in
                 !c.hasFrameLimiter ? "Ferry can't limit the frame rate of this {noun}'s graphics on this engine, or the {noun} has anti-cheat. Use the {noun}'s own setting instead."
                     : c.settings.vsync ? "With VSync on, the {noun} runs at the display's rate ({hz} FPS), or at a lower limit picked here, with every frame still shown on a refresh. A limit a little below what the {noun} can hold keeps frame times even when it can't reach {hz}."
                     : nil
             }),
        make("vsync", "VSync", graphicsSection, bool(\.vsync),
             info: "Shows each frame in step with the display's refresh, so the picture doesn't tear (a frame showing partway through another), and keeps the {noun} from drawing more frames than the display can show: {hz} a second on this Mac's display. The time it would spend on frames you never see goes to the {noun} and macOS instead, and the Mac runs cooler. Use the frame rate limit with it to cap lower. Mullion's DirectX 10–12 can still tear. Turn it off for the highest frame rate and lowest input delay."),
        make("macFullScreenButton", "Native full-screen button", graphicsSection, bool(\.macFullScreenButton),
             info: "Enables the green window button for a windowed {noun}, opening it in a macOS full-screen space."),

        make("reportNVIDIA", "Report graphics card as NVIDIA", advancedSection, bool(\.reportNVIDIA),
             info: "D3DMetal tells games the Mac has an AMD card. Some games take AMD-only paths or workarounds that break on a Mac; this makes them see an NVIDIA GeForce RTX 3060 instead.",
             appliesTo: { $0.engine == .d3dmetal }),
        make("hideROV", "Hide ROV support", advancedSection, bool(\.hideROV),
             info: "Fixes some DirectX 12 games that show a black screen on D3DMetal. Tells the {noun} the graphics card has no rasterizer-ordered views, so it uses its ordinary drawing path. Needs Report graphics card as NVIDIA: some games use ROV on an AMD card whatever they're told.",
             appliesTo: { $0.engine == .d3dmetal },
             needs: { $0.settings.reportNVIDIA ? nil : "Needs Report graphics card as NVIDIA on." },
             needsTexts: ["Needs Report graphics card as NVIDIA on."]),
        make("nativeXAudio2", "Microsoft XAudio2", advancedSection, bool(\.nativeXAudio2),
             info: "This {noun} plays sound with an older XAudio2 from the DirectX SDK. Wine's own version can hold back or drop sounds such as dialogue, so Ferry loads Microsoft's copy instead. Turn off if the game's sound breaks.",
             appliesTo: { $0.usesSDKXAudio2 }),
        make("mullionRosetta", "CPU translation", advancedSection, bool(\.mullionRosetta),
             info: "How the {noun}'s Intel code runs on Apple silicon. FEX works without Rosetta, so it keeps working once macOS drops Rosetta. Rosetta 2 is usually faster, and uses MetalSharp's Intel build of the same Wine (it comes with D3DMetal 4 in Settings ▸ Components) in a Windows environment of its own. Without Rosetta or that build, Mullion uses FEX.",
             appliesTo: { $0.engine == .mullion },
             needs: { $0.intelMullionInstalled ? nil : "Rosetta 2 needs D3DMetal 4 (beta) from Settings ▸ Components, which includes MetalSharp's Intel build." },
             needsTexts: ["Rosetta 2 needs D3DMetal 4 (beta) from Settings ▸ Components, which includes MetalSharp's Intel build."],
             choices: [(.bool(false), "FEX"), (.bool(true), "Rosetta 2")]),
        make("metalSharpBackend", "MetalSharp renderer", advancedSection, string(\.metalSharpBackend),
             info: "How Mullion draws DirectX. Automatic uses Mullion for DirectX 10–12 and WineD3D for DirectX 9 and older. DXVK goes through Vulkan (64-bit only), WineD3D uses Wine's own DirectX for every version, and VKD3D-Proton is for DirectX 12 games that draw incorrectly on Mullion.",
             appliesTo: { $0.engine == .mullion },
             choices: [(.string(""), "Automatic (Mullion)"), (.string("dxvk"), "DXVK"), (.string("wine"), "WineD3D"),
                       (.string("vkd3d"), "VKD3D-Proton (DirectX 12)")]),
        make("metalSharpOpenGL", "OpenGL implementation", advancedSection, string(\.metalSharpOpenGL),
             info: "Which OpenGL draws OpenGL games, and DirectX 9 and older through WineD3D. WineMetalGL supports OpenGL 4.6 on Metal; Apple's OpenGL stops at 4.1 but is long-tested. Try Apple's if the {noun} draws incorrectly.",
             appliesTo: { $0.engine == .mullion },
             choices: [(.string(""), "WineMetalGL (default)"), (.string("wine"), "Apple's OpenGL")]),
        make("mullionVulkan", "Vulkan driver", advancedSection, string(\.mullionVulkan),
             info: "What Vulkan games, and the DXVK and VKD3D-Proton renderers, draw through. KosmicKrisp runs all of Vulkan 1.4 on Metal; MoltenVK is the long-tested default. Try the other one if the {noun} crashes or draws wrong.",
             appliesTo: { $0.engine == .mullion },
             needs: { c in
                 c.onRosetta ? "Only with CPU translation set to FEX: KosmicKrisp doesn't run through Rosetta 2, which uses MoltenVK."
                     : c.kosmicKrispAvailable ? nil : "Install Mach9 in Settings ▸ Components first."
             },
             needsTexts: ["Only with CPU translation set to FEX: KosmicKrisp doesn't run through Rosetta 2, which uses MoltenVK.",
                          "Install Mach9 in Settings ▸ Components first."],
             choices: [(.string(""), "MoltenVK (default)"), (.string("kosmickrisp"), "KosmicKrisp (from Mach9)")]),
        make("mach9Direct3D", "Mach9 renderer", advancedSection, string(\.mach9Direct3D),
             info: "How Mach9 draws DirectX. Metal uses mtld3d for DirectX 9 and DXMT for DirectX 10 and 11, straight to Metal. WineD3D uses Wine's own DirectX through OpenGL: slower, but worth trying if the {noun} draws incorrectly.",
             appliesTo: { $0.engine == .mach9 },
             choices: [(.string(""), "Metal: mtld3d, DXMT (default)"), (.string("wined3d"), "WineD3D")]),
        make("maxTessellation", "Tessellation detail", advancedSection, int(\.maxTessellation),
             info: "The most extra shape detail (DirectX 11 tessellation) the {noun} gets. Apple's graphics chips can only draw so much detail at once: above that, objects blink, vanish or show only from some angles. Automatic starts at \(autoTessellationStart) and, if objects were still skipped, uses less the next time. Higher numbers look smoother up close; 64 is the {noun}'s own maximum and can make objects vanish.",
             appliesTo: { $0.engine == .mach9 && $0.graphics == .dx11 },
             needs: { c in
                 c.settings.useDX9 ? turnOffDX9 : c.settings.mach9Direct3D == "wined3d" ? "Needs Mach9 renderer set to Metal." : nil
             },
             needsTexts: [turnOffDX9, "Needs Mach9 renderer set to Metal."],
             choices: [(.int(0), "Automatic")] + tessellationLevels.map { (.int($0), $0 == tessellationLevels[0] ? "\($0) (lowest)" : $0 == 64 ? "64 (full detail)" : "\($0)") }),
        make("fullMemory32", "Large address aware (4 GB)", advancedSection, bool(\.fullMemory32),
             info: "Gives this 32-bit {noun} 4 GB of address space instead of 2 GB, preventing out-of-memory crashes. Turn off if the {noun} won't start.",
             appliesTo: { $0.engine == .mach9 && $0.arch == .x86 }),
        make("dxvkD3D9", "DirectX 9 via DXVK", advancedSection, bool(\.dxvkD3D9),
             info: "Renders DirectX 9 through DXVK (Vulkan → Metal) instead of WineD3D. On Mullion, 64-bit programs use MetalSharp's newer DXVK, which runs natively on Apple silicon (needs Mach9 installed for its KosmicKrisp driver); 32-bit games use DXVK 1.10.3, the newest 32-bit build for macOS.",
             appliesTo: { dx9Capable($0) && $0.engine != .mach9 }, needs: dx9Needs, needsTexts: [dx9Text]),
        make("dxvkBeta", "DXVK 3 on KosmicKrisp (beta)", advancedSection, bool(\.dxvkBeta),
             info: "Uses the newest official DXVK ({dxvkVersion}) through KosmicKrisp instead of DXVK 1.10.3 from 2023 through MoltenVK. Experimental: turn it off if the {noun} draws incorrectly or won't start.",
             appliesTo: { dx9Capable($0) && $0.engine == .mullion && $0.arch == .x86 },
             needs: { c in
                 dxvkNeeds(c)
                     ?? (c.onRosetta ? "Only with CPU translation set to FEX: KosmicKrisp doesn't run through Rosetta 2. DXVK 1.10.3 is used instead."
                         : !c.betaDXVKInstalled ? "Optional beta download: install it in Settings ▸ Components ▸ Optional beta downloads."
                         : !c.kosmicKrispAvailable ? "Needs Mach9 installed, for its KosmicKrisp driver." : nil)
             },
             needsTexts: [dx9Text, dxvkText,
                          "Only with CPU translation set to FEX: KosmicKrisp doesn't run through Rosetta 2. DXVK 1.10.3 is used instead.",
                          "Optional beta download: install it in Settings ▸ Components ▸ Optional beta downloads.",
                          "Needs Mach9 installed, for its KosmicKrisp driver."]),
        make("dxvkVideoMemory", "Video memory (DXVK)", advancedSection, int(\.dxvkVideoMemory),
             info: "How much video memory the {noun} is told it has. On Macs with 8 GB or less, games told they have lots keep every texture loaded until macOS runs out of memory, which makes them stutter or play in slow motion. Raise it if a game hides graphics options or won't start.",
             appliesTo: { dx9Capable($0) && $0.engine != .mach9 }, needs: dxvkNeeds, needsTexts: [dx9Text, dxvkText],
             choices: [(.int(0), "Automatic (1 GB on Macs with 8 GB or less)"), (.int(512), "512 MB"), (.int(1024), "1 GB"),
                       (.int(2048), "2 GB"), (.int(4096), "4 GB"), (.int(-1), "DXVK's own")]),
        make("drawCopies", "Faster screen copies", advancedSection,
             ({ .string($0.drawCopies.map { $0 ? "on" : "off" } ?? "auto") },
              { s, v in if case .string(let t) = v { s.drawCopies = t == "on" ? true : t == "off" ? false : nil } }),
             info: "Performs DirectX 9 copies into the frame being drawn as draws, which Apple GPUs handle several times faster. Games with screen effects such as panoramas, blur or glow can make hundreds of these copies per frame. On automatically for DirectX 9 games. Turn it off if a game draws incorrectly or won't start.",
             appliesTo: dx9Capable, needs: dx9Needs, needsTexts: [dx9Text],
             choices: [(.string("auto"), "Automatic"), (.string("on"), "On"), (.string("off"), "Off")]),
        make("cncDdraw", "DirectDraw compatibility (cnc-ddraw)", advancedSection,
             ({ .bool($0.cncDdraw) }, { s, v in if case .bool(let b) = v { s.cncDdraw = b; if b { s.dgVoodoo = false } } }),
             info: "Fixes slow, flickering or broken DirectDraw games from the 1990s and 2000s.",
             appliesTo: { $0.arch == .x86 }),
        make("dgVoodoo", "Old 3D game fix (dgVoodoo2)", advancedSection,
             ({ .bool($0.dgVoodoo) }, { s, v in if case .bool(let b) = v { s.dgVoodoo = b; if b { s.cncDdraw = false } } }),
             info: "For 3D games from the late 1990s that use 3dfx Glide or DirectX 1–7, and draw wrong, crash or won't start. dgVoodoo2 draws them through DirectX 11 instead. Experimental under Wine: turn it off if the {noun} gets worse. Turns cnc-ddraw off, since both replace the same file.",
             appliesTo: { $0.arch == .x86 },
             needs: { $0.dgVoodooInstalled ? nil : "Install it in Settings ▸ Components first." },
             needsTexts: ["Install it in Settings ▸ Components first."]),
        make("dxmtUpstream", "DirectX 10/11 via DXMT (beta)", advancedSection, bool(\.dxmtUpstream),
             info: "Draws DirectX 10 and 11 with the newest official DXMT{dxmtVersion} straight to Metal, instead of DXVK through Vulkan. Often much faster. Experimental: turn it off if the {noun} crashes or draws wrong.",
             appliesTo: { $0.graphics.hasDX9Fallback && [EngineID.dxvk, .wined3d].contains($0.engine) },
             needs: { c in
                 c.settings.useDX9 ? turnOffDX9 : c.dxmtInstalled ? nil : "Install DXMT (beta) in Settings ▸ Components first."
             },
             needsTexts: [turnOffDX9, "Install DXMT (beta) in Settings ▸ Components first."],
             shownInfo: { $0.engine == .wined3d ? "Draws DirectX 10 and 11 with the newest official DXMT{dxmtVersion} straight to Metal, instead of WineD3D through OpenGL. Often much faster. Experimental: turn it off if the {noun} crashes or draws wrong." : nil }),
        make("wined3dVulkan", "WineD3D renderer", advancedSection, bool(\.wined3dVulkan),
             info: "What WineD3D draws DirectX 9 and older with. OpenGL is the most tested on the Mac. Vulkan goes through MoltenVK and can crash some games.",
             appliesTo: usesWineD3D, needs: wined3dNeeds, needsTexts: [wined3dText],
             choices: [(.bool(false), "OpenGL (default)"), (.bool(true), "Vulkan")]),
        make("wined3dSingleThread", "Single-threaded rendering", advancedSection, bool(\.wined3dSingleThread),
             info: "Turns off WineD3D's command-stream threading (CSMT). Fixes parts of models lagging a frame behind; slightly slower.",
             appliesTo: usesWineD3D, needs: wined3dNeeds, needsTexts: [wined3dText]),
        make("openGLBackingStore", "OpenGL backing store", advancedSection, bool(\.openGLBackingStore),
             info: "Fixes windows that freeze, stay blank or flicker.",
             appliesTo: usesWineD3D, needs: { wined3dNeeds($0) ?? owner($0) }, needsTexts: [wined3dText, ownerText]),

        make("windowsVersion", "Windows version", compatibilitySection, string(\.windowsVersion),
             info: "The Windows version the {noun} sees. Some older programs refuse to start, or behave differently, on newer versions.",
             needs: owner, needsTexts: [ownerText],
             choices: [(.string("win11"), "Windows 11"), (.string("win10"), "Windows 10"), (.string("win81"), "Windows 8.1"),
                       (.string("win7"), "Windows 7"), (.string("winxp64"), "Windows XP")]),
        make("windowsLanguage", "Windows language", compatibilitySection, string(\.windowsLanguage),
             info: "The language and region Windows tells the {noun} it has. Many games made for Japan, China, Korea or Russia show garbled text, crash or won't start unless Windows is set to their language, because they write text in that language's old character set. This changes only what the {noun} sees, not the {noun}'s own language setting.",
             choices: [(.string(""), "Same as this Mac")] + GameSettings.windowsLanguages.map { (.string($0.code), $0.name) }),
        make("commandIsCtrl", "⌘ Command as Ctrl", compatibilitySection, bool(\.commandIsCtrl),
             info: "Command works as Ctrl in the {noun}, so ⌘C and ⌘S act as Ctrl+C and Ctrl+S.",
             needs: owner, needsTexts: [ownerText]),
        make("optionIsAlt", "⌥ Option as Alt", compatibilitySection, bool(\.optionIsAlt),
             info: "Option works as Alt in the {noun}, for shortcuts such as Alt+Enter.",
             needs: owner, needsTexts: [ownerText]),
        make("captureFullscreen", "Exclusive full-screen mode", compatibilitySection, bool(\.captureFullscreen),
             info: "Lets the {noun} change the display's resolution. When off, full screen is virtual: it's scaled to fit the display.",
             needs: owner, needsTexts: [ownerText]),
        make("fastSync", "Fast synchronization (MSync)", compatibilitySection, bool(\.fastSync),
             info: "Handles Windows synchronization with Mach semaphores instead of Wine's server. Faster; rarely incompatible."),
        make("advertiseAVX", "Advertise AVX (Rosetta)", compatibilitySection, bool(\.advertiseAVX),
             info: "Reports AVX support to programs that require it. Applies to engines that run through Rosetta."),
        make("explorerFileDialogs", "Explorer-style file dialogs", compatibilitySection, bool(\.explorerFileDialogs),
             info: "Open and Save dialogs get Wine's Explorer-style window, with large icons, list and details views, sortable columns and a Desktop/Documents bar. They start in your Mac's Downloads folder unless the {noun} picks a folder. Dialogs with controls this window can't show (folder pickers, extra buttons or lists) stay Wine's simpler one. Turn it off if a {noun}'s Open or Save dialog misbehaves."),
        make("nativeDirectMusic", "Microsoft's DirectMusic", compatibilitySection, bool(\.nativeDirectMusic),
             info: "Plays the {noun}'s music with Microsoft's DirectMusic instead of Wine's, which is incomplete. Try it if a game from around 1998–2005 has no music, or crashes when music starts. Turn it off if sound gets worse.",
             appliesTo: { $0.arch == .x86 },
             needs: { $0.legacyDirectXInstalled ? nil : "Install DirectMusic and DirectPlay in Settings ▸ Components first." },
             needsTexts: ["Install DirectMusic and DirectPlay in Settings ▸ Components first."]),
        make("nativeDirectPlay", "Microsoft's DirectPlay", compatibilitySection, bool(\.nativeDirectPlay),
             info: "Uses Microsoft's DirectPlay instead of Wine's for the {noun}'s LAN or online multiplayer. Try it if an older game's multiplayer menu fails, crashes or finds no games.",
             appliesTo: { $0.arch == .x86 },
             needs: { $0.legacyDirectXInstalled ? nil : "Install DirectMusic and DirectPlay in Settings ▸ Components first." },
             needsTexts: ["Install DirectMusic and DirectPlay in Settings ▸ Components first."]),
        make("showOnDiscord", "Show on Discord", compatibilitySection, bool(\.showOnDiscord),
             info: "Shows this {noun} on your Discord profile while it runs."),
        make("arguments", "Launch arguments", compatibilitySection, string(\.arguments),
             info: "Extra options passed to the program when it starts, such as -windowed or -skipintro. Which ones work depends on the program."),
        make("extraEnv", "Environment variables", compatibilitySection, string(\.extraEnv),
             info: "Settings passed to Wine and its graphics layers when the program starts, written as NAME = value. For troubleshooting; most programs need none."),
        make("webView2", "WebView2 for launchers", compatibilitySection, bool(\.webView2),
             info: "For launchers whose window or login page is blank. Lets them show built-in web pages with Microsoft's WebView2, installed once in Settings ▸ Components and shared between games and apps. It doesn't work for every launcher under Wine.",
             needs: { $0.webView2Installed ? nil : "Install WebView2 in Settings ▸ Components first." },
             needsTexts: ["Install WebView2 in Settings ▸ Components first."]),
    ]
}
