import AppKit
import Foundation

extension AssistantChatSession {
    func addChangeCards(games ids: [UUID]) {
        for id in Set(ids) {
            guard let g = model.game(id) else { continue }
            let rows = AssistantChangeLog(url: model.assistantChangeLogURL(id)).rows
            for row in AssistantCardRows.unseen(rows, chat: chatID, seen: shownChanges) {
                shownChanges.formUnion(row.map(\.id))
                let title = row.map { model.assistantChangeSummary($0, game: g) }.joined(separator: "; ")
                items.append(.card(id: UUID(), AssistantCard(kind: .change(changeID: row[0].id), game: id, title: title,
                                                             reason: row[0].reason, state: .done)))
            }
        }
    }

    private func index(of cardID: UUID) -> Int? {
        items.firstIndex { $0.id == cardID }
    }

    private func edit(_ cardID: UUID, _ f: (inout AssistantCard) -> Void) {
        guard let i = index(of: cardID), case .card(let id, var card) = items[i] else { return }
        f(&card)
        items[i] = .card(id: id, card)
    }

    private func card(_ cardID: UUID) -> AssistantCard? {
        guard let i = index(of: cardID), case .card(_, let c) = items[i] else { return nil }
        return c
    }

    private func consent(_ kind: AssistantKind, game: UUID) {
        if model.assistantChats[chatID] == nil { model.assistantChats[chatID] = AssistantChat(id: chatID, client: "Ferry's assistant") }
        model.assistantChats[chatID]?.permissions.grant(kind, game: game, now: Date())
    }

    private func resultText(_ r: AssistantResult) -> String {
        r.content.compactMap { if case .text(let s) = $0 { return s } else { return nil } }.joined(separator: "\n")
    }

    func fixCard(_ step: FixStep, game: UUID, reply: String) -> AssistantCard {
        var detail = step.detail
        if case .install(let component, let then) = step.action, !then.isEmpty, let c = Component(rawValue: component) {
            detail += " Ferry downloads it once first (\(c.title), about \(DiskUsage.text(Int64(c.approxBytes)))); then turn it on here."
        }
        var card = AssistantCard(kind: .fix(step), game: game, title: step.title, reason: reply, state: .ready)
        card.detail = detail
        return card
    }

    private func tellApple(_ step: FixStep, value: String?, game: UUID) {
        guard #available(macOS 26.4, *) else { return }
        (appleChat as? AppleChat)?.applied(step, value: value, game: game)
    }

    func apply(_ cardID: UUID, value: String? = nil) {
        guard !ended, let c = card(cardID), !c.working, case .fix(let step) = c.kind else { return }
        switch c.state { case .ready, .failed: break; default: return }
        let changes: [SettingChange]
        switch step.action {
        case .settings(let list): changes = list
        case .picker(let key, _):
            guard let value, model.game(c.game).flatMap({ g in SettingsCatalog.entry(key)?.get(g.settings).text }) != value else { return }
            changes = [SettingChange(key: key, value: value)]
        case .install(let component, let then):
            guard !then.isEmpty, let comp = Component(rawValue: component), model.componentStatus[comp]?.installed == true else { return }
            changes = then
        case .library, .open, .note: return
        }
        edit(cardID) { $0.working = true }
        consent(.change, game: c.game)
        let reason = AssistantCardRows.reason(reply: c.reason, title: c.title)
        Task {
            var made: [UUID] = []
            var failure: String? = nil
            for change in changes {
                let before = Set(model.assistantChanges(c.game).map(\.id))
                let r = await model.runAssistantTool("set_setting", AssistantCall(chat: chatID, args: [
                    "game": c.game.uuidString, "key": change.key, "value": change.value, "reason": reason]))
                made += AssistantCardRows.made(model.assistantChanges(c.game), since: before, chat: chatID, key: change.key).map(\.id)
                if r.isError { failure = resultText(r); break }
            }
            if let failure {
                let kept = undoAll(made)
                let left = AssistantCardRows.remaining(made, in: model.assistantChanges(c.game))
                shownChanges.formUnion(left)
                guard !ended else { return }
                edit(cardID) {
                    $0.working = false
                    $0.state = .failed(([failure] + kept).joined(separator: "\n"))
                    if !left.isEmpty { $0.kind = .changes(left) }
                }
                return
            }
            shownChanges.formUnion(made)
            guard !ended else { return }
            edit(cardID) {
                $0.working = false; $0.state = .done; $0.kind = .changes(made)
                if case .picker(_, let choices) = step.action, let value {
                    $0.title = step.title + ": " + (choices.first { $0.value == value }?.label ?? value)
                }
            }
            tellApple(step, value: value, game: c.game)
        }
    }

