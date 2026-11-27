import Foundation

struct AssistantPrompt: Equatable {
    let id: UUID
    let chat: UUID
    let title: String
    let body: String?
    let allow: String
    let deny: String
    let always: Bool
    let key: String?
}

enum AssistantPrompts {
    static let refused = "The person said no. Ask them in the chat, or try something else."

    static func oneLine(_ s: String) -> String {
        s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined().split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    static func kindText(_ kind: AssistantKind, game: String) -> String {
        switch kind {
        case .read: return "read \(game)'s logs and settings"
        case .change: return "change \(game)'s settings"
        case .editConfig: return "edit \(game)'s config files"
        case .run: return "start and test \(game)"
        }
    }

    static func serverPrompt(id: UUID = UUID(), chat: UUID, server: String) -> AssistantPrompt {
        let name = oneLine(server)
        return AssistantPrompt(id: id, chat: chat, title: "Let the assistant use \(name)'s tools for this chat?", body: nil,
                               allow: "Allow for this chat", deny: "Not now", always: false, key: "mcp \(name)")
    }

    static func prompt(id: UUID = UUID(), chat: UUID, kind: AssistantKind, always: AlwaysAsk?,
                       game: (id: UUID, name: String)?, detail: String?) -> AssistantPrompt {
        let name = game?.name ?? "this game"
        guard always != nil else {
            return AssistantPrompt(id: id, chat: chat, title: "Let the assistant \(kindText(kind, game: name)) for this chat?", body: nil,
                                   allow: "Allow for this chat", deny: "Not now", always: false,
                                   key: "\(kind.rawValue) \(game?.id.uuidString ?? "")")
        }
        var lines = (detail ?? "").components(separatedBy: "\n")
        var first = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        if first.hasSuffix(":") || first.hasSuffix(".") { first.removeLast() }
        if first.isEmpty { first = kindText(kind, game: name) }
        let rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return AssistantPrompt(id: id, chat: chat, title: "Let the assistant \(first)?", body: rest.isEmpty ? nil : rest,
                               allow: "Allow", deny: "Don't allow", always: true, key: nil)
    }
}

struct AssistantPromptQueue {
    private(set) var waiting: [AssistantPrompt] = []

    var current: AssistantPrompt? { waiting.first }

    mutating func add(_ p: AssistantPrompt) -> UUID {
        if let key = p.key, let same = waiting.first(where: { $0.chat == p.chat && $0.key == key }) { return same.id }
        waiting.append(p)
        return p.id
    }

    mutating func remove(_ id: UUID) { waiting.removeAll { $0.id == id } }

    mutating func removeAll(chat: UUID) -> [AssistantPrompt] {
        let gone = waiting.filter { $0.chat == chat }
        waiting.removeAll { $0.chat == chat }
        return gone
    }
}
