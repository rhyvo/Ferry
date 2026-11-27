import Foundation

enum AssistantKind: String, Codable { case read, change, editConfig, run }

enum AlwaysAsk: String, Codable { case delete, download, saveFile, outside }

struct AssistantPermissions {
    private struct Key: Hashable { let kind: AssistantKind; let game: UUID }
    private var granted: Set<Key> = []
    private var lastActivity: Date?
    let idleLimit: TimeInterval

    init(idleLimit: TimeInterval = 1800) { self.idleLimit = idleLimit }

    mutating func grant(_ k: AssistantKind, game: UUID, now: Date) {
        expireIfIdle(now)
        granted.insert(Key(kind: k, game: game))
        lastActivity = now
    }

    mutating func isAllowed(_ k: AssistantKind, game: UUID, now: Date) -> Bool {
        expireIfIdle(now)
        guard granted.contains(Key(kind: k, game: game)) else { return false }
        lastActivity = now
        return true
    }

    mutating func touch(now: Date) {
        expireIfIdle(now)
        lastActivity = now
    }

    private mutating func expireIfIdle(_ now: Date) {
        if let last = lastActivity, now.timeIntervalSince(last) > idleLimit { granted.removeAll() }
    }
}
