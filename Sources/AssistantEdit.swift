import Foundation

extension AppModel {
    static let assistantEditTools: [AssistantTool] = [
        AssistantTool("set_setting", "Changes one of a game's Ferry settings, by its key from game_details, with the same rules as Ferry's settings window: a greyed-out setting says what it needs instead of changing. The person sees the reason in the game's settings, where they can undo it.",
                      kind: .change, args: ["game": gameArg, "key": ("string", "The setting's key, from game_details."),
                                            "value": ("string", "The new value: one of the setting's values or their labels from game_details, or on/off."),
                                            "reason": reasonArg],
                      required: ["game", "key", "value", "reason"]) { m, c in try m.assistantSetSetting(c) },
        AssistantTool("set_environment", "Replaces a game's environment variables (Settings ▸ Compatibility), passed to Wine and its graphics layers when it starts. Give them all, as NAME=value, one per line; empty clears them. game_details shows the current ones.",
                      kind: .change, args: ["game": gameArg, "value": ("string", "Every variable, as NAME=value, one per line."), "reason": reasonArg],
                      required: ["game", "value", "reason"]) { m, c in try m.assistantSetText(c, environment: true) },
        AssistantTool("set_arguments", "Replaces a game's launch arguments (Settings ▸ Compatibility), such as -windowed, passed to the program when it starts. Give them all; empty clears them. game_details shows the current ones.",
                      kind: .change, args: ["game": gameArg, "value": ("string", "Every argument, separated by spaces."), "reason": reasonArg],
                      required: ["game", "value", "reason"]) { m, c in try m.assistantSetText(c, environment: false) },
        AssistantTool("edit_config_file", "Edits one of a game's text settings files (up to 64 KB), a path as read_config_file takes it: give the whole new content, or find (text that is in the file exactly once) and replace. Ferry backs the file up first and returns what changed. Save files, files Ferry doesn't recognise as settings, and files in the Mac's own folders (Documents…) change only if the person allows it, asked every time.",
                      kind: .editConfig, args: ["game": gameArg, "path": ("string", "The file's path, as list_config_files gives it."),
                                                "content": ("string", "The file's whole new content. Leave out when using find and replace."),
                                                "find": ("string", "Text to change, exactly as it is in the file, found once."),
                                                "replace": ("string", "What to put instead of find; empty removes it."),
                                                "reason": reasonArg],
                      required: ["game", "path", "reason"]) { m, c in try await m.assistantEditConfigFile(c) },
        AssistantTool("undo", "Undoes this chat's changes to a game: scope last (the most recent, the default) or chat (all of them, newest first). A setting or config file changed since the assistant changed it is left as it is.",
                      kind: .change, args: ["game": gameArg, "scope": ("string", "last or chat.")],
                      required: ["game"]) { m, c in try await m.assistantUndo(c) },
        AssistantTool("new_chat", "Starts a new chat when the person moves on to another problem: Ferry forgets what they allowed so far and asks again.",
                      kind: nil) { m, c in m.assistantNewChat(c) },
    ]

    private static let reasonArg = (type: "string", about: "Why, in a short plain sentence; the person sees it in the game's settings.")

    func assistantChangeLogURL(_ game: UUID) -> URL { bottleURL(game).appendingPathComponent("assistant/changes.json") }

    func assistantChanges(_ game: UUID) -> [AssistantChange] { AssistantChangeLog(url: assistantChangeLogURL(game)).changes }

    func assistantChangeSummary(_ change: AssistantChange, game g: Game) -> String {
        let ctx = settingContext(g)
        func shown(_ s: String) -> String { s.isEmpty ? "(none)" : s.replacingOccurrences(of: "\n", with: ", ") }
        switch change.what {
        case .setting(let key, let old, let new):
            guard let e = SettingsCatalog.entry(key) else { return "\(key): \(old) → \(new)" }
            return "\(ctx.title(key)): \(AssistantEdits.label(old, choices: e.choices)) → \(AssistantEdits.label(new, choices: e.choices))"
        case .environment(let old, let new): return "\(ctx.title("extraEnv")): \(shown(old)) → \(shown(new))"
        case .arguments(let old, let new): return "\(ctx.title("arguments")): \(shown(old)) → \(shown(new))"
        case .configFile(let path, _, _): return shownConfigPath(path, g) + ": edited"
        }
    }

    private func shownConfigPath(_ path: String, _ g: Game) -> String {
        let roots = configRoots(g)
        for (root, shownAs) in [(roots.game, ""), (roots.users, "C:/users/"), (roots.saves, "C:/users/\(NSUserName())/")] {
            let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            if path.hasPrefix(base) { return scrubbed(shownAs + path.dropFirst(base.count)) }
        }
        return scrubbed(path)
    }

