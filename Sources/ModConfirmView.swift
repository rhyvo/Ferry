import AppKit
import SwiftUI

@MainActor
struct ModConfirmView: View {
    @EnvironmentObject var model: AppModel
    let gameID: UUID
    let item: PendingMod
    let onReplace: (ModPreparation) -> Void
    let onInstalled: (InstalledMod) -> Void
    let onManual: () -> Void
    let onClose: () -> Void

    @State private var working = false
    @State private var problem: String? = nil
    @State private var spent = false
    @State private var variant: URL? = nil
    @State private var asset: Int? = nil
    @State private var rows: [Row] = []

    struct Row: Identifiable {
        let id: Int
        let path: String
        let note: String?
    }

    private var game: Game? { model.game(gameID) }
    private var gameName: String { game?.name ?? "the game" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading).font(.title3.weight(.semibold)).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { buttons }.padding(16)
        }
        .frame(width: 540, height: 460)
        .interactiveDismissDisabled(working)
        .task(id: item.step) {
            problem = nil
            spent = false
            await loadRows()
        }
    }

    private var heading: String {
        switch item.prep {
        case .ready(_, _, let name, _, _), .installer(_, let name, _): return "Install \(name)?"
        case .chooseVariant(_, _, _, let name, _, _, _): return "Which version of \(name)?"
        case .chooseAsset: return "Which download of \(item.title)?"
        case .manual: return "Install \(item.title) by hand"
        case .browser: return item.title
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.prep {
        case .ready(let plan, _, let name, _, _):
            unreviewedLine
            let updated = game.flatMap { model.updatedEntry(plan, in: $0) }
            if let updated {
                Text("Updates \(updated.name). Its files are replaced by this version's, and Remove in the Mods window puts the version before back.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.recipe == .program, let updated {
                Text("\(plan.copies.count) files, in \(updated.name)'s folder.").foregroundStyle(.secondary)
            } else if plan.recipe == .program {
                Text("Adds \"\(gameName) (\(ModLayout.programName(plan) ?? name))\" to your library.")
                if let folder = programFolder(plan) {
                    Text("Its \(plan.copies.count) files go into a new folder next to the game: \(folder). The game itself isn't changed.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Its \(plan.copies.count) files go into the game folder\(game.map { " (\(model.gameFolders($0).root.lastPathComponent))" } ?? ""), so it finds the game's data. None of the game's own files are replaced, and Remove in the Mods window takes them all out again.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("These files go into the game folder\(game.map { " (\(model.gameFolders($0).root.lastPathComponent))" } ?? ""):")
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            if let note = row.note { Text("— \(note)").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
                if !plan.overrides.isEmpty {
                    let dlls = plan.overrides.compactMap { $0.split(separator: "=").first.map { "\($0).dll" } }
                    Text("While it's installed, the game loads the mod's \(ListFormatter.localizedString(byJoining: dlls)) instead of Windows' own.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Remove in the Mods window puts the game back as it was.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .installer(let file, _, _):
            unreviewedLine
            Text("Runs this installer inside \(gameName)'s Windows environment. Ferry can't undo what it changes.")
                .fixedSize(horizontal: false, vertical: true)
            Text(file.lastPathComponent).font(.callout.monospaced()).foregroundStyle(.secondary)
        case .chooseVariant(let folders, _, _, _, _, _, _):
            Text("This mod comes in several versions, and Ferry can't tell which one suits \(gameName). Pick one:")
                .fixedSize(horizontal: false, vertical: true)
            Picker("Version", selection: $variant) {
                ForEach(folders, id: \.self) { Text($0.lastPathComponent).tag(Optional($0)) }
            }
            .pickerStyle(.radioGroup).labelsHidden()
        case .chooseAsset(let assets, let repo):
            Text("The latest release of \(repo) has several downloads, and Ferry can't tell which one suits \(gameName). Pick one:")
                .fixedSize(horizontal: false, vertical: true)
            Picker("Download", selection: $asset) {
                ForEach(assets.indices, id: \.self) { i in
                    Text("\(assets[i].name)  (\(ByteCountFormatter.string(fromByteCount: Int64(assets[i].size), countStyle: .file)))")
                        .tag(Optional(i))
                }
            }
            .pickerStyle(.radioGroup).labelsHidden()
        case .manual(let file, let reason):
            Text(reason).fixedSize(horizontal: false, vertical: true)
            Text(file.lastPathComponent).font(.callout.monospaced()).foregroundStyle(.secondary)
            Text("Nothing was changed. The mod's own readme usually says where its files go.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .browser(_, let reason):
            Text(reason).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var unreviewedLine: some View {
        if item.unreviewed {
            Label("Not reviewed by PCGamingWiki", systemImage: "exclamationmark.shield").foregroundStyle(.orange)
        }
    }

    private func programFolder(_ plan: ModPlan) -> String? {
        guard let g = game, let exe = plan.programExe else { return nil }
        let root = model.gameFolders(g).root
        if exe.standardizedFileURL.path.lowercased().hasPrefix(root.standardizedFileURL.path.lowercased() + "/") { return nil }
        return modDisplayPath(exe, root: root.deletingLastPathComponent()).split(separator: "/").first.map(String.init)
    }

    private func loadRows() async {
        guard case .ready(let plan, _, _, _, _) = item.prep, plan.recipe != .program, let g = game else { rows = []; return }
        let root = model.gameFolders(g).root
        let owned = model.modOwnedPaths(g)
        let targets = plan.copies.map(\.to)
        let exists = await Task.detached { targets.map { FileManager.default.fileExists(atPath: $0.path) } }.value
        rows = targets.enumerated().map { i, t in
            var note: String? = nil
            if owned.contains(t.standardizedFileURL.path.lowercased()), let other = model.modOwning(t, in: g) {
                note = "replaces a file from \(other.name)"
            } else if exists[i] {
                note = "replaces the game's file, backed up"
            }
            return Row(id: i, path: modDisplayPath(t, root: root), note: note)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch item.prep {
        case .ready, .installer:
            if problem != nil && !working { Button("Install Manually", action: onManual) }
            Spacer()
            progress
            Button("Cancel", action: onClose).keyboardShortcut(.cancelAction).disabled(working)
            Button("Install", action: install).keyboardShortcut(.defaultAction).disabled(working || spent)
        case .chooseVariant:
            Spacer()
            progress
            Button("Cancel", action: onClose).keyboardShortcut(.cancelAction).disabled(working)
            Button("Continue", action: pickVariant).keyboardShortcut(.defaultAction).disabled(working || spent || variant == nil)
        case .chooseAsset:
            Spacer()
            progress
            Button("Cancel", action: onClose).keyboardShortcut(.cancelAction).disabled(working)
            Button("Continue", action: pickAsset).keyboardShortcut(.defaultAction).disabled(working || asset == nil)
        case .manual(let file, _):
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("Open Game Folder") { if let g = game { NSWorkspace.shared.open(model.gameFolders(g).root) } }
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.defaultAction)
        case .browser(let url, _):
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var progress: some View {
        if working {
            ProgressView().controlSize(.small)
            Text(model.status ?? "Working…").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func install() {
        let prep = item.prep
        working = true
        problem = nil
        Task {
            do {
                let mod = try await model.applyMod(prep, to: gameID)
                working = false
                onInstalled(mod)
            } catch {
                problem = error.localizedDescription
                spent = !Self.stillPrepared(prep)
                working = false
            }
        }
    }

    private static func stillPrepared(_ prep: ModPreparation) -> Bool {
        switch prep {
        case .ready(_, let staging, _, _, _): return FileManager.default.fileExists(atPath: staging.path)
        case .installer(let file, _, _): return FileManager.default.fileExists(atPath: file.path)
        default: return false
        }
    }

    private func pickVariant() {
        guard let folder = variant, let g = game else { return }
        let prep = item.prep
        working = true
        problem = nil
        Task {
            do {
                let next = try await model.prepareModVariant(folder, of: prep, game: g)
                working = false
                onReplace(next)
            } catch {
                model.discardModPreparation(prep)
                problem = error.localizedDescription
                spent = true
                working = false
            }
        }
    }

    private func pickAsset() {
        guard let i = asset, case .chooseAsset(let assets, _) = item.prep, i < assets.count,
              let r = item.result, let g = game else { return }
        working = true
        problem = nil
        Task {
            do {
                let next = try await model.downloadModResult(r, game: g, asset: assets[i])
                working = false
                onReplace(next)
            } catch {
                problem = error.localizedDescription
                working = false
            }
        }
    }
}
