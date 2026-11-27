import Foundation

func runAssistantModelsTests() {
    check(AssistantModels.baseURL("https://openrouter.ai/api/v1") == .ok(URL(string: "https://openrouter.ai/api/v1")!), "https base")
    check(AssistantModels.baseURL(" http://localhost:1234/v1/ ") == .ok(URL(string: "http://localhost:1234/v1")!), "local http, trimmed, no trailing slash")
    check(AssistantModels.baseURL("http://192.168.1.5/v1") == .refused("Use an https:// address. Plain http:// works only for a server on this Mac (localhost)."), "plain http elsewhere refused")
    check(AssistantModels.pick(listed: ["a", "b"], remembered: "b", suggested: "a") == "b", "remembered wins while listed")
    check(AssistantModels.pick(listed: ["a", "b"], remembered: "gone", suggested: "a") == "a", "then the suggestion")
    check(AssistantModels.pick(listed: ["a", "b"], remembered: nil, suggested: "z") == nil, "nothing listed matches: the person picks")
    let gemini = ["models/gemini-3-flash", "models/gemini-3-pro"]
    check(AssistantModels.pick(listed: gemini, remembered: nil, suggested: "gemini-3-pro") == "models/gemini-3-pro", "suggestion matches Gemini's models/ id, listed id returned")
    check(AssistantModels.pick(listed: ["gemini-3-pro"], remembered: "models/gemini-3-pro", suggested: nil) == "gemini-3-pro", "remembered models/ id matches a bare one")
    check(AssistantModels.pick(listed: gemini, remembered: "models/gemini-3-flash", suggested: "gemini-3-pro") == "models/gemini-3-flash", "remembered still wins")
    check(AssistantModels.pick(listed: ["models/x", "x"], remembered: "x", suggested: nil) == "x", "an exact match comes first")
    check(!AssistantModels.sameModel("models/a", "b") && AssistantModels.sameModel("models/a", "a"), "sameModel")
    let d = UserDefaults(suiteName: "ferry-tests-models-\(UUID())")!
    check(AssistantModelChoice.load(d).provider == .apple, "Apple by default")
    AssistantModelChoice(provider: .claude, model: "claude-opus-5-5", base: "").save(d)
    check(AssistantModelChoice.load(d) == AssistantModelChoice(provider: .claude, model: "claude-opus-5-5", base: ""), "saved and loaded")
    check(AssistantProvider.claude.wire is ClaudeWire && AssistantProvider.gemini.wire is OpenAIWire && AssistantProvider.chatgpt.wire is ResponsesWire && AssistantProvider.other.wire is OpenAIWire && AssistantProvider.apple.wire == nil, "wires")
    check(AssistantModels.needs(.claude, hasKey: false, appleReason: nil) == "Add your API key.", "blank key greys Claude")
    check(AssistantModels.needs(.gemini, hasKey: true, appleReason: nil) == nil && AssistantModels.needs(.other, hasKey: false, appleReason: nil) == nil, "key saved, or Other needs none")
    check(AssistantModels.needs(.apple, hasKey: false, appleReason: "Needs macOS 26.4 or later.") == "Needs macOS 26.4 or later." && AssistantModels.needs(.apple, hasKey: false, appleReason: nil) == nil, "Apple: its reason")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .claude, model: "m", base: ""), hasKey: false, appleReason: nil) == "Add your API key.", "blocker: key first")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .claude, model: " ", base: ""), hasKey: true, appleReason: nil) == "Choose a model.", "blocker: model")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .other, model: "m", base: ""), hasKey: false, appleReason: nil) == "Add the service's address.", "blocker: address")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .other, model: "m", base: "http://example.com"), hasKey: false, appleReason: nil)?.hasPrefix("Use an https://") == true, "blocker: refused address")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .other, model: "m", base: "http://localhost:1234/v1"), hasKey: false, appleReason: nil) == nil, "blocker: local server ready")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .apple, model: "", base: ""), hasKey: false, appleReason: nil) == nil, "blocker: Apple ready")
    check(AssistantModels.blocker(AssistantModelChoice(provider: .other, model: "m", base: "http://localhost:1234/v1"), hasKey: true, appleReason: nil) == nil, "blocker: Other with a key ready")

    check(Keychain.classify(errSecSuccess, Data("sk-x".utf8)) == .found("sk-x"), "keychain: found")
    check(Keychain.classify(errSecSuccess, Data(" \n".utf8)) == .missing && Keychain.classify(errSecSuccess, nil) == .missing, "keychain: blank is none")
    check(Keychain.classify(errSecItemNotFound, nil) == .missing, "keychain: not found is none")
    for s in [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed] {
        check(Keychain.classify(s, nil) == .unreadable, "keychain: \(s) is unreadable, not missing")
    }
    check(KeyRead.unreadableNote == "Ferry couldn't read the API key from your Keychain. Allow Ferry when the Mac asks, or save the key again in Settings ▸ AI.", "unreadable note")
    check(AssistantModels.billingNote(.claude) == "Kept in your Mac's Keychain. Using it is billed by Claude to your account.", "billing note")
}
