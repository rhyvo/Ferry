import Foundation

private func fixContext(engine: EngineID = .mach9, graphics: GraphicsAPI = .dx9, arch: PEArch = .x86,
                        edit: (inout FixContext) -> Void = { _ in }) -> FixContext {
    var s = SettingContext.test(engine: engine, graphics: graphics)
    s.arch = arch
    var c = FixContext(setting: s, fallbackOrder: [.mach9, .dxvk, .wined3d], lowPowerMode: false, rovSeen: false,
                       learnedTessellation: nil, usesUpstreamDXMT: false, componentInstalled: [])
    edit(&c)
    return c
}

func runTroubleshootFixesTests() {
    var c = fixContext { $0.setting.settings.fullMemory32 = false }
    var first = TroubleshootFixes.steps(for: .crashes, c).first
    check(first?.id == "laa", "crashes: laa first")
    check(first?.action == .settings([SettingChange(key: "fullMemory32", value: "on")]), "crashes: laa turns it on")
    check(first?.inEffect == false, "crashes: laa not in effect when off")
    check(first?.title == "Large address aware (4 GB)", "crashes: laa title")
    c = fixContext { $0.setting.settings.fullMemory32 = true }
    first = TroubleshootFixes.steps(for: .crashes, c).first
    check(first?.id == "laa" && first?.inEffect == true, "crashes: laa in effect when on")
    c = fixContext(arch: .x64)
    check(!TroubleshootFixes.steps(for: .crashes, c).contains { $0.id == "laa" }, "crashes: no laa on 64-bit")

    c = fixContext(graphics: .dx11, arch: .x64)
    let dx9 = TroubleshootFixes.steps(for: .crashes, c).first { $0.id == "usedx9" }
    check(dx9?.action == .settings([SettingChange(key: "useDX9", value: "on")]), "crashes: dx9 fallback")

    let dxmtChanges = [SettingChange(key: "engine", value: "dxvk"), SettingChange(key: "useDX9", value: "off"),
                       SettingChange(key: "dxmtUpstream", value: "on")]
    c = fixContext(graphics: .dx11, arch: .x64) { $0.componentInstalled = ["dxmt"] }
    check(TroubleshootFixes.steps(for: .crashes, c).first { $0.id == "dxmt" }?.action == .settings(dxmtChanges), "dxmt: changes together")
    c = fixContext(graphics: .dx11, arch: .x64)
    check(TroubleshootFixes.steps(for: .crashes, c).first { $0.id == "dxmt" }?.action == .install(component: "dxmt", then: dxmtChanges),
          "dxmt: install first")

    c = fixContext(engine: .mach9)
    let sw = TroubleshootFixes.steps(for: .crashes, c).first { $0.id == "engine-dxvk" }
    check(sw?.action == .settings([SettingChange(key: "engine", value: "dxvk")]) && sw?.button == "Switch", "engine: next in order")

    c = fixContext()
    let fps = TroubleshootFixes.steps(for: .slow, c).first { $0.id == "fps" }
    check(fps?.action == .settings([SettingChange(key: "fpsLimit", value: "30")]) && fps?.button == "Set", "slow: frame limit")
    c = fixContext { $0.setting.hasFrameLimiter = false }
    let steps = TroubleshootFixes.steps(for: .slow, c)
    check(!steps.contains { $0.id == "fps" }, "slow: no limiter step")
    check(steps.contains { $0.action == .note && $0.detail.contains("own graphics settings") }, "slow: note about the game's settings")

    c = fixContext()
    let lang = TroubleshootFixes.steps(for: .garbledText, c).first { $0.id == "lang" }
    if case .picker(let key, let choices)? = lang?.action {
        check(key == "windowsLanguage", "lang: key")
        check(choices.first == PickerChoice(value: "", label: "Same as this Mac"), "lang: first choice")
        check(Array(choices.dropFirst()).map(\.value) == GameSettings.windowsLanguages.map(\.code), "lang: languages in order")
    } else {
        check(false, "lang: picker step")
    }

    let open = TroubleshootFixes.steps(for: .mouseStuck, c).first { $0.action == .open(.desktopAndDock) }
    check(open?.button == "Desktop & Dock", "mouseStuck: desktop and dock")

    var s = GameSettings()
    TroubleshootFixes.apply([SettingChange(key: "engine", value: "dxvk"), SettingChange(key: "dxmtUpstream", value: "on")], to: &s)
    check(s.engine == .dxvk && s.dxmtUpstream, "apply sets in order")

    c = fixContext(engine: .mach9, graphics: .dx9, arch: .x86)
    for symptom in Symptom.allCases {
        check(!TroubleshootFixes.steps(for: symptom, c).isEmpty, "steps for \(symptom.rawValue)")
    }
}
