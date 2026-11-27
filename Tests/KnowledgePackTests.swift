import Foundation

func runKnowledgePackTests() {
    guard let repo = ProcessInfo.processInfo.environment["FERRY_REPO"],
          let pack = try? KnowledgePack(folder: URL(fileURLWithPath: repo + "/Tests/Fixtures/knowledge")) else {
        check(false, "knowledge fixture readable (FERRY_REPO set?)")
        return
    }
    check(pack.doc("known-issues/tessellation")?.tags == ["dx11", "shards"], "front matter tags")
    check(pack.doc("known-issues/tessellation")?.title == "Objects blink or vanish on DirectX 11 games", "front matter title")
    check(pack.doc("how-it-works/wine.md") == nil && pack.doc("how-it-works/wine") != nil, "id has no extension")
    check(pack.search("black shards on walls", limit: 3).first?.id == "known-issues/tessellation", "tags and title beat plain body hits")
    check(pack.search("the of and", limit: 3).isEmpty, "stop words only finds nothing")
    check(pack.search("wine", limit: 1).count == 1, "limit")

    let empty = tempDir()
    check((try? KnowledgePack(folder: empty)) == nil, "folder without a manifest throws")

    let tie = KnowledgePack(docs: [KnowledgeDoc(id: "b", title: "x", tags: [], body: "zebra"), KnowledgeDoc(id: "a", title: "x", tags: [], body: "zebra")])
    check(tie.search("zebra", limit: 5).map(\.id) == ["a", "b"], "ties by id")

    let docs = KnowledgePack.generated(settings: SettingsCatalog.all, symptoms: [(title: "It's slow", guide: "Limit the frame rate.")])
    let d = docs.first { $0.id == "settings/maxTessellation" }
    check(d?.title == "Tessellation detail" && d?.body.contains("Turn off Use DirectX 9 first.") == true, "generated setting doc")
    check(docs.filter { $0.id.hasPrefix("settings/") }.count == SettingsCatalog.all.count, "one doc per setting")
    check(docs.first { $0.id == "troubleshoot/it-s-slow" }?.body.contains("Limit the frame rate.") == true, "generated troubleshoot doc")
    for doc in docs { check(!doc.body.contains("{") && !doc.title.contains("{"), "no placeholder left in \(doc.id)") }
    check(Set(docs.map(\.id)).count == docs.count, "generated ids unique")

    let knowledge = URL(fileURLWithPath: repo + "/Knowledge")
    guard let manifest = KnowledgeManifest.read(folder: knowledge), let repoPack = try? KnowledgePack(folder: knowledge) else {
        check(false, "Knowledge/ loads")
        return
    }
    check(manifest.version == 4 && !manifest.files.isEmpty && manifest.entriesAreSafe, "Knowledge manifest")
    for path in manifest.files {
        let id = String(path.dropLast(3))
        let doc = repoPack.doc(id)
        check(doc != nil && doc?.title != id && doc?.tags.isEmpty == false, "\(path) has a title and tags")
        let text = (try? String(contentsOf: knowledge.appendingPathComponent(path), encoding: .utf8)) ?? ""
        check(text.count <= 4000, "\(path) is under 4,000 characters")
    }
    let onDisk = (FileManager.default.enumerator(atPath: knowledge.path)?.allObjects as? [String] ?? [])
        .filter { $0.hasSuffix(".md") && $0 != "README.md" }
    check(Set(onDisk) == Set(manifest.files), "every Knowledge document is in the manifest")
}
