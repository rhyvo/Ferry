import CryptoKit
import Foundation

enum AssistantEdits {
    struct Refusal: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static let offWhileGreyed: Set<String> = ["mullionRosetta", "dxvkD3D9", "dgVoodoo", "dxmtUpstream",
                                              "nativeDirectMusic", "nativeDirectPlay"]

    static func blocked(key: String, needs: String?, from old: SettingValue, to new: SettingValue) -> String? {
        guard let needs else { return nil }
        if offWhileGreyed.contains(key), old == .bool(true), new == .bool(false) { return nil }
        return needs
    }

    static func value(_ text: String, for entry: SettingEntry, title: String, like current: SettingValue) throws -> SettingValue {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.choices.isEmpty {
            guard let v = SettingValue(text: t, like: current) else {
                if case .bool = current { throw Refusal("\(title) is on or off.") }
                throw Refusal("\(title) takes a whole number.")
            }
            return v
        }
        let lower = t.lowercased()
        if let c = entry.choices.first(where: { $0.value.text.lowercased() == lower })
            ?? entry.choices.first(where: { $0.label.lowercased() == lower }) { return c.value }
        if let v = SettingValue(text: t, like: current), entry.choices.contains(where: { $0.value == v }) { return v }
        let listed = entry.choices.map { c -> String in
            let v = c.value.text.isEmpty ? "\"\"" : c.value.text
            return c.label == c.value.text ? v : "\(v) (\(c.label))"
        }
        throw Refusal("“\(t)” isn't a value for \(title). Its values: \(listed.joined(separator: ", ")).")
    }

    static func label(_ text: String, choices: [(value: SettingValue, label: String)]) -> String {
        if let c = choices.first(where: { $0.value.text == text }) { return c.label }
        switch text {
        case "on": return "On"
        case "off": return "Off"
        case "": return "(none)"
        default: return text
        }
    }

    enum Held: Equatable { case changedSince, unknownSetting }

    static func revertSettings(_ changes: [AssistantChange], in settings: inout GameSettings) -> Held? {
        var next = settings
        for c in changes {
            switch c.what {
            case .setting(let key, let old, let new):
                guard let e = SettingsCatalog.entry(key), let v = SettingValue(text: old, like: e.get(settings)) else { return .unknownSetting }
                guard e.get(settings).text == new else { return .changedSince }
                e.set(&next, v)
            case .environment(let old, let new):
                guard settings.extraEnv == new else { return .changedSince }
                next.extraEnv = old
            case .arguments(let old, let new):
                guard settings.arguments == new else { return .changedSince }
                next.arguments = old
            case .configFile: return nil
            }
        }
        settings = next
        return nil
    }

    static func changedKeys(from old: GameSettings, to new: GameSettings) -> [String] {
        SettingsCatalog.all.filter { $0.get(old) != $0.get(new) }.map(\.key)
    }

