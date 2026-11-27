import Foundation

enum Symptom: String, CaseIterable, Identifiable {
    case blackScreen, blackObjects, vanishingObjects, blurryTextures, crashes, slow, sound, noMusic, garbledText, multiplayer, blankLauncher,
         mouseStuck, pointerShows
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blackScreen: return "The screen is black, but there's sound"
        case .blackObjects: return "Objects or effects are black, or take ages to appear"
        case .vanishingObjects: return "Objects, walls or floors flicker or vanish from some angles"
        case .blurryTextures: return "Textures are blurry, grey or low-detail"
        case .crashes: return "It crashes or closes"
        case .slow: return "It's slow or stutters"
        case .sound: return "The sound crackles"
        case .noMusic: return "Music or sound effects are missing"
        case .garbledText: return "Text is garbled or shows question marks"
        case .multiplayer: return "Multiplayer (LAN or online) doesn't work"
        case .blankLauncher: return "A launcher's window or login page is blank"
        case .mouseStuck: return "The mouse is stuck inside the window"
        case .pointerShows: return "The Mac's mouse pointer shows while I play"
        }
    }
    var guide: String {
        switch self {
        case .blackScreen:
            return "Offers, in order: Hide ROV support (D3DMetal engine only; some DirectX 12 games use a drawing method called ROV that D3DMetal can show as black), Report graphics card as NVIDIA (D3DMetal only), Try DXMT (beta) for DirectX 10 and 11 games (needs Rosetta), Old 3D game fix (dgVoodoo2) for old 32-bit games, then switching to the next engine. If it is still black, show the log and check it for errors."
        case .blackObjects:
            return "The first time a game needs a material or effect, its shader has to be translated for Metal and built; until it is ready many games draw nothing there. It gets faster every session: quit from the game's own menu so the built shaders are saved. Offers Hide ROV support (D3DMetal only), switching a DirectX 11 or 12 game from Mach9 to D3DMetal when Rosetta is installed, and a 30 frames per second limit that leaves the processor and graphics room to build shaders."
        case .vanishingObjects:
            return "Things that blink, vanish or only show from certain angles usually mean the Mac's graphics chip refuses to draw them, often because the game asks for more DirectX 11 tessellation than Apple's chips can draw at once. Offers the Tessellation detail setting (Mach9 engine, DirectX 11 games), Use DirectX 9 for games that have an older renderer without tessellation, and switching engine. Also try turning tessellation, geometry or detail down or off in the game's own graphics settings."
        case .blurryTextures:
            return "Many games load sharp textures while you play; when they stay blurry the loading part is stuck or the game thinks there is too little video memory. Offers turning Fast Sync off (a busy part of the game can keep a shared lock so textures never load), telling DXVK the game has 2 GB of video memory (DirectX 9 via DXVK, not Mach9), and switching engine. Also check the game's own texture quality setting: changing its DirectX version or graphics card can reset it to low."
        case .crashes:
            return "Offers, in order: Large address aware for 32-bit games on Mach9 (out-of-memory crashes), Report graphics card as NVIDIA (D3DMetal only), Use DirectX 9 for DirectX 10 and 11 games that have an older renderer (turn it off again if the game will not start), Try DXMT (beta) for DirectX 10 and 11 games, Old 3D game fix (dgVoodoo2) for old 32-bit games, switching engine, and showing the log, whose last lines usually say what went wrong."
        case .slow:
            return "Offers turning off Low Power Mode if it is on, a 30 frames per second limit for steadier pacing and less heat and battery use (if Ferry can limit the engine; otherwise set it in the game's own settings), MetalFX upscaling for DirectX 9 games on Mach9 (renders at 75% resolution), and Try DXMT (beta) on DXVK or WineD3D. Close other apps while playing, especially on a Mac with 8 GB of memory: when memory runs short macOS moves data to disk and games stutter."
        case .sound:
            return "Crackling usually means the processor is fully busy and the sound misses its deadline. Offers a 30 frames per second limit to give it room and turning off Low Power Mode if it is on. Close other apps while playing: in testing, crackling lined up with the processor being fully loaded and memory being moved to disk."
        case .noMusic:
            return "For 32-bit games, offers Microsoft's DirectMusic (installs Microsoft's own copy, since Wine's is incomplete; many games from about 1998 to 2005 play music through it), then switching engine. Also check the game's own sound settings: some games turn music off or pick a missing sound device after their first start."
        case .garbledText:
            return "Offers the Windows language setting: set Windows to the language the game was made for, which fixes garbled text, crashes or failure to start in many games from Japan, China, Korea or Russia. It does not change the language the game itself uses; that is in the game's own settings."
        case .multiplayer:
            return "For 32-bit games, offers Microsoft's DirectPlay (installs Microsoft's own copy, since Wine's is incomplete; many older games run LAN and online multiplayer through it). If the Mac asks whether to allow incoming connections, click Allow, or other players cannot reach the game. Online games that need anti-cheat software do not run under Wine at all."
        case .blankLauncher:
            return "Many newer launchers draw their window or login page with Microsoft's WebView2. Offers installing WebView2 once (about 215 MB, shared between games), then turning on WebView2 for launchers, and switching engine. It does not work for every launcher under Wine: look for the launcher's offline mode, or add the game's own .exe to Ferry to start it without the launcher."
        case .mouseStuck:
            return "To get out now press Esc or click once. Windows keeps the mouse inside a program's window while you drag it, and if the Mac snaps the window into place mid-drag Wine can miss the release. Offers opening Desktop & Dock settings to turn off window tiling (it affects every app), and turning off Exclusive full-screen mode if it is on for the program, since that holds the mouse and suits games, not apps."
        case .pointerShows:
            return "On the Mach9 engine, offers Exclusive full-screen mode: Mach9 normally shows full screen at a scaled, virtual resolution, keeping the mouse in the game but leaving the Mac's pointer drawn; exclusive full screen lets the game hide it, and the screen switches resolution while it runs. Otherwise click once inside the window so it is the active app (macOS only lets the app in front hide the pointer; the pointer returns while the game's own menus are open), or switch engine."
        }
    }
    var icon: String {
        switch self {
        case .blackScreen: return "rectangle.fill"
        case .blackObjects: return "cube.transparent"
        case .vanishingObjects: return "eye.slash"
        case .blurryTextures: return "photo"
        case .crashes: return "xmark.octagon"
        case .slow: return "tortoise"
        case .sound: return "speaker.wave.2"
        case .noMusic: return "music.note"
        case .garbledText: return "character.bubble"
        case .multiplayer: return "person.2"
        case .blankLauncher: return "macwindow"
        case .mouseStuck: return "cursorarrow.rays"
        case .pointerShows: return "cursorarrow"
        }
    }
}

