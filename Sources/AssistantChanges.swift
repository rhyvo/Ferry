import Foundation

struct AssistantChange: Codable, Identifiable {
    enum What: Codable {
        case setting(key: String, old: String, new: String)
        case configFile(path: String, backup: String, hash: String? = nil)
        case environment(old: String, new: String)
        case arguments(old: String, new: String)
    }
    var id: UUID
    var game: UUID
    var chat: UUID
    var date: Date
    var reason: String
    var what: What
    var group: UUID? = nil
}

struct AssistantChangeLog {
    let url: URL
    private(set) var changes: [AssistantChange]

    init(url: URL) {
        self.url = url
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard FileManager.default.fileExists(atPath: url.path) else { changes = []; return }
        if let data = try? Data(contentsOf: url), let list = try? dec.decode([AssistantChange].self, from: data) {
            changes = list
        } else {
            let aside = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            changes = []
        }
    }

    mutating func record(_ c: AssistantChange) throws {
        var next = changes
        next.append(c)
        try save(next)
        changes = next
    }

    func undoPlan(chat: UUID) -> [AssistantChange] {
        changes.filter { $0.chat == chat }.reversed()
    }

    func together(_ c: AssistantChange) -> [AssistantChange] {
        guard let g = c.group else { return [c] }
        return changes.filter { $0.group == g }.reversed()
    }

    var rows: [[AssistantChange]] {
        var out: [[AssistantChange]] = []
        for c in changes.reversed() {
            if let g = c.group, let i = out.firstIndex(where: { $0.first?.group == g }) { out[i].append(c) } else { out.append([c]) }
        }
        return out
    }

    mutating func remove(_ ids: [UUID]) throws {
        let drop = Set(ids)
        let next = changes.filter { !drop.contains($0.id) }
        try save(next)
        changes = next
    }

    private func save(_ list: [AssistantChange]) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(list).write(to: url, options: .atomic)
    }
}
