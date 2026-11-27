import Foundation
import FoundationModels

enum AppleAssistant {
    static var unavailableReason: String? {
        guard #available(macOS 26.4, *) else { return "Needs macOS 26.4 or later." }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings ▸ Apple Intelligence & Siri."
        case .unavailable(.modelNotReady): return "Apple's model is still downloading. Try again in a few minutes."
        case .unavailable(.deviceNotEligible): return "This Mac can't run Apple's model."
        case .unavailable: return "This Mac can't run Apple's model."
        }
    }

    static let tooLong = "That was too long for Apple's model. Ask something shorter."
    static let couldNot = "Apple's model couldn't answer that. Ask again."
}

struct AppleReply {
    let text: String
    let pick: SymptomPick
    let cards: [FixStep]
}

@available(macOS 26.4, *)
@MainActor final class AppleChat {
    unowned let model: AppModel
    let chat: AssistantChat
    private(set) var gameID: UUID?
    private(set) var lastPrompt = ""

    private let lm = SystemLanguageModel.default
    private var session: LanguageModelSession?
    private(set) var instructions = ""
    private var sessionTexts: [String] = []
    private var records: [AppleTurnRecord] = []
    private var lastSymptom: Symptom?
    private var symptomsSeen: [(game: UUID, symptom: Symptom)] = []
    private var shownIDs: [UUID: Set<String>] = [:]
    private var shownChanges: [UUID: Set<String>] = [:]
    private var appliedKeys: [UUID: Set<String>] = [:]
    private var appliedSinceLastTurn: [String] = []
    private var snapshot: [String: String]?
    private var findingsTold: Date?
    private var findingOffered: [UUID: [String: Date]] = [:]
    private var switches = 0

    init(model: AppModel, chat: AssistantChat, gameID: UUID?) {
        self.model = model
        self.chat = chat
        self.gameID = gameID
    }

    private var game: Game? { gameID.flatMap { model.game($0) } }

    func switchGame(to id: UUID?) {
        guard id != gameID else { return }
        gameID = id
        switches += 1
        session = nil
        snapshot = nil
        findingsTold = nil
        lastSymptom = nil
    }

    func applied(_ step: FixStep, value: String?, game: UUID) {
        let keys: [String]
        var title = step.title
        switch step.action {
        case .settings(let c): keys = c.map(\.key)
        case .picker(let key, let choices):
            keys = [key]
            if let value { title += ": " + (choices.first { $0.value == value }?.label ?? value) }
        case .install(_, let then): keys = then.map(\.key)
        case .library, .open, .note: keys = []
        }
        appliedKeys[game, default: []].formUnion(keys)
        appliedSinceLastTurn.append(title)
        if !records.isEmpty { records[records.count - 1].applied.append(title) }
    }

    func reply(to message: String, onText: @escaping (String) -> Void) async throws -> AppleReply {
        if let why = AppleAssistant.unavailableReason { throw AssistantFailure(why) }
        let g = game
        if let g, !(await model.ensureAssistantPermission(chat: chat, kind: .read, game: g)) {
            throw AssistantFailure(AssistantPrompts.refused)
        }
        do {
            return try await turn(message, game: g, onText: onText)
        } catch let f as AssistantFailure {
            session = nil
            throw f
        } catch is CancellationError {
            session = nil
            throw CancellationError()
        } catch let e as LanguageModelSession.GenerationError {
            session = nil
            switch e {
            case .exceededContextWindowSize: throw AssistantFailure(AppleAssistant.tooLong)
            case .guardrailViolation, .refusal: throw AssistantFailure("Apple's model won't answer that. Try rephrasing.")
            case .rateLimited, .concurrentRequests: throw AssistantFailure("Apple's model is busy. Try again in a moment.")
            case .assetsUnavailable: throw AssistantFailure("Apple's model is still downloading. Try again in a few minutes.")
            case .unsupportedLanguageOrLocale: throw AssistantFailure("Apple's model doesn't support this language. Ask in English.")
            default: throw AssistantFailure(AppleAssistant.couldNot)
            }
        } catch {
            session = nil
            throw AssistantFailure(AppleAssistant.couldNot)
        }
    }

    private func scrub(_ s: String, _ g: Game?) -> String {
        AssistantText.scrub(s, home: NSHomeDirectory(), user: NSUserName(), gameFolder: g.map { model.gameFolders($0).root.path })
    }

