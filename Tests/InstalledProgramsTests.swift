import Foundation

func runInstalledProgramsTests() {
    if let repo = ProcessInfo.processInfo.environment["FERRY_REPO"],
       let npp = FileManager.default.contents(atPath: repo + "/Tests/Fixtures/Notepad++.lnk") {
        check(InstalledPrograms.lnkTarget(npp) == "C:\\Program Files\\Notepad++\\notepad++.exe", "Notepad++ shortcut target")
    } else {
        check(false, "fixture Notepad++.lnk readable (FERRY_REPO set?)")
    }
    let utf16 = Data([0x4C, 0, 0, 0, 0x23, 0x43, 0x3A, 0x5C, 0, 0]) + Data("C:\\Games\\Foo Bar\\foo.exe".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }) + Data([0, 0])
    check(InstalledPrograms.lnkTarget(utf16) == "C:\\Games\\Foo Bar\\foo.exe", "UTF-16 shortcut target")
    check(InstalledPrograms.lnkTarget(Data([7]) + utf16) == "C:\\Games\\Foo Bar\\foo.exe", "UTF-16 target at an odd offset")
    check(InstalledPrograms.lnkTarget(Data("\0C:\\A\\one.exe\0C:\\B\\two.exe\0".utf8)) == "C:\\A\\one.exe", "first path wins")
    check(InstalledPrograms.lnkTarget(Data("\0Z:\\Users\\x\\game.exe\0".utf8)) == nil, "Z: path is not inside drive_c")
    check(InstalledPrograms.lnkTarget(Data("\0C:\\Docs\\readme.txt\0".utf8)) == nil, "non-.exe target")

    let root = URL(fileURLWithPath: "/x/drive_c")
    check(InstalledPrograms.macURL("C:\\Program Files\\A\\a.exe", driveC: root)?.path == "/x/drive_c/Program Files/A/a.exe", "macURL")
    check(InstalledPrograms.macURL("C:\\..\\..\\etc\\a.exe", driveC: root) == nil, "macURL refuses ..")

    for bad in ["unins000", "Uninstall Foo", "Foo Setup", "FooSetup", "setup_x64", "Foo Updater", "FooUpdater", "CrashReporter",
                "Crash Reporter", "Bug Report", "Foo Website", "Read Me", "readme", "Help", "Install", "foo-helper",
                "crashreporter.exe", "crashpad_handler.exe", "dxsetup.exe", "autoupdate.exe", "vcsetup.exe"] {
        check(InstalledPrograms.isExcluded(bad), "\(bad) excluded")
    }
    for good in ["Notepad++", "Foo", "Bar Game", "Crash Bandicoot", "Sun Instruments", "Helpless", "Reporters Notebook", "Updated Edition", "Doom 3", "doom3.exe"] { check(!InstalledPrograms.isExcluded(good), "\(good) kept") }

    let k = tempDir().appendingPathComponent("tool.exe")
    let stamp: [FileAttributeKey: Any] = [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)]
    try? Data("MZ plain program".utf8).write(to: k)
    try? FileManager.default.setAttributes(stamp, ofItemAtPath: k.path)
    check(!InstalledPrograms.looksLikeInstaller(k), "plain program is not an installer")
    try? Data("MZ Inno Setup ab".utf8).write(to: k)
    try? FileManager.default.setAttributes(stamp, ofItemAtPath: k.path)
    check(!InstalledPrograms.looksLikeInstaller(k), "remembered answer used for an unchanged file")
    try? Data("MZ Inno Setup inside".utf8).write(to: k)
    check(InstalledPrograms.looksLikeInstaller(k), "changed file is read again")

    let c = tempDir()
    let menu = "ProgramData/Microsoft/Windows/Start Menu/Programs/"
    let user = "users/someone/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/"
    make(c, [menu + "Old.lnk", "Program Files/Old/", "Program Files/Old/old.exe", "users/Public/"])
    lnk(c, menu + "Old.lnk", "C:\\Program Files\\Old\\old.exe")
    let before = InstalledPrograms.snapshot(driveC: c)
    check(before.shortcuts == [menu + "Old.lnk"] && before.programFolders == ["Program Files/Old"], "snapshot before")
    make(c, ["Program Files/Foo/", "Program Files/Foo/foo.exe", "Program Files/Foo/unins000.exe",
             "Program Files (x86)/Bar/", "Program Files (x86)/Bar/bar.exe", "setup.exe"])
    lnk(c, menu + "Foo/Foo.lnk", "C:\\Program Files\\Foo\\foo.exe")
    lnk(c, menu + "Foo/Uninstall Foo.lnk", "C:\\Program Files\\Foo\\unins000.exe")
    lnk(c, menu + "Foo/Foo Website.lnk", "C:\\Program Files\\Internet Explorer\\iexplore.exe")
    lnk(c, menu + "Foo/Foo Again.lnk", "C:\\Program Files\\Foo\\foo.exe")
    lnk(c, menu + "Foo/Gone.lnk", "C:\\Program Files\\Foo\\gone.exe")
    lnk(c, menu + "Foo/Setup Again.lnk", "C:\\setup.exe")
    lnk(c, user + "Bar/Bar Game.lnk", "C:\\Program Files (x86)\\Bar\\bar.exe")
    make(c, ["windows/system32/rundll32.exe"])
    lnk(c, menu + "Foo/Foo Audio Configuration.lnk", "C:\\windows\\system32\\rundll32.exe")
    let installer = URL(fileURLWithPath: "/Users/someone/Downloads/FooSetup.exe")
    let after = InstalledPrograms.snapshot(driveC: c)
    let found = InstalledPrograms.candidates(before: before, after: after, driveC: c, installer: installer) { _ in "Should Not Be Used" }
    check(found.map(\.name) == ["Foo", "Bar Game"], "shortcut candidates: \(found.map(\.name))")
    check(found.first?.exe == c.appendingPathComponent("Program Files/Foo/foo.exe"), "candidate points at the program")

    let selfInstall = InstalledPrograms.candidates(before: before, after: after, driveC: c,
                                                   installer: c.appendingPathComponent("Program Files/Foo/foo.exe")) { _ in nil }
    check(selfInstall.map(\.name) == ["Bar Game"], "installer skipped")

    let f = tempDir()
    make(f, ["Program Files/Old/", "Program Files/Old/old.exe"])
    let fBefore = InstalledPrograms.snapshot(driveC: f)
    make(f, ["Program Files (x86)/Baz/", "Program Files (x86)/Baz/baz.exe", "Program Files (x86)/Baz/unins000.exe",
             "Program Files (x86)/Baz/BazUpdater.exe", "Program Files (x86)/Baz/bin/", "Program Files (x86)/Baz/bin/deep.exe",
             "Program Files (x86)/Baz/notes.txt", "Program Files/Qux/", "Program Files/Qux/qux.exe"])
    try? Data("MZ junk Inno Setup junk".utf8).write(to: f.appendingPathComponent("Program Files/Qux/tool.exe"))
    lnk(f, menu + "Baz Website.lnk", "C:\\Program Files\\Internet Explorer\\iexplore.exe")
    let fallback = InstalledPrograms.candidates(before: fBefore, after: InstalledPrograms.snapshot(driveC: f), driveC: f, installer: installer) {
        $0.lastPathComponent == "baz.exe" ? "Baz Deluxe" : nil
    }
    check(fallback.map(\.name) == ["Qux", "Baz Deluxe"], "Program Files fallback: \(fallback.map(\.name))")
    check(fallback.last?.exe == f.appendingPathComponent("Program Files (x86)/Baz/baz.exe"), "fallback points at the program")

    check(InstalledPrograms.candidates(before: fBefore, after: fBefore, driveC: f, installer: installer) { _ in nil }.isEmpty, "no change, no offer")

    let many = tempDir()
    let manyBefore = InstalledPrograms.snapshot(driveC: many)
    for n in 1...6 {
        make(many, ["Program Files/P\(n)/", "Program Files/P\(n)/p\(n).exe"])
        lnk(many, menu + "P\(n).lnk", "C:\\Program Files\\P\(n)\\p\(n).exe")
    }
    let four = InstalledPrograms.candidates(before: manyBefore, after: InstalledPrograms.snapshot(driveC: many), driveC: many, installer: installer) { _ in nil }
    check(four.map(\.name) == ["P1", "P2", "P3", "P4"], "first four: \(four.map(\.name))")
}

private func lnk(_ root: URL, _ path: String, _ target: String) {
    let u = root.appendingPathComponent(path)
    try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? (Data([0x4C, 0, 0, 0, 0x23, 0x43, 0x3A, 0x5C, 0, 0]) + Data(target.utf8) + Data([0, 0])).write(to: u)
}
