import AppKit
import Foundation

struct AssistantCall {
    let chat: UUID
    let args: [String: Any]
}

enum AssistantContent {
    case text(String), image(png: Data)
}

struct AssistantResult {
    var content: [AssistantContent]
    var isError: Bool

    static func text(_ s: String) -> AssistantResult { AssistantResult(content: [.text(s)], isError: false) }
    static func error(_ s: String) -> AssistantResult { AssistantResult(content: [.text(s)], isError: true) }
}

struct AssistantFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct AssistantTool {
    let name: String
    let description: String
    let schema: [String: Any]
    let kind: AssistantKind?
    let run: (AppModel, AssistantCall) async -> AssistantResult
}

final class AssistantChat {
    let id: UUID
    let client: String
    var permissions = AssistantPermissions()
    var modResults: [UUID: [ModResult]] = [:]
    var allowedServers: Set<String> = []

    init(id: UUID, client: String) {
        self.id = id
        self.client = client
    }
}

extension AssistantTool {
    init(_ name: String, _ description: String, kind: AssistantKind?, args: [String: (type: String, about: String)] = [:],
         required: [String] = [], _ body: @escaping (AppModel, AssistantCall) async throws -> String) {
        var properties: [String: Any] = [:]
        for (key, a) in args { properties[key] = ["type": a.type, "description": a.about] }
        self.init(name: name, description: description,
                  schema: ["type": "object", "properties": properties, "required": required], kind: kind) { model, call in
            do { return .text(try await body(model, call)) } catch let f as AssistantFailure { return .error(f.message) } catch {
                return .error(error.localizedDescription)
            }
        }
    }
}

extension AppModel {
    static let assistantInstructions = MCPProtocol.instructions

    static let assistantTools: [AssistantTool] = assistantReadTools + assistantEditTools + assistantRunTools

    func runAssistantTool(_ name: String, _ call: AssistantCall) async -> AssistantResult {
        guard let tool = Self.assistantTools.first(where: { $0.name == name }) else {
            return .error("Ferry has no action called \(name). Its actions: \(Self.assistantTools.map(\.name).joined(separator: ", ")).")
        }
        guard let chat = assistantChats[call.chat] ?? (AssistantDebug.running ? AssistantChat(id: call.chat, client: "") : nil) else {
            return .error("This chat has ended. Reconnect to Ferry to go on.")
        }
        if assistantChats[call.chat] == nil { assistantChats[call.chat] = chat }
        var game: Game? = nil
        if call.args["game"] != nil || tool.kind != nil {
            do { game = try assistantGame(call) } catch {
                return scrubbed(.error((error as? AssistantFailure)?.message ?? error.localizedDescription), game: nil)
            }
        }
        if let kind = tool.kind, let g = game {
            guard await ensureAssistantPermission(chat: chat, kind: kind, game: g) else { return .error(AssistantPrompts.refused) }
        } else {
            chat.permissions.touch(now: Date())
        }
        var args = call.args
        if let g = game { args["game"] = g.id.uuidString }
        return scrubbed(await tool.run(self, AssistantCall(chat: call.chat, args: args)), game: game)
    }

    func ensureAssistantPermission(chat: AssistantChat, kind: AssistantKind, game g: Game) async -> Bool {
        if chat.permissions.isAllowed(kind, game: g.id, now: Date()) { return true }
        guard await askAssistantPermission(chat: chat, kind: kind, always: nil, game: g, detail: nil) else { return false }
        chat.permissions.grant(kind, game: g.id, now: Date())
        return true
    }

    private func scrubbed(_ r: AssistantResult, game: Game?) -> AssistantResult {
        let folder = game.map { gameFolders($0).root.path }
        var out = r
        out.content = r.content.map {
            if case .text(let s) = $0 { return .text(AssistantText.scrub(s, home: NSHomeDirectory(), user: NSUserName(), gameFolder: folder)) }
            return $0
        }
        return out
    }

    func assistantGame(_ call: AssistantCall) throws -> Game {
        guard let asked = call.args["game"] as? String, !asked.isEmpty else {
            throw AssistantFailure("Say which game, by name or id (list_games lists them).")
        }
        switch AssistantLookup.matchGame(asked, in: games.map { ($0.id, $0.name) }) {
        case .one(let id):
            guard let g = game(id) else { throw AssistantFailure("That game isn't in the library anymore.") }
            return g
        case .ambiguous(let names):
            throw AssistantFailure("More than one game fits “\(asked)”: \(names.joined(separator: "; ")). Say which one.")
        case .none(let names):
            if games.isEmpty { throw AssistantFailure("Ferry's library is empty.") }
            throw AssistantFailure("No game called “\(asked)”. Games in the library: \(names.joined(separator: "; ")).")
        }
    }

    func askAssistantPermission(chat: AssistantChat, kind: AssistantKind, always: AlwaysAsk?, game: Game?, detail: String?) async -> Bool {
        let prompt = AssistantPrompts.prompt(chat: chat.id, kind: kind, always: always, game: game.map { ($0.id, $0.name) }, detail: detail)
        #if !FERRY_RELEASE
        if AssistantDebug.running { return AssistantDebug.ask(prompt) }
        #endif
        guard assistantChats[chat.id] === chat else { return false }
        return await assistantPrompter.ask(prompt)
    }

    func askMCPServerPermission(chat: AssistantChat, server: String) async -> Bool {
        if chat.allowedServers.contains(server) { return true }
        let prompt = AssistantPrompts.serverPrompt(chat: chat.id, server: server)
        #if !FERRY_RELEASE
        if AssistantDebug.running { return AssistantDebug.ask(prompt) }
        #endif
        guard assistantChats[chat.id] === chat, await assistantPrompter.ask(prompt) else { return false }
        chat.allowedServers.insert(server)
        return true
    }