    func install(_ cardID: UUID) {
        guard !ended, let c = card(cardID), !c.working, case .fix(let step) = c.kind, case .ready = c.state else { return }
        switch step.action {
        case .install(let component, let then):
            guard let comp = Component(rawValue: component) else { return }
            model.installComponentNow(comp)
            if then.isEmpty { tellApple(step, value: nil, game: c.game) }
        case .library(let component):
            guard let comp = Component(rawValue: component) else { return }
            model.apply(.library(comp), to: c.game)
            edit(cardID) { $0.state = .done }
            tellApple(step, value: nil, game: c.game)
        default: return
        }
    }

    func openFix(_ cardID: UUID) {
        guard !ended, let c = card(cardID), case .fix(let step) = c.kind, case .open(let target) = step.action else { return }
        switch target {
        case .desktopAndDock:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") { NSWorkspace.shared.open(url) }
        case .battery:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
        case .log:
            model.showLog(c.game, "game")
        }
        edit(cardID) { $0.state = .done }
    }

    private func undoAll(_ ids: [UUID]) -> [String] {
        var kept: [String] = []
        for id in ids.reversed() {
            do { try model.undoAssistantChange(id) } catch {
                kept.append((error as? AssistantFailure)?.message ?? error.localizedDescription)
            }
        }
        return kept
    }

    func undo(_ cardID: UUID) {
        guard !ended, let c = card(cardID), !c.working else { return }
        let ids: [UUID]
        switch c.kind {
        case .change(let id): ids = [id]
        case .changes(let list): ids = list
        case .fix: return
        }
        let kept = undoAll(ids)
        edit(cardID) { $0.state = kept.isEmpty ? .undone : .failed(kept.joined(separator: "\n")) }
    }

    func start(_ cardID: UUID) {
        guard !ended, let c = card(cardID), !c.working, c.startResult != "" else { return }
        edit(cardID) { $0.working = true; $0.startResult = nil }
        consent(.run, game: c.game)
        Task {
            let r = await model.runAssistantTool("start_game", AssistantCall(chat: chatID, args: ["game": c.game.uuidString]))
            guard !ended else { return }
            edit(cardID) { $0.working = false; $0.startResult = r.isError ? resultText(r) : "" }
        }
    }
}

#if !FERRY_RELEASE
extension AssistantDebug {
    @MainActor static func runCardCheck(_ args: [String]) -> Never {
        guard let name = args.first else {
            print("Usage: Ferry --assistant-card-check \"<game>\"")
            exit(1)
        }
        if otherFerryOpen {
            print("Ferry is open. Quit Ferry first: --assistant-card-check changes a setting and saves Ferry's library, and must not while Ferry has it open.")
            exit(1)
        }
        running = true
        let model = AppModel(libraryOnly: ())
        func spin(_ seconds: Double) {
            let until = Date(timeIntervalSinceNow: seconds)
            while Date() < until { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
        }
        guard let g = try? model.assistantGame(AssistantCall(chat: UUID(), args: ["game": name])), let entry = SettingsCatalog.entry("fullMemory32") else {
            print("No such game, or no fullMemory32 setting.")
            exit(1)
        }
        let original = entry.get(g.settings)
        let flipped = original.text == "on" ? "off" : "on"
        let session = AssistantChatSession(model: model, gameID: g.id)
        func add(_ changes: [SettingChange]) -> UUID {
            let id = UUID()
            let step = FixStep(id: "check", title: "check", detail: "Checking the card.", action: .settings(changes), button: "Turn On", inEffect: false)
            session.items.append(.card(id: id, session.fixCard(step, game: g.id, reply: "Checking the card.")))
            return id
        }
        var cardID = add([SettingChange(key: "fullMemory32", value: flipped)])
        func state() -> String {
            guard case .card(_, let c)? = session.items.first(where: { $0.id == cardID }) else { return "no card" }
            switch c.state {
            case .ready: return "ready"
            case .done: return "done"
            case .undone: return "undone"
            case .failed(let why): return "failed: \(why)"
            }
        }
        func value() -> String { model.game(g.id).map { entry.get($0.settings).text } ?? "?" }
        session.apply(cardID)
        spin(1.5)
        print("after Apply: \(state())")
        if let c = model.assistantChanges(g.id).last { print("newest change: \(model.assistantChangeSummary(c, game: g)) (\(c.reason))") }
        session.undo(cardID)
        spin(0.5)
        print("after Undo: \(state()); fullMemory32 = \(value()) (was \(original.text))")
        cardID = add([SettingChange(key: "fullMemory32", value: flipped), SettingChange(key: "noSuchSetting", value: "on")])
        session.apply(cardID)
        spin(1.5)
        print("after a failing Apply: \(state()); fullMemory32 = \(value()) (was \(original.text))")
        exit(0)
    }
}
#endif
