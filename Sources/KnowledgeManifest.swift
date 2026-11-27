import Foundation

struct KnowledgeManifest {
    let version: Int
    let minFerry: String
    let files: [String]
    var suggestedModels: [String: String] = [:]

    static let maxFileSize = 512 * 1024
    static let maxFiles = 200
    static let maxTotalSize = 8 * 1024 * 1024

    static let githubURL = URL(string: "https://raw.githubusercontent.com/rhyvo/Ferry/main/Knowledge/")!

    static func endpoint(override: String?) -> URL {
        guard let override, let url = URL(string: override) else { return githubURL }
        let local = url.scheme == "file" || ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host ?? "")
        return local ? url : githubURL
    }

    static func decode(_ data: Data) -> KnowledgeManifest? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? Int, let minFerry = root["minFerry"] as? String,
              let files = root["files"] as? [String] else { return nil }
        return KnowledgeManifest(version: version, minFerry: minFerry, files: files, suggestedModels: root["suggestedModels"] as? [String: String] ?? [:])
    }

    static func read(folder: URL) -> KnowledgeManifest? {
        (try? Data(contentsOf: folder.appendingPathComponent("manifest.json"))).flatMap(decode)
    }

    static func isSafeEntry(_ path: String) -> Bool {
        !path.isEmpty && path.hasSuffix(".md") && !path.hasPrefix("/") && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    var entriesAreSafe: Bool { files.allSatisfy(Self.isSafeEntry) }

    func isCompatible(with ferry: String) -> Bool { !Self.isNewer(minFerry, than: ferry) }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func loadBest(downloaded: URL, bundled: URL?, ferry: String) -> KnowledgePack? {
        let folders = [downloaded, bundled].compactMap { $0 }
        let usable = folders.compactMap { f in read(folder: f).map { (folder: f, version: $0.version, ok: $0.isCompatible(with: ferry)) } }
            .filter(\.ok).sorted { $0.version > $1.version }
        for c in usable { if let pack = try? KnowledgePack(folder: c.folder) { return pack } }
        return nil
    }

    static func bestSuggestedModels(downloaded: URL, bundled: URL?, ferry: String) -> [String: String] {
        [downloaded, bundled].compactMap { $0 }.compactMap(read(folder:))
            .filter { $0.isCompatible(with: ferry) }.max { $0.version < $1.version }?.suggestedModels ?? [:]
    }

    static func install(from base: URL, current: Int, ferry: String, staging: URL, installed: URL) async throws -> Bool {
        let fm = FileManager.default
        let manifestData = try await fetch(base.appendingPathComponent("manifest.json"))
        guard let manifest = decode(manifestData), manifest.version > current, manifest.isCompatible(with: ferry) else { return false }
        guard manifest.entriesAreSafe else { throw KnowledgeInvalid(why: "the manifest lists an unsafe file path") }
        guard manifest.files.count <= maxFiles else { throw KnowledgeInvalid(why: "the manifest lists too many files") }
        var budget = maxTotalSize
        try? fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for path in manifest.files {
            let dest = staging.appendingPathComponent(path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try await fetch(base.appendingPathComponent(path), limit: min(maxFileSize, budget))
            budget -= data.count
            try data.write(to: dest)
        }
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))
        _ = try KnowledgePack(folder: staging)
        if fm.fileExists(atPath: installed.path) {
            _ = try fm.replaceItemAt(installed, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: installed)
        }
        return true
    }

    struct KnowledgeInvalid: Error { let why: String }

    private static func fetch(_ url: URL, limit: Int = maxFileSize) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Ferry-macOS", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw KnowledgeInvalid(why: "HTTP \(http.statusCode)") }
        if response.expectedContentLength > Int64(limit) { throw KnowledgeInvalid(why: "a file is too big") }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw KnowledgeInvalid(why: "a file is too big") }
        }
        return data
    }
}
