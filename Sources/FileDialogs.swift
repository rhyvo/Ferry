import Foundation

extension AppModel {
    private static let fileDialogClasses = ["{DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}", "{C0B4E2F3-BA21-4773-8DBA-335EC946EB8B}"]
    private static let fileDialogServer = "C:\\\\windows\\\\system32\\\\ferry-filedlg.dll"

    func applyFileDialogs(_ p: PreparedGame) async {
        let windows = p.prefix.appendingPathComponent("drive_c/windows")
        for (arch, folder) in [("x64", "system32"), ("x86", "syswow64")] {
            guard let helper = Bundle.main.url(forResource: "ferry-filedlg-" + arch, withExtension: "dll") else { return }
            let dir = windows.appendingPathComponent(folder, isDirectory: true)
            guard fm.isDirectory(dir) else { continue }
            let target = dir.appendingPathComponent("ferry-filedlg.dll")
            if fm.contentsEqual(atPath: helper.path, andPath: target.path) { continue }
            fm.removeIfPresent(target)
            try? fm.copyItem(at: helper, to: target)
        }
        let registry = (try? Data(contentsOf: p.prefix.appendingPathComponent("system.reg"))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let wanted = Self.fileDialogClasses.count * 2
        if registry.components(separatedBy: "@=\"\(Self.fileDialogServer)\"").count - 1 >= wanted { return }
        let lines = ["", "Wow6432Node\\"].flatMap { view in
            Self.fileDialogClasses.flatMap { id in [
                "[HKEY_LOCAL_MACHINE\\Software\\Classes\\\(view)CLSID\\\(id)\\InprocServer32]",
                "@=\"\(Self.fileDialogServer)\"",
                "\"ThreadingModel\"=\"Apartment\"",
                "",
            ] }
        }
        await applyRegistry(lines, name: "ferry-filedlg", wine: p.wine, env: p.env, prefix: p.prefix, log: logURL(p.game.id, "setup"))
    }
}