struct SettingChange: Equatable { let key: String; let value: String }
struct PickerChoice: Equatable { let value: String; let label: String }
enum OpenTarget: Equatable { case desktopAndDock, battery, log }

struct FixStep: Equatable {
    enum Action: Equatable {
        case settings([SettingChange])
        case picker(key: String, choices: [PickerChoice])
        case install(component: String, then: [SettingChange])
        case library(component: String)
        case open(OpenTarget)
        case note
    }
    let id: String
    let title: String
    let detail: String
    let action: Action
    let button: String
    let inEffect: Bool
    var afterInstall = "Turn On"
}

struct FixContext {
    var setting: SettingContext
    var fallbackOrder: [EngineID]
    var lowPowerMode: Bool
    var rovSeen: Bool
    var learnedTessellation: Int?
    var usesUpstreamDXMT: Bool
    var componentInstalled: Set<String>
}

enum TroubleshootFixes {
    static func steps(for symptom: Symptom, _ c: FixContext) -> [FixStep] {
        var b = Builder(c)
        let s = c.setting.settings, engine = c.setting.engine, noun = c.setting.noun
        switch symptom {
        case .blackScreen:
            if engine == .d3dmetal { b.hideROV(first: true); b.nvidia() }
            b.dxmt()
            b.dgVoodoo()
            b.switchEngine()
            b.note("Still black? Show the log from its settings and check for errors, or ask for help with the log.")
        case .blackObjects:
            b.note("The first time a game needs a material or effect, its shader has to be translated for Metal and built. Until it's ready, many games draw nothing there. It gets faster every session: quit from the game's own menu so the built shaders are saved.")
            if engine == .d3dmetal { b.hideROV(first: false) }
            if engine == .mach9 && c.setting.arch != .x86 && [.dx11, .dx12].contains(c.setting.drawsWith) && c.setting.rosettaAvailable {
                b.engineStep(.d3dmetal, why: "D3DMetal turns DirectX 11 and 12 shaders straight into Metal with Apple's own converter, much faster than Mach9's route through Vulkan.")
            }
            b.frameLimit(why: "Leaves the processor and graphics room to build shaders while you play.")
        case .vanishingObjects:
            b.note("When things blink, disappear, or only show from certain angles or spots, the Mac's graphics chip is usually refusing to draw them: often because the \(noun) asks for more shape detail (DirectX 11 tessellation) than Apple's graphics chips can draw at once.")
            b.tessellation()
            if c.setting.graphics.hasDX9Fallback {
                b.toggle("usedx9", "Use DirectX 9",
                         "The \(noun)'s older DirectX 9 renderer has no tessellation, so nothing gets refused, at the cost of the DirectX 10 and 11 extras.",
                         key: "useDX9", isOn: s.useDX9)
            }
            b.switchEngine()
            b.note("Also try turning tessellation, or the \(noun)'s geometry or detail level, down or off in its own graphics settings.")
        case .blurryTextures:
            b.note("Many games start with low-detail textures and swap in sharp ones while you play. When they stay blurry, the part of the game that loads them is stuck, or the game thinks there's too little video memory.")
            b.toggle("fastsync", "Fast Sync",
                     "With Fast Sync on, a busy part of the \(noun) can keep a shared lock to itself, so the part that loads sharp textures never gets its turn. Turning it off fixed textures that stayed blurry in testing; it can cost a little speed.",
                     key: "fastSync", isOn: s.fastSync, suggest: false)
            if s.dxvkD3D9 && engine != .mach9 && s.dxvkVideoMemory != 2048 {
                b.add("dxvkmem", "Video memory (DXVK)", "Games told they have little video memory pick low-detail textures. This tells it there's 2 GB.",
                      .settings([SettingChange(key: "dxvkVideoMemory", value: "2048")]), button: "Use 2 GB")
            }
            b.note("Check the \(noun)'s own texture quality setting too: changing its DirectX version or graphics card can reset it to low.")
            b.switchEngine()
        case .crashes:
            if c.setting.applies("fullMemory32") {
                b.toggle("laa", c.setting.title("fullMemory32"), c.setting.info("fullMemory32"), key: "fullMemory32", isOn: s.fullMemory32)
            }
            if engine == .d3dmetal { b.nvidia() }
            if c.setting.graphics.hasDX9Fallback {
                b.toggle("usedx9", "Use DirectX 9",
                         "Many \(c.setting.graphics.label) games from around 2006–2010 also have a DirectX 9 renderer, which every engine runs more reliably. This hides DirectX 10 and 11 so the \(noun) uses it. Turn it off again if the \(noun) won't start, since not every game still has one.",
                         key: "useDX9", isOn: s.useDX9)
            }
            b.dxmt()
            b.dgVoodoo()
            b.switchEngine()
            b.add("log", "Show the log", "The last lines usually say what went wrong.", .open(.log), button: "Show Log")
        case .slow:
            b.lowPower()
            b.frameLimit(why: "Steadier frame pacing, and less heat and battery use.")
            if engine == .mach9 && c.setting.drawsWith == .dx9 {
                b.toggle("metalfx", "MetalFX upscaling", "Renders at 75% resolution and upscales with MetalFX.", key: "metalFX", isOn: s.metalFX)
            }
            if [EngineID.dxvk, .wined3d].contains(engine) { b.dxmt() }
            b.note("Close other apps while playing, especially on a Mac with 8 GB of memory: when memory runs short, macOS moves data to disk and games stutter.")
        case .sound:
            b.frameLimit(why: "Crackling usually means the processor is fully busy and the sound misses its deadline. A frame limit gives it room.")
            b.lowPower()
            b.note("Close other apps while playing. In our testing, crackling lined up with the processor being fully loaded and memory being moved to disk.")
        case .noMusic:
            if c.setting.arch == .x86 {
                b.component(ComponentName.legacyDirectX, "dmusic", "Microsoft's DirectMusic",
                            "Many games from around 1998–2005 play their music with DirectMusic, and Wine's version is incomplete, so the music is silent or the \(noun) crashes when it starts. This uses Microsoft's instead.",
                            changes: [SettingChange(key: "nativeDirectMusic", value: "on")], isOn: s.nativeDirectMusic)
            }
            b.switchEngine()
            b.note("Also check the \(noun)'s own sound settings: some games turn music off, or pick a sound device that isn't there, after their first start.")
        case .garbledText:
            b.language()
            b.note("This is for games made for one language, often Japanese, Chinese, Korean or Russian, that write text in its old character set. It doesn't change the language the \(noun) itself uses; that's in its own settings, if it has one.")
        case .multiplayer:
            if c.setting.arch == .x86 {
                b.component(ComponentName.legacyDirectX, "dplay", "Microsoft's DirectPlay",
                            "Many older games run their LAN and online multiplayer through DirectPlay, and Wine's version is incomplete: the multiplayer menu fails, crashes or finds no games. This uses Microsoft's instead.",
                            changes: [SettingChange(key: "nativeDirectPlay", value: "on")], isOn: s.nativeDirectPlay)
            }
            b.note("If the Mac asks whether to allow incoming connections, click Allow, or other players can't reach your game. Online games that need anti-cheat software don't run under Wine at all.")
        case .mouseStuck:
            b.note("To get out now: press Esc, or click once. While you drag a Windows program's window, Windows keeps the mouse inside it until the button is released; if the Mac snaps the window into place mid-drag, Wine can miss the release.")
            b.add("tiling", "Turn off window tiling", "Stops the Mac snapping windows when they're dragged to a screen edge, which is what usually causes this. It affects every app; you can still tile from the green button's menu.",
                  .open(.desktopAndDock), button: "Desktop & Dock")
            if s.captureFullscreen {
                b.toggle("exclusive", "Exclusive full-screen mode", "It's on for this program. It lets Wine take over the display and hold the mouse whenever a window covers the screen, which suits games but traps the mouse in apps.",
                         key: "captureFullscreen", isOn: s.captureFullscreen, suggest: false)
            }
        case .pointerShows:
            if engine == .mach9 {
                b.toggle("exclusive", "Exclusive full-screen mode",
                         s.captureFullscreen
                            ? "It's on for this \(noun), which lets it hide the Mac's pointer. If the pointer still shows, try the steps below."
                            : "Mach9 normally shows full-screen programs at a scaled, virtual resolution. In that mode it keeps the mouse in the \(noun) but can leave the Mac's pointer on screen. Exclusive full-screen lets the \(noun) hide it; the screen switches resolution when the \(noun) starts and quits.",
                         key: "captureFullscreen", isOn: s.captureFullscreen)
            }
            if engine != .mach9 || s.captureFullscreen {
                b.note("Click once inside its window so it's the active app: macOS only lets the app in front hide the pointer. If its own menus use the mouse, the pointer comes back while they're open.")
                b.switchEngine()
            }
        case .blankLauncher:
            if c.setting.webView2Installed {
                b.toggle("webview2", "WebView2 for launchers",
                         "Many newer launchers draw their window or login page as a web page with Microsoft's WebView2. This points it at Ferry's shared copy.",
                         key: "webView2", isOn: s.webView2)
            } else {
                b.add("webview2", "Install WebView2",
                      "Many newer launchers draw their window or login page as a web page with Microsoft's WebView2. Ferry installs it once (about 215 MB) and shares it between games; afterwards, turn on WebView2 for launchers here or in the game's settings.",
                      .install(component: ComponentName.webView2, then: []), button: "Install")
            }
            b.switchEngine()
            b.note("WebView2 doesn't work for every launcher under Wine. If it stays blank, look for the launcher's offline mode, or add the game's own .exe to Ferry to start it without the launcher.")
        }
        return b.steps
    }

