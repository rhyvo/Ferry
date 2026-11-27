import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AssistantHandoff {
    enum Ask { case installMod(ModResult), removeGame }

    let id = UUID()
    let game: UUID
    let ask: Ask
    var taken = false
    private(set) var answer: String?

    init(game: UUID, ask: Ask) {
        self.game = game
        self.ask = ask
    }

    func finish(_ text: String) { if answer == nil { answer = text } }
}

extension AppModel {
    static let assistantRunTools: [AssistantTool] = [
        AssistantTool("start_game", "Starts a game as its Play button does, without waiting for it: wait_for_game with until: started says when it is running or why it couldn't start. If starting would first download anything (an engine, Windows libraries, .NET parts), Ferry asks the person before, naming each.",
                      kind: .run, args: ["game": gameArg], required: ["game"]) { m, c in try await m.assistantStartGame(c) },
        AssistantTool("stop_game", "Stops a running game, as its Stop button does.",
                      kind: .run, args: ["game": gameArg], required: ["game"]) { m, c in try await m.assistantStopGame(c) },
        AssistantTool("wait_for_game", "Waits until a game has started (until: started), has exited (exited) or has crashed (crash), for at most timeout seconds (default 120, at most 600). Says how it ended and gives the log's lines that matter.",
                      kind: .run, args: ["game": gameArg, "until": ("string", "started, exited or crash."),
                                         "timeout": ("number", "Optional: seconds to wait, at most 600.")],
                      required: ["game", "until"]) { m, c in try await m.assistantWaitForGame(c) },
        AssistantTool(name: "screenshot", description: "Takes a picture of a game's window (which: game, the default) or of Ferry's own window (which: ferry). Needs Screen Recording permission for Ferry.",
                      schema: ["type": "object", "required": ["game"], "properties": [
                        "game": ["type": gameArg.type, "description": gameArg.about],
                        "which": ["type": "string", "description": "game (default) or ferry."]]],
                      kind: .run) { m, c in await m.assistantScreenshot(c) },
        AssistantTool("open_window", "Opens one of Ferry's windows for the person to look at: a game's settings, troubleshoot, mods, or its log. Only for showing the person; act with the other actions.",
                      kind: .run, args: ["game": gameArg, "which": ("string", "settings, troubleshoot, mods or log.")],
                      required: ["game", "which"]) { m, c in try m.assistantOpenWindow(c) },
        AssistantTool("open_system_settings", "Opens a System Settings pane for the person: battery (Low Power Mode), desktop-dock (window tiling, Stage Manager) or privacy (Screen Recording, which screenshots need). Ferry can't change Mac settings: tell the person what to change there.",
                      kind: nil, args: ["pane": ("string", "battery, desktop-dock or privacy.")], required: ["pane"]) { m, c in try m.assistantOpenSystemSettings(c) },
        AssistantTool("install_component", "Downloads and installs one of Ferry's components (Settings ▸ Components): engines, Windows libraries and fixes, by name as engines_and_components lists them. Ferry asks the person every time, naming it and its size.",
                      kind: nil, args: ["name": ("string", "The component's name, like DXVK or PhysX.")], required: ["name"]) { m, c in try await m.assistantInstallComponent(c) },
        AssistantTool("install_mod", "Installs a mod or fix that search_mods found (result: its id). Ferry asks the person before downloading it, then shows them exactly what it would change; nothing is installed unless they confirm.",
                      kind: nil, args: ["game": gameArg, "result": ("string", "The result's id from search_mods, like pcgw-0.")],
                      required: ["game", "result"]) { m, c in try await m.assistantInstallMod(c) },
        AssistantTool("remove_mod", "Removes a mod Ferry installed for a game, putting back the files it replaced. Ferry asks the person every time.",
                      kind: nil, args: ["game": gameArg, "mod": ("string", "The installed mod's name (or a unique part of it).")],
                      required: ["game", "mod"]) { m, c in try await m.assistantRemoveMod(c) },
        AssistantTool("delete_game", "Asks the person, in Ferry's own Remove confirmation, whether to remove a game from Ferry. They choose there whether its Windows environment and saves are deleted too; the game's own files are never touched.",
                      kind: nil, args: ["game": gameArg], required: ["game"]) { m, c in try await m.assistantDeleteGame(c) },
    ]

