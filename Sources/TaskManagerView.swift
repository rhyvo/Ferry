import Darwin
import SwiftUI

extension AppModel {
    func environmentFolders() -> [String] {
        func children(_ url: URL) -> [String] { (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] }
        var folders: [String] = []
        for game in children(Paths.bottles) {
            let bottle = Paths.bottles.appendingPathComponent(game)
            folders += children(bottle).filter { $0.hasPrefix("windows-") }.map { bottle.appendingPathComponent($0).path }
        }
        folders += children(Paths.templates).filter { $0.hasPrefix("windows-") }.map { Paths.templates.appendingPathComponent($0).path }
        folders += children(Paths.runtimes).filter { $0.hasSuffix(".building") }.map { Paths.runtimes.appendingPathComponent($0).path }
        return folders
    }

    func endWindowsProgram(_ process: WindowsProcess, owner: TaskList.Owner) {
        if case .game(let id, _) = owner, running.contains(id), let g = game(id),
           URL(fileURLWithPath: g.exePath).lastPathComponent.lowercased() == process.name.lowercased() {
            stopping.insert(id)
        }
        let pid = process.id
        kill(pid, SIGTERM)
        Task.detached {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    func endEnvironment(_ owner: TaskList.Owner, prefix: String?, processes: [WindowsProcess]) {
        let kindName: String?
        switch owner {
        case .game(let id, let kind):
            if running.contains(id), let g = game(id), runtimeKind(g).rawValue == kind {
                stop(id)
                return
            }
            kindName = kind
        case .setup(let kind): kindName = kind
        case .other: kindName = nil
        }
        if let prefix, fm.isDirectory(URL(fileURLWithPath: prefix)),
           let kind = kindName.flatMap(RuntimeKind.init(rawValue:)), let server = runtimes.wineserver(for: kind) {
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = prefix
            Task { await Shell.run(server.path, ["-k"], env: env) }
        } else {
            for p in processes { endWindowsProgram(p, owner: owner) }
        }
    }
}

struct TaskManagerView: View {
    @EnvironmentObject var model: AppModel
    @State private var processes: [WindowsProcess] = []
    @State private var cpu: [Int32: Double] = [:]
    @State private var lastCPU: [Int32: UInt64] = [:]
    @State private var lastSample = Date()
    @State private var gpu: [Int32: Double] = [:]
    @State private var lastGPU: [Int32: UInt64] = [:]
    @State private var gpuDevice: Int? = nil
    @State private var confirmEnd: ProgramGroup? = nil
    @State private var confirmEndEverything = false
    @AppStorage("taskManagerShowsWine") private var showWine = false

    private struct ProgramGroup: Identifiable {
        let id: TaskList.Owner
        let title: String
        let detail: String
        let prefix: String?
        let all: [WindowsProcess]
        let shown: [WindowsProcess]
        var memory: UInt64 { all.reduce(0) { $0 + $1.memory } }
        var isGame: Bool { if case .game = id { return true } else { return false } }
    }

    private var groups: [ProgramGroup] {
        let root = Paths.root.path
        var byOwner: [TaskList.Owner: [WindowsProcess]] = [:]
        var prefixes: [TaskList.Owner: String] = [:]
        for p in processes {
            let owner = p.prefix.map { TaskList.owner(ofPrefix: $0, root: root) } ?? .other("")
            byOwner[owner, default: []].append(p)
            if let prefix = p.prefix { prefixes[owner] = prefix }
        }
        return byOwner.map { owner, list in
            let (title, detail) = describe(owner)
            let sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            var removed = false
            if case .game(let id, _) = owner { removed = model.game(id) == nil }
            return ProgramGroup(id: owner, title: title, detail: detail, prefix: prefixes[owner], all: sorted,
                         shown: showWine || removed ? sorted : sorted.filter { !$0.isWineSystem })
        }
        .sorted { ($0.detail.hasPrefix("Ferry") ? 1 : 0, $0.title) < ($1.detail.hasPrefix("Ferry") ? 1 : 0, $1.title) }
    }

    private func describe(_ owner: TaskList.Owner) -> (String, String) {
        func engine(_ kind: String) -> String { RuntimeKind(rawValue: kind)?.engineName ?? kind }
        switch owner {
        case .game(let id, let kind):
            return (model.game(id)?.name ?? "Removed program", model.game(id) == nil ? "Left running · \(engine(kind))" : engine(kind))
        case .setup(let kind): return ("Preparing \(engine(kind))", "Ferry setup")
        case .other(let prefix):
            return prefix.isEmpty ? ("Other Wine programs", "Not in one of Ferry's environments")
                                  : (URL(fileURLWithPath: prefix).lastPathComponent, "Ferry")
        }
    }

    private static func memoryText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private let memoryWidth: CGFloat = 80
    private let usageWidth: CGFloat = 50
    private let endWidth: CGFloat = 64

    private static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "–" }
    private static func spoken(_ value: Double?) -> String { value.map { String(format: "%.0f percent", $0) } ?? "not measured yet" }

    private func total(_ usage: [Int32: Double], _ list: [WindowsProcess]) -> Double? {
        let values = list.compactMap { usage[$0.id] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var body: some View {
        let groups = self.groups
        let visible = groups.filter { showWine || !$0.shown.isEmpty }
        let hidden = processes.count - visible.reduce(0) { $0 + $1.shown.count }
        VStack(spacing: 0) {
            if visible.isEmpty {
                ContentUnavailableView("No Windows Programs Running", systemImage: "checkmark.circle",
                                       description: Text("Games, apps, launchers and installers started by Ferry show up here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                columnHeader
                Divider()
                List {
                    ForEach(visible) { group in
                        Section {
                            ForEach(group.shown) { row($0, owner: group.id) }
                        } header: {
                            header(group)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Toggle("Show Wine's system processes", isOn: $showWine)
                    .help("services.exe, explorer.exe and the other background programs every Windows environment runs")
                if visible.count >= 2 {
                    Button("End Everything…") { confirmEndEverything = true }
                        .help("End every Windows program Ferry is running")
                }
                Spacer()
                Text(footer(shown: processes.count - hidden, hidden: hidden))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(10)
        }
        .frame(minWidth: 560, minHeight: 360)
        .confirmationDialog("End \(confirmEnd?.title ?? "")?", isPresented: Binding(
            get: { confirmEnd != nil }, set: { if !$0 { confirmEnd = nil } }), presenting: confirmEnd) { group in
            Button("End All", role: .destructive) { endAll(group) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Anything not saved in it is lost.")
        }
        .confirmationDialog("End every Windows program?", isPresented: $confirmEndEverything) {
            Button("End Everything", role: .destructive) { visible.forEach(endAll) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(visible.map(\.title).joined(separator: ", ")) will close. Anything not saved in them is lost.")
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("Program")
            Spacer()
            Text("Memory").frame(width: memoryWidth, alignment: .trailing)
            Text("CPU").frame(width: usageWidth, alignment: .trailing)
            Text("GPU").frame(width: usageWidth, alignment: .trailing)
            Color.clear.frame(width: endWidth, height: 1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    private func header(_ group: ProgramGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.title).font(.headline)
            Text(group.detail).foregroundStyle(.secondary)
            Spacer()
            Group {
                Text(Self.memoryText(group.memory)).frame(width: memoryWidth, alignment: .trailing)
                    .accessibilityLabel("Memory \(Self.memoryText(group.memory))")
                Text(Self.percent(total(cpu, group.all))).frame(width: usageWidth, alignment: .trailing)
                    .accessibilityLabel("CPU \(Self.spoken(total(cpu, group.all)))")
                Text(Self.percent(total(gpu, group.all))).frame(width: usageWidth, alignment: .trailing)
                    .accessibilityLabel("GPU \(Self.spoken(total(gpu, group.all)))")
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .help("Everything in this Windows environment together, Wine's own programs included")
            Button("End All") {
                if group.isGame && model.game(gameID(group.id)) != nil { confirmEnd = group } else { endAll(group) }
            }
            .controlSize(.small)
            .frame(width: endWidth, alignment: .trailing)
            .help("Closes every program in this Windows environment, including Wine's own")
            .accessibilityLabel("End all programs of \(group.title)")
        }
        .accessibilityElement(children: .contain)
    }

    private func gameID(_ owner: TaskList.Owner) -> UUID {
        if case .game(let id, _) = owner { return id }
        return UUID()
    }

    private func endAll(_ group: ProgramGroup) {
        model.endEnvironment(group.id, prefix: group.prefix, processes: group.all)
    }

    private func footer(shown: Int, hidden: Int) -> String {
        let total = processes.reduce(UInt64(0)) { $0 + $1.memory }
        func count(_ n: Int, _ what: String) -> String { "\(n) \(what)\(n == 1 ? "" : "s")" }
        let gpu = gpuDevice.map { " · GPU \($0)% in use" } ?? ""
        if shown == 0 && hidden == 0 { return "Nothing running" + gpu }
        let text = shown == 0 && hidden > 0 ? count(hidden, "background program")
                 : count(shown, "program") + (hidden > 0 ? " (+\(hidden) background)" : "")
        return text + " · " + Self.memoryText(total) + gpu
    }

    private func row(_ p: WindowsProcess, owner: TaskList.Owner) -> some View {
        let usage = cpu[p.id]
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name)
                Text(p.commandLine).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .help(p.commandLine)
            Spacer()
            Text(Self.memoryText(p.memory))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: memoryWidth, alignment: .trailing)
                .accessibilityLabel("Memory \(Self.memoryText(p.memory))")
            Text(Self.percent(usage))
                .monospacedDigit()
                .foregroundStyle((usage ?? 0) >= 90 ? Color.orange : Color.secondary)
                .frame(width: usageWidth, alignment: .trailing)
                .accessibilityLabel("CPU \(Self.spoken(usage))")
                .help("CPU use. 100% is one full core. A program that sits at 0% for minutes while you wait is usually stuck.")
            Text(Self.percent(gpu[p.id]))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: usageWidth, alignment: .trailing)
                .accessibilityLabel("GPU \(Self.spoken(gpu[p.id]))")
                .help("GPU use: how much of the time the graphics chip spent on this program's drawing.")
            Button("End") { model.endWindowsProgram(p, owner: owner) }
                .controlSize(.small)
                .frame(width: endWidth, alignment: .trailing)
                .help("Close \(p.name)")
                .accessibilityLabel("End \(p.name)")
        }
    }

    private func refresh() async {
        let root = Paths.root.path
        let prefixes = model.environmentFolders()
        let (list, gpuNow) = await Task.detached { (TaskList.snapshot(root: root, prefixes: prefixes), TaskList.gpuSnapshot()) }.value
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSample) * 1_000_000_000
        var usage: [Int32: Double] = [:]
        for p in list {
            if let before = lastCPU[p.id], p.cpuNanoseconds >= before, elapsed > 0 {
                usage[p.id] = Double(p.cpuNanoseconds - before) / elapsed * 100
            }
        }
        var gpuUsage: [Int32: Double] = [:]
        for p in list {
            guard let now = gpuNow.times[p.id] else { gpuUsage[p.id] = 0; continue }
            if let before = lastGPU[p.id], now >= before, elapsed > 0 {
                gpuUsage[p.id] = min(100, Double(now - before) / elapsed * 100)
            }
        }
        processes = list
        cpu = usage
        gpu = gpuUsage
        lastGPU = gpuNow.times
        gpuDevice = gpuNow.devicePercent
        lastCPU = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.cpuNanoseconds) })
        lastSample = now
    }
}
