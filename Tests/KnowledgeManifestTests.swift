import Foundation

private func writePack(_ dir: URL, version: Int, minFerry: String = "1.0.0", files: [String: String]) {
    let fm = FileManager.default
    for (path, text) in files {
        let u = dir.appendingPathComponent(path)
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }
    let list = files.keys.sorted().map { "\"\($0)\"" }.joined(separator: ",")
    try? "{\"version\": \(version), \"minFerry\": \"\(minFerry)\", \"files\": [\(list)]}".write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
}

private func runSync<T>(_ body: @escaping () async -> T) -> T {
    var result: T!
    let done = DispatchSemaphore(value: 0)
    Task { result = await body(); done.signal() }
    done.wait()
    return result
}

func runKnowledgeManifestTests() {
    let m = KnowledgeManifest.decode(Data(#"{"version": 3, "minFerry": "1.4", "files": ["a.md", "b/c.md"]}"#.utf8))
    check(m?.version == 3 && m?.minFerry == "1.4" && m?.files == ["a.md", "b/c.md"], "manifest decodes")
    check(KnowledgeManifest.decode(Data("{}".utf8)) == nil && KnowledgeManifest.decode(Data("nope".utf8)) == nil, "bad manifest is nil")
    for bad in ["../x.md", "a/../../x.md", "/etc/x.md", "a.txt", "", "a/..", "a.md/.."] { check(!KnowledgeManifest.isSafeEntry(bad), "unsafe entry \(bad)") }
    for good in ["a.md", "known-issues/tessellation.md", "a..b.md"] { check(KnowledgeManifest.isSafeEntry(good), "safe entry \(good)") }
    check(m?.isCompatible(with: "1.4.0") == true && m?.isCompatible(with: "1.3.9") == false, "minFerry compatibility")
    let repo = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FERRY_REPO"] ?? ".")
    let plist = (try? Data(contentsOf: repo.appendingPathComponent("Info.plist")))
        .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    let shipping = plist?["CFBundleShortVersionString"] as? String
    let repoPack = KnowledgeManifest.read(folder: repo.appendingPathComponent("Knowledge"))
    check(shipping != nil && repoPack != nil && repoPack!.isCompatible(with: shipping!),
          "Knowledge/manifest.json minFerry (\(repoPack?.minFerry ?? "?")) ≤ Info.plist version (\(shipping ?? "?"))")
    let withModels = KnowledgeManifest.decode(Data(#"{"version": 1, "minFerry": "1.0", "files": [], "suggestedModels": {"claude": "claude-opus-5-5"}}"#.utf8))
    check(withModels?.suggestedModels == ["claude": "claude-opus-5-5"], "suggestedModels parse")
    check(m?.suggestedModels == [:], "missing suggestedModels is empty")
    check(repoPack?.suggestedModels["claude"] != nil, "repo manifest suggests a Claude model")
    check(KnowledgeManifest.isNewer("1.0.10", than: "1.0.9") && !KnowledgeManifest.isNewer("1.0", than: "1.0.0"), "version compare")

    let ok = "---\ntitle: T\ntags: x\n---\nbody"
    let bundled = tempDir(), downloaded = tempDir(), none = tempDir()
    writePack(bundled, version: 1, files: ["a.md": ok])
    writePack(downloaded, version: 2, files: ["a.md": ok, "b.md": ok])
    check(KnowledgeManifest.loadBest(downloaded: downloaded, bundled: bundled, ferry: "1.5")?.doc("b") != nil, "newer downloaded pack wins")
    check(KnowledgeManifest.loadBest(downloaded: none, bundled: bundled, ferry: "1.5")?.doc("a") != nil, "no downloaded pack: bundled")
    writePack(downloaded, version: 2, minFerry: "9.0", files: ["b.md": ok])
    check(KnowledgeManifest.loadBest(downloaded: downloaded, bundled: bundled, ferry: "1.5")?.doc("b") == nil, "too-new minFerry is skipped")
    writePack(downloaded, version: 3, files: ["b.md": ok])
    try? FileManager.default.removeItem(at: downloaded.appendingPathComponent("b.md"))
    check(KnowledgeManifest.loadBest(downloaded: downloaded, bundled: bundled, ferry: "1.5")?.doc("a") != nil, "broken downloaded pack falls back to bundled")
    check(KnowledgeManifest.loadBest(downloaded: none, bundled: nil, ferry: "1.5") == nil, "nothing to load is nil")

    func tryInstall(_ server: URL, current: Int) -> (Bool?, URL) {
        let work = tempDir(), inst = work.appendingPathComponent("Knowledge")
        let r = runSync { try? await KnowledgeManifest.install(from: server, current: current, ferry: "1.5", staging: work.appendingPathComponent("Knowledge.new"), installed: inst) }
        return (r, inst)
    }
    let good = tempDir()
    writePack(good, version: 5, files: ["a.md": ok, "sub/b.md": ok])
    var (r, inst) = tryInstall(good, current: 2)
    check(r == true && (try? KnowledgePack(folder: inst))?.doc("sub/b") != nil, "newer pack installs")
    check(!FileManager.default.fileExists(atPath: inst.deletingLastPathComponent().appendingPathComponent("Knowledge.new").path), "staging is cleaned up")
    (r, inst) = tryInstall(good, current: 5)
    check(r == false && !FileManager.default.fileExists(atPath: inst.path), "same version doesn't install")

    let evil = tempDir()
    writePack(evil, version: 9, files: ["a.md": ok])
    try? #"{"version": 9, "minFerry": "1.0", "files": ["a.md", "../evil.md"]}"#.write(to: evil.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    (r, inst) = tryInstall(evil, current: 2)
    check(r == nil && !FileManager.default.fileExists(atPath: inst.path), "bad entry rejects the whole download")

    let broken = tempDir()
    writePack(broken, version: 9, files: ["a.md": ok, "b.md": ok])
    try? FileManager.default.removeItem(at: broken.appendingPathComponent("b.md"))
    (r, inst) = tryInstall(broken, current: 2)
    check(r == nil && !FileManager.default.fileExists(atPath: inst.path), "missing file installs nothing")

    let big = tempDir()
    writePack(big, version: 9, files: ["a.md": String(repeating: "x", count: KnowledgeManifest.maxFileSize + 1)])
    (r, inst) = tryInstall(big, current: 2)
    check(r == nil && !FileManager.default.fileExists(atPath: inst.path), "file over 512 KB installs nothing")

    let work = tempDir(), keep = work.appendingPathComponent("Knowledge")
    writePack(keep, version: 4, files: ["a.md": ok])
    _ = runSync { try? await KnowledgeManifest.install(from: broken, current: 4, ferry: "1.5", staging: work.appendingPathComponent("Knowledge.new"), installed: keep) }
    check(KnowledgeManifest.read(folder: keep)?.version == 4, "failed update keeps the current pack")

    let many = tempDir()
    writePack(many, version: 9, files: Dictionary(uniqueKeysWithValues: (0...KnowledgeManifest.maxFiles).map { ("f\($0).md", ok) }))
    (r, inst) = tryInstall(many, current: 2)
    check(r == nil && !FileManager.default.fileExists(atPath: inst.path), "too many files installs nothing")

    let heavy = tempDir()
    writePack(heavy, version: 9, files: Dictionary(uniqueKeysWithValues: (0..<17).map { ("f\($0).md", String(repeating: "x", count: 500_000)) }))
    (r, inst) = tryInstall(heavy, current: 2)
    check(r == nil && !FileManager.default.fileExists(atPath: inst.path), "over 8 MB in total installs nothing")

    let w2 = tempDir(), old = w2.appendingPathComponent("Knowledge")
    writePack(old, version: 4, files: ["a.md": ok])
    let up = runSync { try? await KnowledgeManifest.install(from: good, current: 4, ferry: "1.5", staging: w2.appendingPathComponent("Knowledge.new"), installed: old) }
    check(up == true && KnowledgeManifest.read(folder: old)?.version == 5, "update replaces the installed pack")

    let gh = KnowledgeManifest.githubURL
    check(KnowledgeManifest.endpoint(override: nil) == gh, "no override: GitHub")
    check(KnowledgeManifest.endpoint(override: "https://evil.example/Knowledge/") == gh, "remote override ignored")
    check(KnowledgeManifest.endpoint(override: "http://localhost:8000/").host == "localhost", "localhost override kept")
    check(KnowledgeManifest.endpoint(override: "http://127.0.0.1:8000/").host == "127.0.0.1", "127.0.0.1 override kept")
    check(KnowledgeManifest.endpoint(override: "http://[::1]:8000/").host?.contains("::1") == true, "::1 override kept")
    check(KnowledgeManifest.endpoint(override: "file:///tmp/x/").scheme == "file", "file override kept")
    check(KnowledgeManifest.endpoint(override: "http://localhost.evil.example/") == gh, "lookalike host ignored")
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ferry-suggest-\(UUID())")
    func write(_ name: String, _ json: String) -> URL {
        let d = tmp.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: d.appendingPathComponent("manifest.json"))
        return d
    }
    let mOld = write("old", #"{"version": 1, "minFerry": "1.0", "files": [], "suggestedModels": {"claude": "old"}}"#)
    let mNew = write("new", #"{"version": 2, "minFerry": "1.0", "files": [], "suggestedModels": {"claude": "new"}}"#)
    let mFuture = write("future", #"{"version": 9, "minFerry": "99", "files": [], "suggestedModels": {"claude": "future"}}"#)
    check(KnowledgeManifest.bestSuggestedModels(downloaded: mOld, bundled: mNew, ferry: "1.5")["claude"] == "new", "newest manifest's suggestion")
    check(KnowledgeManifest.bestSuggestedModels(downloaded: mFuture, bundled: mOld, ferry: "1.5")["claude"] == "old", "a manifest for a newer Ferry is skipped")
    check(KnowledgeManifest.bestSuggestedModels(downloaded: tmp.appendingPathComponent("none"), bundled: nil, ferry: "1.5").isEmpty, "none: empty")
    try? FileManager.default.removeItem(at: tmp)
}
