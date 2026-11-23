import Foundation

struct RuntimeInfo: Codable {
    var version: String
    var binDir: String? = nil
    var dxvk64: String? = nil
    var dxvk32: String? = nil
    var d3dmetalImported: String? = nil
    var asset: String? = nil
}

@MainActor
final class RuntimeManager: ObservableObject {
    @Published private(set) var info: [RuntimeKind: RuntimeInfo] = [:]
    @Published var task: String? = nil
    @Published var progress: Double? = nil
    @Published var rosetta: Bool = true
    @Published private(set) var hasD3DMetalBackup = false

    @Published private(set) var latest: [RuntimeKind: String] = [:]
    @Published private(set) var lastUpdateCheck: Date? = nil
    @Published private(set) var checkingForUpdates = false

    private var inflight: [RuntimeKind: Task<Void, Error>] = [:]
    private let fm = FileManager.default

    init() {
        reload()
        lastUpdateCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
        if let saved = UserDefaults.standard.dictionary(forKey: "latestVersions") as? [String: String] {
            for (key, tag) in saved { if let kind = RuntimeKind(rawValue: key) { latest[kind] = tag } }
        }
        Task { await checkRosetta() }
    }

    func updateAvailable(_ kind: RuntimeKind) -> Bool {
        guard let installed = info[kind]?.version, let newest = latest[kind] else { return false }
        return installed != newest
    }

    var availableUpdates: [RuntimeKind] { RuntimeKind.allCases.filter { updateAvailable($0) } }

    @discardableResult
    func checkForUpdates() async -> Bool {
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        var reached = false
        for kind in RuntimeKind.allCases where info[kind] != nil {
            if let found = try? await GitHub.latestAsset(repo: kind.repo, matching: kind.matches) {
                latest[kind] = found.tag
                reached = true
            }
        }
        if reached {
            let now = Date()
            lastUpdateCheck = now
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
            saveLatest()
        }
        return reached
    }

    private func saveLatest() {
        var dict: [String: String] = [:]
        for (kind, tag) in latest { dict[kind.rawValue] = tag }
        UserDefaults.standard.set(dict, forKey: "latestVersions")
    }

    func folder(_ kind: RuntimeKind) -> URL { Paths.runtimes.appendingPathComponent(kind.rawValue, isDirectory: true) }
    private var gptkBackup: URL { Paths.runtimes.appendingPathComponent("gptk.original", isDirectory: true) }

    func reload() {
        var fresh: [RuntimeKind: RuntimeInfo] = [:]
        for kind in RuntimeKind.allCases {
            let marker = folder(kind).appendingPathComponent(".ferry.json")
            if let data = try? Data(contentsOf: marker),
               let decoded = try? JSONDecoder().decode(RuntimeInfo.self, from: data) {
                fresh[kind] = decoded
            }
        }
        info = fresh
        RuntimeKind.d3dmetalWine = fresh[.x64] != nil ? .x64 : .gptk
        hasD3DMetalBackup = fm.exists(gptkBackup)
    }

