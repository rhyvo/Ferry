import Foundation

enum AssistantProvider: String, CaseIterable {
    case apple, claude, chatgpt, gemini, other

    var title: String {
        switch self {
        case .apple: return "Apple (on this Mac)"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .other: return "Other (OpenAI-compatible)"
        }
    }

    var wire: ChatWire? {
        switch self {
        case .apple: return nil
        case .claude: return ClaudeWire()
        case .chatgpt: return ResponsesWire()
        case .gemini, .other: return OpenAIWire()
        }
    }

    var defaultBase: URL? {
        switch self {
        case .claude: return URL(string: "https://api.anthropic.com/v1")
        case .chatgpt: return URL(string: "https://api.openai.com/v1")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")
        case .apple, .other: return nil
        }
    }

    var needsKey: Bool { self != .apple && self != .other }
}

struct AssistantModelChoice: Equatable {
    var provider: AssistantProvider
    var model: String
    var base: String

    static func load(_ d: UserDefaults) -> AssistantModelChoice {
        let p = d.string(forKey: "assistantProvider").flatMap(AssistantProvider.init(rawValue:)) ?? .apple
        return AssistantModelChoice(provider: p, model: d.string(forKey: "assistantModel.\(p.rawValue)") ?? "", base: d.string(forKey: "assistantBase") ?? "")
    }

    func save(_ d: UserDefaults) {
        d.set(provider.rawValue, forKey: "assistantProvider")
        d.set(model, forKey: "assistantModel.\(provider.rawValue)")
        d.set(base, forKey: "assistantBase")
    }
}

enum BaseURLCheck: Equatable { case ok(URL), refused(String) }

enum AssistantModels {
    static func baseURL(_ text: String) -> BaseURLCheck {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("/") { t.removeLast() }
        guard let url = URL(string: t), url.scheme != nil, url.host != nil else {
            return .refused("That isn't a web address. Use something like https://example.com/v1.")
        }
        guard ChatBase.isAllowed(url) else {
            return .refused("Use an https:// address. Plain http:// works only for a server on this Mac (localhost).")
        }
        return .ok(url)
    }

    static func needs(_ p: AssistantProvider, hasKey: Bool, appleReason: String?) -> String? {
        if p == .apple { return appleReason }
        if p.needsKey, !hasKey { return "Add your API key." }
        return nil
    }

    static func blocker(_ c: AssistantModelChoice, hasKey: Bool, appleReason: String?) -> String? {
        if let n = needs(c.provider, hasKey: hasKey, appleReason: appleReason) { return n }
        if c.provider == .apple { return nil }
        if c.provider == .other {
            if c.base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the service's address." }
            if case .refused(let why) = baseURL(c.base) { return why }
        }
        if c.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Choose a model." }
        return nil
    }

    static func billingNote(_ p: AssistantProvider) -> String {
        "Kept in your Mac's Keychain. Using it is billed by \(p == .other ? "the service" : p.title) to your account."
    }

    static func sameModel(_ a: String, _ b: String) -> Bool {
        func bare(_ s: String) -> Substring { s.hasPrefix("models/") ? s.dropFirst("models/".count) : Substring(s) }
        return bare(a) == bare(b)
    }

    static func pick(listed: [String], remembered: String?, suggested: String?) -> String? {
        for m in [remembered, suggested] {
            if let m, let hit = listed.first(where: { $0 == m }) ?? listed.first(where: { sameModel($0, m) }) { return hit }
        }
        return nil
    }
}