    private func poll<T>(seconds: Double, _ done: () -> T?) async -> T? {
        let end = Date().addingTimeInterval(seconds)
        while true {
            if let r = done() { return r }
            if Date() >= end || Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func askAlways(_ c: AssistantCall, _ always: AlwaysAsk, game: Game?, detail: String) async -> Bool {
        let chat = assistantChats[c.chat] ?? AssistantChat(id: c.chat, client: "")
        return await askAssistantPermission(chat: chat, kind: .run, always: always, game: game, detail: detail)
    }

    func assistantStartGame(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        if running.contains(g.id) { return "\(g.name) is already running." }
        if preparing.contains(g.id) { return "\(g.name) is already starting. wait_for_game with until: started waits for it." }
        let downloads = pendingDownloads(g.id)
        if !downloads.isEmpty {
            guard await askAlways(c, .download, game: g, detail: "download " + downloads.joined(separator: ", ") + " to start \(g.name)") else {
                throw AssistantFailure(AssistantPrompts.refused)
            }
        }
        try startGameInBackground(g.id)
        return "Starting \(g.name)… Use wait_for_game with until: started to know when it's running."
    }

    func assistantStopGame(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        guard running.contains(g.id) else {
            if preparing.contains(g.id) {
                throw AssistantFailure("\(g.name) is still getting ready, which Ferry can't stop partway. Wait for it to start (wait_for_game), then stop it.")
            }
            return "\(g.name) isn't running."
        }
        stop(g.id)
        if await poll(seconds: 15, { running.contains(g.id) ? nil : true }) != nil { return "Stopped \(g.name)." }
        return "Ferry asked \(g.name) to stop; it is still closing."
    }

    func assistantWaitForGame(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        guard let until = string(c, "until").flatMap({ AssistantRuns.Until(rawValue: $0.lowercased()) }) else {
            throw AssistantFailure("until is started, exited or crash.")
        }
        let timeout = AssistantRuns.timeout(c.args["timeout"])
        let began = Date(), log = logURL(g.id, "game")
        var outcome: AssistantRuns.WaitOutcome? = nil, crashInLog = false, looks = 0
        while true {
            let ended = lastEnded[g.id].flatMap { $0.at >= began ? $0 : nil }
            outcome = AssistantRuns.waitOutcome(until, running: running.contains(g.id), preparing: preparing.contains(g.id),
                                                ended: ended, crashInLog: crashInLog, startFailure: startFailures[g.id])
            if outcome != nil || Date().timeIntervalSince(began) >= Double(timeout) || Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
            looks += 1
            if until == .crash && looks % 4 == 0 && running.contains(g.id) {
                crashInLog = await Task.detached { AssistantRuns.crashReported(LogDoctor.read(log)) }.value
            }
        }
        var head: String
        switch outcome {
        case .started?: head = "\(g.name) has started."
        case .ended(let e)?: head = "\(g.name) \(AssistantRuns.describe(e))."
        case .crashedRunning?: head = "\(g.name) crashed: Windows reported it in the log, and it is still open (probably showing a crash message)."
        case .startFailed(let why)?: head = "\(g.name) couldn't start: \(why)"
        case .notStarting?: head = "\(g.name) isn't running or starting. start_game starts it."
        case .notRunning?:
            head = "\(g.name) isn't running." + (lastEnded[g.id].map { " Its last run \(AssistantRuns.describe($0))." } ?? "")
        case nil:
            head = preparing.contains(g.id) ? "\(g.name) is still getting ready after \(timeout) seconds" + (status.map { " (\($0))" } ?? "") + "."
                : running.contains(g.id) ? "\(g.name) is still running after \(timeout) seconds." : "Nothing changed in \(timeout) seconds."
        }
        let text = await Task.detached { LogDoctor.read(log) }.value
        guard !text.isEmpty else { return head }
        return head + "\n\nThe game log's lines that matter:\n" + AssistantText.focusLog(text, search: nil, maxLines: 40)
    }
}

extension AppModel {
    func assistantScreenshot(_ c: AssistantCall) async -> AssistantResult {
        do {
            let g = try assistantGame(c)
            let which = string(c, "which")?.lowercased() ?? "game"
            guard which == "game" || which == "ferry" else { throw AssistantFailure("which is game or ferry.") }
            guard CGPreflightScreenCaptureAccess() else {
                if let pane = AssistantRuns.settingsPane("privacy"), let url = URL(string: pane.url) { NSWorkspace.shared.open(url) }
                throw AssistantFailure("Ferry needs Screen Recording permission for screenshots: System Settings ▸ Privacy & Security ▸ Screen Recording.")
            }
            let pids: Set<Int32>
            if which == "ferry" {
                pids = [ProcessInfo.processInfo.processIdentifier]
            } else {
                guard running.contains(g.id) else { throw AssistantFailure("\(g.name) isn't running, so it has no window. start_game starts it.") }
                pids = Set(await Self.programsRunning(from: g))
            }
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
            guard let window = AssistantRuns.pickWindow(AssistantRuns.windows(from: list), pids: pids) else {
                throw AssistantFailure(which == "ferry" ? "Ferry has no window on screen."
                    : "\(g.name) has no window on screen yet: it may still be loading, minimised, or on another Space.")
            }
            let png = try await Self.capture(window: window)
            return AssistantResult(content: [.text(which == "ferry" ? "Ferry's window:" : "\(g.name)'s window:"), .image(png: png)], isError: false)
        } catch let f as AssistantFailure {
            return .error(f.message)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func capture(window: Int) async throws -> Data {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ferry-screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let (code, _) = await Shell.capture("/usr/sbin/screencapture", ["-x", "-o", "-l", "\(window)", file.path])
        guard code == 0, let data = try? Data(contentsOf: file), !data.isEmpty else {
            throw AssistantFailure("macOS couldn't take the screenshot. The window may have just closed.")
        }
        return scaledPNG(data)
    }

    static func scaledPNG(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let side = AssistantRuns.scaledLongestSide(width: w, height: h),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                  kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return data }
        CGImageDestinationAddImage(dest, small, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : data
    }

    private func otherSheet(than which: String, game: UUID) -> String? {
        func name(_ id: UUID) -> String { self.game(id)?.name ?? "a game" }
        if let s = settingsGame, !(which == "settings" && s == game) { return "\(name(s))'s Settings" }
        if let t = troubleshootGame, !(which == "troubleshoot" && t == game) { return "Troubleshoot for \(name(t))" }
        if let m = modsGame, !(which == "mods" && m == game) { return "Mods for \(name(m))" }
        return showStorage ? "Storage" : nil
    }

    func assistantOpenWindow(_ c: AssistantCall) throws -> String {
        let g = try assistantGame(c)
        let which = string(c, "which")?.lowercased() ?? ""
        guard ["settings", "troubleshoot", "mods", "log"].contains(which) else { throw AssistantFailure("which is settings, troubleshoot, mods or log.") }
        if which == "log" {
            guard fm.exists(logURL(g.id, "game")) else { throw AssistantFailure("\(g.name) has no log yet: Ferry writes one each time it starts.") }
            showLog(g.id, "game")
            return "Opened \(g.name)'s log for the person."
        }
        if let open = otherSheet(than: which, game: g.id) {
            throw AssistantFailure("Ferry has \(open) open. The person needs to close it first; Ferry shows one of these windows at a time.")
        }
        switch which {
        case "settings": settingsGame = g.id
        case "troubleshoot": troubleshootGame = g.id
        default: modsGame = g.id
        }
        return "Opened \(g.name)'s \(which == "settings" ? "settings" : which == "mods" ? "Mods window" : "Troubleshoot window") in Ferry for the person."
    }

    func assistantOpenSystemSettings(_ c: AssistantCall) throws -> String {
        guard let asked = string(c, "pane"), let pane = AssistantRuns.settingsPane(asked), let url = URL(string: pane.url) else {
            throw AssistantFailure("pane is battery, desktop-dock or privacy.")
        }
        NSWorkspace.shared.open(url)
        return "Opened \(pane.title) for the person. Ferry can't change it: tell them what to change there."
    }
}

extension AppModel {
    func assistantInstallComponent(_ c: AssistantCall) async throws -> String {
        guard let asked = string(c, "name") else { throw AssistantFailure("Say which component (name), as engines_and_components lists it.") }
        let optional = Component.allCases.filter { $0.tier != .required }
        let q = AssistantLookup.normalized(asked)
        let found = optional.filter { AssistantLookup.normalized($0.title) == q || $0.rawValue.lowercased() == asked.lowercased() }
        let containing = optional.filter { AssistantLookup.normalized($0.title).contains(q) }
        guard let comp = found.first ?? (containing.count == 1 ? containing[0] : nil) else {
            throw AssistantFailure((containing.count > 1 ? "More than one component fits “\(asked)”. " : "No component called “\(asked)”. ")
                                   + "Components: " + optional.map(\.title).joined(separator: "; ") + ".")
        }
        if componentStatus[comp]?.installed == true { return "\(comp.title) is already installed." }
        if let busy = installingComponent { throw AssistantFailure("Ferry is installing \(busy.title) now. Try again when it's done.") }
        guard !setupRunning, !updating else { throw AssistantFailure("Ferry is setting up or installing updates. Try again when it's done.") }
        let size = comp.approxBytes > 0 ? " (about \(max(1, comp.approxBytes / 1_000_000)) MB)" : ""
        guard await askAlways(c, .download, game: nil, detail: "download and install \(comp.title)\(size)") else {
            throw AssistantFailure(AssistantPrompts.refused)
        }
        let shown = errorMessage
        installComponentNow(comp)
        guard installingComponent == comp else { throw AssistantFailure("Ferry couldn't start installing \(comp.title).") }
        _ = await poll(seconds: 60 * 60) { installingComponent == comp ? nil : true }
        if installingComponent == comp { return "\(comp.title) is still installing after an hour; Settings ▸ Components shows how it's going." }
        if componentStatus[comp]?.installed == true { return "Installed \(comp.title)." }
        let why = errorMessage != shown ? errorMessage : nil
        throw AssistantFailure("\(comp.title) didn't install." + (why.map { " \($0)" } ?? ""))
    }

    private func handOff(_ h: AssistantHandoff, open: () -> Void, giveUp: () -> Void) async throws -> String {
        assistantHandoff = h
        defer { if assistantHandoff === h { assistantHandoff = nil } }
        open()
        guard await poll(seconds: 15, { h.taken ? true : nil }) != nil else {
            giveUp()
            throw AssistantFailure("Ferry couldn't show its window for this. Ferry's main window has to be open.")
        }
        guard let answer = await poll(seconds: 15 * 60, { h.answer }) else {
            throw AssistantFailure("The person hasn't decided after 15 minutes. Ask them in plain words whether they still want this.")
        }
        return answer
    }

    func assistantInstallMod(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        guard let id = string(c, "result") else { throw AssistantFailure("Say which result (result), by the id search_mods gave.") }
        guard let r = assistantChats[c.chat]?.modResults[g.id]?.first(where: { $0.id == id }) else {
            throw AssistantFailure("No search_mods result \(id) for \(g.name) in this chat. Search with search_mods first, then use one of its ids.")
        }
        guard r.canAutoInstall else {
            throw AssistantFailure(r.steps > 1
                ? "“\(r.title)” has several steps, so Ferry can't install it in one go. Walk the person through its steps instead."
                : "“\(r.title)” can only be downloaded from its web page, so Ferry can't install it. The person can use Install Manually in Ferry's Mods window.")
        }
        if let busy = modBlocker(g) { throw AssistantFailure(modBlockerReason(busy)) }
        if let open = otherSheet(than: "mods", game: g.id) {
            throw AssistantFailure("Ferry has \(open) open. The person needs to close it first; the mod's confirmation shows in the Mods window.")
        }
        let from: String
        switch r.link {
        case .githubRepo(let owner, let repo): from = "github.com/\(owner)/\(repo)"
        case .directFile(let u), .webPage(let u): from = u.host ?? u.absoluteString
        case nil: from = "the web"
        }
        guard await askAlways(c, .download, game: g, detail: "download the mod “\(AssistantPrompts.oneLine(r.title))” from \(from)"
                              + (r.reviewed ? "" : " (not reviewed by PCGamingWiki)")
                              + " for \(g.name).\nFerry then shows what it would change, and installs nothing unless you confirm.") else {
            throw AssistantFailure(AssistantPrompts.refused)
        }
        let wasOpen = modsGame == g.id
        return try await handOff(AssistantHandoff(game: g.id, ask: .installMod(r)), open: { modsGame = g.id },
                                 giveUp: { if !wasOpen, modsGame == g.id { modsGame = nil } })
    }

    func assistantRemoveMod(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        guard !g.mods.isEmpty else { return "\(g.name) has no mods installed by Ferry." }
        guard let asked = string(c, "mod") else { throw AssistantFailure("Say which mod (mod). Installed: \(g.mods.map(\.name).joined(separator: "; ")).") }
        let mod: InstalledMod
        switch AssistantLookup.matchGame(asked, in: g.mods.map { ($0.id, $0.name) }) {
        case .one(let id): mod = g.mods.first { $0.id == id }!
        case .ambiguous(let names): throw AssistantFailure("More than one mod fits “\(asked)”: \(names.joined(separator: "; ")). Say which one.")
        case .none: throw AssistantFailure("No mod called “\(asked)”. Installed: \(g.mods.map(\.name).joined(separator: "; ")).")
        }
        if let busy = modBlocker(g) { throw AssistantFailure(modBlockerReason(busy)) }
        guard await askAlways(c, .delete, game: g, detail: "remove the mod “\(AssistantPrompts.oneLine(mod.name))” from \(g.name), putting back the files it replaced") else {
            throw AssistantFailure(AssistantPrompts.refused)
        }
        let entry = mod.addedGameID.flatMap { game($0) }
        let result = try await removeMod(mod.id, from: g.id)
        if mod.recipe == .installer {
            return "“\(mod.name)” was taken off \(g.name)'s list. It was installed by its own installer, so Ferry can't take its files out: the person can use its own uninstaller."
        }
        let root = gameFolders(g).root
        func shown(_ paths: [String]) -> String { paths.map { modDisplayPath(URL(fileURLWithPath: $0), root: root) }.joined(separator: ", ") }
        var out = ["Removed “\(mod.name)” from \(g.name)."]
        if !result.changed.isEmpty { out.append("Left as they are, because they changed after it was installed: \(shown(result.changed)).") }
        if !result.notDeleted.isEmpty { out.append("Couldn't delete: \(shown(result.notDeleted)).") }
        if !result.notRestored.isEmpty { out.append("Couldn't put the originals back for: \(shown(result.notRestored.map(\.path))).") }
        if let entry, game(entry.id) == nil { out.append("“\(entry.name)” was taken out of the library; its Windows environment is kept.") }
        return out.joined(separator: "\n")
    }

    func assistantDeleteGame(_ c: AssistantCall) async throws -> String {
        let g = try assistantGame(c)
        if let open = otherSheet(than: "settings", game: g.id) {
            throw AssistantFailure("Ferry has \(open) open. The person needs to close it first; the Remove confirmation shows in the game's settings.")
        }
        let hadEnvironment = g.sharedWith == nil && fm.exists(bottleURL(g.id))
        let sharers = sharers(of: g.id).map(\.name)
        let wasOpen = settingsGame == g.id
        _ = try await handOff(AssistantHandoff(game: g.id, ask: .removeGame), open: { settingsGame = g.id },
                              giveUp: { if !wasOpen, settingsGame == g.id { settingsGame = nil } })
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard game(g.id) == nil else { return "The person kept \(g.name) in Ferry." }
        var out = "Removed \(g.name) from Ferry. Its own files on the Mac weren't touched."
        if hadEnvironment {
            out += fm.exists(bottleURL(g.id)) ? " Its Windows environment and saves were kept (Settings ▸ Storage can delete them later)."
                : " Its Windows environment and saves were deleted, as the person chose."
        }
        if !sharers.isEmpty { out += " Also removed, as they ran inside its environment: \(sharers.joined(separator: ", "))." }
        return out
    }
}
