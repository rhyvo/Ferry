import Foundation

extension SettingContext {
    static func test(engine: EngineID, graphics: GraphicsAPI) -> SettingContext {
        SettingContext(settings: GameSettings(), engine: engine, graphics: graphics, arch: .x64,
                       dgVoodooInstalled: false, kosmicKrispAvailable: false, intelMullionInstalled: false,
                       mach9Available: true, sharedEnvironmentOwner: nil, noun: "game", rosettaAvailable: true,
                       betaDXVKInstalled: false, dxmtInstalled: false, legacyDirectXInstalled: false,
                       webView2Installed: false, usesSDKXAudio2: false, hasFrameLimiter: true, displayHz: 60,
                       betaDXVKVersion: nil, upstreamDXMTVersion: nil)
    }
}

func runSettingsCatalogTests() {
    var c = SettingContext.test(engine: .mach9, graphics: .dx11)
    c.settings.useDX9 = true
    check(SettingsCatalog.entry("maxTessellation")!.needs(c) == "Turn off Use DirectX 9 first.", "tessellation needs DX9 off")
    c.settings.useDX9 = false; c.settings.mach9Direct3D = "wined3d"
    check(SettingsCatalog.entry("maxTessellation")!.needs(c) == "Needs Mach9 renderer set to Metal.", "tessellation needs Metal renderer")
    c.settings.mach9Direct3D = ""
    check(SettingsCatalog.entry("maxTessellation")!.needs(c) == nil, "tessellation ready on Mach9 Metal")

    let d3d = SettingContext.test(engine: .d3dmetal, graphics: .dx11)
    check(!SettingsCatalog.entry("maxTessellation")!.appliesTo(d3d), "tessellation hidden off Mach9")
    check(SettingsCatalog.entry("hideROV")!.needs(d3d) == "Needs Report graphics card as NVIDIA on.", "hide ROV needs NVIDIA")

    var s = GameSettings(); let e = SettingsCatalog.entry("maxTessellation")!
    e.set(&s, SettingValue(text: "4", like: e.get(s))!)
    check(s.maxTessellation == 4 && e.get(s).text == "4", "set and read tessellation as text")
    let dx9 = SettingsCatalog.entry("useDX9")!
    dx9.set(&s, SettingValue(text: "on", like: dx9.get(s))!)
    check(s.useDX9 && dx9.get(s) == .bool(true) && dx9.get(s).text == "on", "set a toggle from text")
    check(SettingValue(text: "maybe", like: .bool(false)) == nil, "a toggle refuses other text")
    check(SettingValue(text: "four", like: .int(0)) == nil, "a number refuses other text")
    let copies = SettingsCatalog.entry("drawCopies")!
    check(copies.get(s).text == "auto", "unset drawCopies reads as auto")
    copies.set(&s, .string("off"))
    check(s.drawCopies == false, "drawCopies off")

    for e in SettingsCatalog.all { check(!e.info.isEmpty, e.key) }

    let props = Set(Mirror(reflecting: GameSettings()).children.compactMap(\.label))
    let keys = SettingsCatalog.all.map(\.key)
    check(Set(keys) == props, "catalogue keys are GameSettings' properties: \(props.symmetricDifference(keys).sorted())")
    check(Set(keys).count == keys.count, "no key twice")

    var variants: [GameSettings] = [GameSettings()]
    var v = GameSettings(); v.useDX9 = true; v.mach9Direct3D = "wined3d"; v.mullionRosetta = true; variants.append(v)
    v = GameSettings(); v.dxvkD3D9 = true; v.mullionRosetta = true; variants.append(v)
    v = GameSettings(); v.dxvkD3D9 = true; v.hideROV = true; variants.append(v)
    for engine in EngineID.allCases {
        for graphics in [GraphicsAPI.dx9, .dx11, .dx12, .unknown] {
            for arch in [PEArch.x86, .x64] {
                for settings in variants {
                    for installed in [false, true] {
                        var x = SettingContext.test(engine: engine, graphics: graphics)
                        x.arch = arch; x.settings = settings
                        x.dgVoodooInstalled = installed; x.kosmicKrispAvailable = installed
                        x.intelMullionInstalled = !installed; x.betaDXVKInstalled = installed
                        x.dxmtInstalled = installed; x.legacyDirectXInstalled = installed; x.webView2Installed = installed
                        x.sharedEnvironmentOwner = installed ? "{owner}" : nil
                        for e in SettingsCatalog.all {
                            if let n = e.needs(x) { check(e.needsTexts.contains(n), "\(e.key) needsTexts lacks: \(n)") }
                        }
                    }
                }
            }
        }
    }

    var app = SettingContext.test(engine: .mach9, graphics: .dx11)
    app.noun = "app"
    check(app.info("maxTessellation").hasPrefix("The most extra shape detail (DirectX 11 tessellation) the app gets."), "noun filled in")
    check(app.info("maxTessellation").contains("Automatic starts at 28 and"), "tessellation start filled in")
    check(app.title("metalFX") == "MetalFX upscaling", "Mach9 calls it MetalFX upscaling")
    check(d3d.title("metalFX") == "DLSS via MetalFX", "D3DMetal calls it DLSS via MetalFX")
    var off = d3d; off.settings.vsync = false
    check(off.info("fpsLimit").hasPrefix("Caps the frame rate."), "limit without VSync")
    check(d3d.info("fpsLimit").contains("display's rate (60 FPS)"), "limit with VSync names the display rate")
    var none = d3d; none.hasFrameLimiter = false
    check(!none.applies("fpsLimit") && none.info("fpsLimit").hasPrefix("Ferry can't limit"), "no limiter on this engine")
    check(!d3d.info("dxvkBeta").contains("{"), "no placeholder left in what's shown")
}
