import AppKit
import SwiftUI

enum DiskUsage {
    static func privateSize(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 16)
        let status = buffer.withUnsafeMutableBytes {
            getattrlist(path, &list, $0.baseAddress, 16, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int64.self) }
    }

    static func freeableBytes(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        func size(_ file: URL) -> Int64 {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return 0 }
            return privateSize(file.path) ?? Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard FileManager.default.isDirectory(url) else { return size(url) }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let file = walker?.nextObject() as? URL { total += size(file) }
        return total
    }

    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static var freeOnDisk: Int64 { free(at: Paths.root) ?? 0 }

    static func free(at url: URL) -> Int64? {
        var u = url
        while !FileManager.default.fileExists(atPath: u.path), u.path != "/" { u = u.deletingLastPathComponent() }
        let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let n = v?.volumeAvailableCapacityForImportantUsage, n > 0 { return n }
        return v?.volumeAvailableCapacity.map(Int64.init)
    }
}

struct StorageItem: Identifiable, Hashable {
    enum Status {
        case inUse, holdsFiles, lastUsed, needed, optional, unused, leftover, downloads, engine

        var badge: String {
            switch self {
            case .inUse: return "In use"
            case .holdsFiles: return "Has program files"
            case .lastUsed: return "Last used"
            case .needed: return "Needed"
            case .optional: return "Optional"
            case .unused: return "Not used"
            case .leftover: return "Left over"
            case .downloads: return "Downloads"
            case .engine: return "Engine"
            }
        }

        var color: Color {
            switch self {
            case .inUse: return .green
            case .holdsFiles, .lastUsed: return .blue
            case .unused, .leftover: return .orange
            default: return .secondary
            }
        }
    }

    var id: String { url.path }
    let url: URL
    let group: String
    let title: String
    let note: String
    let status: Status
    var gameID: UUID? = nil
    var kind: RuntimeKind? = nil
    var bytes: Int64? = nil

    var canDelete: Bool { [.lastUsed, .optional, .unused, .leftover, .downloads].contains(status) }
    var recommended: Bool { [.unused, .leftover, .downloads].contains(status) }
}

extension RuntimeKind {
    var engineName: String {
        switch self {
        case .gptk: return "D3DMetal"
        case .staging: return "Wine Staging (WineD3D, DXVK)"
        case .dxvk: return "DXVK"
        case .arm64: return "Mullion"
        case .mach9: return "Mach9"
        case .x64: return "MetalSharp Wine x86_64 (D3DMetal 4, Mullion on Rosetta)"
        }
    }
}