    static func apply(_ changes: [SettingChange], to settings: inout GameSettings) {
        for change in changes {
            guard let entry = SettingsCatalog.entry(change.key),
                  let value = SettingValue(text: change.value, like: entry.get(settings)) else { continue }
            entry.set(&settings, value)
        }
    }

    private enum ComponentName {
        static let dxmt = "dxmt", legacyDirectX = "legacyDirectX", dgVoodoo = "dgVoodoo", webView2 = "webView2"
    }

    private struct Builder {
        let c: FixContext
        var steps: [FixStep] = []
        private var notes = 0
        init(_ c: FixContext) { self.c = c }
        private var s: GameSettings { c.setting.settings }
        private var noun: String { c.setting.noun }
        private var engine: EngineID { c.setting.engine }

        mutating func add(_ id: String, _ title: String, _ detail: String, _ action: FixStep.Action, button: String, inEffect: Bool = false,
                          afterInstall: String = "Turn On") {
            steps.append(FixStep(id: id, title: title, detail: detail, action: action, button: button, inEffect: inEffect, afterInstall: afterInstall))
        }

        mutating func note(_ text: String) {
            notes += 1
            add("note\(notes)", "", text, .note, button: "")
        }

        mutating func toggle(_ id: String, _ title: String, _ detail: String, key: String, isOn: Bool, suggest: Bool = true) {
            add(id, title, detail, .settings([SettingChange(key: key, value: suggest ? "on" : "off")]),
                button: suggest ? "Turn On" : "Turn Off", inEffect: isOn == suggest)
        }