    private func save(_ value: RuntimeInfo, for kind: RuntimeKind) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: folder(kind).appendingPathComponent(".ferry.json"))
    }

    func binDir(_ kind: RuntimeKind) -> URL? {
        guard let rel = info[kind]?.binDir else { return nil }
        return folder(kind).appendingPathComponent(rel, isDirectory: true)
    }

    func d3dmetalDLLs() -> [URL] {
        guard let bin = binDir(.gptk) else { return [] }
        let wineLib = bin.deletingLastPathComponent().appendingPathComponent("lib/wine", isDirectory: true)
        let unix = wineLib.appendingPathComponent("x86_64-unix", isDirectory: true)
        let windows = wineLib.appendingPathComponent("x86_64-windows", isDirectory: true)
        let names = (try? fm.contentsOfDirectory(atPath: unix.path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".so"),
                  let target = try? fm.destinationOfSymbolicLink(atPath: unix.appendingPathComponent(name).path),
                  target.hasSuffix("libd3dshared.dylib") else { return nil }
            let dll = windows.appendingPathComponent((name as NSString).deletingPathExtension + ".dll")
            return fm.exists(dll) ? dll : nil
        }
    }

    func wine(for kind: RuntimeKind, arch: PEArch) -> URL? {
        guard let bin = binDir(kind) else { return nil }
        let wine64 = bin.appendingPathComponent("wine64")
        let wine = bin.appendingPathComponent("wine")
        if arch != .x86, fm.exists(wine64) { return wine64 }
        if fm.exists(wine) { return wine }
        return fm.exists(wine64) ? wine64 : nil
    }

    func kosmicKrispDriver() -> URL? {
        guard let bin = binDir(.mach9) else { return nil }
        let folder = bin.deletingLastPathComponent().appendingPathComponent("share/vulkan/icd.d")
        let name = (try? fm.contentsOfDirectory(atPath: folder.path))?
            .first { $0.lowercased().hasPrefix("kosmickrisp") && $0.hasSuffix(".json") }
        return name.map { folder.appendingPathComponent($0) }
    }

    func wineserver(for kind: RuntimeKind) -> URL? {
        guard let bin = binDir(kind) else { return nil }
        let ws = bin.appendingPathComponent("wineserver")
        return fm.exists(ws) ? ws : nil
    }

    func dxvkFolders() -> (x64: URL?, x32: URL?) {
        guard let i = info[.dxvk] else { return (nil, nil) }
        return (i.dxvk64.map { folder(.dxvk).appendingPathComponent($0) },
                i.dxvk32.map { folder(.dxvk).appendingPathComponent($0) })
    }

    func ensure(_ kind: RuntimeKind) async throws {
        if info[kind] != nil { return }
        if let running = inflight[kind] { return try await running.value }
        let job = Task { try await self.install(kind) }
        inflight[kind] = job
        defer { inflight[kind] = nil }
        try await job.value
    }

    func install(_ kind: RuntimeKind) async throws {
        task = "Looking up the latest \(kind.title)…"
        progress = nil
        defer { task = nil; progress = nil }

        let (tag, asset) = try await GitHub.latestAsset(repo: kind.repo, matching: kind.matches)
        guard let url = URL(string: asset.browserDownloadUrl) else { throw FerryError("Bad download link for \(kind.title).") }

        let archive = Paths.cache.appendingPathComponent(asset.name)
        if fm.byteSize(archive) != asset.size {
            task = "Downloading \(kind.title) \(tag)…"
            try await download(url, to: archive, expectedBytes: asset.size)
        }

        task = "Unpacking \(kind.title)…"
        progress = nil
        let staging = Paths.runtimes.appendingPathComponent(kind.rawValue + ".new", isDirectory: true)
        fm.removeIfPresent(staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let status: Int32
        if asset.name.lowercased().hasSuffix(".zip") {
            status = await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        } else {
            status = await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path])
        }
        guard status == 0 else {
            fm.removeIfPresent(staging)
            fm.removeIfPresent(archive)
            throw FerryError("Couldn't unpack \(asset.name). The download may be damaged; try again.")
        }
        await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])

        let dest = folder(kind)
        fm.removeIfPresent(dest)
        if kind == .gptk { fm.removeIfPresent(gptkBackup) }
        try fm.moveItem(at: staging, to: dest)

        var newInfo = RuntimeInfo(version: tag)
        newInfo.asset = asset.name
        let prefix = dest.path + "/"
        func relative(_ u: URL) -> String { u.path.replacingOccurrences(of: prefix, with: "") }

        switch kind {
        case .dxvk:
            func dllFolder(_ name: String) -> URL? {
                fm.firstItem(under: dest) {
                    $0.lastPathComponent == name && self.fm.exists($0.appendingPathComponent("d3d11.dll"))
                }
            }
            guard let x64 = dllFolder("x64") else { throw FerryError("The DXVK download didn't contain 64-bit DLLs.") }
            newInfo.dxvk64 = relative(x64)
            newInfo.dxvk32 = dllFolder("x32").map(relative)
        case .gptk, .staging, .arm64, .mach9, .x64:
            func inBin(_ name: String) -> URL? {
                fm.firstItem(under: dest, where: {
                    $0.lastPathComponent == name && ["bin", "MacOS"].contains($0.deletingLastPathComponent().lastPathComponent)
                        && !$0.path.contains("/lib/wine/")
                })
            }
            guard let wineProgram = inBin("wineserver") ?? inBin("wine") else {
                throw FerryError("The \(kind.title) download didn't contain Wine.")
            }
            newInfo.binDir = relative(wineProgram.deletingLastPathComponent())
        }
        try save(newInfo, for: kind)
        fm.removeIfPresent(archive)
        latest[kind] = tag
        saveLatest()
        reload()
    }

    func remove(_ kind: RuntimeKind) {
        fm.removeIfPresent(folder(kind))
        if kind == .gptk { fm.removeIfPresent(gptkBackup) }
        reload()
    }

    func download(_ url: URL, to dest: URL, expectedBytes: Int) async throws {
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let base = task
        progress = expectedBytes > 0 ? 0 : nil
        var split = false
        if expectedBytes >= Self.splitAbove { split = await acceptsRanges(url) }
        let parts = split ? (0..<Self.pieces).map { dest.appendingPathExtension("part\($0)") }
                          : [dest.appendingPathExtension("part")]
        if parts.count > 1 { adoptSingleDownload(dest, as: parts[0], limit: Self.ranges(expectedBytes)[0].count) }
        let poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if expectedBytes > 0 {
                    let done = parts.reduce(0) { $0 + self.fm.byteSize($1) }
                    self.progress = min(1, Double(done) / Double(expectedBytes))
                    if let base { self.task = base + " " + Self.sizeText(done, of: expectedBytes) }
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { poll.cancel(); if base != nil { task = base } }

        let ok: Bool
        if parts.count == 1 {
            if expectedBytes > 0 && fm.byteSize(parts[0]) == expectedBytes {
                ok = true
            } else {
                ok = await curl(["-C", "-", "-o", parts[0].path, url.absoluteString]) == 0
                    && (expectedBytes == 0 || fm.byteSize(parts[0]) == expectedBytes)
            }
        } else {
            let ranges = Self.ranges(expectedBytes)
            ok = await withTaskGroup(of: Bool.self) { group in
                for (part, range) in zip(parts, ranges) {
                    group.addTask { await self.fetch(url, range: range, into: part) }
                }
                var all = true
                for await done in group { all = all && done }
                return all
            }
        }
        guard ok else {
            throw FerryError("The download from \(url.host ?? "the internet") stopped. Check your connection and try again; it carries on from where it stopped.")
        }
        fm.removeIfPresent(dest)
        if parts.count == 1 {
            try fm.moveItem(at: parts[0], to: dest)
        } else {
            guard await join(parts, into: dest), fm.byteSize(dest) == expectedBytes else {
                fm.removeIfPresent(dest)
                parts.forEach(fm.removeIfPresent)
                throw FerryError("The download from \(url.host ?? "the internet") came out the wrong size. Try again.")
            }
            parts.forEach(fm.removeIfPresent)
        }
    }

    static let splitAbove = 32 * 1_048_576
    static let pieces = 4

    static func ranges(_ total: Int) -> [ClosedRange<Int>] {
        let size = (total + pieces - 1) / pieces
        return (0..<pieces).compactMap { i in
            let start = i * size, end = min(total, start + size) - 1
            return start <= end ? start...end : nil
        }
    }

    static func sizeText(_ done: Int, of total: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: Int64(done))) of \(f.string(fromByteCount: Int64(total)))"
    }

    private func acceptsRanges(_ url: URL) async -> Bool {
        let (status, output) = await Shell.capture("/usr/bin/curl", ["-L", "-s", "-r", "0-0", "-o", "/dev/null",
                                                                     "-w", "%{http_code}", "--max-time", "20", url.absoluteString])
        return status == 0 && output.trimmingCharacters(in: .whitespacesAndNewlines) == "206"
    }

    private func adoptSingleDownload(_ dest: URL, as first: URL, limit: Int) {
        let single = dest.appendingPathExtension("part")
        guard fm.exists(single), !fm.exists(first) else { fm.removeIfPresent(single); return }
        guard (try? fm.moveItem(at: single, to: first)) != nil else { return }
        if fm.byteSize(first) > limit, let handle = try? FileHandle(forWritingTo: first) {
            try? handle.truncate(atOffset: UInt64(limit))
            try? handle.close()
        }
    }

    private func fetch(_ url: URL, range: ClosedRange<Int>, into part: URL) async -> Bool {
        for _ in 0..<3 {
            let have = fm.byteSize(part)
            if have == range.count { return true }
            if have > range.count { fm.removeIfPresent(part); continue }
            if !fm.exists(part) { fm.createFile(atPath: part.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: part) else { return false }
            _ = try? handle.seekToEnd()
            _ = await curl(["-r", "\(range.lowerBound + have)-\(range.upperBound)", url.absoluteString], output: handle)
            try? handle.close()
        }
        return fm.byteSize(part) == range.count
    }

    private func join(_ parts: [URL], into dest: URL) async -> Bool {
        guard fm.createFile(atPath: dest.path, contents: nil), let out = try? FileHandle(forWritingTo: dest) else { return false }
        defer { try? out.close() }
        for part in parts {
            guard let input = try? FileHandle(forReadingFrom: part) else { return false }
            defer { try? input.close() }
            while let chunk = try? input.read(upToCount: 8 * 1_048_576), !chunk.isEmpty {
                guard (try? out.write(contentsOf: chunk)) != nil else { return false }
            }
        }
        return true
    }

    private var downloads: [Process] = []

    func stopDownloads() {
        downloads.forEach { $0.terminate() }
    }

    private func curl(_ args: [String], output: FileHandle? = nil) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-L", "--fail", "--retry", "3", "-s"] + args
            p.standardOutput = output ?? FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { proc in
                Task { @MainActor in self.downloads.removeAll { $0 === proc } }
                cont.resume(returning: proc.terminationStatus)
            }
            do {
                try p.run()
                downloads.append(p)
            } catch {
                cont.resume(returning: -1)
            }
        }
    }

    func isCached(_ name: String) -> Bool {
        fm.byteSize(Paths.cache.appendingPathComponent("windows", isDirectory: true).appendingPathComponent(name)) > 0
    }

    func cachedInstaller(_ url: URL, name: String) async throws -> URL {
        let dest = Paths.cache.appendingPathComponent("windows", isDirectory: true).appendingPathComponent(name)
        if fm.byteSize(dest) > 0 { return dest }
        try await download(url, to: dest, expectedBytes: 0)
        return dest
    }

    func importD3DMetal(from dmg: URL) async throws {
        try await ensure(.gptk)
        task = "Opening \(dmg.lastPathComponent)…"
        progress = nil
        defer { task = nil }

        let (status, output) = await Shell.capture("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-plist", dmg.path])
        guard status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw FerryError("macOS couldn't open that disk image.") }
        let volume = URL(fileURLWithPath: mount)

        do {
            if fm.firstItem(under: volume, where: { $0.lastPathComponent == "D3DMetal.framework" }) == nil,
               let inner = fm.firstItem(under: volume, where: {
                   $0.pathExtension.lowercased() == "dmg" && $0.lastPathComponent.lowercased().contains("evaluation environment")
               }) {
                try await importD3DMetal(from: inner)
                await Shell.run("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
                return
            }
            guard let newExternal = fm.firstItem(under: volume, where: {
                $0.lastPathComponent == "external" && self.fm.exists($0.appendingPathComponent("D3DMetal.framework"))
            }) else { throw FerryError("That disk image doesn't contain D3DMetal. Download \"Evaluation environment for Windows games\" from developer.apple.com/games.") }

            let runtime = folder(.gptk)
            guard let framework = fm.firstItem(under: runtime, where: { $0.lastPathComponent == "D3DMetal.framework" }) else {
                throw FerryError("Couldn't find D3DMetal inside the installed Game Porting Toolkit.")
            }
            let external = framework.deletingLastPathComponent()
            let newVersion = d3dmetalVersion(in: newExternal) ?? "this version"
            if !Self.wineRuns(d3dmetal: newExternal.deletingLastPathComponent().appendingPathComponent("wine"),
                              engine: external.deletingLastPathComponent().appendingPathComponent("wine")) {
                throw FerryError("D3DMetal \(newVersion) needs a newer Wine than Ferry's D3DMetal engine has, so games wouldn't start with it. Ferry kept the D3DMetal it has. It can use this one once a Game Porting Toolkit 4 build of Wine is released; Ferry's update check installs that when it is.")
            }

            task = "Backing up the bundled D3DMetal…"
            if !fm.exists(gptkBackup) {
                await Shell.run("/bin/cp", ["-cR", runtime.path, gptkBackup.path])
            }

            task = "Installing the new D3DMetal…"
            fm.removeIfPresent(external)
            guard await Shell.run("/usr/bin/ditto", [newExternal.path, external.path]) == 0 else {
                throw FerryError("Copying D3DMetal failed. Use Restore to put the bundled one back.")
            }
            let newWine = newExternal.deletingLastPathComponent().appendingPathComponent("wine")
            let oldWine = external.deletingLastPathComponent().appendingPathComponent("wine")
            if fm.isDirectory(newWine), fm.isDirectory(oldWine) {
                await Shell.run("/usr/bin/ditto", [newWine.path, oldWine.path])
            }
            await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", runtime.path])

            var updated = info[.gptk] ?? RuntimeInfo(version: "?")
            updated.d3dmetalImported = d3dmetalVersion(in: external) ?? dmg.deletingPathExtension().lastPathComponent
            try save(updated, for: .gptk)
        } catch {
            await Shell.run("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
            reload()
            throw error
        }
        await Shell.run("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
        reload()
    }

    nonisolated static func wineRuns(d3dmetal: URL, engine: URL) -> Bool {
        guard let d3d11 = try? Data(contentsOf: d3dmetal.appendingPathComponent("x86_64-windows/d3d11.dll"), options: .mappedIfSafe),
              let ntdll = try? Data(contentsOf: engine.appendingPathComponent("x86_64-windows/ntdll.dll"), options: .mappedIfSafe)
        else { return true }
        return !needsNewerWine(d3d11: d3d11, ntdll: ntdll)
    }

    nonisolated static func needsNewerWine(d3d11: Data, ntdll: Data) -> Bool {
        let newHook = Data("__wine_init_unix_call".utf8)
        return d3d11.range(of: newHook) != nil && ntdll.range(of: newHook) == nil
    }

    func removeIncompatibleD3DMetal() -> String? {
        guard let imported = info[.gptk]?.d3dmetalImported, fm.exists(gptkBackup), let bin = binDir(.gptk) else { return nil }
        let wine = bin.deletingLastPathComponent().appendingPathComponent("lib/wine", isDirectory: true)
        guard !Self.wineRuns(d3dmetal: wine, engine: wine) else { return nil }
        restoreBundledD3DMetal()
        return imported
    }

    func restoreBundledD3DMetal() {
        guard fm.exists(gptkBackup) else { return }
        fm.removeIfPresent(folder(.gptk))
        try? fm.moveItem(at: gptkBackup, to: folder(.gptk))
        reload()
    }

    var x64D3DMetalVersion: String? {
        let runtime = folder(.x64).appendingPathComponent("MetalSharp-Wine-x86_64.app/Contents/share/metalsharp/runtime")
        let wanted = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "d3dmetal-gptk4" : "d3dmetal-gptk3"
        let folders = (try? fm.contentsOfDirectory(atPath: runtime.path)) ?? []
        guard let match = folders.filter({ $0.hasPrefix(wanted) }).sorted().last else { return nil }
        return d3dmetalVersion(in: runtime.appendingPathComponent(match).appendingPathComponent("external"))
    }

    var backupD3DMetalVersion: String? {
        guard let rel = info[.gptk]?.binDir else { return nil }
        let bin = gptkBackup.appendingPathComponent(rel)
        return d3dmetalVersion(in: bin.deletingLastPathComponent().appendingPathComponent("lib/external"))
    }

    private func d3dmetalVersion(in external: URL) -> String? {
        let fw = external.appendingPathComponent("D3DMetal.framework")
        for rel in ["Resources/Info.plist", "Versions/A/Resources/Info.plist", "Info.plist"] {
            if let dict = NSDictionary(contentsOf: fw.appendingPathComponent(rel)),
               let version = dict["CFBundleShortVersionString"] as? String {
                return version
            }
        }
        return nil
    }

    static let gstreamerFramework = URL(fileURLWithPath: "/Library/Frameworks/GStreamer.framework")
    var gstreamerInstalled: Bool { fm.exists(Self.gstreamerFramework) }

    func gstreamerPackage() async -> (version: String, url: URL)? {
        var version = "1.28.9"
        if let listing = URL(string: "https://gstreamer.freedesktop.org/data/pkg/osx/"),
           let page = try? await URLSession.shared.data(from: listing) {
            let html = String(decoding: page.0, as: UTF8.self)
            let regex = try? NSRegularExpression(pattern: #"href="(\d+)\.(\d+)\.(\d+)/""#)
            var best: [Int]? = nil
            for match in regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
                let parts = (1...3).compactMap { i -> Int? in
                    guard let r = Range(match.range(at: i), in: html) else { return nil }
                    return Int(html[r])
                }
                guard parts.count == 3, parts[0] == 1, parts[1] % 2 == 0 else { continue }
                if best == nil || parts.lexicographicallyPrecedes(best!) == false { best = parts }
            }
            if let best { version = best.map(String.init).joined(separator: ".") }
        }
        guard let url = URL(string: "https://gstreamer.freedesktop.org/data/pkg/osx/\(version)/gstreamer-1.0-\(version)-universal.pkg") else { return nil }
        return (version, url)
    }

    func remoteSize(_ url: URL) async -> Int? {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        guard let result = try? await URLSession.shared.data(for: req) else { return nil }
        let length = result.1.expectedContentLength
        return length > 0 ? Int(length) : nil
    }

    func installGStreamer() async throws {
        if gstreamerInstalled { return }
        guard let package = await gstreamerPackage() else { throw FerryError("Couldn't find the GStreamer download.") }
        let version = package.version
        let url = package.url
        task = "Downloading GStreamer \(version)…"
        defer { task = nil; progress = nil }
        let pkg = Paths.cache.appendingPathComponent("gstreamer-\(version).pkg")
        if fm.byteSize(pkg) == 0 {
            try await download(url, to: pkg, expectedBytes: await remoteSize(url) ?? 0)
        }
        task = "Installing GStreamer \(version) (macOS will ask for your password)…"
        progress = nil
        let script = "do shell script \"/usr/sbin/installer -pkg \" & quoted form of \"\(pkg.path)\" & \" -target /\" with administrator privileges"
        await Shell.run("/usr/bin/osascript", ["-e", script])
        guard gstreamerInstalled else {
            throw FerryError("GStreamer didn't install (the password prompt may have been cancelled).")
        }
        fm.removeIfPresent(pkg)
    }

    func checkRosetta() async {
        rosetta = await Shell.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]) == 0
    }

    func installRosetta() async {
        task = "Installing Rosetta 2…"
        defer { task = nil }
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        await Shell.run("/usr/bin/osascript", ["-e", script])
        await checkRosetta()
    }
}
