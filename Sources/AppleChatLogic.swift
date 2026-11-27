import Foundation

enum SymptomPick: Equatable { case symptom(Symptom), sameAgain, none }

struct AppleTurnRecord { var person: String; var reply: String; var shown: [String]; var applied: [String] }

enum AppleChatLogic {
    static let sortKinds = ["a problem with a game", "the same problem still happens", "a question", "thanks, it worked, nothing else, or chat"]
    static let sortInstructions = "Sort the person's new message in a chat about their games into one kind. Examples: \"the game crashes\" and \"it stutters\" are a problem with a game. \"still crashes\" and \"that didn't help\" mean the same problem still happens. \"what does VSync do?\" and \"which setting is it?\" are a question. \"thanks\", \"that fixed it\", \"nothing for now\", \"ok\" and \"hi\" are thanks or chat."
    static let symptomInstructions = "Pick the problem the person describes, from the list."
    static var symptomOptions: [String] { Symptom.allCases.map(\.title) }
    static let namedInstructions = "Pick the problem the person names, from the list. Pick none of these when the message doesn't name one."
    static let notNamedOption = "None of these, or it doesn't say"

    static func sortKind(json: String) -> Int? {
        guard let p = picked(json) else { return nil }
        return sortKinds.firstIndex(of: p)
    }

    static func symptomCall(kind: Int?) -> (instructions: String, options: [String])? {
        switch kind {
        case 0: return (symptomInstructions, symptomOptions)
        case 1: return (namedInstructions, symptomOptions + [notNamedOption])
        default: return nil
        }
    }

    static func pick(kind: Int?, symptomJSON: String?, last: Symptom?) -> SymptomPick {
        let named = symptomJSON.flatMap(picked).flatMap { p in Symptom.allCases.first { $0.title == p } }
        switch kind {
        case 0: return named.map { .symptom($0) } ?? .none
        case 1:
            if let named, named != last { return .symptom(named) }
            return last == nil ? .none : .sameAgain
        default: return .none
        }
    }

    private static func picked(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["pick"] as? String
    }

    static func nextFixes(_ steps: [FixStep], shownIDs: Set<String>, appliedKeys: Set<String>, settings: GameSettings? = nil, limit: Int = 2) -> [FixStep] {
        var out: [FixStep] = []
        for s in steps where out.count < limit {
            if s.inEffect || shownIDs.contains(s.id) { continue }
            let keys: [String]
            switch s.action {
            case .note: continue
            case .settings(let c), .install(_, let c):
                keys = c.filter { ch in settings.flatMap { st in SettingsCatalog.entry(ch.key).map { $0.get(st).text == ch.value } } != true }.map(\.key)
            case .picker(let key, _): keys = [key]
            case .library, .open: keys = []
            }
            if keys.contains(where: appliedKeys.contains) { continue }
            out.append(s)
        }
        return out
    }

    static func forAssistant(_ steps: [FixStep]) -> [FixStep] {
        steps.map { s in
            guard case .install(let component, let then) = s.action, component == "webView2", then.isEmpty else { return s }
            let detail = s.detail.range(of: " Ferry installs it once").map { String(s.detail[..<$0.lowerBound]) + " Ferry shares it between games." } ?? s.detail
            return FixStep(id: s.id, title: s.title, detail: detail, action: .install(component: component, then: [SettingChange(key: "webView2", value: "on")]),
                           button: s.button, inEffect: s.inEffect)
        }
    }