    static func merged(live: Game, original: Game, edited: Game) -> Game {
        var out = edited
        func fields(_ g: Game) -> [String: Any]? {
            (try? JSONEncoder().encode(g)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        if let l = fields(live), let o = fields(original), let e = fields(edited) {
            var m = l
            for key in Set(o.keys).union(e.keys) where key != "settings" {
                if (o[key] as? NSObject) != (e[key] as? NSObject) { m[key] = e[key] }
            }
            if let data = try? JSONSerialization.data(withJSONObject: m), let g = try? JSONDecoder().decode(Game.self, from: data) { out = g }
        }
        var settings = live.settings
        for key in changedKeys(from: original.settings, to: edited.settings) {
            guard let e = SettingsCatalog.entry(key) else { continue }
            e.set(&settings, e.get(edited.settings))
        }
        out.settings = settings
        return out
    }

    struct TextFile {
        enum Form: Equatable { case utf8(bom: Bool), utf16LE, utf16BE, windowsLatin }
        let text: String
        let form: Form

        init?(data: Data) {
            let bytes = [UInt8](data.prefix(3))
            let decoded: (String?, Form)
            if bytes.starts(with: [0xFF, 0xFE]) {
                decoded = (String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian), .utf16LE)
            } else if bytes.starts(with: [0xFE, 0xFF]) {
                decoded = (String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian), .utf16BE)
            } else if data.contains(0) {
                return nil
            } else if bytes == [0xEF, 0xBB, 0xBF] {
                decoded = (String(data: Data(data.dropFirst(3)), encoding: .utf8), .utf8(bom: true))
            } else if let s = String(data: data, encoding: .utf8) {
                decoded = (s, .utf8(bom: false))
            } else {
                decoded = (String(data: data, encoding: .windowsCP1252), .windowsLatin)
            }
            guard let text = decoded.0 else { return nil }
            self.text = text
            self.form = decoded.1
        }

        func data(_ text: String) -> Data? {
            switch form {
            case .utf8(let bom): return text.data(using: .utf8).map { (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + $0 }
            case .utf16LE: return text.data(using: .utf16LittleEndian).map { Data([0xFF, 0xFE]) + $0 }
            case .utf16BE: return text.data(using: .utf16BigEndian).map { Data([0xFE, 0xFF]) + $0 }
            case .windowsLatin: return text.data(using: .windowsCP1252, allowLossyConversion: false)
            }
        }
    }

    static func matchingLineEndings(_ s: String, of original: String) -> String {
        guard original.contains("\r\n") else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
    }

    static func editedText(_ text: String, content: String?, find: String?, replace: String?, hidden: Bool) throws -> String {
        let note = "Parts of this file are hidden from you (the Mac username shown as user, folders as ~ or .)"
        if let content {
            guard !hidden else { throw Refusal(note + ", so Ferry can't take its whole new content: that would write the hidden versions into it. Use find and replace on the text to change, leaving those parts out.") }
            return matchingLineEndings(content, of: text)
        }
        do { return try replacingOnce(in: text, find: find ?? "", with: replace ?? "") } catch let r as Refusal where hidden {
            throw Refusal(r.message + " " + note + "; choose text without them.")
        }
    }

    static func replacingOnce(in text: String, find: String, with replacement: String) throws -> String {
        guard !find.isEmpty else { throw Refusal("Say what text to find (find).") }
        func lf(_ s: String) -> String { s.replacingOccurrences(of: "\r\n", with: "\n") }
        let t = lf(text), f = lf(find)
        switch (t as NSString).components(separatedBy: f).count - 1 {
        case 0: throw Refusal("That text isn't in the file. Read the file again and copy the text to change exactly.")
        case 1: return matchingLineEndings((t as NSString).replacingOccurrences(of: f, with: lf(replacement)), of: text)
        case let n: throw Refusal("That text is in the file \(n) times. Give more of the text around it, so it matches once.")
        }
    }

    static func refusedVariables(_ names: [String]) -> String? {
        let dyld = names.filter { $0.uppercased().hasPrefix("DYLD_") }
        guard !dyld.isEmpty else { return nil }
        return "Ferry doesn't let the assistant set \(dyld.joined(separator: ", ")): DYLD_ variables make the Mac load other code into Wine. The person can add them in the game's settings (Compatibility) if they need to."
    }

    static let settingsExtensions: Set<String> = ["ini", "cfg", "conf", "config", "xml", "json", "txt", "yaml", "yml",
                                                  "toml", "properties", "prefs", "settings", "lua"]

    static func treatedAsSave(_ paths: [String]) -> Bool {
        paths.contains(where: AssistantText.isSaveFile)
            || paths.contains { !settingsExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func mayRestore(current: Data?, written hash: String?) -> Bool {
        guard let hash else { return true }
        return current.map(sha256) == hash
    }

    static func backupName(_ fileName: String, date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: date) + "-" + fileName
    }

    static func unifiedDiff(old: String, new: String, name: String, context: Int = 3) -> String {
        func lines(_ s: String) -> [String] { s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") }
        let a = lines(old), b = lines(new)
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }

        var ops: [(mark: Character, line: String)] = a[..<start].map { (" ", $0) }
        let midA = Array(a[start..<endA]), midB = Array(b[start..<endB])
        let n = midA.count, m = midB.count
        if n * m <= 2_000_000 {
            var lcs = [Int32](repeating: 0, count: (n + 1) * (m + 1))
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i * (m + 1) + j] = midA[i] == midB[j] ? lcs[(i + 1) * (m + 1) + j + 1] + 1
                        : max(lcs[(i + 1) * (m + 1) + j], lcs[i * (m + 1) + j + 1])
                }
            }
            var i = 0, j = 0
            while i < n || j < m {
                if i < n, j < m, midA[i] == midB[j] { ops.append((" ", midA[i])); i += 1; j += 1 }
                else if j == m || (i < n && lcs[(i + 1) * (m + 1) + j] >= lcs[i * (m + 1) + j + 1]) { ops.append(("-", midA[i])); i += 1 }
                else { ops.append(("+", midB[j])); j += 1 }
            }
        } else {
            ops += midA.map { ("-", $0) } + midB.map { ("+", $0) }
        }
        ops += a[endA...].map { (" ", $0) }

        var ranges: [ClosedRange<Int>] = []
        for i in ops.indices where ops[i].mark != " " {
            let lo = max(0, i - context), hi = min(ops.count - 1, i + context)
            if let last = ranges.last, lo <= last.upperBound + 1 { ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, hi) }
            else { ranges.append(lo...hi) }
        }
        guard !ranges.isEmpty else { return "" }
        var oldLine: [Int] = [], newLine: [Int] = [], o = 1, nw = 1
        for op in ops {
            oldLine.append(o); newLine.append(nw)
            if op.mark != "+" { o += 1 }
            if op.mark != "-" { nw += 1 }
        }
        var out = ["--- a/\(name)", "+++ b/\(name)"]
        for r in ranges {
            let slice = ops[r]
            let oc = slice.filter { $0.mark != "+" }.count, nc = slice.filter { $0.mark != "-" }.count
            out.append("@@ -\(oc == 0 ? oldLine[r.lowerBound] - 1 : oldLine[r.lowerBound]),\(oc) +\(nc == 0 ? newLine[r.lowerBound] - 1 : newLine[r.lowerBound]),\(nc) @@")
            out += slice.map { "\($0.mark)\($0.line)" }
        }
        return out.joined(separator: "\n")
    }
}