    func endAssistantChat(_ id: UUID) {
        assistantServer?.disconnect(chat: id)
        assistantPrompter.cancel(chat: id)
        assistantChats[id]?.permissions = AssistantPermissions()
        assistantChats[id]?.allowedServers = []
        assistantChats[id] = nil
    }
}

enum AssistantDebug {
    #if FERRY_RELEASE
    static let running = false
    #else
    @MainActor static var running = false

    static var otherFerryOpen: Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: "app.ferry.Ferry").contains { $0.processIdentifier != me }
    }

    @MainActor static func run(_ args: [String]) -> Never {
        guard let name = args.first else {
            print("Usage: Ferry --assistant-tool <name> '<json args>'")
            exit(1)
        }
        guard UserDefaults.standard.bool(forKey: AISettingsView.mcpEnabledKey) else {
            print("Settings ▸ AI ▸ Use Ferry from other AI apps is off. Turn it on to use --assistant-tool.")
            exit(1)
        }
        if otherFerryOpen {
            print("Ferry is open. Quit Ferry first: --assistant-tool works on Ferry's library directly, and must not while Ferry has it open.")
            exit(1)
        }
        let json = args.count > 1 ? args[1] : "{}"
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)), let callArgs = parsed as? [String: Any] else {
            print("The arguments must be a JSON object, like '{\"game\":\"arkham\"}'.")
            exit(1)
        }
        running = true
        let model = AppModel(libraryOnly: ())
        final class Box { var result: AssistantResult? }
        let box = Box()
        let chat = UUID(uuidString: "00000000-0000-0000-0000-00000000F377")!
        Task { box.result = await model.runAssistantTool(name, AssistantCall(chat: chat, args: callArgs)) }
        while box.result == nil { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) }
        let result = box.result!
        for c in result.content {
            switch c {
            case .text(let s): print(s)
            case .image(let png): print("[image, \(png.count) bytes]")
            }
        }
        exit(result.isError ? 1 : 0)
    }

    @MainActor static func runAsk(_ args: [String]) -> Never {
        guard args.count >= 2 else {
            print("Usage: Ferry --assistant-ask \"<game>\" \"<message>\" [\"<next message>\" | \"!apply\" ...]")
            exit(1)
        }
        running = true
        let model = AppModel(libraryOnly: ())
        final class Box { var code: Int32? }
        let box = Box()
        func say(_ line: String) { print(line); fflush(stdout) }
        Task {
            if let why = AppleAssistant.unavailableReason { say(why); box.code = 1; return }
            guard #available(macOS 26.4, *) else { say("Needs macOS 26.4 or later."); box.code = 1; return }
            let g: Game
            do { g = try model.assistantGame(AssistantCall(chat: UUID(), args: ["game": args[0]])) } catch {
                say((error as? AssistantFailure)?.message ?? error.localizedDescription); box.code = 1; return
            }
            let apple = AppleChat(model: model, chat: AssistantChat(id: UUID(), client: ""), gameID: g.id)
            var last: [FixStep] = []
            var code: Int32 = 0
            let show = ProcessInfo.processInfo.environment["FERRY_SHOW_NOTE"] != nil
            func indent(_ tag: String, _ text: String) -> String {
                text.split(separator: "\n", omittingEmptySubsequences: false).map { "  [\(tag)] " + $0 }.joined(separator: "\n")
            }
            var shownInstructions = ""
            for q in args.dropFirst() {
                if q == "!apply" {
                    for c in last { apple.applied(c, value: nil, game: g.id) }
                    say("> (Apply pressed on \(last.count) card\(last.count == 1 ? "" : "s"))")
                    continue
                }
                say("> \(q)")
                do {
                    let r = try await apple.reply(to: q) { _ in }
                    if show {
                        if apple.instructions != shownInstructions {
                            shownInstructions = apple.instructions
                            say(indent("instructions", apple.instructions))
                            if let n = try? await apple.instructionsTokens() { say("  [instructions] \(n) tokens") }
                        }
                        say(indent("sent", apple.lastPrompt))
                    }
                    let pick: String
                    switch r.pick {
                    case .symptom(let s): pick = s.title
                    case .sameAgain: pick = "same"
                    case .none: pick = "none"
                    }
                    say("Pick: \(pick)")
                    say("Reply: \(r.text)")
                    for c in r.cards { say("Card: \(c.title) [\(c.button)]") }
                    last = r.cards
                } catch {
                    say("Error: \((error as? AssistantFailure)?.message ?? error.localizedDescription)")
                    code = 1
                }
            }
            box.code = code
        }
        while box.code == nil { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) }
        exit(box.code!)
    }

    static func ask(_ p: AssistantPrompt) -> Bool {
        let text = p.title + (p.body.map { "\n" + $0 } ?? "")
        guard p.always else {
            FileHandle.standardError.write(Data("Ferry asks: \(text) Allowed: --assistant-tool allows per-chat kinds.\n".utf8))
            return true
        }
        FileHandle.standardError.write(Data("Ferry asks: \(text)\n\(p.allow)? [y/N] ".utf8))
        guard isatty(STDIN_FILENO) == 1 else {
            FileHandle.standardError.write(Data("no (no terminal to answer on)\n".utf8))
            return false
        }
        let reply = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return reply == "y" || reply == "yes"
    }
    #endif
}
