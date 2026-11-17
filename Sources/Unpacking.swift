import Foundation

struct ArchiveSet {
    let first: URL
    let parts: [URL]
    let missing: [String]
    let baseName: String

    var isMultiPart: Bool { parts.count > 1 || !missing.isEmpty }

    private enum Style { case single, rarParts, rarOld, split, zipSplit }

    private struct Parsed {
        let base: String
        let ext: String
        let style: Style
        let number: Int
        let width: Int
    }

    static func looksLikeArchive(_ url: URL) -> Bool { parse(url.lastPathComponent) != nil }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let rarPartsPattern = regex(#"^(.+)\.part(\d+)\.rar$"#)
    private static let rarOldPattern = regex(#"^(.+)\.r(\d{2,3})$"#)
    private static let splitPattern = regex(#"^(.+)\.(7z|zip|rar)\.(\d{3,})$"#)
    private static let zipSplitPattern = regex(#"^(.+)\.z(\d{2,})$"#)
    private static let singlePattern = regex(#"^(.+)\.(zip|rar|7z)$"#)

    private static func groups(_ pattern: NSRegularExpression, _ name: String) -> [String]? {
        let whole = NSRange(name.startIndex..., in: name)
        guard let m = pattern.firstMatch(in: name, range: whole) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: name).map { String(name[$0]) } ?? ""
        }
    }

    private static func parse(_ name: String) -> Parsed? {
        if let g = groups(rarPartsPattern, name), let n = Int(g[1]) {
            return Parsed(base: g[0], ext: "rar", style: .rarParts, number: n, width: g[1].count)
        }
        if let g = groups(splitPattern, name), let n = Int(g[2]) {
            return Parsed(base: g[0], ext: g[1].lowercased(), style: .split, number: n, width: g[2].count)
        }
        if let g = groups(rarOldPattern, name), let n = Int(g[1]) {
            return Parsed(base: g[0], ext: "rar", style: .rarOld, number: n, width: g[1].count)
        }
        if let g = groups(zipSplitPattern, name), let n = Int(g[1]) {
            return Parsed(base: g[0], ext: "zip", style: .zipSplit, number: n, width: g[1].count)
        }
        if let g = groups(singlePattern, name) {
            return Parsed(base: g[0], ext: g[1].lowercased(), style: .single, number: 0, width: 0)
        }
        return nil
    }

    private static func padded(_ n: Int, _ width: Int) -> String {
        let digits = String(n)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    static func resolve(_ dropped: URL) -> ArchiveSet? {
        guard let me = parse(dropped.lastPathComponent) else { return nil }
        let dir = dropped.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let base = me.base.lowercased()
        func file(_ name: String) -> URL? {
            names.first { $0.lowercased() == name.lowercased() }.map { dir.appendingPathComponent($0) }
        }
        func siblings(_ style: Style, ext: String? = nil) -> [Int: (url: URL, width: Int)] {
            var found: [Int: (url: URL, width: Int)] = [:]
            for name in names {
                guard let p = parse(name), p.style == style, p.base.lowercased() == base,
                      ext == nil || p.ext == ext else { continue }
                found[p.number] = (dir.appendingPathComponent(name), p.width)
            }
            return found
        }
        func gaps(_ found: [Int: (url: URL, width: Int)], from start: Int) -> [Int] {
            guard let last = found.keys.max(), last >= start else { return [] }
            return (start...last).filter { found[$0] == nil }
        }

        var style = me.style
        if style == .single {
            if me.ext == "rar", file("\(me.base).r00") != nil { style = .rarOld }
            if me.ext == "zip", file("\(me.base).z01") != nil { style = .zipSplit }
        }

        switch style {
        case .single:
            return ArchiveSet(first: dropped, parts: [dropped], missing: [], baseName: me.base)

        case .rarParts, .split:
            let found = style == .rarParts ? siblings(.rarParts) : siblings(.split, ext: me.ext)
            let width = found.values.map(\.width).max() ?? me.width
            func partName(_ n: Int) -> String {
                style == .rarParts ? "\(me.base).part\(padded(n, width)).rar" : "\(me.base).\(me.ext).\(padded(n, width))"
            }
            var missing = gaps(found, from: 1).map(partName)
            if found[1] == nil && !missing.contains(partName(1)) { missing.insert(partName(1), at: 0) }
            let parts = found.keys.sorted().compactMap { found[$0]?.url }
            return ArchiveSet(first: found[1]?.url ?? dropped, parts: parts, missing: missing, baseName: me.base)

        case .rarOld:
            let found = siblings(.rarOld)
            let width = found.values.map(\.width).max() ?? 2
            var missing = gaps(found, from: 0).map { "\(me.base).r\(padded($0, width))" }
            if !found.isEmpty && found[0] == nil { missing.insert("\(me.base).r\(padded(0, width))", at: 0) }
            let main = file("\(me.base).rar")
            if main == nil { missing.insert("\(me.base).rar", at: 0) }
            let parts = (main.map { [$0] } ?? []) + found.keys.sorted().compactMap { found[$0]?.url }
            return ArchiveSet(first: main ?? dropped, parts: parts, missing: missing, baseName: me.base)

        case .zipSplit:
            let found = siblings(.zipSplit)
            let width = found.values.map(\.width).max() ?? 2
            var missing = gaps(found, from: 1).map { "\(me.base).z\(padded($0, width))" }
            if !found.isEmpty && found[1] == nil { missing.insert("\(me.base).z\(padded(1, width))", at: 0) }
            let main = file("\(me.base).zip")
            if main == nil { missing.append("\(me.base).zip") }
            let parts = found.keys.sorted().compactMap { found[$0]?.url } + (main.map { [$0] } ?? [])
            return ArchiveSet(first: main ?? dropped, parts: parts, missing: missing, baseName: me.base)
        }
    }
}

enum Unpacker {
    static func sevenZipTotal(_ listing: String) -> Int {
        var total = 0
        var inFiles = false
        for line in listing.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("----------") { inFiles = true; continue }
            guard inFiles, line.hasPrefix("Size = ") else { continue }
            total += Int(line.dropFirst(7).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return total
    }

    static func percent(in piece: String) -> Int? {
        let text = piece.trimmingCharacters(in: .whitespaces)
        guard let sign = text.firstIndex(of: "%") else { return nil }
        let digits = text[..<sign]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits), (0...100).contains(value) else { return nil }
        return value
    }

    static func problem(from messages: [String], name: String) -> (text: String, tryTar: Bool) {
        let lower = messages.map { $0.lowercased() }
        func line(containing word: String) -> String? {
            lower.firstIndex { $0.contains(word) }.map { messages[$0] }
        }
        if let missing = line(containing: "missing volume") {
            var part = ""
            if let word = missing.range(of: "missing volume", options: .caseInsensitive),
               let colon = missing[word.upperBound...].firstIndex(of: ":") {
                part = missing[missing.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let which = part.isEmpty ? "A part" : (part as NSString).lastPathComponent
            return ("\(which) of this multi-part archive is missing. Put every part in the same folder and drop it again.", false)
        }
        if line(containing: "wrong password") != nil || line(containing: "enter password") != nil
            || line(containing: "encrypted") != nil {
            return ("\(name) is password-protected, and Ferry can't unpack those yet. Unpack it with an app that asks for the password (e.g. The Unarchiver), then drop the game's folder here.", false)
        }
        if line(containing: "no space left") != nil || line(containing: "not enough space") != nil
            || line(containing: "disk full") != nil {
            return ("The disk ran out of space while unpacking \(name). Free up space, or choose a bigger drive in Settings ▸ Defaults ▸ Games from archives.", false)
        }
        if line(containing: "can not open the file as archive") != nil || line(containing: "cannot open the file as archive") != nil
            || line(containing: "unsupported") != nil {
            return ("7-Zip couldn't read \(name).", true)
        }
        let detail = messages.last { $0.lowercased().hasPrefix("error") } ?? messages.last ?? ""
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        return ("\(name) couldn't be unpacked; it may be damaged or incomplete\(suffix).", false)
    }
}

final class UnpackTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Int? = nil
    private var recent: [String] = []

    func take(_ piece: String) {
        let text = piece.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if let value = Unpacker.percent(in: text) {
            latest = max(latest ?? 0, value)
        } else {
            recent.append(text)
            if recent.count > 40 { recent.removeFirst(recent.count - 40) }
        }
    }

    var percent: Int? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recent
    }
}

enum UnpackDestination: String, CaseIterable, Identifiable {
    case games, besideArchive, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games: return "The Games folder in your home folder"
        case .besideArchive: return "Next to the archive"
        case .custom: return "A folder I choose"
        }
    }

    static let defaultsKey = "unpackDestination"
    static let customFolderKey = "unpackCustomFolder"
    static let stagingName = ".Ferry Unpacking.noindex"

    static var current: UnpackDestination {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(UnpackDestination.init(rawValue:)) ?? .games
    }

    static var gamesFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games", isDirectory: true)
    }

    static func folder(for archive: URL) -> (url: URL, note: String?) {
        let fm = FileManager.default
        func usable(_ url: URL) -> Bool { fm.isDirectory(url) && fm.isWritableFile(atPath: url.path) }
        let fallback = gamesFolder
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        switch current {
        case .games:
            return (fallback, nil)
        case .besideArchive:
            let dir = archive.deletingLastPathComponent()
            if usable(dir) { return (dir, nil) }
            return (fallback, "The archive's folder can't be written to, so the game went to your Games folder.")
        case .custom:
            if let path = UserDefaults.standard.string(forKey: customFolderKey), !path.isEmpty {
                let dir = URL(fileURLWithPath: path, isDirectory: true)
                if usable(dir) { return (dir, nil) }
                return (fallback, "Your chosen unpack folder isn't available (is its drive plugged in?), so the game went to your Games folder.")
            }
            return (fallback, nil)
        }
    }
}