extension AppModel {
    func storageItems() -> [StorageItem] {
        var items: [StorageItem] = []

        for g in games where g.sharedWith == nil {
            let users = [g] + sharers(of: g.id)
            let enginesInUse = Set(users.map { runtimeKind($0) })
            let currentReady = enginesInUse.contains { fm.exists(prefixURL(g.id, $0).appendingPathComponent("system.reg")) }
            for kind in RuntimeKind.allCases where kind != .dxvk {
                let prefix = prefixURL(g.id, kind)
                guard fm.isDirectory(prefix) else { continue }
                let installedHere = users.first { $0.exePath.hasPrefix(prefix.path + "/") }
                let status: StorageItem.Status
                let note: String
                if enginesInUse.contains(kind) {
                    status = .inUse
                    note = "\(g.name) runs on \(kind.engineName)."
                } else if let program = installedHere {
                    status = .holdsFiles
                    note = "Not used as an engine any more, but \(program.name) is installed inside it, so it has to stay."
                } else if !currentReady {
                    status = .lastUsed
                    let next = enginesInUse.map(\.engineName).sorted().joined(separator: ", ")
                    note = "\(g.name) is set to \(next) now but hasn't run on it yet. Keep this until it has, in case you need to switch back."
                } else {
                    status = .unused
                    note = "Left from when \(g.name) ran on \(kind.engineName). Saves are kept separately, so deleting it doesn't touch them."
                }
                items.append(StorageItem(url: prefix, group: g.name, title: "\(kind.engineName) environment",
                                         note: note, status: status, gameID: g.id, kind: kind))
            }
        }

        let known = Set(games.map(\.id.uuidString))
        let bottles = (try? fm.contentsOfDirectory(at: Paths.bottles, includingPropertiesForKeys: nil)) ?? []
        for folder in bottles where fm.isDirectory(folder) && !known.contains(folder.lastPathComponent) {
            items.append(StorageItem(url: folder, group: "Removed programs", title: "Windows environment and saves",
                                     note: "Left over from a program that's no longer in Ferry. Its saves are in here too.",
                                     status: .leftover))
        }

        for kind in [RuntimeKind.mach9, .gptk, .staging, .arm64, .x64] {
            let template = templateURL(kind)
            guard fm.isDirectory(template) else { continue }
            let required = kind == .gptk || kind == .staging
            items.append(StorageItem(
                url: template, group: "Ferry", title: "Ready-made \(kind.engineName) environment",
                note: required
                    ? "Needed by Ferry: new games are set up from it, and other environments copy files from it."
                    : "New \(kind.engineName) games are copied from it, so they start right away. If deleted, Ferry rebuilds it (a few minutes) the next time a new game needs \(kind.engineName).",
                status: required ? .needed : .optional, kind: kind))
        }

        if fm.isDirectory(Self.webView2Prefix) {
            let users = games.filter(\.settings.webView2)
            items.append(StorageItem(url: Self.webView2Prefix, group: "Ferry", title: "WebView2",
                                     note: users.isEmpty
                                         ? "No program has WebView2 for launchers turned on. If one does later, Ferry installs it again."
                                         : "Used by \(users.map(\.name).joined(separator: ", ")). If deleted, Ferry installs it again the next time one starts.",
                                     status: users.isEmpty ? .unused : .optional))
        }

        items += leftoverWorkItems()

        let installers = Paths.cache.appendingPathComponent("windows")
        if fm.isDirectory(installers) {
            items.append(StorageItem(url: installers, group: "Ferry", title: "Downloaded library installers",
                                     note: "Kept so Ferry can reinstall Windows libraries without downloading them again.",
                                     status: .downloads))
        }

        for kind in RuntimeKind.allCases where runtimes.info[kind] != nil {
            let users = games.filter { runtimeKind($0) == kind || (kind == .dxvk && resolvedEngine($0) == .dxvk) }
            items.append(StorageItem(
                url: runtimes.folder(kind), group: "Ferry",
                title: runtimes.info[kind]?.d3dmetalImported.map { "Game Porting Toolkit (D3DMetal \($0), imported)" } ?? kind.title,
                note: users.isEmpty
                    ? "Not used by any program in your library. To remove it, use Settings ▸ Engines."
                    : "Used by \(users.map(\.name).joined(separator: ", ")).",
                status: .engine, kind: kind))
        }

        if runtimes.hasD3DMetalBackup {
            items.append(StorageItem(
                url: Paths.runtimes.appendingPathComponent("gptk.original"), group: "Ferry", title: "Bundled D3DMetal\(runtimes.backupD3DMetalVersion.map { " \($0)" } ?? "") (backup)",
                note: "Kept because you imported another D3DMetal, so Settings ▸ Engines ▸ Restore Bundled Version can put this one back. It shares most of its files with the engine.",
                status: .engine))
        }

        for g in games where g.sharedWith == nil {
            if fm.isDirectory(savesURL(g.id)) {
                items.append(StorageItem(url: savesURL(g.id), group: g.name, title: "Saves",
                                         note: "The game's saves and settings, kept apart from its environments so switching engines or deleting an environment never loses them.",
                                         status: .needed, gameID: g.id))
            }
            if fm.isDirectory(shaderCacheURL(g.id)) {
                items.append(StorageItem(url: shaderCacheURL(g.id), group: g.name, title: "Shader cache",
                                         note: "Graphics already prepared for this game, so it doesn't stutter preparing them again. If deleted, it's rebuilt as you play, with some stutter at first.",
                                         status: .optional, gameID: g.id))
            }
            let logs = bottleURL(g.id).appendingPathComponent("logs", isDirectory: true)
            if fm.isDirectory(logs) {
                items.append(StorageItem(url: logs, group: g.name, title: "Logs",
                                         note: "Records of the game's recent runs, which Troubleshoot reads. New ones are written the next time it runs.",
                                         status: .optional, gameID: g.id))
            }
        }

        for g in games where g.sharedWith == nil {
            let folder = bottleURL(g.id).appendingPathComponent("mod-backups", isDirectory: true)
            guard fm.isDirectory(folder) else { continue }
            items.append(StorageItem(url: folder, group: g.name, title: "Mod backups",
                                     note: "The game's original files that installed mods replaced. Ferry puts them back when you remove a mod, so they stay until then.",
                                     status: .needed, gameID: g.id))
        }

        if let dll = betaDXVK32() {
            let users = games.filter { usesBetaDXVK($0, engine: resolvedEngine($0)) }
            let version = betaDXVKVersion.map { " \($0.trimmingCharacters(in: .whitespacesAndNewlines))" } ?? ""
            items.append(StorageItem(
                url: dll.deletingLastPathComponent().deletingLastPathComponent(), group: "Ferry",
                title: "DXVK\(version) on KosmicKrisp (beta)",
                note: (users.isEmpty ? "Not used by any program in your library." : "Used by \(users.map(\.name).joined(separator: ", ")).")
                    + " If deleted, those games go back to Ferry's regular DXVK; download it again from Settings ▸ Components.",
                status: .optional))
        }

        let cncDdraw = Paths.cache.appendingPathComponent("cnc-ddraw", isDirectory: true)
        if fm.isDirectory(cncDdraw) {
            items.append(StorageItem(url: cncDdraw, group: "Ferry", title: "cnc-ddraw (unpacked)",
                                     note: "The old 2D game fix, ready to copy into games that use it. If deleted, Ferry unpacks it again when one needs it.",
                                     status: .downloads))
        }
        let discordList = Paths.cache.appendingPathComponent("discord-games.json")
        if fm.exists(discordList) {
            items.append(StorageItem(url: discordList, group: "Ferry", title: "Discord game list",
                                     note: "Discord's list of games, so Discord can show what you're playing. Downloaded again when it's missing or old.",
                                     status: .downloads))
        }
        if fm.isDirectory(Paths.logs) {
            items.append(StorageItem(url: Paths.logs, group: "Ferry", title: "Ferry logs",
                                     note: "Records of engine, environment and component installs, for when one goes wrong.",
                                     status: .optional))
        }
        items.append(StorageItem(url: Paths.library, group: "Ferry", title: "Library",
                                 note: "Your library: every program, its engine and its settings.", status: .needed))
        let lookups = Paths.root.appendingPathComponent("game-lookups.json")
        if fm.exists(lookups) {
            items.append(StorageItem(url: lookups, group: "Ferry", title: "Game info lookups",
                                     note: "What Ferry has already looked up about your games online, so it doesn't ask again. Looked up again if deleted.",
                                     status: .downloads))
        }
        if fm.isDirectory(Paths.icons) {
            items.append(StorageItem(url: Paths.icons, group: "Ferry", title: "Game icons",
                                     note: "Icons for the library and your Mac shortcuts.", status: .needed))
        }
        if let made = try? fm.contentsOfDirectory(atPath: Paths.shortcuts.path), !made.isEmpty {
            items.append(StorageItem(url: Paths.shortcuts, group: "Ferry", title: "Mac shortcuts (~/Applications/Ferry Games)",
                                     note: "The shortcuts you made to start games from Launchpad, Spotlight or the Dock. Delete one in Finder to remove it (Settings ▸ System ▸ Show Mac Shortcuts Folder).",
                                     status: .needed))
        }
        let saveBackups = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Ferry Backups", isDirectory: true)
        if fm.isDirectory(saveBackups) {
            items.append(StorageItem(url: saveBackups, group: "Ferry", title: "Save backups (Documents/Ferry Backups)",
                                     note: "Zips made by Back Up Saves. Ferry never uses them itself; they're there for you to restore from.",
                                     status: .optional))
        }

        if runtimes.sevenZipInstalled {
            items.append(StorageItem(
                url: RuntimeManager.sevenZipFolder, group: "Ferry", title: "7-Zip\(runtimes.sevenZipVersion.map { " \($0)" } ?? "")",
                note: "Unpacks games and installers from RAR, 7z and multi-part archives.",
                status: .engine))
        }
        return items
    }

