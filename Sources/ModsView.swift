import AppKit
import SwiftUI

struct PendingMod: Identifiable {
    let id = UUID()
    var prep: ModPreparation
    var step = 0
    let result: ModResult?
    let ownFile: URL?

    var title: String { result?.title ?? ownFile.map { $0.deletingPathExtension().lastPathComponent } ?? "This mod" }
    var unreviewed: Bool { result.map { !$0.reviewed } ?? false }
}

func modDisplayPath(_ url: URL, root: URL) -> String {
    let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
    if p.lowercased().hasPrefix(r.lowercased() + "/") { return String(p.dropFirst(r.count + 1)) }
    return (p as NSString).abbreviatingWithTildeInPath
}

@MainActor
struct ModsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let gameID: UUID

    @StateObject private var search = ModsSearch()
    @State private var pending: PendingMod? = nil
    @State private var working: String? = nil
    @State private var notes: [String: String] = [:]
    @State private var notice: Notice? = nil
    @State private var dropTargeted = false
    @State private var removing: UUID? = nil

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private var game: Game? { model.game(gameID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mods — \(game?.name ?? "Game")").font(.title3.weight(.semibold))
                .padding([.horizontal, .top], 20).padding(.bottom, 12)
            HStack {
                TextField("Search, for example widescreen or debug menu", text: $search.query)
                    .textFieldStyle(.roundedBorder)
                Button("Search") { if let g = game { search.start(game: g) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(game == nil)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let g = game {
                        installedSection(g)
                        resultsSection(g)
                    } else {
                        Text("This game isn't in the library anymore.").foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.tint, lineWidth: 3).padding(6)
                }
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            addOwnFile(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .task { if let g = game { search.start(game: g) } }
        .onDisappear {
            search.stop()
            dropPending()
        }
        .sheet(item: Binding(get: { pending }, set: { if $0 == nil { dropPending() } })) { item in
            confirmation(item)
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
               presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { n in
            Text(n.text)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Can't find it?").foregroundStyle(.secondary)
                Button("Search the Web") {
                    NSWorkspace.shared.open(ModSearch.webSearchURL(game: game?.name ?? "", query: search.query))
                }
                Button("Add Mod File…") { chooseOwnFile() }
                    .disabled(working != nil || game == nil)
                if working == "file" { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Or drag a downloaded mod here.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private func installedSection(_ g: Game) -> some View {
        if !g.mods.isEmpty {
            Text("Installed").font(.headline)
            let busy = model.modBlocker(g)
            ForEach(g.mods) { mod in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mod.name).fontWeight(.medium)
                        Text(sourceLabel(mod.source) + (mod.recipe == .installer ? " · ran its own installer" : ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if removing == mod.id { ProgressView().controlSize(.small) }
                    Button("Remove") { remove(mod, from: g) }
                        .disabled(busy != nil || removing != nil)
                        .help(busy.map { model.modBlockerReason($0) } ?? "Take this mod out and put back what it replaced")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            }
            Divider().padding(.vertical, 4)
        }
    }

    private func sourceLabel(_ source: String) -> String {
        guard let url = URL(string: source), let host = url.host?.lowercased() else { return source }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if ModSearch.isGitHubHost(h) {
            let repo = url.path.split(separator: "/").prefix(2).joined(separator: "/")
            return repo.isEmpty ? h : "\(h)/\(repo)"
        }
        return h
    }

    private func remove(_ mod: InstalledMod, from g: Game) {
        let model = self.model
        removing = mod.id
        let entry = mod.addedGameID.flatMap { model.game($0) }
        Task {
            defer { removing = nil }
            let result: ModFiles.Removal
            do {
                result = try await model.removeMod(mod.id, from: g.id)
            } catch {
                notice = Notice(title: "Couldn't remove \(mod.name)", text: error.localizedDescription)
                return
            }
            if mod.recipe == .installer {
                notice = Notice(title: "\(mod.name) was taken off the list",
                                text: "It was installed by its own installer, so Ferry can't take its files out. Use its own uninstaller to remove it from \(g.name).")
                return
            }
            let root = model.gameFolders(g).root
            func shown(_ path: String) -> String { modDisplayPath(URL(fileURLWithPath: path), root: root) }
            var parts: [String] = []
            if !result.changed.isEmpty {
                parts.append("These files changed after it was installed (by a game update, or by you), so Ferry left them as they are:\n"
                             + result.changed.map(shown).joined(separator: "\n"))
            }
            if !result.notDeleted.isEmpty {
                parts.append("Ferry couldn't delete these files, so they're still there:\n" + result.notDeleted.map(shown).joined(separator: "\n"))
            }
            let stranded = result.notRestored.filter { $0.backup != nil }
            if !stranded.isEmpty {
                parts.append("Ferry couldn't put the original back for these files. Each original is still in Ferry's backups:\n"
                             + stranded.map { "\(shown($0.path)) (it's in \(($0.backup! as NSString).abbreviatingWithTildeInPath))" }.joined(separator: "\n"))
            }
            let lost = result.notRestored.filter { $0.backup == nil }
            if !lost.isEmpty {
                parts.append("The originals of these files were missing from Ferry's backups, so they couldn't be put back:\n"
                             + lost.map { shown($0.path) }.joined(separator: "\n"))
            }
            if parts.isEmpty { parts.append("\(g.name)'s files are back as they were before this mod.") }
            parts.append("If this mod changed settings, \(g.name) may have saved them in its own settings, so they can stay after removing it. Change them back in the game's options if anything still looks different.")
            if let entry, model.game(entry.id) == nil {
                parts.append("\"\(entry.name)\" was taken out of your library. Its Windows environment, with any saves, is kept; delete it in Settings ▸ Storage.")
            }
            notice = Notice(title: "Removed \(mod.name)", text: parts.joined(separator: "\n\n"))
        }
    }

    @ViewBuilder
    private func resultsSection(_ g: Game) -> some View {
        Text("Results").font(.headline)
        if search.searching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching…").foregroundStyle(.secondary)
            }
        } else {
            if let message = search.message {
                Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(search.results) { r in resultRow(r, g) }
        }
    }

    private func resultRow(_ r: ModResult, _ g: Game) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.title).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if r.reviewed {
                    Label("Recommended fix", systemImage: "star.fill").font(.caption).foregroundStyle(.tint)
                } else {
                    Label("Not reviewed by PCGamingWiki", systemImage: "exclamationmark.shield").font(.caption).foregroundStyle(.orange)
                }
            }
            if !r.detail.isEmpty {
                Text(r.detail).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(r.reviewed ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    resultSource(r, g)
                    if r.link != nil { Spacer(); resultInstall(r, g) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { resultSource(r, g) }
                    if r.link != nil { HStack(spacing: 8) { Spacer(); resultInstall(r, g) } }
                }
            }
            if let note = notes[r.id] {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private func resultSource(_ r: ModResult, _ g: Game) -> some View {
        if r.reviewed {
            Button("PCGamingWiki Page") { openWikiPage(g) }
        }
        if r.link != nil, let host = Self.host(of: r.link) {
            Text("from \(host)").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultInstall(_ r: ModResult, _ g: Game) -> some View {
        if working == r.id { ProgressView().controlSize(.small) }
        Button("Install Automatically") { autoInstall(r, g) }
            .disabled(!r.canAutoInstall || working != nil)
            .help(r.canAutoInstall ? "Download it, check where it goes, then confirm"
                  : r.steps > 1 ? "This fix has several steps, so Ferry can't do it in one go. Follow the steps above; \"Install Manually\" downloads its file."
                  : "This one can only be downloaded from its web page. Use \"Install Manually\".")
        Button("Install Manually") { manualInstall(r, g) }
            .disabled(working != nil)
    }

    private static func host(of link: ModLink?) -> String? {
        let host: String?
        switch link {
        case .githubRepo: return "github.com"
        case .directFile(let u), .webPage(let u): host = u.host?.lowercased()
        case nil: return nil
        }
        guard let host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func openWikiPage(_ g: Game) {
        if let page = search.wikiPage, let url = URL(string: GameWiki.Info(page: page).url) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(ModSearch.webSearchURL(game: g.name, query: "pcgamingwiki"))
        }
    }

    private func autoInstall(_ r: ModResult, _ g: Game) {
        let model = self.model, session = search
        working = r.id
        notes[r.id] = nil
        Task {
            defer { working = nil }
            do {
                let prep = try await model.downloadModResult(r, game: g)
                present(prep, result: r, ownFile: nil, session: session, model: model)
            } catch {
                if session.windowClosed { return }
                notice = Notice(title: "Couldn't get \(r.title)", text: error.localizedDescription)
            }
        }
    }

    private func manualInstall(_ r: ModResult, _ g: Game) {
        let model = self.model
        switch r.link {
        case .webPage(let url):
            NSWorkspace.shared.open(url)
        case .directFile(let url):
            working = r.id
            Task {
                defer { working = nil }
                await saveForManual(url, result: r, model: model)
            }
        case .githubRepo(let owner, let repo):
            let page = URL(string: "https://github.com/\(owner)/\(repo)") ?? URL(string: "https://github.com")!
            working = r.id
            Task {
                defer { working = nil }
                do {
                    let assets = try await GitHub.latestAssets(repo: "\(owner)/\(repo)").assets
                    switch ModSearch.pickAsset(assets.map(\.name), is64bit: model.gameFolders(g).is64bit) {
                    case .one(let name):
                        if let a = assets.first(where: { $0.name == name }), let url = URL(string: a.browserDownloadUrl) {
                            await saveForManual(url, result: r, model: model)
                            return
                        }
                        fallthrough
                    case .none:
                        NSWorkspace.shared.open(page)
                        notes[r.id] = "Its latest release has no download, so the repository opened in your browser."
                    case .ask:
                        NSWorkspace.shared.open(page)
                        notes[r.id] = "Its latest release has several downloads, so the repository opened in your browser for you to pick one."
                    }
                } catch {
                    NSWorkspace.shared.open(page)
                    notes[r.id] = error.localizedDescription + " The repository opened in your browser instead."
                }
            }
        case nil:
            openWikiPage(g)
        }
    }

    private func saveForManual(_ url: URL, result r: ModResult, model: AppModel) async {
        do {
            let saved = try await model.saveToDownloads(url)
            notes[r.id] = "Saved to your Downloads folder as \(saved.lastPathComponent)."
        } catch let page as ModWebPage {
            NSWorkspace.shared.open(page.url)
            notes[r.id] = ModWebPage.reason
        } catch {
            notice = Notice(title: "Couldn't download \(r.title)", text: error.localizedDescription)
        }
    }

    private func chooseOwnFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a mod you downloaded: an archive, a folder, a .dll or .asi file, or an installer."
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url { addOwnFile(url) }
    }

    private func addOwnFile(_ url: URL) {
        guard let g = game else { return }
        guard working == nil, pending == nil else {
            notice = Notice(title: "One mod at a time", text: "Wait for the current mod to finish, then add \(url.lastPathComponent).")
            return
        }
        let model = self.model, session = search
        working = "file"
        Task {
            defer { working = nil }
            do {
                let prep = try await model.prepareModFile(url, name: url.deletingPathExtension().lastPathComponent,
                                                          source: url.lastPathComponent, reviewed: false, game: g)
                present(prep, result: nil, ownFile: url, session: session, model: model)
            } catch {
                if session.windowClosed { return }
                notice = Notice(title: "Couldn't add \(url.lastPathComponent)", text: error.localizedDescription)
            }
        }
    }

    private func present(_ prep: ModPreparation, result: ModResult?, ownFile: URL?, session: ModsSearch, model: AppModel) {
        guard !session.windowClosed, pending == nil else { model.discardModPreparation(prep); return }
        if case .browser(let url, let reason) = prep {
            NSWorkspace.shared.open(url)
            if let r = result { notes[r.id] = reason } else { notice = Notice(title: "Opened in your browser", text: reason) }
            model.discardModPreparation(prep)
            return
        }
        pending = PendingMod(prep: prep, result: result, ownFile: ownFile)
    }

    private func dropPending() {
        if let p = pending { model.discardModPreparation(p.prep) }
        pending = nil
    }

    private func confirmation(_ item: PendingMod) -> some View {
        let model = self.model, session = search
        return ModConfirmView(
            gameID: gameID, item: item,
            onReplace: { next in
                guard !session.windowClosed, pending?.id == item.id else { model.discardModPreparation(next); return }
                if case .browser = next {
                    dropPending()
                    present(next, result: item.result, ownFile: item.ownFile, session: session, model: model)
                    return
                }
                pending?.prep = next
                pending?.step += 1
            },
            onInstalled: { mod in
                dropPending()
                if let r = item.result {
                    let added = mod.addedGameID != nil && !(game?.mods.contains { $0.id != mod.id && $0.addedGameID == mod.addedGameID } ?? false)
                    notes[r.id] = added ? "Installed, and added to your library." : "Installed."
                }
            },
            onManual: {
                dropPending()
                if let r = item.result, let g = game {
                    manualInstall(r, g)
                } else if let file = item.ownFile {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    if let g = game { NSWorkspace.shared.open(model.gameFolders(g).root) }
                }
            },
            onClose: { dropPending() })
            .environmentObject(model)
    }
}

@MainActor
private final class ModsSearch: ObservableObject {
    @Published var query = ""
    @Published var results: [ModResult] = []
    @Published var searching = false
    @Published var message: String? = nil
    @Published var wikiPage: String? = nil
    var windowClosed = false
    private var generation = 0
    private var task: Task<Void, Never>? = nil

    func start(game: Game) {
        task?.cancel()
        generation += 1
        let mine = generation
        task = Task { await search(game: game, generation: mine) }
    }

    func stop() {
        windowClosed = true
        task?.cancel()
    }

    private func search(game: Game, generation mine: Int) async {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searching = true
        message = nil
        async let wiki = GameWiki.wikitext(exe: URL(fileURLWithPath: game.exePath))
        let github = words.isEmpty ? nil : await GitHubSearch.repositories("\(game.name) \(words)")
        let page = await wiki
        guard mine == generation else { return }

        var found = page.map { ModSearch.fixes(fromWikitext: $0.text) } ?? []
        found += github?.results ?? []
        if !words.isEmpty { found = found.filter { ModSearch.matches($0, query: words) } }
        wikiPage = page?.page
        results = found
        message = github?.failure
        if found.isEmpty && message == nil {
            if !words.isEmpty {
                message = "Nothing found for “\(words)”. Try other words, or use Search the Web below."
            } else if page == nil {
                message = "Ferry couldn't find \(game.name) on PCGamingWiki, or couldn't reach it. Search for a mod by name, or use Search the Web below."
            } else {
                message = "PCGamingWiki lists no fixes for \(game.name). Search for a mod by name, or use Search the Web below."
            }
        }
        searching = false
    }
}