    private func turn(_ message: String, game g: Game?, onText: (String) -> Void) async throws -> AppleReply {
        let switchesAtStart = switches
        let (pick, sortedAsQuestion) = g == nil ? (SymptomPick.none, false) : try await pickSymptom(message, game: g)
        try Task.checkCancellation()
        let symptom: Symptom? = switch pick {
        case .symptom(let s): s
        case .sameAgain: lastSymptom
        case .none: nil
        }

        var cards: [FixStep] = []
        var advice: [String] = []
        var findingLines: [String] = []
        var changed: [String] = []
        var help: KnowledgeDoc?
        var newSnapshot: [String: String]?
        var offeredNow: [String: Date] = [:]
        var logDate: Date?
        var settingKeys: Set<String>?

        if let g {
            let facts = settingFacts(g)
            settingKeys = Set(facts.map(\.key))
            let now = Dictionary(facts.map { ($0.title, $0.value) }, uniquingKeysWith: { a, _ in a })
            newSnapshot = now
            if let before = snapshot { changed = AppleChatLogic.settingChanges(before: before, after: now) }
            changed += appliedSinceLastTurn.filter { t in !changed.contains { $0.hasPrefix(t + ":") } }.map { "\($0) (the person applied it)" }

            let url = model.logURL(g.id, "game")
            logDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            let findings = logDate == nil ? [] : model.logFindings(g)
            if !findings.isEmpty, logDate != findingsTold, symptom != nil || findingsTold != nil {
                findingLines = ["Ferry's check of the game's last log found:"] + findings.map { "- \($0.title): \($0.detail)" }
            }

            if let symptom {
                let id = g.id
                let ctx = model.settingContext(g)
                let applied = appliedKeys[id, default: []]
                let steps = AppleChatLogic.forAssistant(TroubleshootFixes.steps(for: symptom, model.fixContext(g)))
                    .filter { AppleChatLogic.refusal($0, ctx) == nil }
                let sameChange = Set(steps.filter { s in changeSignature(s).map { shownChanges[id, default: []].contains($0) } ?? false }.map(\.id))
                cards = AppleChatLogic.nextFixes(steps, shownIDs: shownIDs[id, default: []].union(sameChange), appliedKeys: applied, settings: g.settings)
                if !symptomsSeen.contains(where: { $0.game == id && $0.symptom == symptom }) {
                    advice = steps.filter { $0.action == .note }.map(\.detail)
                }
                let offered = findingOffered[id, default: [:]]
                for f in findings {
                    guard let date = logDate, offered[f.id] != date, let step = fixStep(f, game: g) else { continue }
                    let sig = changeSignature(step)
                    if let sig, shownChanges[id, default: []].contains(sig) || cards.contains(where: { changeSignature($0) == sig }) { continue }
                    guard AppleChatLogic.refusal(step, ctx) == nil, !AppleChatLogic.nextFixes([step], shownIDs: [], appliedKeys: applied, settings: g.settings).isEmpty else { continue }
                    cards.append(step)
                    offeredNow[f.id] = date
                }
            }
        }
        if pick == .none && (sortedAsQuestion || AppleChatLogic.isQuestion(message)) {
            help = AssistantFacts.docs(model.knowledge, question: message, earlier: records.suffix(2).map(\.person), titles: [], settingKeys: settingKeys).first
        }
        let note = AppleChatLogic.note(pick: pick, symptom: symptom, cards: cards, advice: advice, findings: findingLines,
                                       changed: changed, exhausted: symptom != nil && cards.isEmpty, help: help)
        let prompt = scrub(AppleChatLogic.turnPrompt(note: note, message: message), g)
        lastPrompt = prompt

        try await prepareSession(for: prompt, game: g)
        guard let session else { throw AssistantFailure(AppleAssistant.couldNot) }
        var text = ""
        for try await snap in session.streamResponse(to: prompt, options: GenerationOptions(maximumResponseTokens: 500)) {
            text = snap.content
            onText(text)
        }
        try Task.checkCancellation()
        guard switches == switchesAtStart else { throw CancellationError() }

        sessionTexts += [prompt, text]
        records.append(AppleTurnRecord(person: message, reply: text, shown: cards.map(\.title), applied: []))
        appliedSinceLastTurn = []
        if let newSnapshot { snapshot = newSnapshot }
        if !findingLines.isEmpty { findingsTold = logDate }
        if let symptom {
            lastSymptom = symptom
            if let id = g?.id, !symptomsSeen.contains(where: { $0.game == id && $0.symptom == symptom }) { symptomsSeen.append((id, symptom)) }
        }
        if let id = g?.id {
            shownIDs[id, default: []].formUnion(cards.map(\.id))
            shownChanges[id, default: []].formUnion(cards.compactMap(changeSignature))
            findingOffered[id, default: [:]].merge(offeredNow) { _, new in new }
        }
        return AppleReply(text: text, pick: pick, cards: cards)
    }

