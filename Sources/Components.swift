import Foundation

enum ComponentTier {
    case required, recommended, optional, beta

    var label: String {
        switch self {
        case .required: return "Required"
        case .recommended: return "Recommended"
        case .optional: return "Optional"
        case .beta: return "Optional beta downloads"
        }
    }

    var badge: String { self == .beta ? "Beta" : label }
}

enum Component: String, CaseIterable, Identifiable {
    case rosetta, gptk, staging, visualCpp, directX
    case metalSharp, mach9, dxvk, gstreamer, dotNet48, dotNetModern, xna, openAL, physX, lav, shaderCompiler, cncDdraw, sevenZip
    case webView2
    case dxvk3, d3dmetal4

    var id: String { rawValue }

    var tier: ComponentTier {
        switch self {
        case .rosetta, .gptk, .staging, .visualCpp, .directX: return .required
        case .webView2: return .optional
        case .dxvk3, .d3dmetal4: return .beta
        default: return .recommended
        }
    }

    var title: String {
        switch self {
        case .rosetta: return "Rosetta 2"
        case .gptk: return "Game Porting Toolkit (D3DMetal)"
        case .staging: return "Wine Staging"
        case .visualCpp: return "Visual C++ 2005–2022"
        case .directX: return "DirectX (June 2010)"
        case .metalSharp: return "MetalSharp Wine (Mullion)"
        case .mach9: return "Mach9 Wine"
        case .dxvk: return "DXVK"
        case .gstreamer: return "GStreamer"
        case .dotNet48: return ".NET Framework 4.8"
        case .dotNetModern: return ".NET 6 and 8"
        case .xna: return "XNA Framework 4.0"
        case .openAL: return "OpenAL"
        case .physX: return "PhysX (legacy)"
        case .lav: return "LAV Filters"
        case .shaderCompiler: return "DirectX shader compiler"
        case .cncDdraw: return "Old 2D game fix (cnc-ddraw)"
        case .sevenZip: return "7-Zip"
        case .webView2: return "WebView2"
        case .dxvk3: return "DXVK 3 on KosmicKrisp (beta)"
        case .d3dmetal4: return "D3DMetal 4 (beta)"
        }
    }

    var detail: String {
        switch self {
        case .rosetta: return "Lets Apple silicon run Windows' Intel code for the D3DMetal and Wine Staging engines."
        case .gptk: return "The main engine for modern 64-bit games and programs (DirectX 11/12 → Metal)."
        case .staging: return "Runs 32-bit and older games and programs, and the installers every library needs."
        case .visualCpp: return "The C++ runtime libraries nearly every Windows game and program is built against."
        case .directX: return "DirectX 9–11 helper libraries, sound (XAudio) and controllers (XInput) for older games."
        case .metalSharp: return "A native Apple-silicon Wine that doesn't need Rosetta; best for Clickteam, OpenGL and some 32-bit games."
        case .mach9: return "A native Apple-silicon Wine that turns DirectX 9 straight into Metal (mtld3d), plus DirectX 10–12 (DXMT). The best engine for DirectX 9 games and 32-bit DirectX 10/11 games. macOS 26.4 and later."
        case .dxvk: return "DirectX 10/11 → Vulkan → Metal, the second engine for DirectX 11 games."
        case .gstreamer: return "Plays video cutscenes in Wine Staging games and programs. macOS asks for your password."
        case .dotNet48: return "Microsoft's .NET Framework for older .NET games, tools and launchers. The slowest to install."
        case .dotNetModern: return "Desktop runtimes for newer .NET apps: mod managers, editors, launchers."
        case .xna: return "For indie games built with XNA (early Terraria, Fez, Bastion)."
        case .openAL: return "A sound library many older games use; Wine doesn't include it."
        case .physX: return "NVIDIA's physics library for 2008–2013 games like Mirror's Edge and Borderlands."
        case .lav: return "Video decoders for older games and programs that play video the old Windows way."
        case .shaderCompiler: return "Microsoft's compiler for graphics effects; Wine's own copy occasionally fails."
        case .cncDdraw: return "Fixes slow or broken 90s and 2000s 2D games. Only used for games where it's switched on."
        case .sevenZip: return "Unpacks games that come as archives faster, including multi-part ones (.part1.rar, .7z.001). Under 1 MB."
        case .dxvk3: return "The newest official DXVK, for 32-bit DirectX 9 games on Mullion, drawn through KosmicKrisp (from Mach9) instead of MoltenVK. Ferry's regular DXVK for these games is from 2023. Experimental: used only for games where you turn it on, next to DirectX 9 via DXVK."
        case .d3dmetal4: return "Apple's newest D3DMetal (Game Porting Toolkit 4 beta: DirectX 12 through Metal 4) on Wine 11, from MetalSharp's x86_64 build, instead of the Game Porting Toolkit's Wine 7.7. Once installed, every game on the D3DMetal engine uses it, each with a new Windows environment of its own (the first start sets it up). On macOS before 27 it brings D3DMetal 3.0. Runs through Rosetta. Remove it in Settings ▸ Engines to go back."
        case .webView2: return "The browser engine some newer launchers use for their window or login page. Installed once and shared; each game uses it only with WebView2 for launchers turned on in its settings. Often doesn't work under Wine."
        }
    }

    var withoutIt: String? {
        switch self {
        case .metalSharp: return "Without it: no Mullion engine, and no fallback once Rosetta is limited after macOS 27. Downloaded later if a game is set to use it."
        case .dxvk: return "Without it: downloaded later the first time a game needs DXVK."
        case .mach9: return "Without it: downloaded later the first time a DirectX 9 game needs it, which makes that first start take a few minutes longer."
        case .gstreamer: return "Without it: some cutscenes may show black or freeze."
        case .dotNet48, .dotNetModern, .xna, .physX, .openAL: return "Without it: games and programs that need it won't start."
        case .lav: return "Without it: some older videos may not play."
        case .shaderCompiler: return "Without it: Wine's built-in compiler is used, which misses some effects."
        case .cncDdraw: return "Without it: the old 2D game fix switch won't do anything."
        case .sevenZip: return "Without it: archives unpack with macOS's slower built-in tool, and 7-Zip is downloaded the first time you drop a multi-part archive."
        case .webView2: return "Without it: the WebView2 for launchers switch in game settings stays greyed out. You can install it below at any time."
        default: return nil
        }
    }

    var approxBytes: Int {
        switch self {
        case .visualCpp: return 95_000_000
        case .directX: return 100_000_000
        case .dotNet48: return 120_000_000
        case .dotNetModern: return 222_000_000
        case .xna: return 7_000_000
        case .physX: return 30_000_000
        case .lav: return 13_000_000
        case .shaderCompiler: return 8_000_000
        case .webView2: return 215_000_000
        case .dxvk3: return 18_000_000
        case .openAL, .cncDdraw: return 2_000_000
        case .sevenZip: return 1_000_000
        default: return 0
        }
    }

    var defaultsKey: String { "component.\(rawValue)" }

    static func isOn(_ component: Component) -> Bool {
        if component == .mach9 && !Platform.mach9Available { return false }
        if component.tier == .required { return true }
        if component.tier == .beta { return false }
        return UserDefaults.standard.object(forKey: component.defaultsKey) as? Bool ?? (component.tier == .recommended)
    }

    var runtime: RuntimeKind? {
        switch self {
        case .gptk: return .gptk
        case .staging: return .staging
        case .dxvk: return .dxvk
        case .metalSharp: return .arm64
        case .mach9: return .mach9
        case .d3dmetal4: return .x64
        default: return nil
        }
    }
}
