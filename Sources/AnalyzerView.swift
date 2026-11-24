import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnalyzerModel: ObservableObject {
    static let shared = AnalyzerModel()

    @Published var report: AnalysisReport? = nil
    @Published var working: String? = nil
    @Published var progress: Double? = nil
    @Published var problem: String? = nil
    @Published var addedName: String? = nil
    @Published var note: String? = nil
    @Published private(set) var archiveParts: [URL] = []
    @Published private(set) var archiveDeleted = false

    static let programExtensions = ["exe", "msi", "bat"]
    static let archivePickerExtensions = ["zip", "rar", "7z", "001", "r00", "z01"]

    private var unpackedContainer: URL? = nil
    private var unpackedDestination: URL? = nil
    private var sourceName = ""
    private var busy = false

    @Published private(set) var lastChecked: URL? = nil

    func reset() {
        guard !busy else { return }
        if addedName == nil { discardUnpacked() }
        report = nil
        problem = nil
        addedName = nil
        note = nil
        lastChecked = nil
    }

    static let recentsKey = "recentChecks"
    private func remember(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(6)), forKey: Self.recentsKey)
    }

    static func isArchive(_ url: URL) -> Bool {
        !FileManager.default.isDirectory(url) && ArchiveSet.looksLikeArchive(url)
    }

    func analyze(_ url: URL) {
        guard !busy else { NSSound.beep(); return }
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()
        let isFolder = fm.isDirectory(url)
        let isArchive = Self.isArchive(url)
        guard isFolder || isArchive || Self.programExtensions.contains(ext) else {
            problem = "Ferry can check Windows programs (.exe, .msi, .bat), folders, and .zip, .rar or .7z archives (including multi-part ones)."
            return
        }
        remember(url)
        lastChecked = url
        report = nil
        problem = nil
        addedName = nil
        note = nil
        archiveDeleted = false
        discardUnpacked()
        archiveParts = []
        sourceName = url.deletingPathExtension().lastPathComponent
        busy = true

        Task {
            defer { busy = false }
            var root = url
            var chosen: URL? = nil
            if isArchive {
                guard let unpacked = await unpackArchive(url) else {
                    working = nil
                    progress = nil
                    return
                }
                progress = nil
                root = unpacked
            } else if !isFolder {
                root = url.deletingLastPathComponent()
                chosen = url
            }
            await run(root: root, exe: chosen)
        }
    }

    private func unpackArchive(_ dropped: URL) async -> URL? {
        let fm = FileManager.default
        guard let set = ArchiveSet.resolve(dropped) else {
            problem = "Ferry doesn't recognise \(dropped.lastPathComponent) as an archive."
            return nil
        }
        if !set.missing.isEmpty {
            let list = set.missing.joined(separator: ", ")
            let verb = set.missing.count == 1 ? "isn't" : "aren't"
            problem = "\(dropped.lastPathComponent) is one part of a multi-part archive, and \(list) \(verb) in the same folder. Put every part in one folder, then drop any of them again."
            return nil
        }
        sourceName = set.baseName
        let name = set.first.lastPathComponent

        let runtimes = AppModel.shared.runtimes
        if !runtimes.sevenZipInstalled && (set.isMultiPart || Component.isOn(.sevenZip)) {
            working = "Getting 7-Zip (under 1 MB)…"
            progress = nil
            do {
                try await runtimes.installSevenZip()
            } catch {
                if set.isMultiPart {
                    problem = "Multi-part archives need 7-Zip, and it couldn't be downloaded: \(error.localizedDescription)"
                    return nil
                }
            }
        }
        let sevenZip: URL? = runtimes.sevenZipInstalled ? RuntimeManager.sevenZip : nil

        let place = UnpackDestination.folder(for: set.first)
        let staging = place.url.appendingPathComponent(UnpackDestination.stagingName, isDirectory: true)
        fm.removeIfPresent(staging)
        fm.removeIfPresent(Paths.cache.appendingPathComponent("unpacked", isDirectory: true))
        let container = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: container, withIntermediateDirectories: true)
        } catch {
            problem = "Couldn't create a folder to unpack into in \(place.url.path): \(error.localizedDescription)"
            return nil
        }

        working = "Looking inside \(name)…"
        progress = nil
        var total = 0
        var tarSizes: [String: Int] = [:]
        var tarEntries = 0
        if let sevenZip {
            let listing = await Shell.capture(sevenZip.path, ["l", "-slt", set.first.path])
            total = await Task.detached { Unpacker.sevenZipTotal(listing.output) }.value
        } else {
            let listing = await Shell.capture("/usr/bin/tar", ["-tvf", set.first.path])
            tarSizes = await Task.detached { Self.parseListing(listing.output) }.value
            tarEntries = listing.output.split(whereSeparator: \.isNewline).count
            total = tarSizes.values.reduce(0, +)
        }

        if total > 0, let free = DiskUsage.free(at: place.url).map(Int.init), total + 300_000_000 > free {
            cleanUp(container)
            let drive = (try? place.url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "This drive"
            problem = "\(name) unpacks to \(Self.bytes(total)), but \(drive) only has \(Self.bytes(free)) free. Free up some space, or pick a bigger drive in Settings ▸ Defaults ▸ Games and Apps from archives."
            return nil
        }

        var ok = false
        var reason: String? = nil
        if let sevenZip {
            let result = await extractWithSevenZip(sevenZip, set.first, into: container, total: total, name: name)
            ok = result.ok
            reason = result.problem
            if !ok && result.tryTar && !set.isMultiPart {
                fm.removeIfPresent(container)
                try? fm.createDirectory(at: container, withIntermediateDirectories: true)
                working = "Looking inside \(name)…"
                let listing = await Shell.capture("/usr/bin/tar", ["-tvf", set.first.path])
                tarSizes = await Task.detached { Self.parseListing(listing.output) }.value
                tarEntries = listing.output.split(whereSeparator: \.isNewline).count
                ok = await extractWithTar(set.first, into: container, sizes: tarSizes, entries: tarEntries, name: name)
                if ok { reason = nil }
            }
        } else {
            ok = await extractWithTar(set.first, into: container, sizes: tarSizes, entries: tarEntries, name: name)
        }
        guard ok else {
            cleanUp(container)
            problem = reason ?? "\(name) couldn't be unpacked. It may be damaged, password-protected, or a format macOS doesn't read."
            return nil
        }
        unpackedContainer = container
        unpackedDestination = place.url
        archiveParts = set.parts
        note = place.note
        return Self.innerFolder(of: container)
    }

    private func extractWithSevenZip(_ tool: URL, _ archive: URL, into container: URL, total: Int,
                                     name: String) async -> (ok: Bool, problem: String?, tryTar: Bool) {
        let tracker = UnpackTracker()
        working = "Unpacking \(name)…"
        progress = 0
        let poll = Task { @MainActor [weak self] in
            var measureEvery = 0.5
            var lastMeasured = Date.distantPast
            var written: Int? = nil
            while !Task.isCancelled {
                if total > 0 && Date().timeIntervalSince(lastMeasured) >= measureEvery {
                    let started = Date()
                    written = await Task.detached { Self.folderSize(container) }.value
                    measureEvery = max(0.5, Date().timeIntervalSince(started) * 4)
                    lastMeasured = Date()
                }
                let reported = tracker.percent.map { Double($0) / 100 }
                let measured = written.map { Double($0) / Double(total) }
                if let fraction = [reported, measured].compactMap({ $0 }).min().map({ min(0.99, $0) }) {
                    self?.progress = fraction
                    self?.working = total > 0
                        ? "Unpacking \(name): \(Self.bytes(Int(Double(total) * fraction))) of \(Self.bytes(total)) (\(Int(fraction * 100))%)"
                        : "Unpacking \(name): \(Int(fraction * 100))%"
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let status = await Shell.runStreaming(tool.path, ["x", archive.path, "-o" + container.path, "-y", "-bsp1", "-bso1", "-bse1"],
                                              separators: [10, 13, 8]) { piece in tracker.take(piece) }
        poll.cancel()
        if status == 0 || status == 1 { return (true, nil, false) }
        let found = Unpacker.problem(from: tracker.messages, name: name)
        return (false, found.text, found.tryTar)
    }

    private func extractWithTar(_ archive: URL, into container: URL, sizes: [String: Int], entries totalEntries: Int,
                                name: String) async -> Bool {
        let totalBytes = sizes.values.reduce(0, +)
        let counter = UnpackCounter()
        let measureDisk = totalEntries < 2000
        working = "Unpacking \(name)…"
        let poll = Task { @MainActor [weak self] in
            var measureEvery = 0.5
            var lastMeasured = Date.distantPast
            var written = 0
            while !Task.isCancelled {
                let done = counter.snapshot
                if measureDisk && Date().timeIntervalSince(lastMeasured) >= measureEvery {
                    let started = Date()
                    written = await Task.detached { Self.folderSize(container) }.value
                    measureEvery = max(0.5, Date().timeIntervalSince(started) * 4)
                    lastMeasured = Date()
                } else if !measureDisk {
                    written = done.bytes
                }
                if totalBytes > 0 {
                    let fraction = min(0.99, Double(written) / Double(totalBytes))
                    self?.progress = fraction
                    self?.working = "Unpacking \(name): \(Self.bytes(written)) of \(Self.bytes(totalBytes)) (\(Int(fraction * 100))%)"
                } else if totalEntries > 0 && done.files > 0 {
                    let fraction = min(0.99, Double(done.files) / Double(totalEntries))
                    self?.progress = fraction
                    self?.working = "Unpacking \(name): \(done.files) of \(totalEntries) items (\(Int(fraction * 100))%)"
                } else {
                    self?.progress = nil
                    self?.working = "Unpacking \(name): \(Self.bytes(written)) so far…"
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let status = await Shell.runStreaming("/usr/bin/tar", ["-xvf", archive.path, "-C", container.path]) { line in
            guard line.hasPrefix("x ") else { return }
            counter.add(bytes: sizes[Self.entryKey(line.dropFirst(2))] ?? 0)
        }
        poll.cancel()
        return status == 0
    }

    nonisolated static func parseListing(_ text: String) -> [String: Int] {
        var sizes: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.first != "d" else { continue }
            var fields: [Substring] = []
            var index = line.startIndex
            while fields.count < 8 && index < line.endIndex {
                while index < line.endIndex && line[index] == " " { index = line.index(after: index) }
                let start = index
                while index < line.endIndex && line[index] != " " { index = line.index(after: index) }
                fields.append(line[start..<index])
            }
            while index < line.endIndex && line[index] == " " { index = line.index(after: index) }
            guard fields.count == 8, let size = Int(fields[4]), index < line.endIndex else { continue }
            sizes[entryKey(line[index...])] = size
        }
        return sizes
    }

    nonisolated static func folderSize(_ folder: URL) -> Int {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            total += values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
        }
        return total
    }

    nonisolated static func entryKey(_ raw: Substring) -> String {
        var key = raw.trimmingCharacters(in: .whitespaces)
        while key.hasPrefix("./") { key.removeFirst(2) }
        while key.hasSuffix("/") { key.removeLast() }
        return key.replacingOccurrences(of: "\\", with: "/")
    }

    nonisolated private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    func choose(_ exe: URL) {
        guard let current = report, exe != current.exe else { return }
        addedName = nil
        Task { await run(root: current.root, exe: exe, keeping: current.candidates) }
    }

    private func run(root: URL, exe: URL?, keeping known: [URL]? = nil) async {
        working = "Reading \(exe?.lastPathComponent ?? root.lastPathComponent)…"
        let rosetta = AppModel.shared.runtimes.rosetta
        let pinned = exe
        let result = await Task.detached { () -> AnalysisReport? in
            let found = known ?? (pinned == nil ? Analyzer.candidates(in: root) : [])
            guard let target = pinned ?? found.first else { return nil }
            return await Analyzer.analyzeWithLookup(exe: target, root: root, candidates: found, rosetta: rosetta)
        }.value
        working = nil
        if let result {
            report = result
        } else {
            problem = "There's no Windows program in there (no .exe, .msi or .bat)."
        }
    }

    private static func innerFolder(of container: URL) -> URL {
        let fm = FileManager.default
        let items = ((try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? [])
            .filter { !["__MACOSX", ".DS_Store"].contains($0.lastPathComponent) }
        if items.count == 1, let only = items.first, fm.isDirectory(only) { return only }
        return container
    }

    private func cleanUp(_ container: URL) {
        let fm = FileManager.default
        fm.removeIfPresent(container)
        let staging = container.deletingLastPathComponent()
        if staging.lastPathComponent == UnpackDestination.stagingName,
           ((try? fm.contentsOfDirectory(atPath: staging.path)) ?? ["?"]).isEmpty {
            try? fm.removeItem(at: staging)
        }
    }

    private func discardUnpacked() {
        if let container = unpackedContainer { cleanUp(container) }
        unpackedContainer = nil
        unpackedDestination = nil
    }

    func add(play: Bool) {
        guard let r = report else { return }
        let fm = FileManager.default
        var exe = r.exe
        if let container = unpackedContainer {
            let destination = unpackedDestination ?? UnpackDestination.gamesFolder
            try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
            let baseName = r.root == container ? sourceName : r.root.lastPathComponent
            var dest = destination.appendingPathComponent(baseName, isDirectory: true)
            var n = 2
            while fm.exists(dest) {
                dest = destination.appendingPathComponent("\(baseName) \(n)", isDirectory: true)
                n += 1
            }
            do {
                try fm.moveItem(at: r.root, to: dest)
            } catch {
                problem = "Couldn't move it into \(destination.path): \(error.localizedDescription)"
                return
            }
            exe = URL(fileURLWithPath: dest.path + r.exe.path.dropFirst(r.root.path.count))
            cleanUp(container)
            unpackedContainer = nil
            unpackedDestination = nil
            note = "Unpacked to \((dest.path as NSString).abbreviatingWithTildeInPath)."

            if UserDefaults.standard.bool(forKey: "deleteArchiveAfterAdd") && !archiveParts.isEmpty {
                var failed: [String] = []
                for part in archiveParts {
                    do { try fm.removeItem(at: part) } catch { failed.append(part.lastPathComponent) }
                }
                archiveDeleted = failed.isEmpty
                if !failed.isEmpty {
                    note = "Couldn't delete \(failed.joined(separator: ", ")); you can delete it yourself."
                }
            }
        }
        AppModel.shared.add(exe, launch: play, settings: r.settings, name: r.name)
        addedName = r.name
    }
}

struct AnalyzerView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var analyzer = AnalyzerModel.shared
    @State private var targeted = false
    @AppStorage("deleteArchiveAfterAdd") private var deleteAfterAdd = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            dropArea
                .padding(16)
            Divider()
            if analyzer.working == nil && (analyzer.report != nil || analyzer.problem != nil) {
                HStack {
                    Button { analyzer.reset() } label: { Label("All Checks", systemImage: "chevron.left") }
                        .help("Back to your library and recent checks")
                    Spacer()
                    if let url = analyzer.lastChecked {
                        Button { analyzer.analyze(url) } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                            .help("Read \(url.lastPathComponent) again, e.g. after changing its files")
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let working = analyzer.working {
                        if let progress = analyzer.progress {
                            VStack(alignment: .leading, spacing: 8) {
                                TaskProgressBar(value: progress)
                                Text(working)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(working).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else if let problem = analyzer.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else if let report = analyzer.report {
                        ReportView(report: report)
                    } else {
                        startPage
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            if let report = analyzer.report, analyzer.working == nil {
                Divider()
                actionBar(report)
                    .padding(14)
            }
        }
        .frame(minWidth: 560, minHeight: 620)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            analyzer.analyze(url)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var startPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Ferry reads the program's files without running it, and tells you what it is, what it needs, whether anything will block it, and which settings to use.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let games = model.games.filter { !$0.exePath.isEmpty }
            if !games.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Library").font(.headline)
                    Text("See what Ferry found in a game or app you've already added, and why it picked its engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(games) { g in
                        startRow(title: g.name, detail: model.subtitle(for: g)) {
                            GameIconView(game: g, side: 26)
                        } action: {
                            analyzer.analyze(URL(fileURLWithPath: g.exePath))
                        }
                    }
                }
            }
            let recents = recentChecks
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Checks").font(.headline)
                    ForEach(recents, id: \.self) { url in
                        startRow(title: url.lastPathComponent,
                                 detail: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 26, height: 26)
                        } action: {
                            analyzer.analyze(url)
                        }
                    }
                }
            }
        }
    }

    private var recentChecks: [URL] {
        (UserDefaults.standard.stringArray(forKey: AnalyzerModel.recentsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private func startRow<Icon: View>(title: String, detail: String, @ViewBuilder icon: () -> Icon,
                                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Check \(title)")
    }

    private var dropArea: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(spacing: 14) {
            Image(systemName: "stethoscope")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop a program, folder or archive to check it").font(.headline)
                Text(".exe, .msi, .bat, a folder, or .zip / .rar / .7z (any part of a multi-part archive)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Choose…") { choose() }
        }
        .padding(16)
        .background(shape.fill(targeted ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(Color.secondary.opacity(0.06))))
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.4))))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = (AnalyzerModel.programExtensions + AnalyzerModel.archivePickerExtensions)
            .compactMap { UTType(filenameExtension: $0) } + [.folder]
        panel.message = "Choose a Windows program, a folder, or an archive"
        if panel.runModal() == .OK, let url = panel.url { analyzer.analyze(url) }
    }

    @ViewBuilder
    private func actionBar(_ report: AnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = analyzer.note {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !analyzer.archiveParts.isEmpty && analyzer.addedName == nil {
                Toggle(analyzer.archiveParts.count > 1
                       ? "Permanently delete the archive's \(analyzer.archiveParts.count) parts after adding (can't be undone)"
                       : "Permanently delete the archive after adding (can't be undone)", isOn: $deleteAfterAdd)
                    .toggleStyle(.themedCheckbox)
                    .font(.caption)
            }
            buttonRow(report)
        }
    }

    @ViewBuilder
    private func buttonRow(_ report: AnalysisReport) -> some View {
        let existing = model.games.first { $0.exePath == report.exe.path }
        HStack {
            if analyzer.addedName == nil, let existing {
                Label("\(existing.name) is already in your library", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Its Settings") {
                    model.settingsGame = existing.id
                    openWindow(id: "main")
                }
            } else if let added = analyzer.addedName {
                Label(analyzer.archiveDeleted ? "\(added) is in your library; the archive was deleted" : "\(added) is in your library",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.setupComplete {
                Text("Finish Ferry's setup in the main window to add games and apps.").font(.caption).foregroundStyle(.secondary)
            } else if report.verdict == .wontWork {
                Text("Ferry can't run this one.").font(.caption).foregroundStyle(.secondary)
            }
            if existing == nil || analyzer.addedName != nil {
                Spacer()
                Button("Add to Ferry") { analyzer.add(play: false) }
                    .disabled(!canAdd(report))
                Button("Add and Play") { analyzer.add(play: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd(report))
            }
        }
    }

    private func canAdd(_ report: AnalysisReport) -> Bool {
        model.setupComplete && report.verdict != .wontWork && analyzer.addedName == nil
    }
}

private struct ReportView: View {
    let report: AnalysisReport
    @ObservedObject private var analyzer = AnalyzerModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.name).font(.title2.weight(.semibold))
                Spacer()
                verdictBadge
            }

            if report.candidates.count > 1 {
                if report.asksWhichProgram {
                    Label("This folder has more than one program. Choose the one Ferry should start. When single-player and multiplayer are separate programs, Ferry offers to add the other one as its own entry too.",
                          systemImage: "questionmark.circle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Program to run", selection: Binding(get: { report.exe }, set: { analyzer.choose($0) })) {
                    ForEach(report.candidates, id: \.self) { url in
                        Text(report.candidateLabels[url].map { "\($0) — \(relativePath(url))" } ?? relativePath(url)).tag(url)
                    }
                }
                .help("Ferry ranks the programs it found: a game's single-player program first, then multiplayer and launchers; servers, editors and settings tools last.")
            } else {
                Text(report.exe.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            section("What it is") {
                row("Type", report.isInstaller ? "Installer" : (report.framework.map { "\($0) game" } ?? "Windows program"))
                row("Architecture", report.arch.label)
                row("Graphics", report.graphics == .unknown ? "Not detected" : report.graphics.label)
                row("Needs", report.libraries.isEmpty ? "Nothing beyond standard Windows" : report.libraries.joined(separator: ", "))
            }

            if !report.findings.isEmpty {
                section("Worth knowing") {
                    ForEach(report.findings.sorted { $0.level.rawValue > $1.level.rawValue }) { finding in
                        Label {
                            Text(finding.text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: icon(finding.level)).foregroundStyle(color(finding.level))
                        }
                    }
                }
            }

            if report.verdict != .wontWork {
                section("Recommended settings") {
                    row("Translation", report.engine.title)
                    row("Windows version", windowsName(report.settings.windowsVersion))
                    if report.settings.cncDdraw {
                        row("Old 2D game fix", "On (cnc-ddraw)")
                    }
                    if !report.settings.metalSharpBackend.isEmpty {
                        row("MetalSharp draws with", ["dxvk": "DXVK", "wine": "WineD3D", "vkd3d": "VKD3D-Proton"][report.settings.metalSharpBackend] ?? report.settings.metalSharpBackend)
                    }
                    if !report.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.reasons, id: \.self) { reason in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•")
                                    Text(reason).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            Text("This is a best guess from the program's files; Ferry hasn't run it. If it doesn't start, Ferry offers the next engine to try.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var verdictBadge: some View {
        let (text, tint): (String, Color) = {
            switch report.verdict {
            case .shouldWork: return ("Should work", .green)
            case .mightWork: return ("Might work", .orange)
            case .wontWork: return ("Won't run", .red)
            }
        }()
        return Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.07)))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func relativePath(_ url: URL) -> String {
        let root = report.root.path
        return url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count + 1)) : url.lastPathComponent
    }

    private func windowsName(_ tag: String) -> String {
        switch tag {
        case "win11": return "Windows 11"
        case "win81": return "Windows 8.1"
        case "win7": return "Windows 7"
        case "winxp64": return "Windows XP"
        default: return "Windows 10"
        }
    }

    private func icon(_ level: Finding.Level) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocker: return "xmark.octagon.fill"
        }
    }

    private func color(_ level: Finding.Level) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}