    private func pickSymptom(_ message: String, game g: Game?) async throws -> (pick: SymptomPick, question: Bool) {
        let said = scrub("The person now says: \(String(message.prefix(1000)))", g)
        func choose(_ instructions: String, _ options: [String]) async throws -> String {
            let root = DynamicGenerationSchema(name: "Pick", properties: [.init(name: "pick", schema: DynamicGenerationSchema(name: "Choice", anyOf: options))])
            let session = LanguageModelSession(model: lm, instructions: Instructions(instructions))
            return try await session.respond(to: said, schema: try GenerationSchema(root: root, dependencies: []),
                                             options: GenerationOptions(maximumResponseTokens: 60)).content.jsonString
        }
        let kind = AppleChatLogic.sortKind(json: try await choose(AppleChatLogic.sortInstructions, AppleChatLogic.sortKinds))
        var named: String?
        if let call = AppleChatLogic.symptomCall(kind: kind) { named = try await choose(call.instructions, call.options) }
        return (AppleChatLogic.pick(kind: kind, symptomJSON: named, last: lastSymptom), kind == 2)
    }

    private func prepareSession(for prompt: String, game g: Game?) async throws {
        if session == nil { startSession(game: g) }
        if try await AppleChatLogic.needsRestart(used: used(adding: prompt), contextSize: lm.contextSize) {
            guard !sessionTexts.isEmpty else { throw AssistantFailure(AppleAssistant.tooLong) }
            startSession(game: g)
            if try await AppleChatLogic.needsRestart(used: used(adding: prompt), contextSize: lm.contextSize) {
                throw AssistantFailure(AppleAssistant.tooLong)
            }
        }
    }

    func instructionsTokens() async throws -> Int {
        try await lm.tokenCount(for: Instructions(instructions))
    }

    private func used(adding prompt: String) async throws -> Int {
        try await lm.tokenCount(for: Instructions(instructions)) + lm.tokenCount(for: Prompt((sessionTexts + [prompt]).joined(separator: "\n")))
    }

    private func startSession(game g: Game?) {
        var parts = [AssistantFacts.instructions]
        if let g {
            var facts = "Game: \(g.name) (\(model.subtitle(for: g)))\nSettings:\n" + AssistantFacts.settingsText(settingFacts(g))
            if !LogDoctor.read(model.logURL(g.id, "game")).isEmpty {
                let titles = model.logFindings(g).map(\.title)
                facts += titles.isEmpty ? "\nFerry's check of the last start's log: nothing it recognises."
                    : "\nFerry's check of the last start's log found: " + titles.joined(separator: "; ")
            }
            parts.append(facts)
        }
        if !records.isEmpty {
            var titles: [String] = []
            for s in symptomsSeen where !titles.contains(s.symptom.title) { titles.append(s.symptom.title) }
            parts.append(AppleChatLogic.summary(records, symptoms: titles))
        }
        instructions = scrub(parts.joined(separator: "\n\n"), g)
        sessionTexts = []
        session = LanguageModelSession(model: lm, instructions: Instructions(instructions))
    }

    private func settingFacts(_ g: Game) -> [FactSettings] {
        let ctx = model.settingContext(g)
        return SettingsCatalog.all.filter { $0.appliesTo(ctx) }.map { e in
            let v = e.get(g.settings)
            let text = v.text.isEmpty ? "(empty)" : String(v.text.prefix(200))
            return FactSettings(key: e.key, title: ctx.title(e.key), value: e.choices.first(where: { $0.value == v })?.label ?? text,
                                needs: e.needs(ctx).map { ctx.fill($0) })
        }
    }

    private func changeSignature(_ s: FixStep) -> String? {
        let changes: [SettingChange]
        switch s.action {
        case .settings(let c): changes = c
        case .install(_, let then): changes = then
        default: return nil
        }
        return changes.isEmpty ? nil : changes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
    }

    private func fixStep(_ f: LogFinding, game g: Game) -> FixStep? {
        let id = "log-" + f.id
        func set(_ key: String, _ value: String, _ button: String, _ inEffect: Bool) -> FixStep {
            FixStep(id: id, title: f.title, detail: f.detail, action: .settings([SettingChange(key: key, value: value)]), button: button, inEffect: inEffect)
        }
        switch f.fix {
        case .library(let c):
            return FixStep(id: id, title: f.title, detail: f.detail, action: .library(component: c.rawValue), button: "Install", inEffect: false)
        case .engine(let e): return set("engine", e.rawValue, "Switch", model.resolvedEngine(g) == e)
        case .useDX9: return set("useDX9", "on", "Turn On", g.settings.useDX9)
        case .fastSyncOff: return set("fastSync", "off", "Turn Off", !g.settings.fastSync)
        case .webView2:
            if model.webView2Installed { return set("webView2", "on", "Turn On", g.settings.webView2) }
            return FixStep(id: id, title: f.title, detail: f.detail, action: .install(component: Component.webView2.rawValue, then: [SettingChange(key: "webView2", value: "on")]),
                           button: "Install", inEffect: false)
        case .none: return nil
        }
    }
}
