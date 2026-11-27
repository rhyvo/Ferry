import Foundation

func runAssistantEditsTests() {
    let tess = SettingsCatalog.entry("maxTessellation")!
    func value(_ t: String, _ e: SettingEntry, like: SettingValue) -> SettingValue? {
        try? AssistantEdits.value(t, for: e, title: e.title, like: like)
    }
    check(value(" 1 ", tess, like: .int(0)) == nil, "1 isn't a tessellation level (DXMT ignores a cap below 4)")
    check(value(" 16 ", tess, like: .int(0)) == .int(16), "a choice's value, trimmed")
    check(value("automatic", tess, like: .int(16)) == .int(0), "a choice's label, any case")
    do {
        _ = try AssistantEdits.value("5", for: tess, title: "Tessellation detail", like: .int(0))
        check(false, "5 should be refused")
    } catch {
        let m = error.localizedDescription
        check(m.contains("“5” isn't a value for Tessellation detail") && m.contains("0 (Automatic)") && m.contains("16"), "refusal lists the values: \(m)")
    }
    let engine = SettingsCatalog.entry("engine")!
    check(value("mach9", engine, like: .string("auto")) == .string("mach9"), "an engine's raw value")
    check(value("Banana", engine, like: .string("auto")) == nil, "an unknown engine is refused")
    let rosetta = SettingsCatalog.entry("mullionRosetta")!
    check(value("Rosetta 2", rosetta, like: .bool(false)) == .bool(true), "a two-way picker by label")
    check(value("on", rosetta, like: .bool(false)) == .bool(true), "a two-way picker by on/off")
    let hud = SettingsCatalog.entry("metalHUD")!
    check(value("ON", hud, like: .bool(false)) == .bool(true), "a toggle takes on")
    check(value("maybe", hud, like: .bool(false)) == nil, "a toggle refuses other words")
    let backend = SettingsCatalog.entry("metalSharpBackend")!
    check(value("", backend, like: .string("dxvk")) == .string(""), "the empty choice is a value")
    check(value("Automatic (Mullion)", backend, like: .string("dxvk")) == .string(""), "the empty choice by its label")

    check(AssistantEdits.blocked(key: "dgVoodoo", needs: "Install it", from: .bool(true), to: .bool(false)) == nil, "greyed dgVoodoo can be turned off")
    check(AssistantEdits.blocked(key: "dgVoodoo", needs: "Install it", from: .bool(false), to: .bool(true)) == "Install it", "greyed dgVoodoo can't be turned on")
    check(AssistantEdits.blocked(key: "maxTessellation", needs: "Turn off", from: .int(16), to: .int(0)) == "Turn off", "greyed tessellation can't change")
    check(AssistantEdits.blocked(key: "retina", needs: "Set in X", from: .bool(true), to: .bool(false)) == "Set in X", "only listed settings turn off while greyed")
    check(AssistantEdits.blocked(key: "retina", needs: nil, from: .bool(true), to: .bool(false)) == nil, "not greyed: proceeds")

    check(AssistantEdits.label("0", choices: tess.choices) == "Automatic", "labels come from choices")
    check(AssistantEdits.label("16", choices: tess.choices) == "16", "a plain level reads as itself")
    check(AssistantEdits.label("off", choices: []) == "Off", "toggles read On/Off")

    check(AssistantEdits.refusedVariables(["DXVK_HUD", "dyld_insert_libraries", "DYLD_LIBRARY_PATH"])?.contains("dyld_insert_libraries, DYLD_LIBRARY_PATH") == true,
          "DYLD_ variables are refused, any case")
    check(AssistantEdits.refusedVariables(["DXVK_HUD", "MY_DYLD_X"]) == nil, "other variables are fine")

    let ini = "[Engine]\r\nMaxTess=64\r\nVSync=1\r\n"
    check((try? AssistantEdits.replacingOnce(in: ini, find: "MaxTess=64", with: "MaxTess=16")) == "[Engine]\r\nMaxTess=16\r\nVSync=1\r\n", "replaces once")
    check((try? AssistantEdits.replacingOnce(in: ini, find: "MaxTess=64\nVSync=1", with: "MaxTess=8\nVSync=0")) == "[Engine]\r\nMaxTess=8\r\nVSync=0\r\n", "\\n matches \\r\\n files and is written as \\r\\n")
    let crlf = try? AssistantEdits.replacingOnce(in: ini, find: "\nVSync=1", with: "\nVSync=0")
    check(crlf == "[Engine]\r\nMaxTess=64\r\nVSync=0\r\n" && !(crlf ?? "").contains("\r\r"), "a find starting with \\n keeps a CRLF file CRLF, no \\r\\r\\n")
    check((try? AssistantEdits.replacingOnce(in: "a=1\nb=2\n", find: "\nb=2", with: "\nb=3")) == "a=1\nb=3\n", "LF files stay LF")
    check((try? AssistantEdits.replacingOnce(in: ini, find: "Nope", with: "x")) == nil, "missing text refused")
    check((try? AssistantEdits.replacingOnce(in: "a=1\na=1\n", find: "a=1", with: "a=2")) == nil, "text found twice refused")
    check((try? AssistantEdits.replacingOnce(in: ini, find: "", with: "x")) == nil, "empty find refused")
    check(AssistantEdits.matchingLineEndings("a\nb", of: "x\r\ny") == "a\r\nb", "full content takes the file's line endings")
    check(AssistantEdits.matchingLineEndings("a\nb", of: "x\ny") == "a\nb", "\\n files stay \\n")
    check((try? AssistantEdits.editedText("Name=robin\nRes=720\n", content: "Name=user\nRes=1080\n", find: nil, replace: nil, hidden: true)) == nil,
          "whole content refused when parts were hidden")
    check((try? AssistantEdits.editedText("Name=robin\nRes=720\n", content: nil, find: "Res=720", replace: "Res=1080", hidden: true)) == "Name=robin\nRes=1080\n",
          "find and replace keeps the hidden parts")
    do { _ = try AssistantEdits.editedText("Name=robin\n", content: nil, find: "Name=user", replace: "Name=x", hidden: true); check(false, "hidden text can't be found") }
    catch { check(error.localizedDescription.contains("hidden from you"), "not-found says why: \(error.localizedDescription)") }
    check((try? AssistantEdits.editedText("a=1\r\n", content: "a=2\n", find: nil, replace: nil, hidden: false)) == "a=2\r\n", "whole content when nothing was hidden")

    for bytes in [[0xEF, 0xBB, 0xBF, 0x61, 0x3D, 0x31], [0xFF, 0xFE, 0x61, 0x00, 0x3D, 0x00], [0xFE, 0xFF, 0x00, 0x61], [0x61, 0xE9], [0x61, 0x3D]] as [[UInt8]] {
        let data = Data(bytes)
        guard let f = AssistantEdits.TextFile(data: data) else { check(false, "decodes \(bytes)"); continue }
        check(f.data(f.text) == data, "round-trips \(bytes)")
    }
    check(AssistantEdits.TextFile(data: Data([0x61, 0x00, 0x62])) == nil, "binary isn't text")
    check(AssistantEdits.TextFile(data: Data([0x61, 0xE9]))?.form == .windowsLatin, "non-UTF-8 is Windows Latin")
    check(AssistantEdits.TextFile(data: Data([0x61, 0xE9]))?.data("✓") == nil, "characters Windows Latin can't hold refused")

    let diff = AssistantEdits.unifiedDiff(old: "a\nb\nc\nd\ne\nf\ng\nh\n", new: "a\nb\nc\nD\ne\nf\ng\nh\n", name: "x.ini")
    check(diff == "--- a/x.ini\n+++ b/x.ini\n@@ -1,7 +1,7 @@\n a\n b\n c\n-d\n+D\n e\n f\n g", "unified diff with 3 lines of context:\n\(diff)")
    check(AssistantEdits.unifiedDiff(old: "a\r\nb", new: "a\nb", name: "x") == "", "line endings alone aren't a change")
    let added = AssistantEdits.unifiedDiff(old: "a\nb", new: "a\nb\nc", name: "x")
    check(added.contains("@@ -1,2 +1,3 @@") && added.hasSuffix("+c"), "an added line:\n\(added)")

    check(!AssistantEdits.treatedAsSave(["BmGame/Config/BmEngine.ini", "AppData/Local/WB/settings.ini"]), "settings files don't")
    check(AssistantEdits.treatedAsSave(["SaveData/options.ini"]), "a save folder does")
    check(AssistantEdits.treatedAsSave(["config/player"]), "no extension does")
    check(AssistantEdits.treatedAsSave(["data/profile.dat"]), "an unknown extension does")

    let written = Data("MaxTess=16".utf8)
    let hash = AssistantEdits.sha256(written)
    check(hash.count == 64, "hex SHA-256")
    check(AssistantEdits.mayRestore(current: written, written: hash), "unchanged since: restore")
    check(!AssistantEdits.mayRestore(current: Data("MaxTess=8".utf8), written: hash), "changed since: refuse")
    check(!AssistantEdits.mayRestore(current: nil, written: hash), "gone since: refuse")
    check(AssistantEdits.mayRestore(current: nil, written: nil), "no hash recorded: restore")
    check(AssistantEdits.backupName("BmEngine.ini", date: Date()).hasSuffix("-BmEngine.ini"), "backup name ends with the file's name")

    let old = #"[{"id":"\#(UUID().uuidString)","game":"\#(UUID().uuidString)","chat":"\#(UUID().uuidString)","date":"2026-11-25T10:00:00Z","reason":"r","what":{"configFile":{"path":"/a","backup":"/b"}}}]"#
    let url = tempDir().appendingPathComponent("changes.json")
    try? Data(old.utf8).write(to: url)
    let log = AssistantChangeLog(url: url)
    if case .configFile(let p, let b, let h)? = log.changes.first?.what {
        check(p == "/a" && b == "/b" && h == nil, "old config change decodes without a hash")
    } else { check(false, "old change log decodes") }
    check(log.changes.first?.group == nil, "old changes have no group")

    var live = GameSettings()
    live.dgVoodoo = true
    let cnc = SettingsCatalog.entry("cncDdraw")!
    let before = live
    var after = live
    cnc.set(&after, .bool(true))
    check(!after.dgVoodoo, "cnc-ddraw turns dgVoodoo2 off")
    let moved = AssistantEdits.changedKeys(from: before, to: after)
    check(Set(moved) == ["cncDdraw", "dgVoodoo"], "both settings moved: \(moved)")
    var grouped = AssistantChangeLog(url: tempDir().appendingPathComponent("changes.json"))
    let chat = UUID(), group = UUID()
    do {
        try grouped.record(.init(id: UUID(), game: UUID(), chat: chat, date: Date(), reason: "earlier", what: .setting(key: "metalHUD", old: "off", new: "on")))
        try grouped.record(.init(id: UUID(), game: UUID(), chat: chat, date: Date(), reason: "r", what: .setting(key: "dgVoodoo", old: "on", new: "off"), group: group))
        try grouped.record(.init(id: UUID(), game: UUID(), chat: chat, date: Date(), reason: "r", what: .setting(key: "cncDdraw", old: "off", new: "on"), group: group))
    } catch { check(false, "record threw \(error)") }
    let last = grouped.undoPlan(chat: chat).first.map(grouped.together) ?? []
    check(last.count == 2, "undo last takes the whole group")
    var undone = after
    for c in last {
        if case .setting(let key, let old, _) = c.what, let e = SettingsCatalog.entry(key) { e.set(&undone, SettingValue(text: old, like: e.get(undone))!) }
    }
    check(undone.dgVoodoo && !undone.cncDdraw, "undo last puts both back")
    check(grouped.rows.count == 2 && grouped.rows[0].count == 2, "the group is one row, the earlier change another")
    if case .setting(let key, _, _) = grouped.rows[0][0].what { check(key == "cncDdraw", "the asked setting leads its row") }

    func change(_ key: String, _ old: String, _ new: String, group: UUID? = nil) -> AssistantChange {
        AssistantChange(id: UUID(), game: UUID(), chat: UUID(), date: Date(), reason: "r", what: .setting(key: key, old: old, new: new), group: group)
    }
    let a1 = change("maxTessellation", "0", "16"), b1 = change("maxTessellation", "16", "32")
    var t = GameSettings(); t.maxTessellation = 32
    check(AssistantEdits.revertSettings([a1], in: &t) == .changedSince && t.maxTessellation == 32, "undoing the older change first is refused")
    check(AssistantEdits.revertSettings([b1], in: &t) == nil && t.maxTessellation == 16, "the newer change undoes")
    check(AssistantEdits.revertSettings([a1], in: &t) == nil && t.maxTessellation == 0, "then the older one")
    t.maxTessellation = 32
    for c in [b1, a1] { _ = AssistantEdits.revertSettings([c], in: &t) }
    check(t.maxTessellation == 0, "newest first goes all the way back")
    var person = GameSettings(); person.maxTessellation = 48
    check(AssistantEdits.revertSettings([a1], in: &person) == .changedSince && person.maxTessellation == 48, "the person's later change is kept")
    var envs = GameSettings(); envs.extraEnv = "A=2"
    let env = AssistantChange(id: UUID(), game: UUID(), chat: UUID(), date: Date(), reason: "r", what: .environment(old: "", new: "A=1"))
    check(AssistantEdits.revertSettings([env], in: &envs) == .changedSince && envs.extraEnv == "A=2", "environment changed since is kept")
    envs.extraEnv = "A=1"
    check(AssistantEdits.revertSettings([env], in: &envs) == nil && envs.extraEnv == "", "environment as set is undone")
    let g1 = UUID(), g2 = UUID()
    let cncGroup = [change("cncDdraw", "off", "on", group: g1), change("dgVoodoo", "on", "off", group: g1)]
    let dgGroup = [change("dgVoodoo", "off", "on", group: g2), change("cncDdraw", "on", "off", group: g2)]
    var pair = GameSettings(); pair.dgVoodoo = true
    check(AssistantEdits.revertSettings(cncGroup, in: &pair) == .changedSince && pair.dgVoodoo && !pair.cncDdraw, "a group with a changed member is left whole")
    check(AssistantEdits.revertSettings(dgGroup, in: &pair) == nil && pair.cncDdraw && !pair.dgVoodoo, "the newer group undoes")
    check(AssistantEdits.revertSettings(cncGroup, in: &pair) == nil && !pair.cncDdraw && pair.dgVoodoo, "then the older group: back to the start")

    let keys = Set(SettingsCatalog.all.map(\.key))
    for child in Mirror(reflecting: GameSettings()).children {
        if let label = child.label { check(keys.contains(label), "\(label) is in the settings catalogue") }
    }

    var opened = Game(name: "Arkham", exePath: "/g/a.exe")
    opened.lastPlayed = Date(timeIntervalSinceReferenceDate: 812_345_678.123456)
    var current = opened
    current.settings.maxTessellation = 16
    var draft = opened
    draft.settings.metalHUD = true
    draft.name = "Arkham City"
    let saved = AssistantEdits.merged(live: current, original: opened, edited: draft)
    check(saved.settings.maxTessellation == 16 && saved.settings.metalHUD, "both the assistant's and the person's settings kept")
    check(saved.name == "Arkham City", "the person's other fields kept")
    var expected = current
    expected.settings.metalHUD = true
    expected.name = "Arkham City"
    check(saved == expected, "nothing else changes (dates included)")
    draft.settings.maxTessellation = 24
    check(AssistantEdits.merged(live: current, original: opened, edited: draft).settings.maxTessellation == 24, "a setting the person changed too: theirs wins")
    draft.settings.hideROV = true
    let rov = AssistantEdits.merged(live: current, original: opened, edited: draft).settings
    check(rov.hideROV && rov.reportNVIDIA, "settings that moved together in the sheet are saved together")
    var cleared = opened
    cleared.lastPlayed = nil
    check(AssistantEdits.merged(live: opened, original: opened, edited: cleared).lastPlayed == nil, "a field the person cleared is cleared")
}