        mutating func component(_ component: String, _ id: String, _ title: String, _ detail: String, changes: [SettingChange], isOn: Bool) {
            if c.componentInstalled.contains(component) {
                add(id, title, detail, .settings(changes), button: "Turn On", inEffect: isOn)
            } else {
                add(id, title, detail, .install(component: component, then: changes), button: "Install")
            }
        }

        mutating func hideROV(first: Bool) {
            add("rov", "Hide ROV support",
                "\(c.rovSeen ? "Ferry saw this \(noun) draw with ROV. " : "")Some DirectX 12 games use a drawing method called ROV, which D3DMetal says it supports but can show as black. This tells the game it isn't available (and reports an NVIDIA card), so it uses its ordinary method.\(first ? " Fixed a black screen in testing." : "")",
                .settings([SettingChange(key: "reportNVIDIA", value: "on"), SettingChange(key: "hideROV", value: "on")]),
                button: "Turn On", inEffect: s.hideROV)
        }

        mutating func nvidia() {
            toggle("nvidia", "Report graphics card as NVIDIA",
                   "D3DMetal tells games the Mac has an AMD card. Some games take AMD-only paths or workarounds that crash or draw wrong on a Mac; this makes them see an NVIDIA card instead.\(s.hideROV ? " Hide ROV support needs it, so turning it off turns that off too." : "")",
                   key: "reportNVIDIA", isOn: s.reportNVIDIA)
        }

