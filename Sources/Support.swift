import AppKit

enum Platform {
    static var metalSharpRuns32bit: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0))
    }

    static var mach9Available: Bool { metalSharpRuns32bit }

    static var memoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }

    @MainActor static var displayHz: Int {
        let hz = NSScreen.screens.first?.maximumFramesPerSecond ?? 60
        return hz >= 24 ? hz : 60
    }
}

struct FerryError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Paths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ferry", isDirectory: true)
    }()
    static let runtimes = root.appendingPathComponent("Runtimes", isDirectory: true)
    static let bottles = root.appendingPathComponent("Bottles", isDirectory: true)
    static let cache = root.appendingPathComponent("Cache", isDirectory: true)
    static let templates = root.appendingPathComponent("Templates", isDirectory: true)
    static let logs = root.appendingPathComponent("Logs", isDirectory: true)
    static let icons = root.appendingPathComponent("Icons", isDirectory: true)
    static let library = root.appendingPathComponent("library.json")
    static let shortcuts = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Ferry Games", isDirectory: true)

    static func ensure() {
        for dir in [root, runtimes, bottles, cache, templates, logs] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

extension FileManager {
    func exists(_ url: URL) -> Bool { fileExists(atPath: url.path) }

    func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    func byteSize(_ url: URL) -> Int {
        ((try? attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    func removeIfPresent(_ url: URL) {
        if exists(url) { try? removeItem(at: url) }
    }

    func firstItem(under root: URL, where match: (URL) -> Bool) -> URL? {
        guard let walker = enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker where match(url) { return url }
        return nil
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String], env: [String: String]? = nil,
                    cwd: URL? = nil, log: URL? = nil) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            if let env { p.environment = env }
            if let cwd { p.currentDirectoryURL = cwd }
            let handle = log.flatMap { Shell.openLog($0, truncate: false) }
            p.standardOutput = handle ?? FileHandle.nullDevice
            p.standardError = handle ?? FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { proc in
                try? handle?.close()
                cont.resume(returning: proc.terminationStatus)
            }
            do { try p.run() } catch {
                try? handle?.close()
                cont.resume(returning: -1)
            }
        }
    }

    static func runStreaming(_ path: String, _ args: [String], separators: Set<UInt8> = [10],
                             onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            let lines = LineSplitter(separators: separators, onLine)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { lines.feed(data) }
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                lines.feed(pipe.fileHandleForReading.readDataToEndOfFile())
                lines.flush()
                cont.resume(returning: proc.terminationStatus)
            }
            do { try p.run() } catch { cont.resume(returning: -1) }
        }
    }

    static func openLog(_ url: URL, truncate: Bool) -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if truncate || !fm.exists(url) { fm.createFile(atPath: url.path, contents: nil) }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }

    static func capture(_ path: String, _ args: [String], env: [String: String]? = nil) async -> (status: Int32, output: String) {
        await Task.detached { () -> (status: Int32, output: String) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            if let env { p.environment = env }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return (-1, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}

func splitArguments(_ text: String) -> [String] {
    var out: [String] = []
    var current = ""
    var quote: Character? = nil
    var quoted = false
    for ch in text {
        if let q = quote {
            if ch == q { quote = nil } else { current.append(ch) }
        } else if ch == "\"" || ch == "'" {
            quote = ch
            quoted = true
        } else if ch.isWhitespace {
            if !current.isEmpty || quoted { out.append(current) }
            current = ""
            quoted = false
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty || quoted { out.append(current) }
    return out
}

struct GHAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
    let size: Int
}

struct GHRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GHAsset]
}

enum GitHub {
    static func latestAsset(repo: String, matching match: (String) -> Bool) async throws -> (tag: String, asset: GHAsset) {
        let (data, response) = try await URLSession.shared.data(for: try releasesRequest(repo: repo, perPage: 40, timeout: 60))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FerryError("GitHub didn't answer for \(repo). If you've installed a lot today you may be rate-limited; try again in an hour.")
        }
        let releases = try decodeReleases(data)
        for release in releases where !release.draft && !release.prerelease {
            if let asset = release.assets.first(where: { match($0.name) }) {
                return (release.tagName, asset)
            }
        }
        throw FerryError("Couldn't find a macOS download in \(repo)'s releases.")
    }

    static func latestAssets(repo: String) async throws -> (tag: String, assets: [GHAsset]) {
        let request = try releasesRequest(repo: repo, perPage: 20, timeout: 20)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            throw FerryError(ModSearch.failureMessage(status: nil))
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200 else { throw FerryError(ModSearch.failureMessage(status: status)) }
        guard let releases = try? decodeReleases(data) else {
            throw FerryError("GitHub sent an answer Ferry couldn't read for \(repo).")
        }
        guard let latest = releases.first(where: { !$0.draft && !$0.prerelease }) else { return ("", []) }
        return (latest.tagName, latest.assets)
    }

    private static func releasesRequest(repo: String, perPage: Int, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=\(perPage)") else {
            throw FerryError("Bad release address for \(repo).")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Ferry-macOS", forHTTPHeaderField: "User-Agent")
        return req
    }

    private static func decodeReleases(_ data: Data) throws -> [GHRelease] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([GHRelease].self, from: data)
    }
}