    static func refusal(_ step: FixStep, _ start: SettingContext) -> String? {
        var ctx = start
        let changes: [SettingChange]
        switch step.action {
        case .settings(let c): changes = c
        case .install(let component, let then):
            switch component {
            case "dxmt": ctx.dxmtInstalled = true
            case "legacyDirectX": ctx.legacyDirectXInstalled = true
            case "webView2": ctx.webView2Installed = true
            case "dgVoodoo": ctx.dgVoodooInstalled = true
            default: break
            }
            changes = then
        case .picker(let key, _):
            guard let e = SettingsCatalog.entry(key) else { return "No setting \(key)." }
            return e.appliesTo(ctx) ? e.needs(ctx).map(ctx.fill) : "Not a setting for this game."
        case .library, .open, .note: return nil
        }
        for change in changes {
            guard let e = SettingsCatalog.entry(change.key) else { return "No setting \(change.key)." }
            guard e.appliesTo(ctx) else { return "Not a setting for this game." }
            let old = e.get(ctx.settings)
            guard let new = try? AssistantEdits.value(change.value, for: e, title: change.key, like: old) else { return "Not a value for \(change.key)." }
            if new == old { continue }
            if let needs = AssistantEdits.blocked(key: change.key, needs: e.needs(ctx), from: old, to: new) { return ctx.fill(needs) }
            e.set(&ctx.settings, new)
            if change.key == "engine", case .string(let id) = new, let engine = EngineID(rawValue: id), engine != .auto { ctx.engine = engine }
        }
        return nil
    }

    static func isQuestion(_ text: String) -> Bool {
        if text.contains("?") { return true }
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        return ["what", "how", "why", "does", "is", "can", "which"].contains(first)
    }

    static func settingChanges(before: [String: String], after: [String: String]) -> [String] {
        before.keys.sorted().compactMap { k in
            guard let b = before[k], let a = after[k], a != b else { return nil }
            return "\(k): \(b) → \(a)"
        }
    }

    static func note(pick: SymptomPick, symptom: Symptom?, cards: [FixStep], advice: [String], findings: [String],
                     changed: [String], exhausted: Bool, help: KnowledgeDoc?) -> String? {
        var lines: [String] = []
        if let symptom, pick != .none { lines.append("The person seems to describe: \(symptom.title).") }
        if !cards.isEmpty {
            lines.append("Ferry is showing buttons for: " + cards.map(\.title).joined(separator: "; "))
            lines += cards.map { "\($0.title): \($0.detail)" }
        }
        lines += advice
        lines += findings
        if !changed.isEmpty { lines.append("Changed since your last reply: " + changed.joined(separator: "; ")) }
        if exhausted {
            lines.append("Ferry has no more fixes to offer for this. Say that the person can look at the game's log (Show Log in the game's settings), or add a Claude, ChatGPT or Gemini key in Settings ▸ AI for deeper help: name those three and Settings ▸ AI exactly.")
        }
        if let help { lines.append("Help topic: \(help.title). \(String(help.body.prefix(600)))") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func turnPrompt(note: String?, message: String) -> String {
        let line = "The person says: \(message)"
        guard let note, !note.isEmpty else { return line }
        return line + "\n\n(Ferry's note, not shown to the person:\n" + note + ")"
    }

    static func needsRestart(used: Int, contextSize: Int, reserve: Int = 1000) -> Bool {
        used > contextSize - reserve
    }

    static func summary(_ turns: [AppleTurnRecord], symptoms: [String]) -> String {
        func clip(_ s: String, _ n: Int) -> String {
            let t = s.replacingOccurrences(of: "\n", with: " ")
            return t.count <= n ? t : String(t.prefix(n - 1)) + "…"
        }
        let cap = 1200
        var head = "Earlier in this chat."
        if !symptoms.isEmpty { head += " Problems: " + symptoms.joined(separator: "; ") + "." }
        let applied = turns.flatMap(\.applied).reversed()
        if !applied.isEmpty { head += " Applied: " + applied.joined(separator: "; ") + "." }
        head = clip(head, 450)
        var tail = ""
        if let last = turns.last { tail = "Last: the person said \"\(clip(last.person, 200))\"; you replied \"\(clip(last.reply, 300))\"" }
        var middle: [String] = []
        var room = cap - head.count - tail.count - 2
        for t in turns.dropLast().reversed() {
            let line = "- " + clip(t.person, 70)
            if line.count + 1 > room { break }
            middle.append(line); room -= line.count + 1
        }
        return ([head] + middle.reversed() + [tail]).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