    private func reason(_ c: AssistantCall) throws -> String {
        guard let r = string(c, "reason") else {
            throw AssistantFailure("Say why, in a short plain sentence (reason): the person sees it in the game's settings.")
        }
        return r
    }

    private func record(_ what: AssistantChange.What, game: UUID, chat: UUID, reason: String, group: UUID? = nil) throws {
        var log = AssistantChangeLog(url: assistantChangeLogURL(game))
        try log.record(AssistantChange(id: UUID(), game: game, chat: chat, date: Date(), reason: reason, what: what, group: group))
        assistantChangeRevision += 1
    }

    private func changed(_ text: String, _ g: Game) -> String {
        text + " To undo: undo, or \(g.name)'s settings ▸ Changes by the assistant."
            + (running.contains(g.id) ? " Takes effect next time \(g.name) starts." : "")
    }

    func assistantSetSetting(_ c: AssistantCall) throws -> String {
        var g = try assistantGame(c)
        guard let key = string(c, "key") else { throw AssistantFailure("Say which setting (key), as game_details gives it.") }
        guard let entry = SettingsCatalog.entry(key) else { throw AssistantFailure("Ferry has no setting \(key). game_details lists them.") }
        if key == "arguments" { throw AssistantFailure("Launch arguments change with set_arguments.") }
        if key == "extraEnv" { throw AssistantFailure("Environment variables change with set_environment.") }
        let ctx = settingContext(g)
        guard entry.appliesTo(ctx) else { throw AssistantFailure("Not a setting for this game.") }
        let text: String
        switch c.args["value"] {
        case let s as String: text = s
        case let n as NSNumber: text = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "on" : "off") : n.stringValue
        default: throw AssistantFailure("Say the new value (value).")
        }
        let reason = try reason(c)
        let title = ctx.title(key)
        let old = entry.get(g.settings)
        let new = try AssistantEdits.value(text, for: entry, title: title, like: old)
        if key == "engine", case .string(let id) = new, let e = EngineID(rawValue: id), e != .auto, !e.runtime.availableHere {
            throw AssistantFailure("\(e.title) can't run on this Mac.")
        }
        func label(_ v: SettingValue) -> String { AssistantEdits.label(v.text, choices: entry.choices) }
        guard new != old else { return "\(title) is already \(label(old)) for \(g.name). Nothing changed." }
        if let needs = AssistantEdits.blocked(key: key, needs: entry.needs(ctx), from: old, to: new) { throw AssistantFailure(ctx.fill(needs)) }
        var after = g.settings
        entry.set(&after, new)
        let alsoMoved = SettingsCatalog.all.filter { $0.key != key && $0.get(g.settings) != $0.get(after) }
        let group = alsoMoved.isEmpty ? nil : UUID()
        for e in alsoMoved {
            try record(.setting(key: e.key, old: e.get(g.settings).text, new: e.get(after).text), game: g.id, chat: c.chat, reason: reason, group: group)
        }
        try record(.setting(key: key, old: old.text, new: new.text), game: g.id, chat: c.chat, reason: reason, group: group)
        g.settings = after
        update(g)
        var out = "Changed \(title) for \(g.name) from \(label(old)) to \(label(new))."
        for e in alsoMoved {
            out += " Also turned \(e.get(after) == .bool(false) ? "off" : "on") \(ctx.title(e.key)), as the settings window does."
        }
        return changed(out, g)
    }

    func assistantSetText(_ c: AssistantCall, environment: Bool) throws -> String {
        var g = try assistantGame(c)
        let key = environment ? "extraEnv" : "arguments"
        guard let raw = c.args["value"] as? String else {
            throw AssistantFailure("Say the new \(environment ? "variables" : "arguments") (value); empty clears them.")
        }
        let reason = try reason(c)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = environment ? EnvText.text(EnvText.pairs(trimmed)) : trimmed
        if environment, !trimmed.isEmpty, new.isEmpty { throw AssistantFailure("Write each variable as NAME=value, one per line.") }
        if environment, let why = AssistantEdits.refusedVariables(EnvText.pairs(trimmed).map(\.key)) { throw AssistantFailure(why) }
        let old = environment ? g.settings.extraEnv : g.settings.arguments
        let title = settingContext(g).title(key)
        func shown(_ s: String) -> String { s.isEmpty ? "nothing" : s.replacingOccurrences(of: "\n", with: ", ") }
        guard new != old else { return "\(title) for \(g.name) are already \(shown(old)). Nothing changed." }
        try record(environment ? .environment(old: old, new: new) : .arguments(old: old, new: new), game: g.id, chat: c.chat, reason: reason)
        if environment { g.settings.extraEnv = new } else { g.settings.arguments = new }
        update(g)
        return changed("Set \(g.name)'s \(title.lowercased()) to \(shown(new)) (were \(shown(old))).", g)
    }

    private func alwaysAsk(changing url: URL, asked: String?, _ g: Game) -> AlwaysAsk? {
        let roots = configRoots(g), home = NSHomeDirectory()
        for root in [roots.game, roots.users, roots.saves] where !AssistantLookup.isPersonalFolder(root, home: home) {
            let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            guard url.path.hasPrefix(base) else { continue }
            return AssistantEdits.treatedAsSave([String(url.path.dropFirst(base.count))] + (asked.map { [$0] } ?? [])) ? .saveFile : nil
        }
        return .outside
    }

    private func replaceFile(_ url: URL, with data: Data) throws {
        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        try data.write(to: url, options: .atomic)
        if let permissions { try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
    }

    func assistantEditConfigFile(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        guard let asked = string(c, "path") else { throw AssistantFailure("Say which file (path), as list_config_files gives it.") }
        let reason = try reason(c)
        let content = c.args["content"] as? String, find = c.args["find"] as? String, replace = c.args["replace"] as? String
        guard (content == nil) != (find == nil) else {
            throw AssistantFailure("Give the file's whole new content, or find and replace: one of the two.")
        }
        if find != nil && replace == nil { throw AssistantFailure("Say what to put instead (replace); empty removes the text.") }
        if asked.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains(where: { $0.hasPrefix(".") }) {
            throw AssistantFailure("Ferry doesn't edit hidden files, or paths with . or .. in them.")
        }
        let roots = configRoots(g)
        let path = AssistantLookup.requestedPath(asked, gameFolder: roots.game.path, driveC: roots.driveC.path,
                                                 home: NSHomeDirectory(), user: NSUserName())
        let url: URL
        switch AssistantLookup.access(path, roots: [roots.game, roots.users, roots.saves], userFolders: roots.users, home: NSHomeDirectory()) {
        case .inside(let u), .linkedOutside(let u): url = u
        case .refused: throw AssistantFailure("Ferry only edits files in \(g.name)'s folder and its Windows user folders (C:/users/user/…).")
        }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            throw AssistantFailure("There's no file at \(asked). list_config_files lists them.")
        }
        let limit = 64 * 1024
        let size = fm.byteSize(url)
        guard size <= limit else { throw AssistantFailure("\(asked) is \(size / 1024) KB; Ferry edits files up to 64 KB.") }
        guard let data = try? Data(contentsOf: url) else { throw AssistantFailure("Ferry couldn't read \(asked).") }
        guard let file = AssistantEdits.TextFile(data: data) else { throw AssistantFailure("\(asked) isn't a text file; Ferry edits only text files.") }
        let hidden = AssistantText.scrub(file.text, home: NSHomeDirectory(), user: NSUserName(), gameFolder: gameFolders(g).root.path) != file.text
        let newText = try AssistantEdits.editedText(file.text, content: content, find: find, replace: replace, hidden: hidden)
        guard newText != file.text else { return "\(asked) already says that. Nothing changed." }
        guard let newData = file.data(newText) else { throw AssistantFailure("The new text has characters \(asked)'s encoding can't hold.") }
        guard newData.count <= limit else { throw AssistantFailure("\(asked) would be over 64 KB; Ferry edits files up to 64 KB.") }
        let diff = AssistantLookup.clipped(AssistantEdits.unifiedDiff(old: file.text, new: newText, name: asked), maxChars: 12_000)

        if let always = alwaysAsk(changing: url, asked: asked, g) {
            let chat = assistantChats[c.chat] ?? AssistantChat(id: c.chat, client: "")
            let place = always == .outside ? "\(scrubbed(url.path)), in the Mac's own folders" : "\(asked), which may be a save file"
            guard await askAssistantPermission(chat: chat, kind: .editConfig, always: always, game: g, detail: "change \(place):\n\(diff)") else {
                throw AssistantFailure(AssistantPrompts.refused)
            }
            guard (try? Data(contentsOf: url)) == data else { throw AssistantFailure("\(asked) changed while Ferry was asking. Read it again first.") }
        }

        let backups = bottleURL(g.id).appendingPathComponent("assistant/backups", isDirectory: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        let backup = backups.appendingPathComponent(AssistantEdits.backupName(url.lastPathComponent, date: Date()))
        try data.write(to: backup, options: .atomic)
        try replaceFile(url, with: newData)
        do {
            try record(.configFile(path: url.path, backup: backup.path, hash: AssistantEdits.sha256(newData)), game: g.id, chat: c.chat, reason: reason)
        } catch {
            try? replaceFile(url, with: data)
            throw error
        }
        return changed("Edited \(asked) for \(g.name); the file as it was is backed up.", g) + "\n" + diff
    }

    private func revert(_ plan: [AssistantChange], game id: UUID) throws -> (undone: [String], kept: [String]) {
        guard var g = game(id) else { throw AssistantFailure("That game isn't in the library anymore.") }
        var done: [UUID] = [], undone: [String] = [], kept: [String] = [], settingsChanged = false
        var handled = Set<UUID>()
        for change in plan where !handled.contains(change.id) {
            let unit = change.group.map { gid in plan.filter { $0.group == gid } } ?? [change]
            handled.formUnion(unit.map(\.id))
            let summary = unit.map { assistantChangeSummary($0, game: g) }.joined(separator: "; ")
            switch change.what {
            case .setting, .environment, .arguments:
                switch AssistantEdits.revertSettings(unit, in: &g.settings) {
                case .changedSince?:
                    kept.append("\(summary): changed since the assistant set \(unit.count > 1 ? "them" : "it"), so Ferry left \(unit.count > 1 ? "them" : "it") as \(unit.count > 1 ? "they are" : "it is").")
                    continue
                case .unknownSetting?: kept.append("\(summary): Ferry no longer has this setting."); continue
                case nil: settingsChanged = true
                }
            case .configFile(let path, let backup, let hash):
                let url = URL(fileURLWithPath: path), name = url.lastPathComponent
                guard AssistantEdits.mayRestore(current: try? Data(contentsOf: url), written: hash) else {
                    kept.append("\(name) has changed since the assistant edited it, so Ferry left it as it is. The file from before the edit is kept at \(backup).")
                    continue
                }
                guard let old = try? Data(contentsOf: URL(fileURLWithPath: backup)) else {
                    kept.append("The backup of \(name) is gone, so Ferry can't put it back."); continue
                }
                do { try replaceFile(url, with: old) } catch { kept.append("Ferry couldn't put \(name) back: \(error.localizedDescription)"); continue }
            }
            done += unit.map(\.id)
            undone.append(summary)
        }
        if settingsChanged { update(g) }
        var log = AssistantChangeLog(url: assistantChangeLogURL(id))
        try log.remove(done)
        assistantChangeRevision += 1
        return (undone, kept)
    }

    func assistantUndo(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        let scope = string(c, "scope")?.lowercased() ?? "last"
        guard scope == "last" || scope == "chat" else { throw AssistantFailure("scope is last or chat.") }
        let log = AssistantChangeLog(url: assistantChangeLogURL(g.id))
        let plan = log.undoPlan(chat: c.chat)
        let picked = scope == "last" ? plan.first.map(log.together) ?? [] : plan
        guard !picked.isEmpty else {
            return "This chat hasn't changed anything for \(g.name). The person can undo earlier changes in \(g.name)'s settings ▸ Changes by the assistant."
        }
        for change in picked {
            guard case .configFile(let path, _, _) = change.what else { continue }
            let url = URL(fileURLWithPath: path)
            guard let always = alwaysAsk(changing: url, asked: nil, g) else { continue }
            let chat = assistantChats[c.chat] ?? AssistantChat(id: c.chat, client: "")
            guard await askAssistantPermission(chat: chat, kind: .editConfig, always: always, game: g,
                                               detail: "put \(shownConfigPath(path, g)) back as it was before the assistant edited it") else {
                throw AssistantFailure(AssistantPrompts.refused)
            }
        }
        let r = try revert(picked, game: g.id)
        guard !r.undone.isEmpty else { throw AssistantFailure(r.kept.joined(separator: "\n")) }
        var out = ["Undid for \(g.name):"] + r.undone.map { "- " + $0 } + r.kept
        if running.contains(g.id) { out.append("Takes effect next time \(g.name) starts.") }
        return out.joined(separator: "\n")
    }

    func assistantNewChat(_ c: AssistantCall) -> String {
        assistantChats[c.chat]?.permissions = AssistantPermissions()
        return "New chat started: Ferry asks the person again before reading or changing anything. Changes so far stay in each game's settings ▸ Changes by the assistant."
    }

    func undoAssistantChange(_ id: UUID) throws {
        for g in games {
            let log = AssistantChangeLog(url: assistantChangeLogURL(g.id))
            guard let change = log.changes.first(where: { $0.id == id }) else { continue }
            let r = try revert(log.together(change), game: g.id)
            if !r.kept.isEmpty { throw AssistantFailure(r.kept.joined(separator: "\n")) }
            return
        }
    }

    func undoAllAssistantChanges(game: UUID) throws {
        let r = try revert(assistantChanges(game).reversed(), game: game)
        if !r.kept.isEmpty { throw AssistantFailure(r.kept.joined(separator: "\n")) }
    }
}
