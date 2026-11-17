import Foundation

enum ProgramRole: Equatable {
    case singleplayer, multiplayer, launcher, server, editor, settings, benchmark, other

    var label: String? {
        switch self {
        case .singleplayer: return "Single-player"
        case .multiplayer: return "Multiplayer"
        case .launcher: return "Launcher"
        case .server: return "Dedicated server"
        case .editor: return "Editor or tools"
        case .settings: return "Settings"
        case .benchmark: return "Benchmark"
        case .other: return nil
        }
    }

    var weight: Double {
        switch self {
        case .singleplayer: return 3
        case .multiplayer: return -1
        case .launcher: return -2
        case .server, .editor: return -6
        case .settings, .benchmark: return -4
        case .other: return 0
        }
    }

    var isPlayable: Bool { [.singleplayer, .multiplayer, .launcher, .other].contains(self) }
}

enum ProgramChoice {
    static func role(fileName: String, description: String?) -> ProgramRole {
        let name = (fileName as NSString).deletingPathExtension.lowercased()
        let text = (description ?? "").lowercased()
        let words = (name + " " + text).replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        func has(_ any: String...) -> Bool { any.contains { words.contains($0) } }

        if has("dedicated", "server", "srcds", "hlds") || name.hasSuffix("ded") { return .server }
        if has("editor", "radiant", "mod tools", "modtools", "sdk", "toolkit", "level design", "creationkit", "unrealed")
            || name == "ucc" { return .editor }
        if has("benchmark") { return .benchmark }
        if has("config", "settings", "options", "setup tool", "graphics setup") { return .settings }
        if has("multiplayer", "multi player", "multi-player") { return .multiplayer }
        if has("singleplayer", "single player", "single-player", "campaign") { return .singleplayer }
        let stem = Self.stem(fileName)
        if stem.hasSuffix("sp") || stem.hasSuffix("mp") {
            let kind: ProgramRole = stem.hasSuffix("sp") ? .singleplayer : .multiplayer
            let separated = stem.dropLast(2).hasSuffix("_") || stem.dropLast(2).hasSuffix(" ")
            let prefix = stem.dropLast(2)
            if separated || prefix.contains(where: { $0.isNumber }) || prefix.hasPrefix("cod") { return kind }
        }
        if has("launcher") { return .launcher }
        return .other
    }

    static func roles(of programs: [(fileName: String, description: String?)]) -> [ProgramRole] {
        func pairStem(_ fileName: String) -> (stem: String, isSP: Bool)? {
            let stem = Self.stem(fileName)
            guard stem.count > 2, stem.hasSuffix("sp") || stem.hasSuffix("mp") else { return nil }
            return (String(stem.dropLast(2)), stem.hasSuffix("sp"))
        }
        let stems = programs.map { Self.stem($0.fileName) }
        let pairs = programs.map { pairStem($0.fileName) }
        var roles = programs.map { role(fileName: $0.fileName, description: $0.description) }
        for i in programs.indices where roles[i] == .other {
            guard let mine = pairs[i] else { continue }
            if pairs.contains(where: { $0 != nil && $0!.stem == mine.stem && $0!.isSP != mine.isSP }) {
                roles[i] = mine.isSP ? .singleplayer : .multiplayer
            }
            if !mine.isSP, let plain = stems.firstIndex(of: mine.stem), roles[plain] == .other {
                roles[i] = .multiplayer
                roles[plain] = .singleplayer
            }
        }
        return roles
    }

    static func partner(of chosen: Int, roles: [ProgramRole], inLibrary: [Bool]) -> Int? {
        guard roles.indices.contains(chosen), roles[chosen] == .singleplayer || roles[chosen] == .multiplayer else { return nil }
        let wanted: ProgramRole = roles[chosen] == .singleplayer ? .multiplayer : .singleplayer
        return roles.indices.first { $0 != chosen && roles[$0] == wanted && !inLibrary[$0] }
    }

    static func stem(_ fileName: String) -> String {
        var stem = (fileName as NSString).deletingPathExtension.lowercased()
        var changed = true
        while changed {
            changed = false
            for suffix in ["_shipping", "-shipping", "_ship", "_s", "_x86", "_x64", "_64", "_32", "64", "32"]
            where stem.hasSuffix(suffix) && stem.count > suffix.count + 2 {
                stem = String(stem.dropLast(suffix.count))
                changed = true
            }
        }
        return stem
    }

    static func label(fileName: String, description: String?, role: ProgramRole) -> String {
        let detail = description.flatMap { $0.isEmpty ? nil : $0 }
        switch (role.label, detail) {
        case let (role?, detail?): return "\(role) · \(detail)"
        case let (role?, nil): return role
        case let (nil, detail?): return detail
        default: return fileName
        }
    }

    static func isClose(_ ranked: [(role: ProgramRole, score: Double)], margin: Double = 3) -> Bool {
        let playable = ranked.filter { $0.role.isPlayable }
        guard playable.count > 1 else { return false }
        if playable.contains(where: { $0.role == .singleplayer }) && playable.contains(where: { $0.role == .multiplayer }) {
            return true
        }
        return playable[0].score - playable[1].score < margin
    }
}