        mutating func dxmt() {
            guard [GraphicsAPI.dx10, .dx11].contains(c.setting.graphics) && c.setting.rosettaAvailable && c.setting.sharedEnvironmentOwner == nil else { return }
            let keepsEngine = [EngineID.dxvk, .wined3d].contains(engine)
            let instead = engine == .mullion ? "Mullion's own DXMT, so it can work where that crashes"
                : engine == .mach9 ? "Mach9's own DXMT, so it can work where that crashes"
                : engine == .wined3d ? "WineD3D, which draws DirectX 10 and 11 through OpenGL"
                : engine == .dxvk ? "DXVK, which draws them through Vulkan" : "D3DMetal, so it can work where that crashes"
            let detail = "The newest DXMT, from its own project, draws DirectX 10 and 11 straight to Metal, instead of \(instead). \(keepsEngine ? "This turns it on" : "This moves the \(noun) to the DXVK engine (Wine Staging, through Rosetta) with DXMT drawing")\(s.useDX9 ? ", and turns Use DirectX 9 off" : ""). Experimental."
            let changes = (keepsEngine ? [] : [SettingChange(key: "engine", value: EngineID.dxvk.rawValue)])
                + [SettingChange(key: "useDX9", value: "off"), SettingChange(key: "dxmtUpstream", value: "on")]
            if c.componentInstalled.contains(ComponentName.dxmt) {
                add("dxmt", "Try DXMT (beta)", detail, .settings(changes), button: "Try It", inEffect: c.usesUpstreamDXMT)
            } else {
                add("dxmt", "Try DXMT (beta)", detail, .install(component: ComponentName.dxmt, then: changes), button: "Install", afterInstall: "Try It")
            }
        }

