import Foundation

enum AssistantCardRows {
    static func unseen(_ rows: [[AssistantChange]], chat: UUID, seen: Set<UUID>) -> [[AssistantChange]] {
        rows.filter { row in row.contains { $0.chat == chat } && !row.contains { seen.contains($0.id) } }.reversed()
    }

    static func made(_ changes: [AssistantChange], since before: Set<UUID>, chat: UUID, key: String) -> [AssistantChange] {
        let new = changes.filter { $0.chat == chat && !before.contains($0.id) }
        guard let main = new.last(where: { c in
            if case .setting(let k, _, _) = c.what { return k == key }
            return false
        }) else { return [] }
        return new.filter { $0.id == main.id || ($0.group != nil && $0.group == main.group) }
    }

    static func remaining(_ ids: [UUID], in changes: [AssistantChange]) -> [UUID] {
        let logged = Set(changes.map(\.id))
        return ids.filter { logged.contains($0) }
    }

    static func reason(reply: String, title: String) -> String {
        let r = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((r.isEmpty ? title : r).prefix(200))
    }
}