    func deleteStorage(_ chosen: [StorageItem]) {
        for item in chosen where item.canDelete {
            if let id = item.gameID, running.contains(id) { continue }
            if leftoverInUse(item) { continue }
            fm.removeIfPresent(item.url)
            if let id = item.gameID, let kind = item.kind, var g = game(id) {
                g.applied[kind.rawValue] = nil
                g.runtimesInstalled.removeAll { $0 == kind.rawValue }
                update(g)
            }
        }
        refreshSetupState()
    }

    func checkForReclaimableStorage() {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: "storagePromptDate") as? Date, Date().timeIntervalSince(last) < 7 * 86_400 { return }
        let urls = storageItems().filter(\.recommended).map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            let total = await Task.detached { urls.reduce(Int64(0)) { $0 + DiskUsage.freeableBytes($1) } }.value
            if total >= 1_000_000_000 && storageSuggestion == nil {
                storageSuggestion = total
                defaults.set(Date(), forKey: "storagePromptDate")
            }
        }
    }
}

struct StorageView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var showsDone = true

    @State private var items: [StorageItem] = []
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var free: Int64 = 0
    @State private var onlyDeletable = false

    private enum Category: CaseIterable {
        case games, engines, templates, other
        var title: String {
            switch self {
            case .games: return "Games and saves"
            case .engines: return "Engines"
            case .templates: return "Ready-made environments"
            case .other: return "Downloads and other"
            }
        }
        var color: Color {
            switch self {
            case .games: return .blue
            case .engines: return .purple
            case .templates: return .teal
            case .other: return .gray
            }
        }
    }

    private func category(_ item: StorageItem) -> Category {
        if item.group != "Ferry" && item.group != "Removed programs" { return .games }
        if item.title.hasPrefix("Ready-made") { return .templates }
        if item.status == .engine { return .engines }
        return .other
    }

    private var shownItems: [StorageItem] { onlyDeletable ? items.filter(\.canDelete) : items }

    private var groups: [(name: String, bytes: Int64)] {
        var totals: [String: Int64] = [:]
        var order: [String] = []
        for item in shownItems {
            if totals[item.group] == nil { order.append(item.group) }
            totals[item.group, default: 0] += item.bytes ?? 0
        }
        func rank(_ name: String) -> Int { name == "Ferry" ? 2 : name == "Removed programs" ? 1 : 0 }
        let bySize = !measuring
        return order.enumerated().map { (index: $0.offset, name: $0.element, bytes: totals[$0.element] ?? 0) }
            .sorted { (rank($0.name), bySize ? -$0.bytes : 0, $0.index) < (rank($1.name), bySize ? -$1.bytes : 0, $1.index) }
            .map { ($0.name, $0.bytes) }
    }

    private var selectedItems: [StorageItem] { items.filter { selected.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + ($1.bytes ?? 0) } }
    private var ferryTotal: Int64 { items.reduce(0) { $0 + ($1.bytes ?? 0) } }
    private var measuring: Bool { items.contains { $0.bytes == nil } }

    private func bytes(of category: Category) -> Int64 {
        items.filter { self.category($0) == category }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            List {
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(shownItems.filter { $0.group == group.name }) { item in row(item) }
                    } header: {
                        HStack {
                            Text(group.name)
                            Spacer()
                            if !measuring { Text(DiskUsage.text(group.bytes)).monospacedDigit() }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if onlyDeletable && shownItems.isEmpty && !items.isEmpty {
                    ContentUnavailableView("Nothing to Delete", systemImage: "checkmark.circle",
                                           description: Text("Everything Ferry keeps is in use or needed."))
                }
            }

            Divider()
            HStack {
                Button("Select Unused Items") {
                    selected = Set(items.filter { $0.recommended && !isRunning($0) }.map(\.id))
                }
                .help("Selects old environments, leftovers and downloaded installers: nothing in use, and no saves.")
                if !selected.isEmpty {
                    Button("Deselect All") { selected = [] }
                }
                Spacer()
                if !selected.isEmpty {
                    Text("Frees \(DiskUsage.text(selectedBytes))").foregroundStyle(.secondary).monospacedDigit()
                }
                Button(selected.count > 1 ? "Delete \(selected.count) Items…" : "Delete…", role: .destructive) { confirming = true }
                    .disabled(selected.isEmpty)
                if showsDone {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 500)
        .task { await reload() }
        .alert("Delete \(selected.count) item\(selected.count == 1 ? "" : "s")?", isPresented: $confirming) {
            Button("Delete", role: .destructive) {
                model.deleteStorage(selectedItems)
                selected = []
                Task { await reload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees about \(DiskUsage.text(selectedBytes)) and can't be undone. Ferry sets up an environment again if a game needs it later.")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if showsDone { Text("Storage").font(.title2.weight(.semibold)) }
                if measuring {
                    ProgressView().controlSize(.small)
                    Text("Measuring… \(DiskUsage.text(ferryTotal)) so far").foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("Ferry uses \(DiskUsage.text(ferryTotal))").font(.headline).monospacedDigit()
                    Text("· \(DiskUsage.text(free)) free on this Mac").foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Picker("Show", selection: $onlyDeletable) {
                    Text("All Items").tag(false)
                    Text("Can Be Deleted").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show everything Ferry keeps, or only what you can delete")
            }
            usageBar
            HStack(spacing: 16) {
                ForEach(Category.allCases, id: \.self) { c in
                    HStack(spacing: 5) {
                        Circle().fill(c.color).frame(width: 8, height: 8)
                        Text(c.title)
                        Text(measuring && bytes(of: c) == 0 ? "…" : DiskUsage.text(bytes(of: c)))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var usageBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Category.allCases, id: \.self) { c in
                    let share = ferryTotal > 0 ? CGFloat(bytes(of: c)) / CGFloat(ferryTotal) : 0
                    if share > 0 { c.color.frame(width: max(2, (geo.size.width - 3) * share)) }
                }
                Spacer(minLength: 0)
            }
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .animation(.easeOut(duration: 0.25), value: ferryTotal)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func isRunning(_ item: StorageItem) -> Bool {
        guard let id = item.gameID else { return false }
        return model.running.contains(id)
    }

    @ViewBuilder
    private func row(_ item: StorageItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if item.canDelete {
                Toggle(item.title, isOn: Binding(
                    get: { selected.contains(item.id) },
                    set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }))
                    .labelsHidden()
                    .disabled(isRunning(item))
                    .accessibilityLabel("Select \(item.title)\(item.group == "Ferry" ? "" : ", \(item.group)")")
            } else {
                Color.clear.frame(width: 14, height: 14).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).fontWeight(.medium)
                Text(isRunning(item) ? "Running now." : item.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Text(item.status.badge)
                .font(.caption.weight(.medium))
                .foregroundStyle(item.status.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(item.status.color.opacity(0.12)))
            Group {
                if let bytes = item.bytes { Text(DiskUsage.text(bytes)) } else { ProgressView().controlSize(.mini) }
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }

    private func reload() async {
        free = DiskUsage.freeOnDisk
        var fresh = model.storageItems()
        items = fresh
        selected = selected.filter { id in fresh.contains { $0.id == id && $0.canDelete } }
        let urls = fresh.map(\.url)
        await withTaskGroup(of: (Int, Int64).self) { group in
            var next = 0
            func start() {
                guard next < urls.count else { return }
                let i = next, url = urls[i]
                next += 1
                group.addTask { (i, await Task.detached { DiskUsage.freeableBytes(url) }.value) }
            }
            for _ in 0..<4 { start() }
            for await (i, bytes) in group {
                fresh[i].bytes = bytes
                if i < items.count, items[i].id == fresh[i].id { items[i].bytes = bytes }
                start()
            }
        }
        free = DiskUsage.freeOnDisk
    }
}
