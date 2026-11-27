import Foundation

func runAppleChatLogicTests() {
    typealias L = AppleChatLogic
    check(L.sortKind(json: #"{"pick":"a question"}"#) == 2 && L.sortKind(json: "garbled {") == nil && L.sortKind(json: #"{"pick":"other"}"#) == nil, "sortKind parses")
    check(L.sortKinds.count == 4 && L.sortInstructions.contains("nothing for now"), "sort kinds and examples")
    check(L.symptomOptions == Symptom.allCases.map(\.title), "symptom options are the titles")
    check(L.symptomCall(kind: 0)?.options == L.symptomOptions && L.symptomCall(kind: 1)?.options == L.symptomOptions + [L.notNamedOption]
          && L.symptomCall(kind: 2) == nil && L.symptomCall(kind: nil) == nil, "second call per kind")
    let crash = #"{"pick":"It crashes or closes"}"#, notNamed = "{\"pick\":\"\(L.notNamedOption)\"}"
    check(L.pick(kind: 0, symptomJSON: crash, last: nil) == .symptom(.crashes), "pick parses")
    check(L.pick(kind: 1, symptomJSON: notNamed, last: .slow) == .sameAgain && L.pick(kind: 1, symptomJSON: #"{"pick":"It's slow or stutters"}"#, last: .slow) == .sameAgain, "same with earlier")
    check(L.pick(kind: 1, symptomJSON: crash, last: .slow) == .symptom(.crashes), "still happening, naming another problem, is that problem")
    check(L.pick(kind: 1, symptomJSON: crash, last: nil) == .symptom(.crashes) && L.pick(kind: 1, symptomJSON: notNamed, last: nil) == .none, "same without earlier")
    check(L.pick(kind: 2, symptomJSON: nil, last: .slow) == .none && L.pick(kind: 3, symptomJSON: nil, last: nil) == .none, "question and chat pick none")
    check(L.pick(kind: 0, symptomJSON: "garbled {", last: nil) == .none && L.pick(kind: nil, symptomJSON: nil, last: .slow) == .none, "unreadable picks none")

    func step(_ id: String, _ a: FixStep.Action, inEffect: Bool = false) -> FixStep {
        FixStep(id: id, title: "T-\(id)", detail: "d", action: a, button: "b", inEffect: inEffect)
    }
    let steps = [step("laa", .settings([SettingChange(key: "fullMemory32", value: "1")])),
                 step("usedx9", .settings([SettingChange(key: "useDX9", value: "1")])),
                 step("note", .note),
                 step("engine-dxvk", .settings([SettingChange(key: "engine", value: "dxvk")])),
                 step("eff", .settings([SettingChange(key: "x", value: "1")]), inEffect: true)]
    check(L.nextFixes(steps, shownIDs: ["laa"], appliedKeys: ["useDX9"]).map(\.id) == ["engine-dxvk"], "nextFixes skips applied and shown")
    check(L.nextFixes(steps, shownIDs: [], appliedKeys: []).map(\.id) == ["laa", "usedx9"], "nextFixes limit and per-game")
    check(L.nextFixes([step("i", .install(component: "c", then: [SettingChange(key: "k", value: "1")]))], shownIDs: [], appliedKeys: ["k"]).isEmpty, "install then keys")

    let doc = KnowledgeDoc(id: "d", title: "About fast sync", tags: [], body: "Body text")
    check(L.note(pick: .none, symptom: nil, cards: [], advice: [], findings: [], changed: [], exhausted: false, help: nil) == nil, "note none nil")
    let h = L.note(pick: .none, symptom: nil, cards: [], advice: [], findings: [], changed: [], exhausted: false, help: doc)
    check(h?.contains("About fast sync") == true && h?.contains("showing buttons") == false, "note help")
    let n = L.note(pick: .symptom(.crashes), symptom: .crashes, cards: [steps[0]].map { s in
        FixStep(id: s.id, title: "Large address aware (4 GB)", detail: "d", action: s.action, button: "b", inEffect: false) },
        advice: ["Advice line one"], findings: ["Finding one"], changed: ["Use DirectX 9: Off → On"], exhausted: true, help: nil) ?? ""
    check(n.contains("The person seems to describe: It crashes or closes."), "note symptom")
    check(n.contains("Ferry is showing buttons for: Large address aware (4 GB)") && n.contains("\nLarge address aware (4 GB): d"), "note cards, with their details")
    check(n.contains("Advice line one") && n.contains("Finding one"), "note advice and findings")
    check(n.contains("Changed since your last reply: Use DirectX 9: Off → On"), "note changed")
    check(n.contains("Claude, ChatGPT or Gemini key in Settings ▸ AI") && n.contains("log"), "note exhausted")
    check(!n.contains("fullMemory32"), "note has no keys")

    check(L.turnPrompt(note: nil, message: "hi") == "The person says: hi", "turnPrompt nil")
    check(L.turnPrompt(note: "N", message: "hi") == "The person says: hi\n\n(Ferry's note, not shown to the person:\nN)", "turnPrompt: message, then the note")
    check(L.settingChanges(before: ["VSync": "on", "A": "1"], after: ["VSync": "off", "A": "1", "New": "x"]) == ["VSync: on → off"], "settingChanges")
    check(!L.needsRestart(used: 3096, contextSize: 4096) && L.needsRestart(used: 3097, contextSize: 4096), "restart threshold")

    let turns = (0..<30).map { AppleTurnRecord(person: "Person message number \($0) " + String(repeating: "x", count: 150), reply: "Reply \($0) " + String(repeating: "y", count: 150), shown: ["Fix \($0)"], applied: ["Applied \($0)"]) }
    let s = L.summary(turns, symptoms: ["It crashes or closes"])
    check(s.count <= 1200, "summary capped")
    check(s.contains("It crashes or closes") && s.contains("Applied 29"), "summary mentions")
    check(s.contains("Reply 29") && (s.split(separator: "\n").last ?? "").contains("Reply 29"), "summary ends with last exchange")

    check(L.isQuestion("what does fast sync do") && !L.isQuestion("thanks!") && L.isQuestion("is it safe?"), "isQuestion")

    check(s.contains("Applied: Applied 29; Applied 28"), "summary applied newest first")
    let long = L.summary((0..<20).map { AppleTurnRecord(person: "p", reply: "r", shown: [], applied: ["Applied \($0) " + String(repeating: "z", count: 40)]) }, symptoms: [])
    check(long.contains("Applied 19 ") && !long.contains("Applied 0 "), "summary clips the oldest applied")

    runAppleFixWalkTests()
}

private func runAppleFixWalkTests() {
    typealias L = AppleChatLogic
    let allComponents: Set<String> = ["dxmt", "legacyDirectX", "webView2", "dgVoodoo"]
    func context(_ engine: EngineID, _ graphics: GraphicsAPI, _ arch: PEArch, installed: Bool, edit: (inout SettingContext) -> Void) -> FixContext {
        var s = SettingContext.test(engine: engine, graphics: graphics)
        s.arch = arch
        s.dxmtInstalled = installed; s.legacyDirectXInstalled = installed; s.webView2Installed = installed; s.dgVoodooInstalled = installed
        edit(&s)
        return FixContext(setting: s, fallbackOrder: [.mach9, .dxvk, .wined3d, .d3dmetal], lowPowerMode: true, rovSeen: false,
                          learnedTessellation: nil, usesUpstreamDXMT: false, componentInstalled: installed ? allComponents : [])
    }
    let variants: [(name: String, installed: Bool, edit: (inout SettingContext) -> Void)] = [
        ("defaults", false, { _ in }),
        ("installed", true, { _ in }),
        ("dx9 on", true, { $0.settings.useDX9 = true; $0.settings.captureFullscreen = true; $0.settings.cncDdraw = true; $0.settings.dxvkD3D9 = true }),
        ("dx9 on, nothing installed", false, { $0.settings.useDX9 = true; $0.settings.fastSync = true }),
        ("shared", true, { $0.sharedEnvironmentOwner = "Other"; $0.settings.captureFullscreen = true; $0.settings.useDX9 = true }),
        ("mach9 wined3d", true, { $0.settings.mach9Direct3D = "wined3d" }),
    ]
    let camelKeys = SettingsCatalog.all.map(\.key).filter { $0 != $0.lowercased() }
    func showsKey(_ text: String) -> String? {
        camelKeys.first { k in text.range(of: "(?<![A-Za-z0-9])\(k)(?![A-Za-z0-9])", options: .regularExpression) != nil }
    }
    var refused: Set<String> = []
    var offered: Set<String> = []
    for engine in EngineID.allCases where engine != .auto {
        for graphics in [GraphicsAPI.dx9, .dx10, .dx11, .dx12, .unknown] {
            for arch in [PEArch.x86, .x64] {
                for v in variants {
                    let c = context(engine, graphics, arch, installed: v.installed, edit: v.edit)
                    for symptom in Symptom.allCases {
                        for step in L.forAssistant(TroubleshootFixes.steps(for: symptom, c)) {
                            if let k = showsKey(step.title + " " + step.detail) { check(false, "fix text shows the key \(k): \(symptom.rawValue)/\(step.id)") }
                            if let why = L.refusal(step, c.setting) {
                                refused.insert("\(step.id) (\(v.name)): \(why)")
                            } else if step.action != .note {
                                offered.insert(step.id)
                            }
                        }
                    }
                }
            }
        }
    }
    check(refused == ["exclusive (shared): Set in Other's settings, whose Windows environment this uses.",
                      "dxvkmem (dx9 on): Not a setting for this game."],
          "walk: refused only \(refused.sorted())")
    check(offered.isSuperset(of: ["rov", "nvidia", "dxmt", "laa", "usedx9", "tess", "lang", "webview2", "dmusic", "dplay", "dgvoodoo", "fps", "exclusive"]),
          "walk: offered \(offered.sorted())")

    var d3d = context(.d3dmetal, .dx12, .x64, installed: true) { _ in }
    let rov = TroubleshootFixes.steps(for: .blackScreen, d3d).first { $0.id == "rov" }
    check(rov.map { L.refusal($0, d3d.setting) == nil } == true && rov?.inEffect == false && rov?.button == "Turn On", "rov offered with NVIDIA off")
    d3d.setting.settings.hideROV = true
    check(TroubleshootFixes.steps(for: .blackScreen, d3d).first { $0.id == "rov" }?.inEffect == true, "rov in effect with Hide ROV on")
    let oldROV = FixStep(id: "rov", title: "", detail: "", action: .settings([SettingChange(key: "hideROV", value: "on")]), button: "", inEffect: false)
    var nvidiaOn = GameSettings(); nvidiaOn.reportNVIDIA = true
    check(rov.map { L.nextFixes([$0], shownIDs: [], appliedKeys: ["reportNVIDIA"], settings: nvidiaOn).count } == 1, "rov offered after NVIDIA applied")
    check(rov.map { L.nextFixes([$0], shownIDs: [], appliedKeys: ["reportNVIDIA"], settings: GameSettings()).isEmpty } == true, "rov hidden when NVIDIA applied, then turned off")
    check(showsKey("Turn on fullMemory32.") == "fullMemory32" && showsKey("Old 3D game fix (dgVoodoo2)") == nil, "key check finds keys")
    check(L.refusal(oldROV, context(.d3dmetal, .dx12, .x64, installed: true) { _ in }.setting) == "Needs Report graphics card as NVIDIA on.", "rov alone refused")
    let dx9On = context(.mach9, .dx11, .x64, installed: false) { $0.settings.useDX9 = true }
    let dxmt = TroubleshootFixes.steps(for: .crashes, dx9On).first { $0.id == "dxmt" }
    check(dxmt.map { L.refusal($0, dx9On.setting) == nil } == true && dxmt?.afterInstall == "Try It", "dxmt offered with DirectX 9 on")
    let oldDXMT = FixStep(id: "dxmt", title: "", detail: "", action: .install(component: "dxmt", then: [SettingChange(key: "engine", value: "dxvk"),
        SettingChange(key: "dxmtUpstream", value: "on"), SettingChange(key: "useDX9", value: "off")]), button: "", inEffect: false)
    check(L.refusal(oldDXMT, dx9On.setting) == "Turn off Use DirectX 9 first.", "dxmt in the old order refused")

    func applied(_ changes: [SettingChange], _ start: GameSettings) -> [String] {
        var s = start
        TroubleshootFixes.apply(changes, to: &s)
        return SettingsCatalog.all.map { $0.get(s).text }
    }
    var start = GameSettings(); start.useDX9 = true
    check(applied([SettingChange(key: "reportNVIDIA", value: "on"), SettingChange(key: "hideROV", value: "on")], start)
          == applied([SettingChange(key: "hideROV", value: "on")], start), "rov: Troubleshoot ends the same")
    if case .install(_, let then)? = dxmt?.action, case .install(_, let old) = oldDXMT.action {
        check(applied(then, start) == applied(old, start), "dxmt: Troubleshoot ends the same")
    } else { check(false, "dxmt install step") }

    let launcher = context(.mach9, .dx11, .x64, installed: false) { _ in }
    let wv = L.forAssistant(TroubleshootFixes.steps(for: .blankLauncher, launcher)).first { $0.id == "webview2" }
    check(wv?.action == .install(component: "webView2", then: [SettingChange(key: "webView2", value: "on")]) && wv?.afterInstall == "Turn On", "webview2 then turns it on")
    check(wv.map { !$0.detail.contains("215") && !$0.detail.contains("afterwards") && $0.detail.contains("Microsoft's WebView2") } == true, "webview2 detail leaves the download out")
    let tsWV = TroubleshootFixes.steps(for: .blankLauncher, launcher).first { $0.id == "webview2" }
    check(tsWV?.action == .install(component: "webView2", then: []) && tsWV?.detail.contains("215 MB") == true, "Troubleshoot's webview2 unchanged")
    check(L.forAssistant(TroubleshootFixes.steps(for: .crashes, launcher)) == TroubleshootFixes.steps(for: .crashes, launcher), "forAssistant leaves the rest")
}