enum GitHubSearch {
    static func repositories(_ q: String) async -> (results: [ModResult], failure: String?) {
        var c = URLComponents(string: "https://api.github.com/search/repositories")!
        c.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "per_page", value: "10")]
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = c.url else { return ([], ModSearch.failureMessage(status: nil)) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Ferry-macOS", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else {
            return ([], ModSearch.failureMessage(status: nil))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return ([], ModSearch.failureMessage(status: status)) }
        return (ModSearch.githubResults(fromSearchJSON: data), nil)
    }
}

enum PEInspector {
    static func arch(of url: URL) -> PEArch {
        guard let h = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? h.close() }
        guard let dos = try? h.read(upToCount: 64), dos.count == 64 else { return .unknown }
        let b = [UInt8](dos)
        guard b[0] == 0x4D, b[1] == 0x5A else { return .unknown }
        let offset = UInt64(b[0x3C]) | UInt64(b[0x3D]) << 8 | UInt64(b[0x3E]) << 16 | UInt64(b[0x3F]) << 24
        guard (try? h.seek(toOffset: offset)) != nil,
              let pe = try? h.read(upToCount: 6), pe.count == 6 else { return .unknown }
        let p = [UInt8](pe)
        guard p[0] == 0x50, p[1] == 0x45, p[2] == 0, p[3] == 0 else { return .unknown }
        switch UInt16(p[4]) | UInt16(p[5]) << 8 {
        case 0x014C: return .x86
        case 0x8664: return .x64
        case 0xAA64: return .arm64
        default: return .unknown
        }
    }

    private static let needles: [(GraphicsAPI, [String])] = [
        (.dx12, ["d3d12.dll", "D3D12.dll", "D3D12.DLL"]),
        (.dx11, ["d3d11.dll", "D3D11.dll", "D3D11.DLL"]),
        (.dx10, ["d3d10.dll", "D3D10.dll", "d3d10_1.dll", "D3D10_1.dll", "D3D10.DLL"]),
        (.dx9, ["d3d9.dll", "D3D9.dll", "D3D9.DLL"]),
        (.dx8, ["d3d8.dll", "D3D8.dll", "D3D8.DLL"]),
        (.vulkan, ["vulkan-1.dll", "VULKAN-1.DLL"]),
        (.opengl, ["opengl32.dll", "OPENGL32.dll", "OPENGL32.DLL", "OpenGL32.dll"]),
    ]

    static func graphicsAPI(for exe: URL) -> GraphicsAPI {
        let fm = FileManager.default
        let dir = exe.deletingLastPathComponent()
        var files = [exe]
        if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            files += items.filter { $0.pathExtension.lowercased() == "dll" }.prefix(80)
        }
        if fm.byteSize(exe) < 15_000_000, let shipping = unrealShippingExe(near: dir) {
            files.append(shipping)
        }

        var found = Set<GraphicsAPI>()
        var budget = 800_000_000
        for file in files {
            let size = fm.byteSize(file)
            if size > budget { continue }
            budget -= size
            guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { continue }
            for (api, words) in needles where !found.contains(api) {
                if words.contains(where: { data.range(of: Data($0.utf8)) != nil }) { found.insert(api) }
            }
        }
        for api in [GraphicsAPI.dx12, .dx11, .dx10, .dx9, .dx8, .vulkan, .opengl] where found.contains(api) {
            return api
        }
        return .unknown
    }

    private static func unrealShippingExe(near dir: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix("-shipping.exe") && url.path.contains("/Binaries/Win64/") { return url }
        }
        return nil
    }
}

final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void
    private let separators: Set<UInt8>

    init(separators: Set<UInt8> = [10], _ onLine: @escaping @Sendable (String) -> Void) {
        self.separators = separators
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        lock.lock()
        pending.append(data)
        var complete: [String] = []
        while let end = pending.firstIndex(where: { separators.contains($0) }) {
            complete.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...end)
        }
        lock.unlock()
        complete.forEach(onLine)
    }

    func flush() {
        lock.lock()
        let rest = pending
        pending = Data()
        lock.unlock()
        if !rest.isEmpty { onLine(String(decoding: rest, as: UTF8.self)) }
    }
}

final class UnpackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0
    private var files = 0

    func add(bytes count: Int) {
        lock.lock()
        bytes += count
        files += 1
        lock.unlock()
    }

    var snapshot: (bytes: Int, files: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (bytes, files)
    }
}