        mutating func dgVoodoo() {
            guard c.setting.arch == .x86 && (c.setting.graphics == .unknown || s.cncDdraw || s.dgVoodoo) else { return }
            component(ComponentName.dgVoodoo, "dgvoodoo", "Old 3D game fix (dgVoodoo2)",
                      "For 3D games from the late 1990s that use 3dfx Glide or DirectX 1–7: draws them through DirectX 11 instead. Experimental under Wine: turn it off if it makes things worse.\(s.cncDdraw ? " Turns cnc-ddraw off, since both replace the same file." : "")",
                      changes: [SettingChange(key: "dgVoodoo", value: "on"), SettingChange(key: "cncDdraw", value: "off")], isOn: s.dgVoodoo)
        }

        mutating func tessellation() {
            guard engine == .mach9 && c.setting.drawsWith == .dx11 && s.mach9Direct3D != "wined3d" else { return }
            let learned = c.learnedTessellation ?? SettingsCatalog.autoTessellationStart
            let levels = SettingsCatalog.tessellationLevels
            let choices = [PickerChoice(value: "0", label: "Automatic (\(learned))")]
                + levels.filter { $0 < 64 }.map { PickerChoice(value: String($0), label: $0 == levels[0] ? "\($0) (lowest)" : "\($0)") }
            add("tess", "Tessellation detail",
                "Caps the extra shape detail, so every object fits what the Mac can draw. Automatic starts at \(SettingsCatalog.autoTessellationStart) and uses less after a run where objects were still skipped; pick a lower number if they still blink. Lower numbers look a little less smooth up close.",
                .picker(key: "maxTessellation", choices: choices), button: "Set")
        }

        mutating func language() {
            let choices = [PickerChoice(value: "", label: "Same as this Mac")]
                + GameSettings.windowsLanguages.map { PickerChoice(value: $0.code, label: $0.name) }
            add("lang", "Windows language",
                "Set Windows to the language the \(noun) was made for, so its text shows properly. Many games from Japan, China, Korea or Russia show garbled text, crash or won't start otherwise.",
                .picker(key: "windowsLanguage", choices: choices), button: "Set")
        }

        mutating func switchEngine() {
            let why = "Each engine translates graphics differently; a program that fails on one often works on another."
            if let i = c.fallbackOrder.firstIndex(of: engine), i + 1 < c.fallbackOrder.count {
                self.engineStep(c.fallbackOrder[i + 1], why: why)
            } else if let other = c.fallbackOrder.first(where: { $0 != engine }) {
                self.engineStep(other, why: why)
            }
        }

        mutating func engineStep(_ e: EngineID, why: String) {
            add("engine-\(e.rawValue)", "Try \(e.short)", why, .settings([SettingChange(key: "engine", value: e.rawValue)]), button: "Switch")
        }

        mutating func frameLimit(why: String) {
            if c.setting.hasFrameLimiter {
                add("fps", "Limit the frame rate to 30", why, .settings([SettingChange(key: "fpsLimit", value: "30")]),
                    button: "Set", inEffect: s.fpsLimit == 30)
            } else {
                note("Limit the frame rate to 30 in the \(noun)'s own graphics settings. \(why) (Ferry can't limit it on \(engine.short).)")
            }
        }

        mutating func lowPower() {
            guard c.lowPowerMode else { return }
            add("lpm", "Turn off Low Power Mode", "It slows the processor and graphics a lot.", .open(.battery), button: "Battery Settings")
        }
    }
}
